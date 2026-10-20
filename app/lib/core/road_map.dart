import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:holescope/core/loaders.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/config.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:holescope/services/providers.dart';

/// Центр Ташкента — стартовая точка карты, пока нет GPS (приблизительно).
const tashkentCenter = (41.311, 69.279);

const _cell = 0.01; // ячейка сетки, градусы (совпадает с сервером)
const _mercator = 78271.517; // метров на пиксель при zoom 0 (тайлы 512 px)

double _zoomOf(double mpp, double lat) =>
    math.log(_mercator * math.cos(lat * math.pi / 180) / mpp) / math.ln2;
double _mppOf(double zoom, double lat) =>
    _mercator * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class RoadMapController extends ChangeNotifier {
  RoadMapController() {
    // веб-версия: ?at=широта,долгота,метров_на_пиксель открывает карту в нужном месте (для проверки)
    final at = kIsWeb ? Uri.base.queryParameters['at']?.split(',') : null;
    if (at != null && at.length >= 2) {
      lat = double.tryParse(at[0]) ?? lat;
      lon = double.tryParse(at[1]) ?? lon;
      if (at.length > 2) metersPerPx = double.tryParse(at[2]) ?? metersPerPx;
    }
  }

  double lat = tashkentCenter.$1, lon = tashkentCenter.$2, metersPerPx = 3.0;
  double? meLat, meLon, meHeading;
  int _version = 0;
  int get version => _version;

  void moveTo(double la, double lo, {double? mpp}) {
    lat = la;
    lon = lo;
    if (mpp != null) metersPerPx = mpp;
    _version++;
    notifyListeners();
  }

  /// Положение камеры сообщает сама карта (после жеста): повторного перемещения не вызывает.
  void syncFromMap(double la, double lo, double mpp) {
    lat = la;
    lon = lo;
    metersPerPx = mpp;
  }

  void setMe(double? la, double? lo, double? heading) {
    meLat = la;
    meLon = lo;
    meHeading = heading;
    notifyListeners();
  }
}

/// Карта качества дорог на векторных тайлах (MapLibre, GPU): подложка — наш тайловый сервер (/map/t), поверх — сегменты
/// оценённых дорог (цвет = класс ровности A–E) и ямы. Данные сегментов приходят ячейками 0.01° и кэшируются.
class RoadMapView extends ConsumerStatefulWidget {
  const RoadMapView({
    super.key,
    required this.controller,
    this.onClusters,
    this.onClusterTap,
    this.filter = 'all',
  });
  final RoadMapController controller;

  /// all | deep | manholes | humps | rails — какие ямы показывать.
  final String filter;
  final ValueChanged<List<ClusterDto>>? onClusters;
  final ValueChanged<ClusterDto>? onClusterTap;

  @override
  ConsumerState<RoadMapView> createState() => _RoadMapViewState();
}

class _RoadMapViewState extends ConsumerState<RoadMapView> {
  final _cells = <String, List<Map<String, dynamic>>>{};
  final _cellsAt = <String, DateTime>{};
  final _inflight = <String>{};
  List<ClusterDto> clusters = const [];
  MapLibreMapController? _map;
  bool _styleReady = false, offline = false;
  int _appliedVersion = 0, _gen = 0;
  Timer? _debounce;
  HpColors? _hp;
  Size _size = Size.zero;

  RoadMapController get c => widget.controller;
  bool get loading => _inflight.isNotEmpty;

  @override
  void initState() {
    super.initState();
    c.addListener(_onCtl);
    _appliedVersion = c.version;
  }

  @override
  void didUpdateWidget(RoadMapView old) {
    super.didUpdateWidget(old);
    if (old.filter != widget.filter) _pushPits();
  }

  @override
  void dispose() {
    c.removeListener(_onCtl);
    _debounce?.cancel();
    super.dispose();
  }

  bool _passes(ClusterDto cl) => switch (widget.filter) {
    'deep' => cl.level == 'deep' || cl.level == 'danger',
    'manholes' => cl.type.startsWith('manhole'),
    'humps' => cl.type.startsWith('bump'),
    'rails' => cl.type.startsWith('rail') || cl.type == 'joint',
    _ => true,
  };

  void _onCtl() {
    final m = _map;
    if (m == null || !_styleReady) return;
    if (c.version != _appliedVersion) {
      _appliedVersion = c.version;
      m.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(c.lat, c.lon),
          _zoomOf(c.metersPerPx, c.lat),
        ),
        duration: const Duration(milliseconds: 450),
      );
    }
    _pushMe();
  }

  Future<void> _onStyleLoaded() async {
    final m = _map;
    final hp = _hp;
    if (m == null || hp == null) return;
    const empty = {
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[],
    };
    await m.addGeoJsonSource('seg', empty);
    await m.addGeoJsonSource('pits', empty);
    await m.addGeoJsonSource('me', empty);
    final cls = [
      'match',
      ['get', 'c'],
      'A',
      _hex(hp.smooth),
      'B',
      _hex(roughnessColor(hp, 'B')),
      'C',
      _hex(hp.amber),
      'D',
      _hex(hp.warn),
      'E',
      _hex(hp.crater),
      _hex(hp.line),
    ];
    const offset = [
      'case',
      [
        '==',
        ['get', 'd'],
        1,
      ],
      1.2,
      -1.2,
    ];
    await m.addLineLayer(
      'seg',
      'seg-casing',
      LineLayerProperties(
        lineColor: _hex(hp.bgBase),
        lineOpacity: 0.55,
        lineCap: 'round',
        lineJoin: 'round',
        lineWidth: const [
          'interpolate',
          ['exponential', 1.4],
          ['zoom'],
          10,
          2.2,
          14,
          6.5,
          18,
          17,
        ],
        lineOffset: offset,
      ),
    );
    await m.addLineLayer(
      'seg',
      'seg-line',
      LineLayerProperties(
        lineColor: cls,
        lineCap: 'round',
        lineJoin: 'round',
        lineWidth: const [
          'interpolate',
          ['exponential', 1.4],
          ['zoom'],
          10,
          1.4,
          14,
          4,
          18,
          11,
        ],
        lineOffset: offset,
      ),
    );
    await m.addCircleLayer(
      'pits',
      'pit-glow',
      CircleLayerProperties(
        circleColor: const ['get', 'col'],
        circleOpacity: 0.28,
        circleRadius: const [
          'interpolate',
          ['linear'],
          ['zoom'],
          10,
          9,
          16,
          20,
        ],
        circleBlur: 0.7,
      ),
    );
    await m.addCircleLayer(
      'pits',
      'pit-ring',
      CircleLayerProperties(
        circleColor: const ['get', 'col'],
        circleStrokeColor: _hex(hp.bgBase),
        circleStrokeWidth: 1.5,
        circleRadius: const [
          'interpolate',
          ['linear'],
          ['zoom'],
          10,
          5,
          16,
          9,
        ],
      ),
    );
    await m.addCircleLayer(
      'pits',
      'pit-core',
      CircleLayerProperties(
        circleColor: _hex(hp.bgBase),
        circleRadius: const [
          'interpolate',
          ['linear'],
          ['zoom'],
          10,
          2,
          16,
          3.8,
        ],
      ),
    );
    await m.addLineLayer(
      'me',
      'me-dir',
      LineLayerProperties(
        lineColor: _hex(hp.info),
        lineWidth: 3,
        lineCap: 'round',
      ),
      filter: const [
        '==',
        ['geometry-type'],
        'LineString',
      ],
    );
    await m.addCircleLayer(
      'me',
      'me-halo',
      CircleLayerProperties(
        circleColor: _hex(hp.info),
        circleOpacity: 0.22,
        circleRadius: 16,
      ),
      filter: const [
        '==',
        ['geometry-type'],
        'Point',
      ],
    );
    await m.addCircleLayer(
      'me',
      'me-dot',
      CircleLayerProperties(
        circleColor: _hex(hp.info),
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
        circleRadius: 7,
      ),
      filter: const [
        '==',
        ['geometry-type'],
        'Point',
      ],
    );
    _styleReady = true;
    _pushMe();
    _pushPits();
    _pushSegments();
    _schedule();
  }

  void _pushMe() {
    final m = _map;
    if (m == null || !_styleReady) return;
    final feats = <Map<String, dynamic>>[];
    if (c.meLat != null && c.meLon != null) {
      feats.add({
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Point',
          'coordinates': [c.meLon, c.meLat],
        },
      });
      final h = c.meHeading;
      if (h != null) {
        final r = h * math.pi / 180, d = 0.00018;
        feats.add({
          'type': 'Feature',
          'properties': {},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [c.meLon, c.meLat],
              [
                c.meLon! + math.sin(r) * d / math.cos(c.meLat! * math.pi / 180),
                c.meLat! + math.cos(r) * d,
              ],
            ],
          },
        });
      }
    }
    m.setGeoJsonSource('me', {'type': 'FeatureCollection', 'features': feats});
  }

  void _pushPits() {
    final m = _map;
    final hp = _hp;
    if (m == null || !_styleReady || hp == null) return;
    m.setGeoJsonSource('pits', {
      'type': 'FeatureCollection',
      'features': [
        for (final cl in clusters.where(_passes))
          {
            'type': 'Feature',
            'properties': {
              'id': cl.id,
              'col': _hex(
                cl.status == 'fixed'
                    ? hp.smooth
                    : (cl.level == 'deep' || cl.level == 'danger'
                          ? hp.crater
                          : hp.warn),
              ),
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [cl.lon, cl.lat],
            },
          },
      ],
    });
  }

  /// Все загруженные ячейки одним набором: MapLibre сам обрезает по экрану и рисует на GPU.
  void _pushSegments() {
    final m = _map;
    if (m == null || !_styleReady) return;
    m.setGeoJsonSource('seg', {
      'type': 'FeatureCollection',
      'features': [for (final f in _cells.values) ...f],
    });
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _fetch);
  }

  String _setFor(double mpp) =>
      mpp >= 7 ? 'major' : (mpp >= 3.5 ? 'main' : 'all');

  Future<void> _fetch() async {
    if (!mounted || _size.isEmpty) return;
    final gen = ++_gen;
    final cam = _map?.cameraPosition;
    if (cam != null)
      c.syncFromMap(
        cam.target.latitude,
        cam.target.longitude,
        _mppOf(cam.zoom, cam.target.latitude),
      );
    // видимая область по центру и масштабу (с запасом 15%): не зависит от готовности платформенной карты
    final halfLat = _size.height * c.metersPerPx / 2 / 111320 * 1.15;
    final halfLon =
        _size.width *
        c.metersPerPx /
        2 /
        (111320 * math.cos(c.lat * math.pi / 180)) *
        1.15;
    final b = LatLngBounds(
      southwest: LatLng(c.lat - halfLat, c.lon - halfLon),
      northeast: LatLng(c.lat + halfLat, c.lon + halfLon),
    );
    final set = _setFor(c.metersPerPx);
    final i0 = (b.southwest.latitude / _cell).floor(),
        i1 = (b.northeast.latitude / _cell).floor();
    final j0 = (b.southwest.longitude / _cell).floor(),
        j1 = (b.northeast.longitude / _cell).floor();
    final now = DateTime.now();
    final need = <(int, int)>[];
    for (var i = i0; i <= i1; i++) {
      for (var j = j0; j <= j1; j++) {
        final key = '$i:$j:$set';
        final at = _cellsAt[key];
        if (at != null && now.difference(at).inMinutes < 10) continue;
        if (_inflight.contains(key)) continue;
        need.add((i, j));
      }
    }
    need.sort(
      (a, bb) => ((a.$1 + .5) * _cell - c.lat).abs().compareTo(
        ((bb.$1 + .5) * _cell - c.lat).abs(),
      ),
    );
    if (need.length > 40) need.removeRange(40, need.length);
    final api = ref.read(apiProvider);
    for (var k = 0; k < need.length; k += 6) {
      if (!mounted || gen != _gen) break;
      final batch = need.sublist(k, math.min(k + 6, need.length));
      for (final x in batch) {
        _inflight.add('${x.$1}:${x.$2}:$set');
      }
      if (mounted) setState(() {});
      await Future.wait([
        for (final x in batch)
          api
              .mapCell(x.$1, x.$2, set: set, scored: true)
              .then((segs) {
                final key = '${x.$1}:${x.$2}:$set';
                _cellsAt[key] = DateTime.now();
                _cells[key] = [
                  for (final s in segs)
                    if (s.cls.isNotEmpty)
                      {
                        'type': 'Feature',
                        'properties': {'c': s.cls, 'd': s.direction},
                        'geometry': {
                          'type': 'LineString',
                          'coordinates': [
                            [s.lonA, s.latA],
                            [s.lonB, s.latB],
                          ],
                        },
                      },
                ];
                offline = false;
              })
              .catchError((_) {
                offline = true;
              })
              .whenComplete(() => _inflight.remove('${x.$1}:${x.$2}:$set')),
      ]);
      _pushSegments();
      if (mounted) setState(() {});
    }
    _evict();
    if (!mounted || gen != _gen) return;
    try {
      final r = await api.mapClusters(
        minLat: b.southwest.latitude,
        minLon: b.southwest.longitude,
        maxLat: b.northeast.latitude,
        maxLon: b.northeast.longitude,
      );
      if (!mounted) return;
      clusters = r;
      offline = false;
      _pushPits();
      setState(() {});
      widget.onClusters?.call(clusters);
    } on ApiException {
      if (mounted) setState(() => offline = true);
    }
  }

  /// В памяти не больше ~150 ячеек: дальние от центра выбрасываем.
  void _evict() {
    if (_cells.length <= 150) return;
    double dist(String k) {
      final p = k.split(':');
      return ((int.parse(p[0]) + .5) * _cell - c.lat).abs() +
          ((int.parse(p[1]) + .5) * _cell - c.lon).abs();
    }

    final keys = _cells.keys.toList()
      ..sort((a, b) => dist(b).compareTo(dist(a)));
    for (final k in keys.take(_cells.length - 120)) {
      _cells.remove(k);
      _cellsAt.remove(k);
    }
  }

  void _onTap(LatLng at) {
    ClusterDto? best;
    var bd = 30 * c.metersPerPx;
    for (final cl in clusters.where(_passes)) {
      final dy = (cl.lat - at.latitude) * 111320,
          dx =
              (cl.lon - at.longitude) *
              111320 *
              math.cos(at.latitude * math.pi / 180);
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < bd) {
        bd = d;
        best = cl;
      }
    }
    if (best != null) widget.onClusterTap?.call(best);
  }

  @override
  Widget build(BuildContext context) {
    final hp = context.hp;
    final dark = hp.bgBase.computeLuminance() < 0.3;
    if (_hp != hp) {
      if (_hp != null)
        _styleReady =
            false; // тема сменилась: стиль перезагрузится, слои добавятся заново
      _hp = hp;
    }
    final style =
        '${AppConfig.resolveApiBase()}/map/style-${dark ? 'dark' : 'light'}.json';
    return LayoutBuilder(
      builder: (context, k) {
        final first = _size.isEmpty;
        _size = Size(k.maxWidth, k.maxHeight);
        if (first)
          WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
        return Stack(
          children: [
            Positioned.fill(
              child: MapLibreMap(
                key: ValueKey(style),
                styleString: style,
                initialCameraPosition: CameraPosition(
                  target: LatLng(c.lat, c.lon),
                  zoom: _zoomOf(c.metersPerPx, c.lat),
                ),
                minMaxZoomPreference: const MinMaxZoomPreference(9.5, 19),
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                compassEnabled: false,
                trackCameraPosition: true,
                onMapCreated: (ctl) => _map = ctl,
                onStyleLoadedCallback: _onStyleLoaded,
                onCameraIdle: _schedule,
                onMapClick: (_, at) => _onTap(at),
              ),
            ),
            if (offline)
              Positioned(
                left: 16,
                bottom: 12,
                child: _Chip(
                  text: 'нет связи с сервером',
                  color: hp.craterText,
                  bg: hp.surface,
                ),
              ),
            if (loading && !offline)
              const Positioned(
                right: 16,
                bottom: 12,
                child: MiniSpinner(size: 20),
              ),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, required this.bg});
  final String text;
  final Color color, bg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: HpText.s(color, 12, FontWeight.w500)),
  );
}

Color roughnessColor(HpColors hp, String cls) => switch (cls) {
  'A' => hp.smooth,
  'B' => Color.lerp(hp.smooth, hp.amber, 0.45)!,
  'C' => hp.amber,
  'D' => hp.warn,
  'E' => hp.crater,
  _ => hp.line,
};

/// Легенда классов ровности A–E.
class RoughnessLegend extends StatelessWidget {
  const RoughnessLegend({super.key, this.vertical = false});
  final bool vertical;
  @override
  Widget build(BuildContext context) {
    final hp = context.hp;
    if (vertical) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: hp.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: hp.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 9,
          children: [
            for (final k in ['A', 'B', 'C', 'D', 'E'])
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Container(
                    width: 18,
                    height: 5,
                    decoration: BoxDecoration(
                      color: roughnessColor(hp, k),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Text(k, style: HpText.s(hp.muted, 12, FontWeight.w600)),
                ],
              ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: hp.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hp.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          for (final k in ['A', 'B', 'C', 'D', 'E'])
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: roughnessColor(hp, k),
                    shape: BoxShape.circle,
                  ),
                ),
                Text(k, style: HpText.s(hp.muted, 11, FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }
}
