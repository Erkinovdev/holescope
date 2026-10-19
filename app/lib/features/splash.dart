
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/loaders.dart';
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

/// Заставка ~1.6 с: знак собирается (кольцо → риски → яма), под ним название и сканер; затем переход дальше.
class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this);
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    final reduce = ref.read(settingsProvider).reduceMotion || MediaQuery.disableAnimationsOf(context);
    ctl.duration = Duration(milliseconds: reduce ? 700 : 1600);
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
    final l = AppLocalizations.of(context);
    final reduce = ref.read(settingsProvider).reduceMotion || MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: c.bgBase,
      body: Semantics(
        label: l.appName,
        child: AnimatedBuilder(
          animation: ctl,
          builder: (_, __) {
            final t = Curves.easeOut.transform(ctl.value);
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, spacing: 22, children: [
                MarkLoader(size: 132, value: reduce ? MarkLoader.assembled : t * MarkLoader.assembled),
                Opacity(opacity: ((ctl.value - .35) / .3).clamp(0.0, 1.0), child: Text(l.appName, style: HpText.s(c.text, 34, FontWeight.w700, ls: -0.68))),
                Opacity(opacity: reduce ? 0 : ((ctl.value - .5) / .3).clamp(0.0, 1.0), child: const ScanBar(width: 180)),
              ]),
            );
          },
        ),
      ),
    );
  }
}
