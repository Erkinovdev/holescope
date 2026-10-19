import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:holescope/core/loaders.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/providers.dart';

/// Центр Ташкента — стартовая точка карты, пока нет GPS (приблизительно).
const tashkentCenter = (41.311, 69.279);

const _kLat = 111320.0;

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

/// Векторная карта качества дорог: сегменты нашей дорожной сети (цвет = класс ровности A–E) и ямы.
/// Не требует внешних тайлов: рисуется CustomPainter из /map/segments и /map/clusters.
class RoadMapView extends ConsumerStatefulWidget {
  const RoadMapView({super.key, required this.controller, this.onClusters, this.onClusterTap});
  final RoadMapController controller;
  final ValueChanged<List<ClusterDto>>? onClusters;
  final ValueChanged<ClusterDto>? onClusterTap;

  @override
  ConsumerState<RoadMapView> createState() => _RoadMapViewState();
}

class _RoadMapViewState extends ConsumerState<RoadMapView> {
  List<SegmentDto> segments = const [];
  List<ClusterDto> clusters = const [];
  bool loading = false, offline = false;
  Timer? _debounce;
  double _startMpp = 3;
  Size _size = Size.zero;

  RoadMapController get c => widget.controller;

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
    _debounce = Timer(const Duration(milliseconds: 450), _fetch);
  }

  Future<void> _fetch() async {
    if (!mounted || _size.isEmpty) return;
    final api = ref.read(apiProvider);
    final dLat = math.min(_size.height * c.metersPerPx / 2 / _kLat * 1.1, 0.045);
    final dLon = math.min(_size.width * c.metersPerPx / 2 / (_kLat * math.cos(c.lat * math.pi / 180)) * 1.1, 0.045);
    setState(() => loading = true);
    try {
      final r = await Future.wait([
        api.mapSegments(minLat: c.lat - dLat, minLon: c.lon - dLon, maxLat: c.lat + dLat, maxLon: c.lon + dLon, limit: 5000),
        api.mapClusters(minLat: c.lat - dLat, minLon: c.lon - dLon, maxLat: c.lat + dLat, maxLon: c.lon + dLon),
      ]);
      if (!mounted) return;
      setState(() {
        segments = r[0] as List<SegmentDto>;
        clusters = r[1] as List<ClusterDto>;
        offline = false;
        loading = false;
      });
      widget.onClusters?.call(clusters);
    } on ApiException {
      if (mounted) {
        setState(() {
          offline = true;
          loading = false;
        });
      }
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
            child: CustomPaint(painter: _MapPainter(segments, clusters, c, hp, _project, _size)),
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
  _MapPainter(this.segments, this.clusters, this.c, this.hp, this.project, this.size0) : super(repaint: c);
  final List<SegmentDto> segments;
  final List<ClusterDto> clusters;
  final RoadMapController c;
  final HpColors hp;
  final Offset Function(double, double) project;
  final Size size0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = hp.surface);
    final w = size.width;
    final base = Paint()..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    // 1) дороги без оценки (под низом)
    for (final s in segments) {
      if (s.cls.isNotEmpty) continue;
      final a = project(s.latA, s.lonA), b = project(s.latB, s.lonB);
      if (!_visible(a, b, w, size.height)) continue;
      base
        ..color = hp.raised
        ..strokeWidth = (s.roadClass == 'R' || s.roadClass == 'A') ? 5 : (s.roadClass == 'B' ? 4 : 2.5);
      canvas.drawLine(a, b, base);
    }
    // 2) оценённые сегменты поверх, со смещением по направлению движения (полосы видны отдельно)
    final lane = c.metersPerPx < 3 ? 2.0 : 0.0;
    for (final s in segments) {
      if (s.cls.isEmpty) continue;
      var a = project(s.latA, s.lonA), b = project(s.latB, s.lonB);
      if (!_visible(a, b, w, size.height)) continue;
      if (lane > 0) {
        final d = b - a;
        final len = d.distance;
        if (len > 0) {
          final n = Offset(-d.dy / len, d.dx / len) * (s.direction == 1 ? lane : -lane);
          a += n;
          b += n;
        }
      }
      base
        ..color = roughnessColor(hp, s.cls)
        ..strokeWidth = 4;
      canvas.drawLine(a, b, base);
    }
    // 3) ямы
    for (final cl in clusters) {
      final p = project(cl.lat, cl.lon);
      if (p.dx < -20 || p.dy < -20 || p.dx > w + 20 || p.dy > size.height + 20) continue;
      final col = cl.status == 'fixed' ? hp.smooth : (cl.level == 'deep' || cl.level == 'danger' ? hp.crater : hp.warn);
      canvas.drawCircle(p, 9, Paint()..color = col);
      canvas.drawCircle(p, 4.2, Paint()..color = hp.bgBase..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    // 4) я
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

  bool _visible(Offset a, Offset b, double w, double h) => !((a.dx < -30 && b.dx < -30) || (a.dx > w + 30 && b.dx > w + 30) || (a.dy < -30 && b.dy < -30) || (a.dy > h + 30 && b.dy > h + 30));

  @override
  bool shouldRepaint(_MapPainter o) => true;
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
