import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/l10n/app_localizations.dart';

/// Рисует знак Holescope (геометрия 1:1 с assets/figma/logo.svg, коробка 96×96).
void drawMark(Canvas canvas, Offset center, double size, {required Color amber, required Color hole, double eye = 1, double ring = 1}) {
  final k = size / 96;
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  canvas.scale(k);
  final a = Paint()..color = amber.withValues(alpha: ring);
  canvas.drawCircle(const Offset(48, 48), 38.88, Paint()..color = a.color..style = PaintingStyle.stroke..strokeWidth = 6.72);
  for (final r in const [Rect.fromLTWH(44.64, 0, 6.72, 21.12), Rect.fromLTWH(44.64, 74.88, 6.72, 21.12), Rect.fromLTWH(0, 44.64, 21.12, 6.72), Rect.fromLTWH(74.88, 44.64, 21.12, 6.72)]) {
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3.36)), a);
  }
  if (eye > 0) {
    canvas.drawOval(Rect.fromCenter(center: const Offset(48, 48), width: 44.16, height: 25.92), Paint()..color = amber.withValues(alpha: eye));
    canvas.drawOval(Rect.fromCenter(center: const Offset(48, 50.4), width: 28.8, height: 14.4), Paint()..color = hole.withValues(alpha: eye));
  }
  canvas.restore();
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this);
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    final reduce = ref.read(settingsProvider).reduceMotion || MediaQuery.disableAnimationsOf(context);
    ctl.duration = Duration(milliseconds: reduce ? 700 : 3000);
    ctl.forward().whenComplete(() {
      if (!mounted) return;
      final done = ref.read(settingsProvider).onboarded;
      context.go(done ? '/map' : '/onboarding/role');
    });
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final reduce = ref.read(settingsProvider).reduceMotion || MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: c.bgBase,
      body: Semantics(
        label: AppLocalizations.of(context).appName,
        child: AnimatedBuilder(
          animation: ctl,
          builder: (_, __) => CustomPaint(
            size: Size.infinite,
            painter: reduce ? _StaticPainter(ctl.value, c) : SplashPainter(ctl.value, c),
            child: Align(
              alignment: const Alignment(0, 0.32),
              child: Opacity(
                opacity: reduce ? ctl.value : ((ctl.value - 0.82) / 0.14).clamp(0.0, 1.0),
                child: Text(AppLocalizations.of(context).appName, style: HpText.s(c.text, 36, FontWeight.w700, ls: -0.72)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// reduce motion: только плавное появление знака.
class _StaticPainter extends CustomPainter {
  _StaticPainter(this.t, this.c);
  final double t;
  final HpColors c;
  @override
  void paint(Canvas canvas, Size s) {
    drawMark(canvas, Offset(s.width / 2, s.height * 0.42), 96, amber: c.amber, hole: c.bgBase, ring: t, eye: t);
  }

  @override
  bool shouldRepaint(_StaticPainter o) => o.t != t;
}

class SplashPainter extends CustomPainter {
  SplashPainter(this.t, this.c);
  final double t;
  final HpColors c;

  // Маршрут прицела в долях экрана и ямы на нём.
  static const _path = [Offset(0.12, 0.30), Offset(0.45, 0.30), Offset(0.45, 0.55), Offset(0.78, 0.55), Offset(0.78, 0.68)];
  static const _holes = [Offset(0.28, 0.30), Offset(0.45, 0.43), Offset(0.62, 0.55), Offset(0.78, 0.62)];

  static double _ease(double x) => x * x * (3 - 2 * x);
  static double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _len() {
    var l = 0.0;
    for (var i = 1; i < _path.length; i++) {
      l += (_path[i] - _path[i - 1]).distance;
    }
    return l;
  }

  /// Позиция вдоль маршрута (0..1) → точка.
  static Offset _at(double p) {
    var d = p * _len();
    for (var i = 1; i < _path.length; i++) {
      final sl = (_path[i] - _path[i - 1]).distance;
      if (d <= sl) return Offset.lerp(_path[i - 1], _path[i], d / sl)!;
      d -= sl;
    }
    return _path.last;
  }

  static double _progressOf(Offset hole) {
    var d = 0.0;
    for (var i = 1; i < _path.length; i++) {
      final a = _path[i - 1], b = _path[i];
      final ab = b - a;
      final u = ((hole - a).dx * ab.dx + (hole - a).dy * ab.dy) / (ab.distanceSquared);
      final proj = Offset.lerp(a, b, u.clamp(0, 1))!;
      if ((proj - hole).distance < 0.005) return (d + (proj - a).distance) / _len();
      d += ab.distance;
    }
    return 1;
  }

  @override
  void paint(Canvas canvas, Size s) {
    Offset px(Offset u) => Offset(u.dx * s.width, u.dy * s.height);
    final center = Offset(s.width / 2, s.height * 0.42);

    final scan = _ease(_seg(t, 0.08, 0.68));
    final collapse = _ease(_seg(t, 0.70, 0.88));
    final reveal = _ease(_seg(t, 0.84, 0.96));
    final mapAlpha = _ease(_seg(t, 0.0, 0.18)) * (1 - collapse);

    final reticleU = _at(scan);
    // «Камера» немного следует за прицелом.
    final pan = (collapse < 1 ? (Offset(0.5, 0.45) - reticleU) * 0.12 * (1 - collapse) : Offset.zero);
    final panPx = Offset(pan.dx * s.width, pan.dy * s.height);

    // Улицы: тонкие линии.
    final street = Paint()..color = c.line.withValues(alpha: 0.55 * mapAlpha)..strokeWidth = 1.2;
    canvas.save();
    canvas.translate(panPx.dx, panPx.dy);
    for (var i = -1; i <= 7; i++) {
      final x = s.width * (0.04 + i * 0.16);
      canvas.drawLine(Offset(x, -40), Offset(x, s.height + 40), street);
    }
    for (var j = -1; j <= 9; j++) {
      final y = s.height * (0.06 + j * 0.11);
      canvas.drawLine(Offset(-40, y), Offset(s.width + 40, y), street);
    }
    // След прицела — янтарная линия по улицам.
    final trail = Paint()..color = c.amber.withValues(alpha: 0.35 * mapAlpha)..strokeWidth = 3..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final tp = Path()..moveTo(px(_path.first).dx, px(_path.first).dy);
    final steps = (scan * 80).ceil();
    for (var i = 1; i <= steps; i++) {
      final o = px(_at(scan * i / steps));
      tp.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(tp, trail);

    // Ямы: вспышка красным при «поимке», затем схлопывание в центр.
    for (final h in _holes) {
      final caught = _ease(_seg(scan, _progressOf(h), _progressOf(h) + 0.05));
      final base = px(h);
      final pos = Offset.lerp(base, center - panPx, collapse)!;
      final alpha = (1 - _ease(_seg(t, 0.86, 0.93))).clamp(0.0, 1.0);
      if (alpha <= 0 || mapAlpha <= 0) continue;
      final r = 7 * (1 - collapse * 0.7);
      final dotColor = Color.lerp(c.muted.withValues(alpha: 0.5), c.crater, caught)!.withValues(alpha: alpha * (0.25 + 0.75 * mapAlpha));
      canvas.drawCircle(pos, r, Paint()..color = dotColor);
      if (caught > 0 && caught < 1) {
        canvas.drawCircle(pos, r + 26 * caught, Paint()..color = c.crater.withValues(alpha: (1 - caught) * 0.6 * alpha)..style = PaintingStyle.stroke..strokeWidth = 3);
      } else if (caught >= 1) {
        canvas.drawCircle(pos, r + 6, Paint()..color = c.crater.withValues(alpha: 0.35 * alpha)..style = PaintingStyle.stroke..strokeWidth = 2);
      }
    }
    canvas.restore();

    // Прицел: едет по маршруту → сходится в центр → становится знаком.
    final pos = Offset.lerp(px(reticleU) + panPx, center, collapse)!;
    final size = ui(72, 96, collapse);
    final appear = _ease(_seg(t, 0.02, 0.12));
    drawMark(canvas, pos, size, amber: c.amber, hole: c.bgBase, ring: appear, eye: reveal);

    // Лёгкое свечение в момент схлопывания.
    if (collapse > 0) {
      final glow = math.sin(math.pi * _seg(t, 0.84, 1.0));
      canvas.drawCircle(center, 70, Paint()..color = c.amber.withValues(alpha: 0.10 * glow)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    }
  }

  static double ui(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(SplashPainter o) => o.t != t || o.c != c;
}
