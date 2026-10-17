import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/demo.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/l10n/app_localizations.dart';

class _Fill extends StatelessWidget {
  const _Fill({required this.children, this.bottom = const []});
  final List<Widget> children, bottom;
  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [...children, const Spacer(), ...bottom]),
          ),
        ),
      ]);
}

Color _scoreColor(HpColors c, num v) => v >= 70 ? c.smoothText : v >= 60 ? c.amberText : v >= 45 ? c.warnText : c.craterText;
Color _scoreFill(HpColors c, num v) => v >= 70 ? c.smooth : v >= 60 ? c.amber : v >= 45 ? c.warn : c.crater;

// ───────────────────────── Жалоба ─────────────────────────
class ComplaintScreen extends StatelessWidget {
  const ComplaintScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return HpPage(
      child: _Fill(bottom: [
        HpButton(l.complaintSend, onPressed: () => context.pushReplacement('/complaint/status')),
      ], children: [
        const SizedBox(height: 4),
        HpTitle(l.complaintTitle),
        HpSub(l.complaintSub),
        HpListItem(tone: Tone.major, title: Demo.potholeStreet, subtitle: '${l.levelDeep} · ${l.driversCount(Demo.potholeDrivers)}', trailing: l.mValue('${Demo.potholeDistanceM}')),
        // TODO(этап 3): список ведомств — из справочника на сервере; названия здесь из макета.
        const Wrap(spacing: 8, runSpacing: 8, children: [HpChip('Xalq Nazorati', Tone.smooth), HpChip('Минтранс', Tone.minor)]),
        HpCard(
          padding: 18,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            Text(l.draft.toUpperCase(), style: HpText.s(c.amberText, 12, FontWeight.w600, ls: 1.44)),
            Text(l.complaintDraftText(Demo.potholeStreet, Demo.potholeDrivers, Demo.potholeDaysAgo), style: HpText.s(c.text, 14, FontWeight.w400, h: 20 / 14)),
          ]),
        ),
        HpDetails([(l.photo, l.optional, null), (l.anonymous, l.yes, null)]),
        const DemoBanner(),
      ]),
    );
  }
}

// ───────────────────────── Рейтинг улиц ─────────────────────────
class StreetsScreen extends StatefulWidget {
  const StreetsScreen({super.key});
  @override
  State<StreetsScreen> createState() => _StreetsScreenState();
}

class _StreetsScreenState extends State<StreetsScreen> {
  int seg = 0;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return HpBody(children: [
      HpTitle(l.streetsTitle),
      HpSub(l.streetsSub),
      HpSegmented(labels: [l.segCity, l.segDistrict], index: seg, onChanged: (i) => setState(() => seg = i)),
      const DemoBanner(),
      if (seg == 0)
        for (var i = 0; i < Demo.streets.length; i++)
          HpCard(
            child: Column(spacing: 8, children: [
              Row(spacing: 12, children: [
                Text('${i + 1}', style: HpText.s(c.muted, 18, FontWeight.w700)),
                Expanded(child: Text(Demo.streets[i].$1, style: HpText.s(c.text, 16, FontWeight.w600))),
                Text('${Demo.streets[i].$2}'.replaceAll('.', ','), style: HpText.s(Demo.streets[i].$2 >= 11 ? c.craterText : c.warnText, 16, FontWeight.w700)),
              ]),
              HpProgress(Demo.streets[i].$2 / 15.6, Demo.streets[i].$2 >= 11 ? c.crater : c.warn),
            ]),
          )
      else
        Text(l.todoBackend, style: HpText.s(c.muted, 14, FontWeight.w400)), // TODO: рейтинг по районам — нужны границы районов (этап 3)
    ]);
  }
}

// ───────────────────────── Статус жалобы ─────────────────────────
class ComplaintStatusScreen extends StatelessWidget {
  const ComplaintStatusScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    Widget step(Color dot, String t, String s, {bool last = false, bool todo = false}) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
            SizedBox(
              width: 20,
              child: Column(children: [
                Container(width: 20, height: 20, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 0), color: c.line)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(t, style: HpText.s(todo ? c.muted : c.text, 18, FontWeight.w600)),
                Text(s, style: HpText.s(c.muted, 14, FontWeight.w400)),
              ]),
            ),
          ]),
        );
    return HpPage(
      child: _Fill(bottom: [HpButton(l.shareChain, kind: HpButtonKind.secondary, onPressed: () {})], children: [
        const SizedBox(height: 4),
        HpTitle(l.statusChainTitle),
        HpSub(Demo.potholeStreet),
        step(c.smooth, l.stepFound, '${l.driversN(Demo.potholeDrivers)} · ${l.detectedDaysAgo(Demo.potholeDaysAgo)}'),
        step(c.smooth, l.stepFiled, 'Xalq Nazorati · ${Demo.complaintNumber}'),
        step(c.amber, l.stepReview, 'Ответ до 12 дней'), // TODO: срок ответа — из ответа ведомства
        step(c.muted, l.stepFixed, l.stepFixedWait, last: true, todo: true),
        const DemoBanner(),
      ]),
    );
  }
}

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

// ───────────────────────── Уведомления ─────────────────────────
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const tones = [Tone.smooth, Tone.major, Tone.amber, Tone.info];
    return HpPage(
      child: HpBody(children: [
        HpTitle(l.notifTitle),
        const DemoBanner(),
        for (final n in Demo.notifications) HpListItem(tone: tones[n.$1], title: n.$2, subtitle: n.$3, trailing: n.$4),
      ]),
    );
  }
}

// ───────────────────────── Дашборд города ─────────────────────────
class CityDashboardScreen extends StatelessWidget {
  const CityDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return HpPage(
      child: HpBody(children: [
        const HpTitle('Ташкент'),
        HpSub(l.cityQuality(l.monthOctober)),
        const DemoBanner(),
        HpCard(
          padding: 24,
          radius: 28,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
            Text('${Demo.cityScore}', style: HpText.s(c.amberText, 72, FontWeight.w700, ls: -2.88, h: 1.1)),
            Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('/ 100', style: HpText.s(c.muted, 20, FontWeight.w500))),
          ]),
        ),
        for (final d in Demo.districts)
          HpCard(
            child: Column(spacing: 8, children: [
              Row(children: [
                Expanded(child: Text(d.$1, style: HpText.s(c.text, 15, FontWeight.w600))),
                Text('${d.$2}', style: HpText.s(_scoreColor(c, d.$2), 16, FontWeight.w700)),
              ]),
              HpProgress(d.$2 / 100, _scoreFill(c, d.$2)),
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

// ───────────────────────── Отчёт недели ─────────────────────────
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    Widget box(int v, String t) => HpCard(
          padding: 20,
          child: Column(spacing: 2, children: [
            Text('$v', style: HpText.s(c.text, 28, FontWeight.w700)),
            Text(t, style: HpText.s(c.muted, 12, FontWeight.w500)),
          ]),
        );
    return HpPage(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 20, children: [
            const HpSvg('logo80', size: 80),
            Text(l.weeklyReport.toUpperCase(), style: HpText.s(c.amberText, 14, FontWeight.w600, ls: 1.68)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(l.weeklyFixedTitle(Demo.weeklyFixed), style: HpText.s(c.text, 72, FontWeight.w700, ls: -2.88))),
            SizedBox(width: 300, child: Text(l.weeklyFixedSub(Demo.weeklyFixed), textAlign: TextAlign.center, style: HpText.s(c.muted, 18, FontWeight.w400, h: 26 / 18))),
            Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [box(Demo.weeklyFound, l.weeklyFound), box(Demo.weeklyComplaints, l.weeklyComplaints)]),
            Text('Holescope · ${l.tagline}', textAlign: TextAlign.center, style: HpText.s(c.muted, 13, FontWeight.w500)),
            const DemoBanner(),
          ]),
        ),
      ),
    );
  }
}
