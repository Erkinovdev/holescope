import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/demo.dart';
import 'package:holescope/core/settings.dart';
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

// ───────────────────────── Разрешения ─────────────────────────
class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    Widget row(String t, String s) => HpCard(
          radius: 20,
          child: Row(spacing: 14, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.amberDim, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Container(width: 12, height: 12, decoration: BoxDecoration(color: c.amber, shape: BoxShape.circle)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(t, style: HpText.s(c.text, 15, FontWeight.w600)),
                Text(s, style: HpText.s(c.muted, 13, FontWeight.w400)),
              ]),
            ),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: _FillScreen(top: 40, bottom: [
          HpButton(l.permCta, onPressed: () {
            // TODO(этап 2): запрос системных разрешений (permission_handler) до перехода.
            ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboarded: true));
            context.go('/map');
          }),
        ], children: [
          Column(spacing: 16, children: [
            const HpSvg('logo', size: 96),
            Text(l.appName, style: HpText.s(c.text, 36, FontWeight.w700, ls: -0.72)),
          ]),
          Text(l.permLead, textAlign: TextAlign.center, style: HpText.s(c.muted, 16, FontWeight.w400, h: 24 / 16)),
          row(l.permMotionTitle, l.permMotionSub),
          row(l.permLocTitle, l.permLocSub),
          row(l.permNotifTitle, l.permNotifSub),
        ]),
      ),
    );
  }
}

// ───────────────────────── Поездка (Drive) ─────────────────────────
/// Локальное состояние записи. TODO(этап 2): состояние из фонового сервиса и авто-старт/стоп (trip_state).
final recordingProvider = StateProvider<bool>((ref) => true);

class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final rec = ref.watch(recordingProvider);
    return _FillScreen(bottom: [
      HpButton(
        rec ? l.driveStop : l.driveStart,
        kind: rec ? HpButtonKind.danger : HpButtonKind.primary,
        onPressed: () {
          ref.read(recordingProvider.notifier).state = !rec;
          if (rec) context.push('/trip-summary');
        },
      ),
    ], children: [
      Row(spacing: 10, children: [
        HpDot(rec ? Tone.smooth : Tone.muted, size: 12),
        Expanded(child: Text(rec ? l.driveRecording : l.driveIdle, style: HpText.s(c.muted, 14, FontWeight.w500))),
      ]),
      const DemoBanner(),
      Padding(
        padding: const EdgeInsets.only(top: 40, bottom: 20),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(rec ? '${Demo.speedKmh}' : '0', style: HpText.s(c.text, 160, FontWeight.w700, ls: -9.6, h: 1.1))),
          Text(l.kmh, style: HpText.s(c.muted, 24, FontWeight.w500)),
        ]),
      ),
      HpCard(
        padding: 24,
        radius: 28,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(l.driveFound, style: HpText.s(c.muted, 13, FontWeight.w500)),
              Text(rec ? '${Demo.tripFound}' : '0', style: HpText.s(c.amberText, 44, FontWeight.w700, ls: -0.88)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 2, children: [
            Text(l.driveDistance, style: HpText.s(c.muted, 13, FontWeight.w500)),
            Text(l.kmValue(rec ? '7,2' : '0'), style: HpText.s(c.text, 24, FontWeight.w600)),
          ]),
        ]),
      ),
    ]);
  }
}

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

// ───────────────────────── Профиль ─────────────────────────
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    Widget stat(String v, String t) => Expanded(
          child: HpCard(
            padding: 16,
            child: Column(spacing: 2, children: [
              Text(v, style: HpText.s(c.amberText, 26, FontWeight.w700, ls: -0.26)),
              Text(t, style: HpText.s(c.muted, 12, FontWeight.w500)),
            ]),
          ),
        );
    return HpBody(children: [
      Column(spacing: 12, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: c.amber, width: 2)),
          alignment: Alignment.center,
          child: const HpSvg('logo52', size: 52),
        ),
        Text(Demo.profileName, style: HpText.s(c.text, 22, FontWeight.w700, ls: -0.22)),
        Text(l.profileAnon, style: HpText.s(c.muted, 13, FontWeight.w400)),
      ]),
      const DemoBanner(),
      Row(spacing: 10, children: [
        stat('${Demo.profileStats.$1}', l.statFound),
        stat('${Demo.profileStats.$2}', l.statConfirmed),
        stat('${Demo.profileStats.$3}', l.statKm),
      ]),
      Wrap(spacing: 8, runSpacing: 8, children: const [HpChip('Разведчик', Tone.smooth), HpChip('Ночной дозор', Tone.minor)]),
      HpListItem(tone: Tone.amber, title: l.myFinds, subtitle: l.myFindsSub(Demo.profileStats.$1), onTap: () => context.push('/my-map')),
      HpListItem(tone: Tone.muted, title: l.settingsTitle, subtitle: l.settingsSub, onTap: () => context.push('/settings')),
      HpListItem(tone: Tone.info, title: l.vehicleTitle, subtitle: l.vehicleSuspension, onTap: () => context.push('/vehicle')),
    ]);
  }
}

// ───────────────────────── Настройки ─────────────────────────
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _mountName(AppLocalizations l, PhoneMount m) => switch (m) { PhoneMount.seat => l.mountSeat, PhoneMount.cupholder => l.mountCupholder, PhoneMount.holder => l.mountHolder };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final sens = switch (s.sensitivity) { Sensitivity.low => l.sensLow, Sensitivity.mid => l.sensMid, Sensitivity.high => l.sensHigh };

    Future<T?> pick<T>(List<(String, T)> opts, T cur) => showModalBottomSheet<T>(
          context: context,
          builder: (_) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final o in opts)
                ListTile(
                  title: Text(o.$1, style: HpText.s(c.text, 16, FontWeight.w500)),
                  trailing: o.$2 == cur ? Icon(Icons.check_rounded, color: c.amberText) : null,
                  onTap: () => Navigator.pop(context, o.$2),
                ),
            ]),
          ),
        );

    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.settingsTitle),
        HpToggleRow(label: l.setVoice, value: s.voice, onChanged: (v) => n.update((x) => x.copyWith(voice: v))),
        HpToggleRow(label: l.setBeep, value: s.beep, onChanged: (v) => n.update((x) => x.copyWith(beep: v))),
        HpNavRow(
          label: l.setWarnDistance(s.warnDistanceM),
          onTap: () async {
            final v = await pick<int>([for (final d in [100, 150, 200, 250, 300]) (l.mValue('$d'), d)], s.warnDistanceM);
            if (v != null) n.update((x) => x.copyWith(warnDistanceM: v));
          },
        ),
        HpNavRow(
          label: l.setSensitivity(sens),
          onTap: () async {
            final v = await pick<Sensitivity>([(l.sensLow, Sensitivity.low), (l.sensMid, Sensitivity.mid), (l.sensHigh, Sensitivity.high)], s.sensitivity);
            if (v != null) n.update((x) => x.copyWith(sensitivity: v));
          },
        ),
        HpNavRow(label: l.setCarMount(s.carName ?? l.vehicleNotSet, _mountName(l, s.mount)), onTap: () => context.push('/vehicle')),
        HpNavRow(label: l.mountTitle, value: _mountName(l, s.mount), onTap: () => context.push('/mount')),
        HpNavRow(label: l.roleTitle, value: s.role == DeviceRole.driver ? l.roleDriver : l.rolePassenger, onTap: () => context.push('/role')),
        HpNavRow(
          label: l.setLanguage,
          value: switch (s.locale?.languageCode) { 'ru' => 'Русский', 'uz' => 'Oʻzbekcha', _ => l.langSystem },
          onTap: () async {
            final v = await pick<String>([(l.langSystem, ''), ('Русский', 'ru'), ('Oʻzbekcha', 'uz')], s.locale?.languageCode ?? '');
            if (v != null) n.update((x) => x.copyWith(locale: v.isEmpty ? null : Locale(v)));
          },
        ),
        HpNavRow(
          label: l.setTheme,
          value: switch (s.themeMode) { ThemeMode.system => l.themeSystem, ThemeMode.dark => l.themeDark, ThemeMode.light => l.themeLight },
          onTap: () async {
            final v = await pick<ThemeMode>([(l.themeSystem, ThemeMode.system), (l.themeDark, ThemeMode.dark), (l.themeLight, ThemeMode.light)], s.themeMode);
            if (v != null) n.update((x) => x.copyWith(themeMode: v));
          },
        ),
        HpToggleRow(label: l.setReduceMotion, value: s.reduceMotion, onChanged: (v) => n.update((x) => x.copyWith(reduceMotion: v))),
        Text(l.setHint, style: HpText.s(c.muted, 13, FontWeight.w400, h: 18 / 13)),
        if (kDebugMode) ...[
          const SizedBox(height: 8),
          Text('DEBUG · экраны', style: HpText.s(c.amberText, 12, FontWeight.w600, ls: 1.44)),
          for (final r in const [
            ('/splash', 'Загрузка'), ('/permissions', 'Разрешения'), ('/warning', 'Предупреждение'), ('/complaint', 'Жалоба'),
            ('/complaint/status', 'Статус жалобы'), ('/route', 'Выбор маршрута'), ('/notifications', 'Уведомления'), ('/city', 'Дашборд города'),
            ('/challenges', 'Челленджи'), ('/weekly', 'Отчёт недели'), ('/question', 'Вопрос'), ('/trip-summary', 'Итоги поездки'),
          ])
            HpNavRow(label: r.$2, onTap: () => context.push(r.$1)),
        ],
      ]),
    );
  }
}
