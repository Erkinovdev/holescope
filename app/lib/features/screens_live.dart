import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/demo.dart';
import 'package:holescope/core/loaders.dart';
import 'package:holescope/core/road_map.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/l10n/app_localizations.dart';
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
class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({super.key});
  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen> {
  final map = RoadMapController();
  bool centered = false;

  @override
  void dispose() {
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final s = ref.watch(recorderSnapshotProvider);
    final eng = ref.read(engineProvider);
    final warn = ref.watch(warningProvider);
    final driving = s.phase == RecorderPhase.driving;
    final armed = s.phase == RecorderPhase.armed;
    final status = driving ? l.driveRecording : (armed ? l.driveDetecting : (s.phase == RecorderPhase.idle ? l.manualStartHint : l.driveIdle));
    final queue = ref.watch(queueSizeProvider);
    if (s.lat != null && s.lon != null) {
      map.setMe(s.lat, s.lon, s.heading);
      if (!centered || driving) {
        final first = !centered;
        centered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => map.moveTo(s.lat!, s.lon!, mpp: first ? 2.4 : null));
      }
    }
    final side = switch (warn?.side) { 'left' => l.sideLeft, 'right' => l.sideRight, _ => '' };
    final level = switch (warn?.level) { 'light' => l.levelLight, 'mid' => l.levelMid, 'danger' => l.levelDanger, _ => l.levelDeep };
    final warnTitle = switch (warn?.type) { 'bump' => context.tr('Лежачий', 'Yotiq'), 'manhole' => context.tr('Люк', 'Lyuk'), 'rail_tram' || 'rail_train' => context.tr('Рельсы', 'Relslar'), _ => context.tr('Яма', 'Choʻqqi') };
    return Stack(children: [
      Positioned.fill(child: RoadMapView(controller: map, onClusterTap: (cl) => context.push('/pothole/${cl.id}'))),
      Positioned(
        left: 16,
        right: 16,
        top: 12,
        child: SafeArea(
          bottom: false,
          child: warn != null
              ? Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 12),
                  decoration: BoxDecoration(color: Color.alphaBlend(c.crater.withValues(alpha: 0.2), c.surface), borderRadius: BorderRadius.circular(24), border: Border.all(color: c.crater.withValues(alpha: 0.75), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18)]),
                  child: Column(spacing: 10, children: [
                    Row(spacing: 14, children: [
                      Container(width: 56, height: 56, decoration: BoxDecoration(color: c.crater, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32)),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                        Text('$warnTitle ${context.tr('через', 'dan keyin')} ${warn.distanceM} ${l.metersWord}', style: HpText.s(c.text, 19, FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('$level${side.isEmpty ? '' : ' · $side'}${warn.safeSpeed != null ? ' · ${context.tr('до', 'gacha')} ${warn.safeSpeed} ${l.kmh}' : ''}', style: HpText.s(c.muted, 14, FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      Column(mainAxisSize: MainAxisSize.min, children: [Text('${warn.distanceM}', style: HpText.s(c.crater, 34, FontWeight.w800, h: 1)), Text(l.metersWord, style: HpText.s(c.muted, 12, FontWeight.w600))]),
                    ]),
                    ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (1 - warn.distanceM / 150).clamp(0.05, 1.0), minHeight: 5, color: c.crater, backgroundColor: c.crater.withValues(alpha: 0.18))),
                  ]),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(color: c.surface.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [HpDot(driving ? Tone.smooth : (armed ? Tone.amber : Tone.muted), size: 10), Flexible(child: Text(status, style: HpText.s(c.text, 13, FontWeight.w600), overflow: TextOverflow.ellipsis))]),
                  ),
                ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.bgBase.withValues(alpha: 0), c.bgBase.withValues(alpha: 0.92)], stops: const [0, 0.35]),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: c.line), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)]),
              child: Row(spacing: 20, children: [
                SizedBox(
                  width: 128,
                  height: 128,
                  child: CustomPaint(
                    painter: _SpeedRing(s.speedKmh / 120, c.amber, c.line),
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('${s.speedKmh.round()}', style: HpText.s(c.text, 44, FontWeight.w800, ls: -1.5, h: 1)), Text(l.kmh, style: HpText.s(c.muted, 13, FontWeight.w500))])),
                  ),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                    for (final r in [(context.tr('Ям на пути', 'Yoʻldagi choʻqqilar'), '${s.found}', s.found > 0 ? c.crater : c.text), (context.tr('Пройдено', 'Bosib oʻtilgan'), l.kmValue(fmtKm(s.distanceKm)), c.text)])
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.$1, style: HpText.s(c.muted, 12, FontWeight.w500)), Text(r.$2, style: HpText.s(r.$3, 24, FontWeight.w800, h: 1.15))]),
                    if (queue > 0) Text(l.syncQueue(queue), style: HpText.s(c.muted, 12, FontWeight.w400)),
                  ]),
                ),
              ]),
            ),
            const HoliPanel(),
            Row(spacing: 10, children: [
              const Expanded(child: HoliCallButton()),
              if (driving) Expanded(child: HpButton(l.skipTrip, kind: HpButtonKind.secondary, onPressed: eng.skipTrip)),
            ]),
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
          ]),
        ),
      ),
    ]);
  }
}

/// Кольцо скорости: янтарная дуга от 0 до 120 км/ч на тёмной окружности.
class _SpeedRing extends CustomPainter {
  _SpeedRing(this.v, this.color, this.track);
  final double v;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 8);
    const start = -math.pi * 0.5, sweep = math.pi * 2;
    canvas.drawArc(r, start, sweep, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = 12);
    canvas.drawArc(r, start, sweep * v.clamp(0.0, 1.0), false, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SpeedRing o) => o.v != v || o.color != color;
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
  String? type; // pothole | bump | manhole | rail | rough | unknown
  String depth = 'mid'; // light | mid | deep
  bool sending = false;

  Future<void> _answer(QuestionDto q, String a) async {
    final eng = ref.read(engineProvider);
    setState(() => sending = true);
    try {
      await eng.api.answerQuestion(q.id, a);
    } on ApiException {
      // не критично: вопрос останется открытым на сервере
    }
    if (!mounted) return;
    setState(() {
      idx++;
      type = null;
      depth = 'mid';
      more = false;
      sending = false;
    });
  }

  /// Ответ для сервера из выбранного типа и глубины.
  String _key() => switch (type) {
        'pothole' => 'pothole_$depth',
        'bump' => 'bump',
        'manhole' => 'manhole',
        'rail' => 'rail_tram',
        'rough' => 'washboard',
        _ => 'not_sure',
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final qs = ref.watch(questionsProvider);
    final tax = ref.watch(taxonomyProvider).value;
    final isUz = Localizations.localeOf(context).languageCode == 'uz';
    String nameOf(String k) {
      final it = tax?.items[k];
      return it == null ? k : (isUz ? it.uz : it.ru);
    }

    final tiles = <(String, String, IconData, Color)>[
      ('pothole', context.tr('Яма', 'Choʻqqi'), Icons.trip_origin_rounded, c.amber),
      ('bump', context.tr('Лежачий', 'Yotiq'), Icons.show_chart_rounded, c.warn),
      ('manhole', context.tr('Люк', 'Lyuk'), Icons.circle_outlined, c.info),
      ('rail', context.tr('Рельсы', 'Relslar'), Icons.train_outlined, c.amber),
      ('rough', context.tr('Неровность', 'Notekislik'), Icons.waves_rounded, c.smooth),
      ('unknown', context.tr('Не знаю', 'Bilmayman'), Icons.help_outline_rounded, c.muted),
    ];
    return HpPage(
      child: HpBody(top: 20, children: [
        Text(l.questionTitle, style: HpText.s(c.text, 30, FontWeight.w800, ls: -0.6)),
        qs.when(
          loading: () => DotsLabel(l.loaderSearching),
          error: (_, __) => HpSub(l.questionsEmpty),
          data: (list) {
            if (idx >= list.length) return HpSub(l.questionsEmpty);
            final q = list[idx];
            final tileW = (MediaQuery.sizeOf(context).width - 50) / 2;
            Widget tile((String, String, IconData, Color) t) {
              final on = type == t.$1;
              return SizedBox(
                width: tileW,
                child: Material(
                  color: on ? t.$4.withValues(alpha: 0.14) : c.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: on ? t.$4 : c.line, width: on ? 2 : 1)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => type = t.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      child: Row(spacing: 12, children: [Icon(t.$3, color: t.$4, size: 24), Expanded(child: Text(t.$2, style: HpText.s(c.text, 16, FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                    ),
                  ),
                ),
              );
            }

            final opts = [for (final o in q.options) if (o != 'noise' && o != 'not_sure' && o != 'nothing') o];
            final groups = <String, List<String>>{};
            for (final k in opts) {
              groups.putIfAbsent(tax?.items[k]?.group ?? 'other', () => []).add(k);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
              Text('${context.tr('Удар', 'Zarba')} · ${q.speedKmh.round()} ${l.kmh}', style: HpText.s(c.muted, 14, FontWeight.w500)),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.line)),
                child: Column(spacing: 6, children: [
                  SizedBox(height: 108, child: CustomPaint(painter: WavePainter(q.wave, c.amber, c.line), size: Size.infinite)),
                  Row(children: [
                    Text('−1,5 ${context.tr('с', 's')}', style: HpText.s(c.muted, 12, FontWeight.w500)),
                    const Spacer(),
                    Text(context.tr('удар', 'zarba'), style: HpText.s(c.amberText, 12, FontWeight.w700)),
                    const Spacer(),
                    Text('+1,5 ${context.tr('с', 's')}', style: HpText.s(c.muted, 12, FontWeight.w500)),
                  ]),
                ]),
              ),
              Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) tile(t)]),
              if (type == 'pothole') ...[
                Text(context.tr('Глубина', 'Chuqurlik'), style: HpText.s(c.muted, 14, FontWeight.w600)),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
                  child: Row(children: [
                    for (final d in [('light', context.tr('Лёгкая', 'Yengil')), ('mid', context.tr('Средняя', 'Oʻrtacha')), ('deep', context.tr('Глубокая', 'Chuqur'))])
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => depth = d.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(color: depth == d.$1 ? c.amber : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                            alignment: Alignment.center,
                            child: Text(d.$2, style: HpText.s(depth == d.$1 ? c.inverse : c.muted, 15, FontWeight.w700)),
                          ),
                        ),
                      ),
                  ]),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                child: Row(spacing: 12, children: [
                  Icon(Icons.lock_outline_rounded, color: c.info, size: 22),
                  Expanded(child: Text(context.tr('Ответ доступен, когда машина стоит. За рулём вопросы не показываем.', 'Javob mashina turganda mavjud. Rul ortida savollarni koʻrsatmaymiz.'), style: HpText.s(c.text, 13, FontWeight.w500, h: 1.35))),
                ]),
              ),
              HpButton(context.tr('Отправить', 'Yuborish'), loading: sending, onPressed: type == null ? null : () => _answer(q, _key())),
              Row(children: [
                Expanded(child: TextButton(onPressed: () => _answer(q, 'nothing'), child: Text(l.optNothing, style: HpText.s(c.muted, 14, FontWeight.w600)))),
                Expanded(child: TextButton(onPressed: () => setState(() => more = !more), child: Text(more ? l.optLess : context.tr('Другой вариант', 'Boshqa variant'), style: HpText.s(c.amberText, 14, FontWeight.w700)))),
              ]),
              if (more)
                for (final g in groups.entries) ...[
                  Text(isUz ? (tax?.groups[g.key]?.uz ?? g.key) : (tax?.groups[g.key]?.ru ?? g.key), style: HpText.s(c.muted, 13, FontWeight.w600)),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final k in g.value)
                      SizedBox(width: tileW, child: HpCard(radius: 16, border: true, padding: 14, onTap: () => _answer(q, k), child: Text(nameOf(k), style: HpText.s(c.text, 14, FontWeight.w600)))),
                  ]),
                ],
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

  /// Уровень водителя по пройденным километрам: название и порог следующего уровня.
  (String, String, double) _level(BuildContext context, double km) {
    if (km < 50) return (context.tr('Новичок', 'Yangi'), context.tr('Водитель', 'Haydovchi'), 50);
    if (km < 300) return (context.tr('Водитель', 'Haydovchi'), context.tr('Следопыт', 'Izquvar'), 300);
    if (km < 1000) return (context.tr('Следопыт', 'Izquvar'), context.tr('Мастер дорог', 'Yoʻl ustasi'), 1000);
    return (context.tr('Мастер дорог', 'Yoʻl ustasi'), '', 1000);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final tot = ref.watch(totalsProvider);
    final nick = ref.watch(nicknameProvider);
    final s = ref.watch(settingsProvider);
    final confirmed = ref.watch(myStatsProvider).value?.confirmed;
    final (lvl, next, goal) = _level(context, tot.km);
    Widget stat(String v, String t, Color col) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: HpText.s(col, 30, FontWeight.w800, ls: -0.6))),
              Text(t, style: HpText.s(c.muted, 13, FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
    Widget group(String title, List<Widget> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Padding(padding: const EdgeInsets.only(left: 4), child: Text(title, style: HpText.s(c.muted, 13, FontWeight.w700, ls: 0.4))),
          Container(
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.line)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 70, color: c.line),
                rows[i],
              ],
            ]),
          ),
        ]);
    Widget row(IconData icon, Color col, String title, String sub, VoidCallback onTap, {String? badge}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(spacing: 14, children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: col, size: 22)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(title, style: HpText.s(c.text, 16, FontWeight.w600)),
                Text(sub, style: HpText.s(c.muted, 13, FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (badge != null) Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: c.amber, borderRadius: BorderRadius.circular(999)), child: Text(badge, style: HpText.s(c.inverse, 12, FontWeight.w800))),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ]),
          ),
        );
    return HpBody(top: 12, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.line),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.amberDim, c.surface]),
        ),
        child: Column(spacing: 16, children: [
          Row(spacing: 16, children: [
            Container(width: 72, height: 72, decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: c.amber, width: 2)), alignment: Alignment.center, child: const HpSvg('logo52', size: 40)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(nick ?? l.profileNoNick, style: HpText.s(c.text, 22, FontWeight.w800, ls: -0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(s.carName ?? context.tr('Автомобиль не указан', 'Avtomobil koʻrsatilmagan'), style: HpText.s(c.muted, 14, FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Row(children: [
              Text(lvl, style: HpText.s(c.amberText, 14, FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(child: Text(next.isEmpty ? context.tr('Максимальный уровень', 'Eng yuqori daraja') : '${fmtKm(tot.km)} / ${goal.round()} ${context.tr('км до', 'km gacha')} «$next»', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: HpText.s(c.muted, 12, FontWeight.w500))),
            ]),
            HpProgress(next.isEmpty ? 1.0 : (tot.km / goal).clamp(0.0, 1.0), c.amber),
          ]),
        ]),
      ),
      Row(spacing: 10, children: [
        stat('${tot.potholes}', context.tr('Находок', 'Topilmalar'), c.crater),
        stat(confirmed?.toString() ?? '—', l.statConfirmed, c.smooth),
        stat(fmtKm(tot.km), l.statKm, c.amberText),
      ]),
      group(context.tr('МОИ ДАННЫЕ', 'MENING MAʼLUMOTLARIM'), [
        row(Icons.place_outlined, c.crater, l.myFinds, l.myFindsSub(tot.potholes), () => context.push('/my-map')),
        row(Icons.route_outlined, c.smooth, l.tripsHistory, '${tot.trips} ${context.tr('поездок', 'safar')}', () => context.push('/trips')),
        row(Icons.directions_car_outlined, c.info, l.vehicleTitle, s.carName ?? l.vehicleSuspension, () => context.push('/vehicle')),
        row(Icons.compare_arrows_rounded, c.warn, context.tr('Подвеска', 'Osma'), context.tr('Удары на ваших поездках за месяц', 'Oylik safarlardagi zarbalar'), () => context.push('/suspension')),
      ]),
      group(context.tr('ПОМОЩНИК', 'YORDAMCHI'), [
        row(Icons.mic_none_rounded, c.smooth, context.tr('Команды «Холи»', 'Holi buyruqlari'), context.tr('Что можно сказать вслух', 'Ovoz chiqarib nima deyish mumkin'), () => context.push('/commands')),
        Consumer(builder: (context, ref, _) {
          ref.watch(notesRevProvider);
          final n = ref.read(dbProvider).unreadNotes();
          return row(Icons.notifications_none_rounded, c.amber, context.tr('Уведомления', 'Bildirishnomalar'), n == 0 ? context.tr('Новых нет', 'Yangilari yoʻq') : context.tr('Новых: $n', 'Yangilari: $n'), () => context.push('/notifications'), badge: n == 0 ? null : '$n');
        }),
      ]),
      group(context.tr('ПРИЛОЖЕНИЕ', 'ILOVA'), [
        row(Icons.settings_outlined, c.muted, l.settingsTitle, l.settingsSub, () => context.push('/settings')),
      ]),
    ]);
  }
}
