import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/demo.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/l10n/app_localizations.dart';

/// Экран, который заполняет высоту и прижимает [bottom] к низу (Figma: Spacer + кнопка).
class _FillScreen extends StatelessWidget {
  const _FillScreen({required this.children, required this.bottom, this.top = 24});
  final List<Widget> children;
  final List<Widget> bottom;
  final double top;
  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
              ...children,
              const Spacer(),
              ...bottom,
            ]),
          ),
        ),
      ]);
}

// ───────────────────────── Поездка (Drive) ─────────────────────────
/// Локальное состояние записи. TODO(этап 2): состояние из фонового сервиса и авто-старт/стоп (trip_state).
// ───────────────────────── Моя карта ─────────────────────────
class MyMapScreen extends StatelessWidget {
  const MyMapScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return HpPage(
      child: Column(children: [
        const SizedBox(
          height: 330,
          width: double.infinity,
          child: SchematicMap(route: true, pins: [
            (0.2662, 0.2745, PinKind.major),
            (0.5962, 0.1745, PinKind.minor),
            (0.6662, 0.5545, PinKind.major),
            (0.1662, 0.6745, PinKind.fixed),
            (0.3862, 0.8345, PinKind.minor),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(l.myFindsToday, style: HpText.s(c.text, 18, FontWeight.w600)),
            const SizedBox(height: 12),
            const DemoBanner(),
            const SizedBox(height: 12),
            for (final f in Demo.myFinds)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: HpListItem(tone: Tone.major, title: f.$1, subtitle: f.$2, trailing: f.$3, onTap: () => context.push('/pothole/1')),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Живая карта ─────────────────────────
class LiveMapScreen extends StatelessWidget {
  const LiveMapScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return Column(children: [
      Expanded(
        child: Stack(children: [
          const Positioned.fill(
            child: SchematicMap(pins: [
              (0.2662, 0.3077, PinKind.major),
              (0.4462, 0.4777, PinKind.minor),
              (0.1662, 0.7277, PinKind.fixed),
              (0.7462, 0.6477, PinKind.major),
            ], clusters: [
              (0.6815, 0.2169, 12),
              (0.1615, 0.1569, 5),
              (0.7815, 0.8369, 27),
            ]),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: HpCard(
              border: true,
              padding: 14,
              radius: 18,
              child: Row(spacing: 10, children: [
                HpSvg('search_icon', size: 22, tint: c.muted),
                Expanded(child: Text(l.searchHint, style: HpText.s(c.muted, 15, FontWeight.w400))),
                Semantics(
                  button: true,
                  label: 'notifications',
                  child: GestureDetector(onTap: () => context.push('/notifications'), child: Icon(Icons.notifications_none_rounded, color: c.muted, size: 22)),
                ),
              ]),
            ),
          ),
          const Positioned(left: 16, bottom: 8, child: DemoBanner()),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: HpListItem(tone: Tone.major, title: Demo.potholeStreet, subtitle: '${l.levelDeep} · ${l.driversCount(Demo.potholeDrivers)}', trailing: l.mValue('${Demo.potholeDistanceM}'), onTap: () => context.push('/pothole/1')),
      ),
    ]);
  }
}

// ───────────────────────── Карточка ямы ─────────────────────────
class PotholeScreen extends StatelessWidget {
  const PotholeScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return HpPage(
      child: _FillScreen(top: 20, bottom: [
        HpButton(l.potholeStillThere, onPressed: () => context.pop()),
        HpButton(l.potholeFixed, kind: HpButtonKind.secondary, onPressed: () => context.pop()),
      ], children: [
        const SizedBox(height: 160, child: SchematicMap(radius: 24, pins: [(0.5114, 0.4925, PinKind.major)])),
        Text(Demo.potholeStreet, style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.42)),
        HpSub(l.detectedDaysAgo(Demo.potholeDaysAgo)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          HpChip(l.levelDeepShort, Tone.major),
          HpChip(l.driversCount(Demo.potholeDrivers), Tone.smooth),
        ]),
        HpDetails([
          (l.confirmedLabel, l.driversN(Demo.potholeDrivers), null),
          (l.statusLabel, l.statusOpen, c.craterText),
          (l.complaintsFiled, '0', null),
          (l.distanceLabel, l.mValue('${Demo.potholeDistanceM}'), null),
        ]),
        const DemoBanner(),
      ]),
    );
  }
}

