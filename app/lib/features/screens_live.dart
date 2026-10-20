import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/demo.dart';
import 'package:holescope/core/loaders.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/l10n/app_localizations.dart';
import 'package:holescope/features/comfort.dart' show comfortScore;
import 'package:holescope/l10n/tr.dart';
import 'package:holescope/services/ahead_warner.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/data_providers.dart';
import 'package:holescope/services/permissions.dart';
import 'package:holescope/services/providers.dart';
import 'package:holescope/services/trip_recorder.dart';
import 'package:holescope/voice/holi_widgets.dart';

// Экраны, работающие с реальным состоянием приложения (датчики, очередь, сервер).

final permStateProvider = FutureProvider<PermState>((ref) => ref.watch(permissionServiceProvider).current());

String _two(int v) => v.toString().padLeft(2, '0');
String fmtDate(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${_two(d.day)}.${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';
}

String fmtKm(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

// ───────────────────────── Разрешения ─────────────────────────
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});
  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  PermState? result;
  bool busy = false;

  Future<void> _request() async {
    setState(() => busy = true);
    final svc = ref.read(permissionServiceProvider);
    final r = await svc.requestAll();
    if (!mounted) return;
    setState(() {
      result = r;
      busy = false;
    });
    if (r.canRecord) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboarded: true, autoRecord: true));
      ref.invalidate(permStateProvider);
      context.go('/map');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final r = result;
    Widget row(String t, String s, bool? ok) => HpCard(
          radius: 20,
          child: Row(spacing: 14, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: ok == false ? c.raised : c.amberDim, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: ok == true
                  ? Icon(Icons.check_rounded, size: 20, color: c.smoothText)
                  : Container(width: 12, height: 12, decoration: BoxDecoration(color: ok == false ? c.craterText : c.amber, shape: BoxShape.circle)),
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
        child: HpFill(top: 40, bottom: [
          if (r != null && !r.canRecord) ...[
            Text(l.permDenied, textAlign: TextAlign.center, style: HpText.s(c.craterText, 14, FontWeight.w500, h: 20 / 14)),
            if (r.permanentlyDenied) HpButton(l.openSettings, kind: HpButtonKind.secondary, onPressed: () => ref.read(permissionServiceProvider).openSettings()),
          ],
          HpButton(l.permCta, onPressed: busy ? null : _request),
        ], children: [
          Column(spacing: 16, children: [
            const HpSvg('logo', size: 96),
            Text(l.appName, style: HpText.s(c.text, 36, FontWeight.w700, ls: -0.72)),
          ]),
          Text(l.permLead, textAlign: TextAlign.center, style: HpText.s(c.muted, 16, FontWeight.w400, h: 24 / 16)),
          row(l.permMotionTitle, l.permMotionSub, r?.motion),
          row(l.permLocTitle, l.permLocSub, r == null ? null : (r.always || r.location)),
          row(l.permNotifTitle, l.permNotifSub, r?.notifications),
        ]),
      ),
    );
  }
}

// ───────────────────────── Поездка (Drive) ─────────────────────────
class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final s = ref.watch(recorderSnapshotProvider);
    final eng = ref.read(engineProvider);
    final driving = s.phase == RecorderPhase.driving;
    final armed = s.phase == RecorderPhase.armed;
    final status = driving ? l.driveRecording : (armed ? l.driveDetecting : (s.phase == RecorderPhase.idle ? l.manualStartHint : l.driveIdle));
    final tone = driving ? Tone.smooth : (armed ? Tone.amber : Tone.muted);
    final queue = ref.watch(queueSizeProvider);
    return HpFill(bottom: [
      if (queue > 0) Text(l.syncQueue(queue), textAlign: TextAlign.center, style: HpText.s(c.muted, 13, FontWeight.w400)),
      const HoliCallButton(),
      if (driving) HpButton(l.skipTrip, kind: HpButtonKind.secondary, onPressed: eng.skipTrip),
      HpButton(
        driving ? l.driveStop : l.driveStart,
        kind: driving ? HpButtonKind.danger : HpButtonKind.primary,
        onPressed: () async {
          if (driving) {
            final t = await eng.stopManual();
            if (context.mounted && t != null) context.push('/trip-summary');
          } else {
            eng.startManual();
          }
        },
      ),
    ], children: [
      Row(spacing: 10, children: [
        HpDot(tone, size: 12),
        Expanded(child: Text(status, style: HpText.s(c.muted, 14, FontWeight.w500))),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 40, bottom: 20),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text('${s.speedKmh.round()}', style: HpText.s(c.text, 160, FontWeight.w700, ls: -9.6, h: 1.1))),
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
              Text('${s.found}', style: HpText.s(c.amberText, 44, FontWeight.w700, ls: -0.88)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 2, children: [
            Text(l.driveDistance, style: HpText.s(c.muted, 13, FontWeight.w500)),
            Text(l.kmValue(fmtKm(s.distanceKm)), style: HpText.s(c.text, 24, FontWeight.w600)),
          ]),
        ]),
      ),
      const HoliPanel(),
    ]);
  }
}

// ───────────────────────── Предупреждение (HUD) ─────────────────────────
class WarningScreen extends ConsumerWidget {
  const WarningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final live = ref.watch(warningProvider);
    final snap = ref.watch(recorderSnapshotProvider);
    final isDemo = live == null;
    final item = live ?? const AheadItem(id: 0, distanceM: 80, side: 'right', level: 'deep', safeSpeed: 30, type: 'pothole', lat: 0, lon: 0);
    final speed = isDemo ? Demo.speedKmh : snap.speedKmh.round();
    // Текст на красном круге: белый (в Figma «muted» на красном имеет низкий контраст).
    const onRed = Color(0xFFFFFFFF);
    final level = switch (item.level) { 'light' => l.levelLight, 'mid' => l.levelMid, 'danger' => l.levelDanger, _ => l.levelDeep };
    final side = switch (item.side) { 'left' => l.sideLeft, 'right' => l.sideRight, _ => l.sideCenter };
    return HpPage(
      child: HpFill(top: 24, bottom: [
        if (item.safeSpeed != null && speed > item.safeSpeed!)
          // совет по скорости (Figma · Flow 17): сколько сейчас и до какой скорости сбросить перед ямой
          HpCard(
            padding: 20,
            radius: 24,
            child: Column(spacing: 10, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, spacing: 14, children: [
                Column(children: [Text('$speed', style: HpText.s(c.text, 52, FontWeight.w800, h: 1)), Text(context.tr('сейчас', 'hozir'), style: HpText.s(c.muted, 12, FontWeight.w500))]),
                Padding(padding: const EdgeInsets.only(bottom: 18), child: Icon(Icons.chevron_right_rounded, color: c.amber, size: 30)),
                Column(children: [Text('${item.safeSpeed}', style: HpText.s(c.smooth, 52, FontWeight.w800, h: 1)), Text(context.tr('цель', 'maqsad'), style: HpText.s(c.muted, 12, FontWeight.w500))]),
              ]),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (item.safeSpeed! / speed).clamp(0.0, 1.0), minHeight: 6, color: c.smooth, backgroundColor: c.raised)),
              Text(context.tr('Сбросьте скорость — подвеска скажет спасибо.', 'Tezlikni kamaytiring — osma rahmat aytadi.'), style: HpText.s(c.muted, 12, FontWeight.w500)),
            ]),
          )
        else
          HpCard(
            padding: 20,
            radius: 24,
            child: Row(children: [
              Expanded(child: Text(l.speedLabel, style: HpText.s(c.muted, 15, FontWeight.w500))),
              Text('$speed ${l.kmh}', style: HpText.s(c.text, 28, FontWeight.w700)),
            ]),
          ),
        HpButton(ref.watch(settingsProvider).voice ? l.muteSound : l.unmuteSound, kind: HpButtonKind.secondary, onPressed: () {
          ref.read(settingsProvider.notifier).update((s) => s.copyWith(voice: !s.voice, beep: !s.voice));
        }),
      ], children: [
        Align(alignment: Alignment.centerLeft, child: HpChip(l.warnAhead, Tone.major)),
        const SizedBox(height: 40),
        Center(
          child: Column(spacing: 12, children: [
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(color: c.crater, shape: BoxShape.circle, border: Border.all(color: c.crater, width: 6)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${item.distanceM}', style: HpText.s(onRed, 96, FontWeight.w700, ls: -3.84, h: 1.1)),
                Text(l.metersWord, style: HpText.s(onRed.withValues(alpha: 0.9), 18, FontWeight.w500)),
              ]),
            ),
            Text(l.warnSlowDown, style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.42)),
            Text(item.safeSpeed != null ? '${l.warnSideLine(level, side)} · ${item.safeSpeed} ${l.kmh}' : l.warnSideLine(level, side), style: HpText.s(c.muted, 16, FontWeight.w400)),
            if (isDemo) const DemoBanner(),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Итоги поездки ─────────────────────────
class TripSummaryScreen extends ConsumerWidget {
  const TripSummaryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final trips = ref.watch(tripsProvider);
    final t = trips.isEmpty ? null : trips.first;
    Widget stat(String v, String label) => Expanded(
          child: HpCard(
            padding: 16,
            child: Column(spacing: 2, children: [
              Text(v, style: HpText.s(c.amberText, 26, FontWeight.w700, ls: -0.26)),
              Text(label, style: HpText.s(c.muted, 12, FontWeight.w500), textAlign: TextAlign.center),
            ]),
          ),
        );
    final seg = <String, int>{
      for (final e in ((t?.summary['segments'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt(),
    };
    final segTotal = seg.values.fold<int>(0, (a, b) => a + b);
    final colors = {'A': c.smooth, 'B': c.smooth, 'C': c.amber, 'D': c.warn, 'E': c.crater};
    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.tripSummary),
        if (t == null)
          HpSub(l.questionsEmpty)
        else ...[
          HpSub(fmtDate(t.startedAt)),
          Row(spacing: 10, children: [
            stat(fmtKm(t.distanceKm), l.tripKm),
            stat('${t.potholes}', l.tripPotholes),
            stat(t.distanceKm > 0 ? fmtKm(t.potholes / t.distanceKm) : '0', l.tripPerKm),
          ]),
          if (comfortScore(seg) != null)
            HpCard(
              radius: 22,
              child: Row(spacing: 16, children: [
                SizedBox(width: 72, height: 72, child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: comfortScore(seg)! / 100, strokeWidth: 6, color: comfortScore(seg)! >= 70 ? c.smooth : (comfortScore(seg)! >= 45 ? c.amber : c.crater), backgroundColor: c.line),
                  Text('${comfortScore(seg)}', style: HpText.s(c.text, 22, FontWeight.w800)),
                ])),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(context.tr('Комфорт поездки', 'Safar qulayligi'), style: HpText.s(c.text, 16, FontWeight.w700)),
                  Text(context.tr('По ровности участков: A — 100, B — 85, C — 60, D — 30, E — 0.', 'Qismlar tekisligi boʻyicha: A — 100, B — 85, C — 60, D — 30, E — 0.'), style: HpText.s(c.muted, 12, FontWeight.w400, h: 1.3)),
                ])),
              ]),
            ),
          HpCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              Text(l.tripRoughness, style: HpText.s(c.muted, 13, FontWeight.w500)),
              Row(spacing: 6, children: [
                for (final k in const ['A', 'B', 'C', 'D', 'E'])
                  Expanded(
                    flex: math.max(1, segTotal == 0 ? 1 : seg[k] ?? 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: colors[k]!.withValues(alpha: (seg[k] ?? 0) == 0 ? 0.08 : 0.28), borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: Text(k, style: HpText.s(c.text, 14, FontWeight.w700)),
                    ),
                  ),
              ]),
              if (segTotal > 0)
                Text([for (final k in const ['A', 'B', 'C', 'D', 'E']) '$k ${((seg[k] ?? 0) * 100 / segTotal).round()}%'].join(' · '), style: HpText.s(c.muted, 12, FontWeight.w400)),
            ]),
          ),
        ],
        HpButton(l.questionTitle, kind: HpButtonKind.secondary, onPressed: () => context.push('/question')),
        HpButton(l.tripDone, onPressed: () => context.go('/map')),
      ]),
    );
  }
}

// ───────────────────────── История поездок ─────────────────────────
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final trips = ref.watch(tripsProvider);
    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.tripsHistory),
        if (trips.isEmpty) HpSub(l.manualStartHint),
        for (final t in trips)
          HpListItem(
            tone: t.status == 'sent' ? Tone.smooth : Tone.amber,
            title: fmtDate(t.startedAt),
            subtitle: '${l.kmValue(fmtKm(t.distanceKm))} · ${l.tripPotholes}: ${t.potholes}',
            trailing: t.status == 'sent' ? null : '…',
          ),
      ]),
    );
  }
}

// ───────────────────────── Вопрос «что это было?» ─────────────────────────
/// Показывается ТОЛЬКО на экране, который открывается после остановки поездки (нет ввода за рулём).
final questionsProvider = FutureProvider.autoDispose<List<QuestionDto>>((ref) async {
  final eng = ref.read(engineProvider);
  try {
    await eng.auth.ensureRegistered(eng.api);
    return await eng.api.questionsNext();
  } on ApiException {
    return const [];
  }
});

/// Справочник вариантов (с сервера); если нет связи — null, экран использует встроенные основные варианты.
final taxonomyProvider = FutureProvider.autoDispose<Taxonomy?>((ref) async {
  final eng = ref.read(engineProvider);
  try {
    return Taxonomy.fromJson(await eng.api.taxonomy());
  } catch (_) {
    return null;
  }
});

class Taxonomy {
  Taxonomy(this.items, this.groups);
  final Map<String, ({String ru, String uz, String group, String level})> items;
  final Map<String, ({String ru, String uz})> groups;
  factory Taxonomy.fromJson(Map<String, dynamic> j) => Taxonomy(
        {for (final i in j['items'] as List) (i as Map)['key'] as String: (ru: i['ru'] as String, uz: i['uz'] as String, group: i['group'] as String, level: (i['level'] as String?) ?? '')},
        {for (final e in (j['groups'] as Map).entries) e.key as String: (ru: (e.value as Map)['ru'] as String, uz: (e.value as Map)['uz'] as String)},
      );
}

class QuestionScreen extends ConsumerStatefulWidget {
  const QuestionScreen({super.key});
  @override
  ConsumerState<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends ConsumerState<QuestionScreen> {
  int idx = 0;
  bool more = false;

  Future<void> _answer(QuestionDto q, String a) async {
    final eng = ref.read(engineProvider);
    try {
      await eng.api.answerQuestion(q.id, a);
    } on ApiException {
      // не критично: вопрос останется открытым на сервере
    }
    if (!mounted) return;
    setState(() => idx++);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final qs = ref.watch(questionsProvider);
    final tax = ref.watch(taxonomyProvider).value;
    final isUz = Localizations.localeOf(context).languageCode == 'uz';
    final fallback = {
      'pothole_light': (l.optPotholeLight, Tone.minor),
      'pothole_mid': (l.optPotholeMid, Tone.minor),
      'pothole_deep': (l.optPotholeDeep, Tone.major),
      'bump': (l.optBump, Tone.smooth),
      'manhole': (l.optManhole, Tone.info),
      'rail': (l.optRail, Tone.amber),
    };
    String nameOf(String k) {
      final it = tax?.items[k];
      return it == null ? (fallback[k]?.$1 ?? k) : (isUz ? it.uz : it.ru);
    }

    Tone toneOf(String k) {
      final lv = tax?.items[k]?.level ?? '';
      return switch (lv) { 'danger' || 'deep' => Tone.major, 'mid' => Tone.minor, 'light' => Tone.amber, _ => fallback[k]?.$2 ?? Tone.info };
    }

    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.questionTitle),
        HpSub(l.questionSub),
        qs.when(
          loading: () => DotsLabel(l.loaderSearching),
          error: (_, __) => HpSub(l.questionsEmpty),
          data: (list) {
            if (idx >= list.length) return HpSub(l.questionsEmpty);
            final q = list[idx];
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
              HpCard(padding: 12, child: SizedBox(height: 120, child: CustomPaint(painter: WavePainter(q.wave, c.amber, c.line), size: Size.infinite))),
              Builder(builder: (context) {
                final opts = [for (final o in q.options) if (o != 'noise' && o != 'not_sure' && o != 'nothing') o];
                final main = opts.take(6).toList();
                final rest = opts.skip(6).toList();
                Widget card(String k) => SizedBox(
                      width: (MediaQuery.sizeOf(context).width - 50) / 2,
                      child: HpCard(
                        radius: 16,
                        border: true,
                        padding: 14,
                        onTap: () => _answer(q, k),
                        child: Row(spacing: 10, children: [HpDot(toneOf(k), size: 10), Expanded(child: Text(nameOf(k), style: HpText.s(c.text, 14, FontWeight.w600)))]),
                      ),
                    );
                final groups = <String, List<String>>{};
                for (final k in rest) {
                  groups.putIfAbsent(tax?.items[k]?.group ?? 'other', () => []).add(k);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                  Wrap(spacing: 10, runSpacing: 10, children: [for (final k in main) card(k)]),
                  if (rest.isNotEmpty) HpButton(more ? l.optLess : l.optMore, kind: HpButtonKind.secondary, onPressed: () => setState(() => more = !more)),
                  if (more)
                    for (final g in groups.entries) ...[
                      Text(isUz ? (tax?.groups[g.key]?.uz ?? g.key) : (tax?.groups[g.key]?.ru ?? g.key), style: HpText.s(c.muted, 13, FontWeight.w600)),
                      Wrap(spacing: 10, runSpacing: 10, children: [for (final k in g.value) card(k)]),
                    ],
                ]);
              }),
              HpButton(l.optNothing, kind: HpButtonKind.secondary, onPressed: () => _answer(q, 'nothing')),
              HpButton(l.optNotSure, kind: HpButtonKind.secondary, onPressed: () => _answer(q, 'not_sure')),
            ]);
          },
        ),
      ]),
    );
  }
}

/// Волна вертикальных ускорений события (с сервера: vz в окне ±2 с, каждый 2-й отсчёт).
class WavePainter extends CustomPainter {
  const WavePainter(this.wave, this.line, this.axis);
  final List<double> wave;
  final Color line, axis;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawLine(Offset(0, s.height / 2), Offset(s.width, s.height / 2), Paint()..color = axis);
    if (wave.length < 2) return;
    final peak = wave.fold<double>(1.0, (a, b) => math.max(a, b.abs()));
    final path = Path();
    for (var i = 0; i < wave.length; i++) {
      final p = Offset(i / (wave.length - 1) * s.width, s.height / 2 - wave[i] / peak * s.height * 0.45);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(WavePainter o) => o.wave != wave || o.line != line;
}

// ───────────────────────── Профиль ─────────────────────────
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final tot = ref.watch(totalsProvider);
    final nick = ref.watch(nicknameProvider);
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
        Text(nick ?? l.profileNoNick, style: HpText.s(c.text, 22, FontWeight.w700, ls: -0.22)),
        Text(l.profileAnon, style: HpText.s(c.muted, 13, FontWeight.w400)),
      ]),
      Row(spacing: 10, children: [
        stat('${tot.potholes}', l.statFound),
        stat(ref.watch(myStatsProvider).value?.confirmed.toString() ?? '—', l.statConfirmed),
        stat(fmtKm(tot.km), l.statKm),
      ]),
      HpListItem(tone: Tone.amber, title: l.myFinds, subtitle: l.myFindsSub(tot.potholes), onTap: () => context.push('/my-map')),
      HpListItem(tone: Tone.smooth, title: l.tripsHistory, subtitle: '${tot.trips}', onTap: () => context.push('/trips')),
      HpListItem(tone: Tone.info, title: l.vehicleTitle, subtitle: l.vehicleSuspension, onTap: () => context.push('/vehicle')),
      HpListItem(tone: Tone.minor, title: context.tr('Подвеска', 'Osma'), subtitle: context.tr('Ямы на ваших поездках за месяц', 'Oylik safarlaringizdagi choʻqqilar'), onTap: () => context.push('/suspension')),
      HpListItem(tone: Tone.smooth, title: context.tr('Команды «Холи»', 'Holi buyruqlari'), subtitle: context.tr('Что можно сказать вслух', 'Ovoz chiqarib nima deyish mumkin'), onTap: () => context.push('/commands')),
      Consumer(builder: (context, ref, _) {
        ref.watch(notesRevProvider);
        final n = ref.read(dbProvider).unreadNotes();
        return HpListItem(tone: Tone.amber, title: context.tr('Уведомления', 'Bildirishnomalar'), subtitle: n == 0 ? context.tr('Новых нет', 'Yangilari yoʻq') : context.tr('Новых: $n', 'Yangilari: $n'), onTap: () => context.push('/notifications'));
      }),
      HpListItem(tone: Tone.muted, title: l.settingsTitle, subtitle: l.settingsSub, onTap: () => context.push('/settings')),
    ]);
  }
}
