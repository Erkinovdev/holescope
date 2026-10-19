import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:holescope/core/loaders.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/providers.dart';

/// Центр Ташкента — стартовая точка карты, пока нет GPS (приблизительно).
const tashkentCenter = (41.311, 69.279);

const _kLat = 111320.0;
const _cell = 0.01; // ячейка сетки, градусы (совпадает с сервером)
final _kLon = _kLat * math.cos(tashkentCenter.$1 * math.pi / 180);

// «мировые» координаты в метрах относительно центра Ташкента: считаются один раз при загрузке ячейки
double _wx(double lon) => (lon - tashkentCenter.$2) * _kLon;
double _wy(double lat) => (lat - tashkentCenter.$1) * _kLat;

class RoadMapController extends ChangeNotifier {
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

  void setMe(double? la, double? lo, double? heading) {
    meLat = la;
    meLon = lo;
    meHeading = heading;
    notifyListeners();
  }
}

/// Готовая к рисованию геометрия одной ячейки: линии по стилям (цвет/толщина) в метрах — для одного вызова рисования на стиль.
class CellGeometry {
  CellGeometry(this.lines, this.at, this.segments);
  final Map<int, Float32List> lines; // стиль → x0,y0,x1,y1,…
  final DateTime at;
  final int segments;

  static const styleMinor = 0, styleB = 1, styleMajor = 2, styleA = 3; // 3 + индекс класса A..E = 3..7

  static int styleOf(SegmentDto s) {
    if (s.cls.isNotEmpty) return 3 + 'ABCDE'.indexOf(s.cls).clamp(0, 4);
    return (s.roadClass == 'R' || s.roadClass == 'A') ? styleMajor : (s.roadClass == 'B' ? styleB : styleMinor);
  }

  factory CellGeometry.build(List<SegmentDto> segs) {
    final buckets = <int, List<double>>{};
    for (final s in segs) {
      var ax = _wx(s.lonA), ay = _wy(s.latA), bx = _wx(s.lonB), by = _wy(s.latB);
      if (s.cls.isNotEmpty) {
        // оценённые сегменты смещаем вправо по ходу движения: полосы видны отдельно (≈ 2.5 м)
        final dx = bx - ax, dy = by - ay;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 0) {
          final k = (s.direction == 1 ? 2.5 : -2.5) / len;
          final nx = dy * k, ny = -dx * k;
          ax += nx;
          ay += ny;
          bx += nx;
          by += ny;
        }
      }
      (buckets[styleOf(s)] ??= []).addAll([ax, ay, bx, by]);
    }
    return CellGeometry({for (final e in buckets.entries) e.key: Float32List.fromList(e.value)}, DateTime.now(), segs.length);
  }
}

/// Векторная карта качества дорог: сегменты нашей дорожной сети (цвет = класс ровности A–E) и ямы.
/// Не требует внешних тайлов: данные приходят ячейками 0.01° (кэшируются на сервере и в приложении), рисуются CustomPainter.
class RoadMapView extends ConsumerStatefulWidget {
  const RoadMapView({super.key, required this.controller, this.onClusters, this.onClusterTap});
  final RoadMapController controller;
  final ValueChanged<List<ClusterDto>>? onClusters;
  final ValueChanged<ClusterDto>? onClusterTap;

  @override
  ConsumerState<RoadMapView> createState() => _RoadMapViewState();
}

class _RoadMapViewState extends ConsumerState<RoadMapView> {
  final _cells = <String, CellGeometry>{};
  final _inflight = <String>{};
  List<ClusterDto> clusters = const [];
  bool offline = false;
  Timer? _debounce;
  double _startMpp = 3;
  Size _size = Size.zero;
  int _gen = 0;

  RoadMapController get c => widget.controller;
  bool get loading => _inflight.isNotEmpty;

  @override
  void initState() {
    super.initState();
    c.addListener(_onCtl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    c.removeListener(_onCtl);
    _debounce?.cancel();
    super.dispose();
  }

  void _onCtl() {
    setState(() {});
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _fetch);
  }

  /// Набор сегментов по масштабу: далеко — только магистрали, ближе — больше дорог.
  String get _set => c.metersPerPx >= 7 ? 'major' : (c.metersPerPx >= 3.5 ? 'main' : 'all');

  Future<void> _fetch() async {
    if (!mounted || _size.isEmpty) return;
    final gen = ++_gen;
    final halfLat = _size.height * c.metersPerPx / 2 / _kLat * 1.15;
    final halfLon = _size.width * c.metersPerPx / 2 / (_kLat * math.cos(c.lat * math.pi / 180)) * 1.15;
    final i0 = ((c.lat - halfLat) / _cell).floor(), i1 = ((c.lat + halfLat) / _cell).floor();
    final j0 = ((c.lon - halfLon) / _cell).floor(), j1 = ((c.lon + halfLon) / _cell).floor();
    final set = _set;
    final now = DateTime.now();
    final need = <(int, int)>[];
    for (var i = i0; i <= i1; i++) {
      for (var j = j0; j <= j1; j++) {
        final key = '$i:$j:$set';
        final have = _cells[key];
        if (have != null && now.difference(have.at).inMinutes < 10) continue;
        if (_inflight.contains(key)) continue;
        need.add((i, j));
      }
    }
    need.sort((a, b) => ((a.$1 + .5) * _cell - c.lat).abs().compareTo(((b.$1 + .5) * _cell - c.lat).abs()));
    if (need.length > 40) need.removeRange(40, need.length);
    final api = ref.read(apiProvider);
    // ячейки идут пачками по 6: ближайшие к центру появляются первыми
    for (var k = 0; k < need.length; k += 6) {
      if (!mounted || gen != _gen) break;
      final batch = need.sublist(k, math.min(k + 6, need.length));
      for (final b in batch) {
        _inflight.add('${b.$1}:${b.$2}:$set');
      }
      if (mounted) setState(() {});
      await Future.wait([
        for (final b in batch)
          api.mapCell(b.$1, b.$2, set: set).then((segs) {
            _cells['${b.$1}:${b.$2}:$set'] = CellGeometry.build(segs);
            offline = false;
          }).catchError((_) {
            offline = true;
          }).whenComplete(() => _inflight.remove('${b.$1}:${b.$2}:$set')),
      ]);
      if (mounted) setState(() {});
    }
    _evict();
    if (!mounted || gen != _gen) return;
    try {
      final r = await api.mapClusters(minLat: c.lat - halfLat, minLon: c.lon - halfLon, maxLat: c.lat + halfLat, maxLon: c.lon + halfLon);
      if (!mounted) return;
      setState(() {
        clusters = r;
        offline = false;
      });
      widget.onClusters?.call(clusters);
    } on ApiException {
      if (mounted) setState(() => offline = true);
    }
  }

  /// Держим в памяти не больше 120 ячеек: лишние (дальние от центра) выбрасываем.
  void _evict() {
    if (_cells.length <= 120) return;
    final keys = _cells.keys.toList()
      ..sort((a, b) {
        double dist(String k) {
          final p = k.split(':');
          return ((int.parse(p[0]) + .5) * _cell - c.lat).abs() + ((int.parse(p[1]) + .5) * _cell - c.lon).abs();
        }

        return dist(b).compareTo(dist(a));
      });
    for (final k in keys.take(_cells.length - 100)) {
      _cells.remove(k);
    }
  }

  Offset _project(double lat, double lon) => Offset(
        (lon - c.lon) * math.cos(c.lat * math.pi / 180) * _kLat / c.metersPerPx + _size.width / 2,
        _size.height / 2 - (lat - c.lat) * _kLat / c.metersPerPx,
      );

  @override
  Widget build(BuildContext context) {
    final hp = context.hp;
    return LayoutBuilder(builder: (context, k) {
      final firstLayout = _size.isEmpty;
      _size = Size(k.maxWidth, k.maxHeight);
      if (firstLayout) WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
      final set = _set;
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => _startMpp = c.metersPerPx,
            onScaleUpdate: (d) {
              final mpp = (_startMpp / d.scale).clamp(0.6, 12.0);
              final dx = d.focalPointDelta.dx * c.metersPerPx, dy = d.focalPointDelta.dy * c.metersPerPx;
              c.lat += dy / _kLat;
              c.lon -= dx / (_kLat * math.cos(c.lat * math.pi / 180));
              c.metersPerPx = mpp;
              setState(() {});
            },
            onScaleEnd: (_) => _schedule(),
            onTapUp: (d) {
              ClusterDto? best;
              var bd = 30.0;
              for (final cl in clusters) {
                final dist = (_project(cl.lat, cl.lon) - d.localPosition).distance;
                if (dist < bd) {
                  bd = dist;
                  best = cl;
                }
              }
              if (best != null) widget.onClusterTap?.call(best);
            },
            child: RepaintBoundary(child: CustomPaint(painter: _MapPainter(_cells, set, clusters, c, hp, _project), size: Size.infinite)),
          ),
        ),
        if (offline) Positioned(left: 16, bottom: 12, child: _Chip(text: 'нет связи с сервером', color: hp.craterText, bg: hp.surface)),
        if (loading && !offline) const Positioned(right: 16, bottom: 12, child: MiniSpinner(size: 20)),
      ]);
    });
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, required this.bg});
  final String text;
  final Color color, bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
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

class _MapPainter extends CustomPainter {
  _MapPainter(this.cells, this.set, this.clusters, this.c, this.hp, this.project) : super(repaint: c);
  final Map<String, CellGeometry> cells;
  final String set;
  final List<ClusterDto> clusters;
  final RoadMapController c;
  final HpColors hp;
  final Offset Function(double, double) project;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = hp.surface);
    final mpp = c.metersPerPx;
    // видимые ячейки (с запасом), нужного набора; если нужной ещё нет — рисуем из любого набора, чтобы карта не мигала при смене масштаба
    final halfLat = size.height * mpp / 2 / _kLat * 1.1, halfLon = size.width * mpp / 2 / (_kLat * math.cos(c.lat * math.pi / 180)) * 1.1;
    final i0 = ((c.lat - halfLat) / _cell).floor(), i1 = ((c.lat + halfLat) / _cell).floor();
    final j0 = ((c.lon - halfLon) / _cell).floor(), j1 = ((c.lon + halfLon) / _cell).floor();
    final geos = <CellGeometry>[];
    for (var i = i0; i <= i1; i++) {
      for (var j = j0; j <= j1; j++) {
        final g = cells['$i:$j:$set'] ?? cells['$i:$j:main'] ?? cells['$i:$j:all'] ?? cells['$i:$j:major'];
        if (g != null) geos.add(g);
      }
    }
    // линии рисуем в метрах одним вызовом на стиль и ячейку: при движении пальца меняется только преобразование
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(1 / mpp, -1 / mpp);
    canvas.translate(-_wx(c.lon), -_wy(c.lat));
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (var style = 0; style < 8; style++) {
      final (color, px) = switch (style) {
        CellGeometry.styleMinor => (hp.raised, 2.5),
        CellGeometry.styleB => (hp.raised, 4.0),
        CellGeometry.styleMajor => (hp.raised, 5.0),
        _ => (roughnessColor(hp, 'ABCDE'[style - 3]), 4.0),
      };
      paint
        ..color = color
        ..strokeWidth = px * mpp;
      for (final g in geos) {
        final pts = g.lines[style];
        if (pts != null) canvas.drawRawPoints(ui.PointMode.lines, pts, paint);
      }
    }
    canvas.restore();
    // ямы
    final w = size.width;
    for (final cl in clusters) {
      final p = project(cl.lat, cl.lon);
      if (p.dx < -20 || p.dy < -20 || p.dx > w + 20 || p.dy > size.height + 20) continue;
      final col = cl.status == 'fixed' ? hp.smooth : (cl.level == 'deep' || cl.level == 'danger' ? hp.crater : hp.warn);
      canvas.drawCircle(p, 9, Paint()..color = col);
      canvas.drawCircle(p, 4.2, Paint()..color = hp.bgBase..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    // я
    if (c.meLat != null && c.meLon != null) {
      final p = project(c.meLat!, c.meLon!);
      canvas.drawCircle(p, 16, Paint()..color = hp.info.withValues(alpha: 0.22));
      canvas.drawCircle(p, 7, Paint()..color = hp.info);
      canvas.drawCircle(p, 7, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      if (c.meHeading != null) {
        final h = c.meHeading! * math.pi / 180;
        final tip = p + Offset(math.sin(h), -math.cos(h)) * 22;
        canvas.drawLine(p, tip, Paint()..color = hp.info..strokeWidth = 3..strokeCap = StrokeCap.round);
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter o) => o.clusters != clusters || o.set != set || !identical(o.cells, cells) || o.hp != hp;
}

/// Легенда классов ровности A–E.
class RoughnessLegend extends StatelessWidget {
  const RoughnessLegend({super.key});
  @override
  Widget build(BuildContext context) {
    final hp = context.hp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: hp.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(10), border: Border.all(color: hp.line)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        for (final k in ['A', 'B', 'C', 'D', 'E'])
          Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: roughnessColor(hp, k), shape: BoxShape.circle)),
            Text(k, style: HpText.s(hp.muted, 11, FontWeight.w600)),
          ]),
      ]),
    );
  }
}
