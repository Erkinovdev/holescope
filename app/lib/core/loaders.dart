import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Загрузчики Holescope по дизайну assets/holescope-loaders.html: знак-загрузчик, мини-спиннер, сканер, точки-ямы, скелетон, «Холи слушает».
/// При reduce motion (системном) анимации не бегут: показывается готовый кадр.

bool _still(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

const _ease = Cubic(.6, 0, .2, 1);

/// Значение между ключевыми кадрами: [t] в 0..1, кадры (позиция, значение), между ними — плавно по [curve].
double _kf(double t, List<(double, double)> k, [Curve curve = Curves.easeInOut]) {
  if (t <= k.first.$1) return k.first.$2;
  for (var i = 1; i < k.length; i++) {
    if (t <= k[i].$1) {
      final a = k[i - 1], b = k[i];
      final u = b.$1 == a.$1 ? 1.0 : (t - a.$1) / (b.$1 - a.$1);
      return a.$2 + (b.$2 - a.$2) * curve.transform(u.clamp(0.0, 1.0));
    }
  }
  return k.last.$2;
}

/// Знак-загрузчик: кольцо рисуется, риски собираются, появляется яма. [value] (0..1) задаёт кадр вручную (для заставки), иначе крутится по кругу.
class MarkLoader extends StatefulWidget {
  const MarkLoader({super.key, this.size = 104, this.value});
  final double size;
  final double? value;

  /// Кадр, на котором знак собран целиком (ring+риски+яма).
  static const assembled = 0.76;

  @override
  State<MarkLoader> createState() => _MarkLoaderState();
}

class _MarkLoaderState extends State<MarkLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.value == null && !_still(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final fixed = widget.value ?? (_still(context) ? MarkLoader.assembled : null);
    return RepaintBoundary(
      child: fixed != null
          ? CustomPaint(size: Size.square(widget.size), painter: MarkLoaderPainter(fixed, c.amber, c.bgBase))
          : AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(size: Size.square(widget.size), painter: MarkLoaderPainter(_c.value, c.amber, c.bgBase))),
    );
  }
}

class MarkLoaderPainter extends CustomPainter {
  MarkLoaderPainter(this.t, this.amber, this.bg);
  final double t; // фаза цикла 0..1
  final Color amber, bg;

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 64;
    canvas.save();
    canvas.scale(k);
    final ring = _kf(t, const [(0, 0), (.55, 1), (1, 1)], _ease);
    final ringOp = _kf(t, const [(0, 1), (.85, 1), (1, 0)], _ease);
    final tickBase = [for (final d in const [0.0, .05, .1, .15]) ((t - d / 2.4) % 1 + 1) % 1];
    final ticks = <(Offset, Offset, Offset)>[
      (const Offset(32, 4), const Offset(32, 15), const Offset(32, 10)),
      (const Offset(32, 60), const Offset(32, 49), const Offset(32, 54)),
      (const Offset(4, 32), const Offset(15, 32), const Offset(10, 32)),
      (const Offset(60, 32), const Offset(49, 32), const Offset(54, 32)),
    ];
    final holeS = _kf(t, const [(0, 0), (.4, 0), (.6, 1.25), (.72, 1), (.88, 1), (1, 1)]);
    final holeOp = _kf(t, const [(0, 0), (.4, 0), (.6, 1), (.72, 1), (.88, 1), (1, 0)]);

    void shapes(Paint Function(double a) p, {required bool gradient}) {
      // кольцо
      if (ring > 0 && ringOp > 0) {
        final paint = p(ringOp);
        if (gradient) {
          paint.shader = ui.Gradient.linear(const Offset(10, 10), const Offset(54, 54), [const Color(0xFFFFCF5A), const Color(0xFFFF9F0A)]);
        }
        canvas.drawArc(Rect.fromCircle(center: const Offset(32, 32), radius: 22), -math.pi / 2, 2 * math.pi * ring, false, paint);
      }
      // риски
      for (var i = 0; i < 4; i++) {
        final tt = tickBase[i];
        final op = _kf(tt, const [(0, 0), (.3, 0), (.55, 1), (.85, 1), (1, 0)]);
        final sc = _kf(tt, const [(0, .6), (.3, .6), (.55, 1), (1, 1)]);
        if (op <= 0) continue;
        final (a, b, o) = ticks[i];
        canvas.drawLine(o + (a - o) * sc, o + (b - o) * sc, p(op));
      }
      // яма
      if (holeS > 0 && holeOp > 0) {
        canvas.save();
        canvas.translate(32, 33);
        canvas.scale(holeS);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 20, height: 12), p(holeOp));
        canvas.restore();
      }
    }

    Paint stroke(double a, {double blur = 0}) => Paint()
      ..color = amber.withValues(alpha: a * (blur > 0 ? .55 : 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null;

    shapes((a) => stroke(a, blur: 5), gradient: false); // свечение
    shapes((a) => stroke(a), gradient: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarkLoaderPainter o) => o.t != t || o.amber != amber;
}

/// Мини-спиннер: вращающаяся дуга. [color] по умолчанию янтарный.
class MiniSpinner extends StatefulWidget {
  const MiniSpinner({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;
  @override
  State<MiniSpinner> createState() => _MiniSpinnerState();
}

class _MiniSpinnerState extends State<MiniSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.duration = Duration(milliseconds: _still(context) ? 3000 : 1100);
    if (!_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.hp.amber;
    return Semantics(
      label: 'loading',
      child: RepaintBoundary(
        child: RotationTransition(turns: _c, child: CustomPaint(size: Size.square(widget.size), painter: _SpinPainter(color))),
      ),
    );
  }
}

class _SpinPainter extends CustomPainter {
  _SpinPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 64;
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 5 * k..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: Offset(32 * k, 32 * k), radius: 22 * k), 0, 2 * math.pi * 44 / 138.2, false, p);
  }

  @override
  bool shouldRepaint(_SpinPainter o) => o.color != color;
}

/// Полоса со «сканером».
class ScanBar extends StatefulWidget {
  const ScanBar({super.key, this.width = 220});
  final double width;
  @override
  State<ScanBar> createState() => _ScanBarState();
}

class _ScanBarState extends State<ScanBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(size: Size(widget.width, 8), painter: _ScanPainter(_ease.transform(_c.value), c.amber, c.raised, _still(context))),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t, this.amber, this.track, this.still);
  final double t;
  final Color amber, track;
  final bool still;
  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(8));
    canvas.drawRRect(r, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(r);
    final w = still ? s.width : s.width * .45;
    final x = still ? 0.0 : -s.width * .45 + t * s.width * 1.485;
    final rect = Rect.fromLTWH(x, 0, w, s.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..shader = ui.Gradient.linear(rect.centerLeft, rect.centerRight, [amber.withValues(alpha: 0), amber.withValues(alpha: .6), amber], const [0.0, .6, 1.0]),
    );
    if (!still) {
      final lx = -s.width * .02 + t * s.width * 1.02;
      canvas.drawRect(Rect.fromLTWH(lx, -2, 2, s.height + 4), Paint()..color = Colors.white..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanPainter o) => o.t != t || o.amber != amber || o.track != track;
}

/// Три точки-ямы.
class DotsLoader extends StatefulWidget {
  const DotsLoader({super.key});
  @override
  State<DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<DotsLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final still = _still(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => SizedBox(
          width: 14 * 3 + 12 * 2 + 20,
          height: 28,
          child: CustomPaint(painter: _DotsPainter(_c.value, c.crater, still)),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.t, this.color, this.still);
  final double t;
  final Color color;
  final bool still;
  @override
  void paint(Canvas canvas, Size s) {
    for (var i = 0; i < 3; i++) {
      final ph = ((t - i * .2 / 1.2) % 1 + 1) % 1;
      final k = still ? 1.0 : (ph < .5 ? ui.lerpDouble(.5, 1.4, Curves.easeInOut.transform(ph * 2))! : ui.lerpDouble(1.4, .5, Curves.easeInOut.transform((ph - .5) * 2))!);
      final op = still ? 1.0 : (ph < .5 ? ui.lerpDouble(.3, 1, ph * 2)! : ui.lerpDouble(1, .3, (ph - .5) * 2)!);
      final cx = 17.0 + i * 26.0;
      final rect = Rect.fromCenter(center: Offset(cx, s.height / 2), width: 14 * k, height: 9 * k);
      canvas.drawOval(rect.inflate(4), Paint()..color = color.withValues(alpha: .5 * op)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawOval(rect, Paint()..color = color.withValues(alpha: op));
    }
  }

  @override
  bool shouldRepaint(_DotsPainter o) => o.t != t || o.color != color;
}

/// Заготовка-«скелетон»: блок с бегущим бликом.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 12, this.radius = 12});
  final double? width;
  final double height, radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final x = -1.0 + 2 * _c.value * 2; // блик бежит слева направо
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(begin: Alignment(x - 1, 0), end: Alignment(x + 1, 0), colors: [c.raised, c.line, c.raised], stops: const [.3, .5, .7]),
          ),
        );
      },
    );
  }
}

/// Скелетон карточки: иконка и строки (для списков, пока грузятся данные).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2});
  final int lines;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.line)),
      child: Column(spacing: 12, children: [
        Row(spacing: 12, children: [
          const Skeleton(width: 46, height: 46, radius: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Skeleton(height: 12), Skeleton(height: 10, width: 120)])),
        ]),
        for (var i = 0; i < lines; i++) Skeleton(height: 12, width: i.isOdd ? 220 : null),
      ]),
    );
  }
}

/// Загрузка списка: несколько карточек-скелетонов.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3});
  final int count;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'loading',
        child: Column(spacing: 12, children: [for (var i = 0; i < count; i++) SkeletonCard(lines: i == 0 ? 2 : 1)]),
      );
}

/// Точки-ямы с подписью («Ищем ямы рядом…»).
class DotsLabel extends StatelessWidget {
  const DotsLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [const DotsLoader(), Text(label, style: HpText.s(c.muted, 13, FontWeight.w500))])),
    );
  }
}

/// «Холи слушает»: расходящиеся круги и эквалайзер.
class HoliWave extends StatefulWidget {
  const HoliWave({super.key, this.size = 120});
  final double size;
  @override
  State<HoliWave> createState() => _HoliWaveState();
}

class _HoliWaveState extends State<HoliWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final still = _still(context);
    return RepaintBoundary(
      child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(size: Size.square(widget.size), painter: _HoliPainter(_c.value, c.amber, c.text, still))),
    );
  }
}

class _HoliPainter extends CustomPainter {
  _HoliPainter(this.t, this.amber, this.ink, this.still);
  final double t;
  final Color amber, ink;
  final bool still;
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 120;
    final o = Offset(s.width / 2, s.height / 2);
    if (!still) {
      for (var i = 0; i < 3; i++) {
        final ph = ((t - i * .7 / 2.2) % 1 + 1) % 1;
        final sc = ui.lerpDouble(.7, 1.6, Curves.easeOut.transform(ph))!;
        final op = ui.lerpDouble(.7, 0, ph)!;
        canvas.drawCircle(o, 60 * k * sc, Paint()..color = amber.withValues(alpha: op)..style = PaintingStyle.stroke..strokeWidth = 2 * k);
      }
    }
    canvas.drawCircle(o, 39.5 * k, Paint()..color = amber.withValues(alpha: .35)..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * k));
    canvas.drawCircle(o, 39.5 * k, Paint()..color = amber..style = PaintingStyle.stroke..strokeWidth = 5 * k);
    for (var i = 0; i < 5; i++) {
      final ph = ((t * 2.2 / 1.0 - i * .15) % 1 + 1) % 1; // период 1 с
      final h = still ? 24.0 : (ph < .5 ? ui.lerpDouble(10, 36, Curves.easeInOut.transform(ph * 2))! : ui.lerpDouble(36, 10, Curves.easeInOut.transform((ph - .5) * 2))!);
      final cx = o.dx + (i - 2) * 10 * k;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, o.dy), width: 5 * k, height: h * k), Radius.circular(3 * k)), Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_HoliPainter o) => o.t != t;
}
