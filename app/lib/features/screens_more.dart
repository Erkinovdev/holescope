import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/demo.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/l10n/app_localizations.dart';


// ───────────────────────── Выбор маршрута ─────────────────────────
class RouteChoiceScreen extends StatefulWidget {
  const RouteChoiceScreen({super.key});
  @override
  State<RouteChoiceScreen> createState() => _RouteChoiceScreenState();
}

class _RouteChoiceScreenState extends State<RouteChoiceScreen> {
  int sel = 1;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    Widget opt(int i, String name, String sub, int score, Color scoreColor) => HpCard(
          radius: 20,
          color: sel == i ? c.amberDim : c.surface,
          borderColor: sel == i ? c.amber : c.line,
          borderWidth: sel == i ? 2 : 1,
          onTap: () => setState(() => sel = i),
          child: Row(spacing: 14, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(name, style: HpText.s(c.text, 17, FontWeight.w600)),
                Text(sub, style: HpText.s(c.muted, 13, FontWeight.w400)),
              ]),
            ),
            Text('$score', style: HpText.s(scoreColor, 32, FontWeight.w700, ls: -0.48)),
          ]),
        );
    return HpPage(
      child: Column(children: [
        const SizedBox(
          height: 330,
          width: double.infinity,
          child: SchematicMap(route: true, pins: [(0.5462, 0.1545, PinKind.major), (0.6662, 0.5745, PinKind.major), (0.3462, 0.8545, PinKind.minor)]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(l.routeTitle, style: HpText.s(c.text, 20, FontWeight.w700, ls: -0.2)),
            const SizedBox(height: 12),
            const DemoBanner(),
            const SizedBox(height: 12),
            opt(0, l.routeFast, Demo.routeFast.$2, Demo.routeFast.$1, c.warnText),
            const SizedBox(height: 12),
            opt(1, l.routeSmooth, Demo.routeSmooth.$2, Demo.routeSmooth.$1, c.smoothText),
            const SizedBox(height: 12),
            HpButton(l.routeGo, onPressed: () => context.pop()),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Челленджи ─────────────────────────
class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    const tones = [Tone.amber, Tone.muted, Tone.minor];
    return HpPage(
      child: HpBody(children: [
        HpTitle(l.challengesTitle),
        HpSub(l.challengesSub),
        const DemoBanner(),
        HpCard(
          padding: 20,
          radius: 28,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Text('НЕДЕЛЯ: ЧИЛАНЗАР', style: HpText.s(c.amberText, 12, FontWeight.w600, ls: 1.44)),
            Text('Подтвердить ${Demo.challengeGoal} ям', style: HpText.s(c.text, 22, FontWeight.w700, ls: -0.22)),
            HpProgress(Demo.challengeDone / Demo.challengeGoal, c.amber),
            Text('${Demo.challengeDone} / ${Demo.challengeGoal} · осталось 3 дня', style: HpText.s(c.muted, 13, FontWeight.w400)),
          ]),
        ),
        Text(l.topDrivers, style: HpText.s(c.text, 18, FontWeight.w600)),
        for (var i = 0; i < Demo.topDrivers.length; i++)
          HpListItem(tone: tones[i], title: Demo.topDrivers[i].$1, subtitle: l.confirmationsWord, trailing: '${Demo.topDrivers[i].$2}'),
      ]),
    );
  }
}

