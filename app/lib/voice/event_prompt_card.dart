// ignore_for_file: sort_child_properties_last
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../algo/taxonomy_data.dart';
import '../core/loaders.dart';
import '../core/nav.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../l10n/tr.dart';
import '../services/config.dart';
import '../services/providers.dart';
import '../services/trip_recorder.dart';
import 'event_ui.dart';
import 'holi_controller.dart';

/// Окно «Что это было?» поверх любого экрана (Figma · Flow 8): кольцо-таймер, крупные кнопки, глубина после «Яма»,
/// «Принято, спасибо!». Окно исчезает само; не успели — вопрос ждёт в очереди до остановки.
class EventPromptOverlay extends ConsumerWidget {
  const EventPromptOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(holiControllerProvider).value;
    return Stack(children: [
      if (ctrl != null)
        ValueListenableBuilder<HoliUi>(
          valueListenable: ctrl.ui,
          builder: (context, ui, _) {
            final pr = ui.prompt;
            if (pr == null) return const SizedBox.shrink();
            final wide = MediaQuery.sizeOf(context).aspectRatio > 1.6;
            return SafeArea(
              child: Align(
                alignment: wide ? Alignment.bottomRight : Alignment.bottomCenter,
                child: Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, wide ? 12 : 84), child: _Card(ctrl: ctrl, ui: ui, pr: pr)),
              ),
            );
          },
        ),
      const _PendingPill(),
      const _BannerHost(),
    ]);
  }
}

String itemName(String key, bool uz) {
  final it = taxItem(key);
  if (it == null) return key;
  return uz ? it.uz : it.ru;
}

String groupLabel(BuildContext c, EvGroup g) => switch (g) {
      EvGroup.pothole => c.tr('Яма', 'Choʻqqi'),
      EvGroup.bump => c.tr('Лежачий', 'Yotiq'),
      EvGroup.manhole => c.tr('Люк', 'Lyuk'),
      EvGroup.rails => c.tr('Рельсы', 'Relslar'),
      EvGroup.uneven => c.tr('Ухаб', 'Gʻadir-budur'),
      EvGroup.unknown => c.tr('Не знаю', 'Bilmayman'),
    };

IconData groupIcon(EvGroup g) => switch (g) {
      EvGroup.pothole => Icons.panorama_fish_eye_rounded,
      EvGroup.bump => Icons.landscape_rounded,
      EvGroup.manhole => Icons.adjust_rounded,
      EvGroup.rails => Icons.drag_indicator_rounded,
      EvGroup.uneven => Icons.waves_rounded,
      EvGroup.unknown => Icons.info_outline_rounded,
    };

Color groupColor(HpColors c, EvGroup g) => switch (g) {
      EvGroup.pothole => c.crater,
      EvGroup.bump => c.warn,
      EvGroup.manhole => c.info,
      EvGroup.rails => c.amber,
      EvGroup.uneven => c.smooth,
      EvGroup.unknown => c.muted,
    };

String depthLabel(BuildContext c, String key) => switch (key) {
      'pothole_light' => c.tr('Лёгкая', 'Yengil'),
      'pothole_mid' => c.tr('Средняя', 'Oʻrtacha'),
      _ => c.tr('Глубокая', 'Chuqur'),
    };

class _Card extends StatefulWidget {
  const _Card({required this.ctrl, required this.ui, required this.pr});
  final HoliController ctrl;
  final HoliUi ui;
  final EventPrompt pr;
  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final pr = widget.pr;
    final ctrl = widget.ctrl;
    final total = math.max(1, pr.deadline.difference(pr.startedAt).inMilliseconds);
    final left = math.max(0, pr.deadline.difference(DateTime.now()).inMilliseconds);
    final frac = (left / total).clamp(0.0, 1.0);
    final elapsed = 1 - frac;
    final secs = (left / 1000).ceil();
    final urgent = !pr.answered && left <= 3000;
    final ring = pr.answered ? c.smooth : (elapsed < 0.5 ? c.amber : (elapsed < 0.85 ? c.warn : c.crater));
    final f = pr.cand.features;
    final listening = widget.ui.status == HoliStatus.listening;
    final wide = MediaQuery.sizeOf(context).aspectRatio > 1.6;
    final big = AppConfig.carMonitor || wide;

    Widget body;
    if (pr.answered) {
      final unknown = pr.chosen == 'unknown';
      body = Column(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: c.smooth.withValues(alpha: .15), shape: BoxShape.circle), child: Icon(Icons.check_rounded, color: c.smooth, size: 30)),
        Text(context.tr('Принято, спасибо!', 'Qabul qilindi, rahmat!'), style: HpText.s(c.text, 20, FontWeight.w800)),
        Text(unknown ? context.tr('Не знаю — тоже ответ', 'Bilmayman — bu ham javob') : '${itemName(pr.chosen!, context.isUz)} · ${pr.via == 'voice' ? context.tr('голосом', 'ovoz bilan') : context.tr('нажатием', 'teginish bilan')}', textAlign: TextAlign.center, style: HpText.s(c.muted, 13, FontWeight.w500)),
      ]);
    } else if (urgent) {
      body = Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
        Row(spacing: 10, children: [
          Expanded(flex: 3, child: _Big(label: context.tr('Яма', 'Choʻqqi'), icon: Icons.panorama_fish_eye_rounded, color: c.crater, filled: true, big: true, onTap: () => ctrl.selectOption(pr.guess.top.startsWith('pothole') ? pr.guess.top : 'pothole_mid'))),
          Expanded(flex: 2, child: _Big(label: context.tr('Не знаю', 'Bilmayman'), icon: Icons.info_outline_rounded, color: c.muted, big: true, onTap: () => ctrl.pickGroup(EvGroup.unknown))),
        ]),
        Text(context.tr('Окно исчезнет через $secs с — вопрос уйдёт в очередь', 'Oyna $secs s dan keyin yoʻqoladi — savol navbatga oʻtadi'), style: HpText.s(c.muted, 12, FontWeight.w500)),
      ]);
    } else {
      final groups = groupsFor(pr.guess);
      final depth = pr.depthStage ? depthKeys(pr.guess) : const <String>[];
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        LayoutBuilder(builder: (context, box) {
          final cols = big && box.maxWidth > 420 ? 3 : 2;
          final w = (box.maxWidth - (cols - 1) * 8) / cols;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in groups)
              SizedBox(
                width: w,
                child: _Big(
                  label: groupLabel(context, g),
                  icon: groupIcon(g),
                  color: groupColor(c, g),
                  big: big,
                  selected: pr.depthStage && g == EvGroup.pothole,
                  suggested: !pr.depthStage && g != EvGroup.unknown && groupProb(pr.guess, g) >= 0.45,
                  onTap: () => ctrl.pickGroup(g),
                ),
              ),
          ]);
        }),
        if (pr.depthStage) ...[
          Text(context.tr('Глубина', 'Chuqurlik').toUpperCase(), style: HpText.s(c.muted, 11, FontWeight.w700, ls: 1.2)),
          Row(spacing: 8, children: [
            for (final k in depth)
              Expanded(child: _Big(label: depthLabel(context, k), icon: null, color: k == 'pothole_deep' ? c.crater : (k == 'pothole_mid' ? c.warn : c.amber), big: big, compact: true, onTap: () => ctrl.selectOption(k))),
          ]),
        ] else
          TextButton(
            onPressed: ctrl.pickFalse,
            style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(context.tr('Ложное срабатывание', 'Yolgʻon signal'), style: HpText.s(c.muted, 12, FontWeight.w600)),
          ),
        Row(spacing: 8, children: [
          if (listening) const SizedBox(width: 22, height: 22, child: HoliWave(size: 22)) else Icon(Icons.mic_none_rounded, size: 16, color: c.muted),
          Expanded(child: Text(widget.ui.error != null ? context.tr('Голос не слышно — нажмите вариант', 'Ovoz eshitilmadi — variantni bosing') : context.tr('Или скажите: «Яма», «Лежачий», «Не знаю»', 'Yoki ayting: «Choʻqqi», «Yotiq», «Bilmayman»'), style: HpText.s(c.muted, 12, FontWeight.w500))),
        ]),
      ]);
    }

    return Semantics(
      liveRegion: true,
      label: context.tr('Что это было?', 'Bu nima edi?'),
      child: Listener(
        onPointerDown: (_) => widget.ctrl.touchPrompt(),
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            constraints: BoxConstraints(maxWidth: big ? 520 : 440),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: urgent ? Color.alphaBlend(c.crater.withValues(alpha: .12), c.surface) : c.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: ring, width: urgent ? 2 : 1.5),
              boxShadow: [BoxShadow(color: urgent ? c.crater.withValues(alpha: .35) : Colors.black.withValues(alpha: 0.35), blurRadius: urgent ? 28 : 22, offset: const Offset(0, 8))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              if (!pr.answered)
                Row(spacing: 12, children: [
                  SizedBox(width: 46, height: 46, child: CustomPaint(painter: _RingPainter(frac, ring, c.line), child: Center(child: Text('$secs', style: HpText.s(ring, 17, FontWeight.w800))))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.tr('Что это было?', 'Bu nima edi?'), style: HpText.s(c.text, 18, FontWeight.w800)),
                      if (f != null) Text('${context.tr('Удар', 'Zarba')} ${f.peak.toStringAsFixed(1).replaceAll('.', ',')} ${context.tr('м/с²', 'm/s²')} · ${f.speedKmh.round()} ${context.tr('км/ч', 'km/soat')}', style: HpText.s(c.muted, 12, FontWeight.w500)),
                    ]),
                  ),
                  // без tooltip: окно стоит выше навигатора, там нет Overlay
                  Semantics(button: true, label: context.tr('Отложить', 'Kechiktirish'), child: IconButton(onPressed: ctrl.expirePrompt, icon: Icon(Icons.close_rounded, color: c.muted))),
                ]),
              body,
              if (!pr.answered) ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: frac, minHeight: 3, color: ring, backgroundColor: c.line)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.color, this.track);
  final double frac;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(3, 3, s.width - 6, s.height - 6);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = 4);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * frac, false, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac || o.color != color;
}

/// Крупная кнопка ответа.
class _Big extends StatelessWidget {
  const _Big({required this.label, required this.icon, required this.color, required this.onTap, this.big = false, this.filled = false, this.selected = false, this.suggested = false, this.compact = false});
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback onTap;
  final bool big, filled, selected, suggested, compact;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final h = compact ? (big ? 64.0 : 46.0) : (big ? 84.0 : 52.0);
    final on = filled ? Colors.white : c.text;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: filled ? color : (selected ? color.withValues(alpha: .22) : c.raised),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected || suggested ? color : c.line, width: selected || suggested ? 1.6 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: h,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
              if (icon != null) Icon(icon, size: big ? 28 : 20, color: filled ? on : color),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: HpText.s(on, big ? 18 : 15, FontWeight.w700))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// «Вопрос ждёт остановки · N» — плашка, пока в очереди есть неотвеченные вопросы и мы едем.
class _PendingPill extends ConsumerWidget {
  const _PendingPill();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notesRevProvider);
    final ctrl = ref.watch(holiControllerProvider).value;
    final driving = ref.watch(recorderSnapshotProvider).phase == RecorderPhase.driving;
    final hours = ref.watch(settingsProvider.select((s) => s.keepQueueH));
    if (ctrl == null || !driving) return const SizedBox.shrink();
    return ValueListenableBuilder<HoliUi>(
      valueListenable: ctrl.ui,
      builder: (context, ui, _) {
        if (ui.prompt != null) return const SizedBox.shrink();
        final n = ref.read(dbProvider).pending(notBeforeMs: DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch).length;
        if (n == 0) return const SizedBox.shrink();
        final c = context.hp;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 84),
              child: Material(
                color: c.surface,
                shape: StadiumBorder(side: BorderSide(color: c.amber.withValues(alpha: .6))),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => openRoute('/queue'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                      Icon(Icons.schedule_rounded, size: 16, color: c.amberText),
                      Text(context.tr('Вопрос ждёт остановки · $n', 'Savol toʻxtashni kutmoqda · $n'), style: HpText.s(c.text, 13, FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Короткие подсказки сверху (исчезают сами через 4 секунды).
class _BannerHost extends ConsumerStatefulWidget {
  const _BannerHost();
  @override
  ConsumerState<_BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends ConsumerState<_BannerHost> {
  Timer? _t;
  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bannerProvider, (_, b) {
      _t?.cancel();
      if (b != null) _t = Timer(const Duration(seconds: 4), () => ref.read(bannerProvider.notifier).clear());
    });
    final b = ref.watch(bannerProvider);
    if (b == null) return const SizedBox.shrink();
    final c = context.hp;
    final col = switch (b.kind) { 'fixed' => c.smooth, 'complaint' => c.info, 'pothole' => c.crater, 'question' => c.amber, _ => c.info };
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => ref.read(bannerProvider.notifier).clear(),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Color.alphaBlend(col.withValues(alpha: .12), c.surface), borderRadius: BorderRadius.circular(18), border: Border.all(color: col.withValues(alpha: .7)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 16)]),
                child: Row(spacing: 10, children: [
                  Icon(Icons.notifications_active_outlined, color: col, size: 22),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b.title, style: HpText.s(c.text, 14, FontWeight.w700)), if (b.body.isNotEmpty) Text(b.body, style: HpText.s(c.muted, 12, FontWeight.w400))])),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
