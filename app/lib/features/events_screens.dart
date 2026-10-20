// ignore_for_file: sort_child_properties_last
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../core/v2.dart';
import '../core/widgets.dart';
import '../l10n/tr.dart';
import '../services/local_db.dart';
import '../services/providers.dart';
import '../voice/event_prompt_card.dart';
import '../voice/event_ui.dart';

String _hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ───────────────────────── Очередь вопросов ─────────────────────────
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});
  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  int? depthFor; // вопрос, у которого раскрыт выбор глубины

  List<PendingQuestion> _items() {
    final hours = ref.read(settingsProvider).keepQueueH;
    return ref.read(dbProvider).pending(notBeforeMs: DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch);
  }

  void _answer(PendingQuestion q, String key) {
    ref.read(holiControllerProvider).value?.answerQueued(q, key);
    ref.read(dbProvider).removePending(q.id);
    ref.read(notesRevProvider.notifier).bump();
    setState(() => depthFor = null);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notesRevProvider);
    final c = context.hp;
    final hours = ref.watch(settingsProvider).keepQueueH;
    final items = _items();
    return V2Screen(
      title: context.tr('Очередь вопросов', 'Savollar navbati'),
      children: [
        Text(context.tr('Ответьте на остановке — это займёт 10 секунд. Без ответа вопрос живёт $hours ч и не портит карту.', 'Toʻxtaganingizda javob bering — 10 soniya. Javobsiz savol $hours soat saqlanadi va xaritani buzmaydi.'), style: HpText.s(c.muted, 13, FontWeight.w400, h: 1.4)),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(spacing: 10, children: [Icon(Icons.check_circle_outline_rounded, size: 48, color: c.smooth), Text(context.tr('Все вопросы закрыты', 'Barcha savollar yopildi'), style: HpText.s(c.text, 16, FontWeight.w600))]),
          ),
        for (final q in items)
          HpCard(
            radius: 20,
            padding: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              Row(children: [
                Text(_hm(q.at), style: HpText.s(c.text, 15, FontWeight.w700)),
                const SizedBox(width: 8),
                Text('${q.speedKmh.round()} ${context.tr('км/ч', 'km/soat')}', style: HpText.s(c.muted, 13, FontWeight.w500)),
                const Spacer(),
                if (q.peak > 0) Text('${q.peak.toStringAsFixed(1).replaceAll('.', ',')} ${context.tr('м/с²', 'm/s²')}', style: HpText.s(c.amberText, 13, FontWeight.w700)),
              ]),
              if (depthFor == q.id)
                Row(spacing: 8, children: [
                  for (final k in const ['pothole_light', 'pothole_mid', 'pothole_deep']) Expanded(child: FilledButton.tonal(onPressed: () => _answer(q, k), child: Text(depthLabel(context, k)))),
                ])
              else
                Row(spacing: 8, children: [
                  Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: c.crater, foregroundColor: Colors.white), onPressed: () => setState(() => depthFor = q.id), child: Text(context.tr('Яма', 'Choʻqqi')))),
                  Expanded(child: FilledButton.tonal(onPressed: () => _answer(q, 'bump'), child: Text(context.tr('Лежачий', 'Yotiq')))),
                  Expanded(child: FilledButton.tonal(onPressed: () => _answer(q, 'unknown'), child: Text(context.tr('Не знаю', 'Bilmayman')))),
                ]),
            ]),
          ),
        if (items.isNotEmpty)
          HpButton(context.tr('Пропустить всё', 'Hammasini oʻtkazib yuborish'), kind: HpButtonKind.secondary, onPressed: () {
            ref.read(dbProvider).clearPending();
            ref.read(notesRevProvider.notifier).bump();
          }),
      ],
    );
  }
}

// ───────────────────────── Что можно отметить ─────────────────────────
class EventTypesScreen extends StatelessWidget {
  const EventTypesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final items = [
      (EvGroup.pothole, context.tr('Провал, острые края', 'Chuqurlik, oʻtkir qirralar')),
      (EvGroup.bump, context.tr('Искусственная неровность', 'Sunʼiy notekislik')),
      (EvGroup.manhole, context.tr('Выше или ниже асфальта', 'Asfaltdan baland yoki past')),
      (EvGroup.rails, context.tr('Трамвайные пути, стык', 'Tramvay yoʻllari, chok')),
      (EvGroup.uneven, context.tr('Волна, просадка', 'Toʻlqin, choʻkish')),
      (EvGroup.unknown, context.tr('Не уверен — тоже ответ', 'Ishonchim komil emas — bu ham javob')),
    ];
    return V2Screen(title: context.tr('Что можно отметить', 'Nimani belgilash mumkin'), children: [
      Text(context.tr('Шесть типов — этого достаточно для карты.', 'Oltita tur — xarita uchun yetarli.'), style: HpText.s(c.muted, 13, FontWeight.w400)),
      for (final it in items)
        HpCard(
          radius: 18,
          padding: 14,
          child: Row(spacing: 12, children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: groupColor(c, it.$1).withValues(alpha: .16), borderRadius: BorderRadius.circular(14)), child: Icon(groupIcon(it.$1), color: groupColor(c, it.$1))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(groupLabel(context, it.$1), style: HpText.s(c.text, 16, FontWeight.w700)), Text(it.$2, style: HpText.s(c.muted, 12, FontWeight.w400))])),
          ]),
        ),
    ]);
  }
}

// ───────────────────────── Центр уведомлений ─────────────────────────
class NotificationCenter extends ConsumerStatefulWidget {
  const NotificationCenter({super.key});
  @override
  ConsumerState<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends ConsumerState<NotificationCenter> {
  String filter = 'all';
  late final Set<int> _unreadAtOpen;

  @override
  void initState() {
    super.initState();
    final db = ref.read(dbProvider);
    _unreadAtOpen = {for (final n in db.notes()) if (n.unread) n.id};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      db.readAllNotes();
      ref.read(notesRevProvider.notifier).bump();
    });
  }

  (IconData, Tone) _look(String kind) => switch (kind) {
        'pothole' => (Icons.warning_amber_rounded, Tone.major),
        'question' => (Icons.schedule_rounded, Tone.amber),
        'fixed' => (Icons.build_outlined, Tone.smooth),
        'complaint' => (Icons.description_outlined, Tone.info),
        'weekly' => (Icons.star_outline_rounded, Tone.amber),
        _ => (Icons.shield_outlined, Tone.muted),
      };

  @override
  Widget build(BuildContext context) {
    ref.watch(notesRevProvider);
    final c = context.hp;
    final all = ref.read(dbProvider).notes();
    bool pass(LocalNote n) => switch (filter) { 'pits' => n.kind == 'pothole' || n.kind == 'fixed', 'asks' => n.kind == 'question', 'complaints' => n.kind == 'complaint', _ => true };
    final list = all.where(pass).toList();
    final now = DateTime.now();
    String section(LocalNote n) {
      final d = DateTime.fromMillisecondsSinceEpoch(n.at);
      final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
      return days <= 0 ? context.tr('Сегодня', 'Bugun') : (days == 1 ? context.tr('Вчера', 'Kecha') : context.tr('Ранее', 'Oldinroq'));
    }

    final chips = [('all', context.tr('Все', 'Hammasi')), ('pits', context.tr('Ямы', 'Choʻqqilar')), ('asks', context.tr('Вопросы', 'Savollar')), ('complaints', context.tr('Жалобы', 'Shikoyatlar'))];
    String? last;
    return V2Screen(
      title: context.tr('Уведомления', 'Bildirishnomalar'),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(spacing: 8, children: [
            for (final ch in chips)
              ChoiceChip(
                label: Text(ch.$2),
                selected: filter == ch.$1,
                onSelected: (_) => setState(() => filter = ch.$1),
                selectedColor: c.amber,
                labelStyle: HpText.s(filter == ch.$1 ? c.inverse : c.text, 13, FontWeight.w700),
                side: BorderSide(color: c.line),
                backgroundColor: c.surface,
                showCheckmark: false,
              ),
          ]),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: Column(spacing: 10, children: [
              Icon(Icons.notifications_none_rounded, size: 46, color: c.muted),
              Text(context.tr('Пока ничего нет', 'Hozircha hech narsa yoʻq'), style: HpText.s(c.text, 16, FontWeight.w600)),
              Text(context.tr('Здесь появятся предупреждения, вопросы, статусы жалоб и итоги недели.', 'Bu yerda ogohlantirishlar, savollar, shikoyat holatlari va hafta yakunlari paydo boʻladi.'), textAlign: TextAlign.center, style: HpText.s(c.muted, 13, FontWeight.w400)),
            ]),
          ),
        for (final n in list) ...[
          if (section(n) != last) V2Section(last = section(n)),
          V2Row(
            icon: _look(n.kind).$1,
            tone: _look(n.kind).$2,
            title: n.title,
            sub: n.body.isEmpty ? null : n.body,
            chevron: false,
            onTap: n.kind == 'question' ? () => context.push('/queue') : (n.ref.startsWith('strong:') ? () => context.push('/strong-hit?${n.ref.substring(7)}') : null),
            trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, spacing: 4, children: [
              Text(_hm(n.at), style: HpText.s(c.muted, 12, FontWeight.w500)),
              if (_unreadAtOpen.contains(n.id)) Container(width: 8, height: 8, decoration: BoxDecoration(color: c.amber, shape: BoxShape.circle)),
            ]),
          ),
        ],
      ],
    );
  }
}
