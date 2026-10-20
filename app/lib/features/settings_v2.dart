// ignore_for_file: sort_child_properties_last
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../core/v2.dart';
import '../core/widgets.dart';
import '../l10n/tr.dart';
import '../services/config.dart';
import '../services/providers.dart';
import '../voice/holi_phrase.dart';
import '../voice/holi_voice.dart';
import 'welcome.dart' show mountName, roleName;

// «Настройки» (Figma · Screens v2.1 · Flow 14): главная с поиском и подразделы по темам. Каждый переключатель здесь действительно управляет приложением.

String _hours(BuildContext c, int h) => c.tr('$h ч', '$h soat');

// ───────────────────────── Главная ─────────────────────────
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final nick = ref.watch(nicknameProvider);
    final tot = ref.watch(totalsProvider);
    final rows = <(String, String, IconData, Tone, String)>[
      (context.tr('Уведомления', 'Bildirishnomalar'), context.tr('Типы, тихие часы, лимит в день', 'Turlari, tinch soatlar, kunlik chegara'), Icons.notifications_none_rounded, Tone.amber, '/settings/notifications'),
      (context.tr('Голос «Холи»', 'Ovoz «Holi»'), context.tr('Слово пробуждения, громкость, дистанция', 'Uygʻotuvchi soʻz, ovoz balandligi, masofa'), Icons.mic_none_rounded, Tone.smooth, '/settings/voice'),
      (context.tr('События и вопросы', 'Hodisalar va savollar'), context.tr('Время окна, очередь, вибрация', 'Oyna vaqti, navbat, tebranish'), Icons.schedule_rounded, Tone.info, '/settings/events'),
      (context.tr('Предупреждения о ямах', 'Choʻqqi ogohlantirishlari'), context.tr('Какие ямы, за сколько метров, звук', 'Qaysi choʻqqilar, necha metr oldin, tovush'), Icons.warning_amber_rounded, Tone.major, '/settings/warnings'),
      (context.tr('Запись и батарея', 'Yozuv va batareya'), context.tr('Автозапись, положение, Wi-Fi', 'Avtoyozuv, joylashuv, Wi-Fi'), Icons.battery_charging_full_rounded, Tone.minor, '/settings/recording'),
      (context.tr('Внешний вид', 'Koʻrinish'), context.tr('Тема, язык, размер текста', 'Mavzu, til, matn oʻlchami'), Icons.wb_sunny_outlined, Tone.amber, '/settings/look'),
      (context.tr('Данные и приватность', 'Maʼlumotlar va maxfiylik'), context.tr('Что хранится и как это убрать', 'Nima saqlanadi va uni qanday olib tashlash'), Icons.lock_outline_rounded, Tone.muted, '/settings/privacy'),
      (context.tr('Режим в машине', 'Mashina rejimi'), context.tr('Для планшета и штатного монитора', 'Planshet va shtat monitor uchun'), Icons.directions_car_outlined, Tone.info, '/settings/car'),
      (context.tr('Автомобиль', 'Avtomobil'), s.carName ?? context.tr('Не указан', 'Koʻrsatilmagan'), Icons.directions_car_filled_outlined, Tone.smooth, '/vehicle'),
      (context.tr('О приложении', 'Ilova haqida'), '${context.tr('Версия', 'Versiya')} ${AppConfig.appVersion}', Icons.info_outline_rounded, Tone.muted, '/settings/about'),
    ];
    final shown = rows.where((r) => q.isEmpty || r.$1.toLowerCase().contains(q.toLowerCase()) || r.$2.toLowerCase().contains(q.toLowerCase())).toList();
    return V2Screen(
      title: context.tr('Настройки', 'Sozlamalar'),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
          child: Row(spacing: 8, children: [
            Icon(Icons.search_rounded, color: c.muted, size: 20),
            Expanded(child: TextField(onChanged: (v) => setState(() => q = v), style: HpText.s(c.text, 15, FontWeight.w500), decoration: InputDecoration(border: InputBorder.none, hintText: context.tr('Найти настройку', 'Sozlamani topish'), hintStyle: HpText.s(c.muted, 15, FontWeight.w400)))),
          ]),
        ),
        if (q.isEmpty)
          HpCard(
            radius: 18,
            padding: 14,
            color: c.amberDim,
            borderColor: c.amber,
            onTap: () => context.go('/profile'),
            child: Row(spacing: 12, children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: c.amber, shape: BoxShape.circle), alignment: Alignment.center, child: Text((nick ?? 'H').characters.first.toUpperCase(), style: HpText.s(c.inverse, 18, FontWeight.w800))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${roleName(context, s.role)} · ${nick ?? context.tr('без имени', 'ismsiz')}', style: HpText.s(c.text, 15, FontWeight.w700)),
                Text('${s.carName ?? context.tr('Автомобиль не указан', 'Avtomobil koʻrsatilmagan')} · ${tot.trips} ${context.tr('поездок', 'safar')}', style: HpText.s(c.muted, 12, FontWeight.w500)),
              ])),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ]),
          ),
        for (final r in shown) V2Row(icon: r.$3, tone: r.$4, title: r.$1, sub: r.$2, onTap: () => context.push(r.$5)),
        if (shown.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(context.tr('Ничего не найдено', 'Hech narsa topilmadi'), textAlign: TextAlign.center, style: HpText.s(c.muted, 14, FontWeight.w500))),
      ],
    );
  }
}

// ───────────────────────── Уведомления ─────────────────────────
class NotificationSettings extends ConsumerWidget {
  const NotificationSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return V2Screen(title: context.tr('Уведомления', 'Bildirishnomalar'), children: [
      V2Section(context.tr('Типы', 'Turlari')),
      V2Toggle(icon: Icons.warning_amber_rounded, tone: Tone.major, title: context.tr('Яма впереди', 'Oldinda choʻqqi'), sub: context.tr('Заранее и со звуком', 'Oldindan va tovush bilan'), value: s.notifPothole, onChanged: (v) => n.update((x) => x.copyWith(notifPothole: v))),
      V2Toggle(icon: Icons.schedule_rounded, tone: Tone.amber, title: context.tr('Вопросы после удара', 'Zarbadan keyingi savollar'), sub: context.tr('Всплывают на 20 секунд', '20 soniyaga chiqadi'), value: s.notifQuestion, onChanged: (v) => n.update((x) => x.copyWith(notifQuestion: v))),
      V2Toggle(icon: Icons.build_outlined, tone: Tone.smooth, title: context.tr('Яму заделали', 'Choʻqqi tuzatildi'), sub: context.tr('На ваших маршрутах', 'Sizning yoʻllaringizda'), value: s.notifFixed, onChanged: (v) => n.update((x) => x.copyWith(notifFixed: v))),
      V2Toggle(icon: Icons.description_outlined, tone: Tone.info, title: context.tr('Статус жалобы', 'Shikoyat holati'), sub: context.tr('При смене статуса', 'Holat oʻzgarganda'), value: s.notifComplaint, onChanged: (v) => n.update((x) => x.copyWith(notifComplaint: v))),
      V2Toggle(icon: Icons.star_outline_rounded, tone: Tone.amber, title: context.tr('Итоги недели', 'Hafta yakunlari'), sub: context.tr('Понедельник, 8:00', 'Dushanba, 8:00'), value: s.notifWeekly, onChanged: (v) => n.update((x) => x.copyWith(notifWeekly: v))),
      V2Section(context.tr('Режим', 'Rejim')),
      V2Toggle(icon: Icons.nightlight_outlined, tone: Tone.info, title: context.tr('Тихие часы', 'Tinch soatlar'), sub: '${_hours(context, s.quietFromH)} – ${_hours(context, s.quietToH)}', value: s.quietOn, onChanged: (v) => n.update((x) => x.copyWith(quietOn: v))),
      if (s.quietOn) ...[
        V2Slider(title: context.tr('Тихие часы с', 'Tinch soatlar boshlanishi'), valueText: _hours(context, s.quietFromH), value: s.quietFromH.toDouble(), min: 18, max: 24, divisions: 6, onChanged: (v) => n.update((x) => x.copyWith(quietFromH: v.round() % 24))),
        V2Slider(title: context.tr('Тихие часы до', 'Tinch soatlar tugashi'), valueText: _hours(context, s.quietToH), value: s.quietToH.toDouble(), min: 4, max: 10, divisions: 6, onChanged: (v) => n.update((x) => x.copyWith(quietToH: v.round()))),
      ],
      V2Slider(title: context.tr('Не больше в день', 'Kuniga koʻpi bilan'), valueText: '${s.maxPerDay}', value: s.maxPerDay.toDouble(), min: 1, max: 10, divisions: 9, onChanged: (v) => n.update((x) => x.copyWith(maxPerDay: v.round()))),
      Text(context.tr('Остальное уходит в центр уведомлений без звука. В тихие часы приходит только срочное.', 'Qolgani ovozsiz bildirishnomalar markaziga tushadi. Tinch soatlarda faqat shoshilinch xabarlar keladi.'), style: HpText.s(context.hp.muted, 12, FontWeight.w400, h: 1.4)),
    ]);
  }
}

// ───────────────────────── Голос Холи ─────────────────────────
class VoiceSettings extends ConsumerWidget {
  const VoiceSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final engine = switch (s.holiEngine) { 'device' => context.tr('На телефоне', 'Telefonda'), 'cloud' => context.tr('Сервер', 'Server'), _ => context.tr('Авто', 'Avto') };
    return V2Screen(title: context.tr('Голос «Холи»', 'Ovoz «Holi»'), children: [
      V2Toggle(icon: Icons.mic_none_rounded, tone: Tone.amber, title: context.tr('«Привет, Холи»', '«Salom, Holi»'), sub: context.tr('Слушать слово пробуждения, пока экран включён', 'Ekran yoniq boʻlganda uygʻotuvchi soʻzni tinglash'), value: s.holiWake, onChanged: (v) => n.update((x) => x.copyWith(holiWake: v))),
      V2Toggle(icon: Icons.volume_up_outlined, tone: Tone.smooth, title: context.tr('Голос и сигналы', 'Ovoz va signallar'), sub: context.tr('Голосовые подсказки и предупреждения', 'Ovozli maslahat va ogohlantirishlar'), value: s.voice, onChanged: (v) => n.update((x) => x.copyWith(voice: v, beep: v ? x.beep : x.beep))),
      V2Section(context.tr('Звук', 'Tovush')),
      V2Slider(title: context.tr('Громкость', 'Ovoz balandligi'), valueText: '${(s.holiVolume * 100).round()}%', value: s.holiVolume, min: 0.3, max: 1, divisions: 7, onChanged: (v) {
        JustAudioHoliPlayer.volume = v;
        n.update((x) => x.copyWith(holiVolume: v));
      }),
      V2Slider(title: context.tr('Предупреждать за', 'Oldindan ogohlantirish'), valueText: context.tr('${s.warnDistanceM} м', '${s.warnDistanceM} m'), value: s.warnDistanceM.toDouble(), min: 100, max: 300, divisions: 8, onChanged: (v) => n.update((x) => x.copyWith(warnDistanceM: ((v / 25).round() * 25)))),
      V2Row(
        icon: Icons.play_arrow_rounded,
        tone: Tone.amber,
        title: context.tr('Прослушать', 'Tinglab koʻrish'),
        sub: context.tr('«Яма через ${s.warnDistanceM} метров»', '«Choʻqqi ${s.warnDistanceM} metrdan keyin»'),
        onTap: () async {
          final v = await ref.read(holiVoiceProvider);
          unawaited(v.play(HoliPhrase.aheadPothole, distanceM: s.warnDistanceM));
        },
      ),
      V2Section(context.tr('Распознавание речи', 'Nutqni aniqlash')),
      V2Row(icon: Icons.graphic_eq_rounded, tone: Tone.info, title: context.tr('Движок', 'Dvigatel'), value: engine, onTap: () async {
        final v = await _pick<String>(context, [(context.tr('Авто', 'Avto'), 'auto'), (context.tr('На телефоне', 'Telefonda'), 'device'), (context.tr('Сервер', 'Server'), 'cloud')], s.holiEngine);
        if (v != null) n.update((x) => x.copyWith(holiEngine: v));
      }),
      V2Row(icon: Icons.record_voice_over_outlined, tone: Tone.muted, title: context.tr('Проверка голоса', 'Ovozni tekshirish'), sub: context.tr('Что слышит приложение и где сбой', 'Ilova nimani eshitadi va xato qayerda'), onTap: () => context.push('/voice-check')),
    ]);
  }
}

Future<T?> _pick<T>(BuildContext context, List<(String, T)> opts, T cur) {
  final c = context.hp;
  return showModalBottomSheet<T>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final o in opts) ListTile(title: Text(o.$1, style: HpText.s(c.text, 16, FontWeight.w500)), trailing: o.$2 == cur ? Icon(Icons.check_rounded, color: c.amberText) : null, onTap: () => Navigator.pop(context, o.$2)),
      ]),
    ),
  );
}

// ───────────────────────── События и вопросы ─────────────────────────
class EventSettings extends ConsumerWidget {
  const EventSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final win = [10, 20, 30];
    return V2Screen(title: context.tr('События и вопросы', 'Hodisalar va savollar'), children: [
      V2Toggle(icon: Icons.help_outline_rounded, tone: Tone.amber, title: context.tr('Спрашивать «что это было?»', '«Bu nima edi?» deb soʻrash'), sub: context.tr('После сильного удара', 'Kuchli zarbadan keyin'), value: s.holiAsk, onChanged: (v) => n.update((x) => x.copyWith(holiAsk: v))),
      V2Section(context.tr('Время окна', 'Oyna vaqti')),
      V2Segments(labels: [for (final w in win) context.tr('$w с', '$w s')], index: win.indexOf(s.eventWindowS).clamp(0, 2), onChanged: (i) => n.update((x) => x.copyWith(eventWindowS: win[i]))),
      V2Toggle(icon: Icons.touch_app_outlined, tone: Tone.amber, title: context.tr('Продлевать касанием', 'Teginish bilan uzaytirish'), sub: context.tr('+5 секунд на каждое касание', 'Har teginishga +5 soniya'), value: s.eventExtend, onChanged: (v) => n.update((x) => x.copyWith(eventExtend: v))),
      V2Toggle(icon: Icons.vibration_rounded, tone: Tone.minor, title: context.tr('Вибрация', 'Tebranish'), sub: context.tr('Тик при показе и при ответе', 'Koʻrsatilganda va javobda tik'), value: s.eventVibrate, onChanged: (v) => n.update((x) => x.copyWith(eventVibrate: v))),
      V2Toggle(icon: Icons.mic_none_rounded, tone: Tone.smooth, title: context.tr('Отвечать голосом', 'Ovoz bilan javob berish'), sub: context.tr('«Яма», «лежачий», «не знаю»', '«Choʻqqi», «yotuvchi», «bilmayman»'), value: s.eventVoiceReply, onChanged: (v) => n.update((x) => x.copyWith(eventVoiceReply: v))),
      V2Section(context.tr('Если не успели', 'Ulgurmasangiz')),
      V2Row(icon: Icons.history_rounded, tone: Tone.muted, title: context.tr('Хранить вопросы', 'Savollarni saqlash'), sub: context.tr('Очередь живёт столько часов', 'Navbat shuncha soat saqlanadi'), value: _hours(context, s.keepQueueH), onTap: () async {
        final v = await _pick<int>(context, [for (final h in [6, 12, 24, 48]) (_hours(context, h), h)], s.keepQueueH);
        if (v != null) n.update((x) => x.copyWith(keepQueueH: v));
      }),
      V2Row(icon: Icons.list_alt_rounded, tone: Tone.info, title: context.tr('Очередь вопросов', 'Savollar navbati'), sub: context.tr('Ответить сейчас', 'Hozir javob berish'), onTap: () => context.push('/queue')),
      V2Row(icon: Icons.category_outlined, tone: Tone.muted, title: context.tr('Что можно отметить', 'Nimani belgilash mumkin'), sub: context.tr('Шесть типов ответов', 'Oltita javob turi'), onTap: () => context.push('/types')),
    ]);
  }
}

// ───────────────────────── Предупреждения о ямах ─────────────────────────
class WarningSettings extends ConsumerWidget {
  const WarningSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final dist = [100, 150, 300];
    return V2Screen(title: context.tr('Предупреждения о ямах', 'Choʻqqi ogohlantirishlari'), children: [
      V2Section(context.tr('Какие ямы', 'Qaysi choʻqqilar')),
      V2Toggle(icon: Icons.panorama_fish_eye_rounded, tone: Tone.amber, title: context.tr('Лёгкие', 'Yengil'), value: s.warnLight, onChanged: (v) => n.update((x) => x.copyWith(warnLight: v))),
      V2Toggle(icon: Icons.panorama_fish_eye_rounded, tone: Tone.minor, title: context.tr('Средние', 'Oʻrtacha'), value: s.warnMid, onChanged: (v) => n.update((x) => x.copyWith(warnMid: v))),
      V2Toggle(icon: Icons.panorama_fish_eye_rounded, tone: Tone.major, title: context.tr('Глубокие', 'Chuqur'), value: s.warnDeep, onChanged: (v) => n.update((x) => x.copyWith(warnDeep: v))),
      V2Section(context.tr('За сколько', 'Necha metr oldin')),
      V2Segments(labels: [for (final d in dist) context.tr('$d м', '$d m')], index: dist.contains(s.warnDistanceM) ? dist.indexOf(s.warnDistanceM) : 1, onChanged: (i) => n.update((x) => x.copyWith(warnDistanceM: dist[i]))),
      V2Toggle(icon: Icons.speed_rounded, tone: Tone.minor, title: context.tr('Учитывать скорость', 'Tezlikni hisobga olish'), sub: context.tr('Чем быстрее, тем раньше', 'Tez boʻlsa — oldinroq'), value: s.warnUseSpeed, onChanged: (v) => n.update((x) => x.copyWith(warnUseSpeed: v))),
      V2Section(context.tr('Как сообщать', 'Qanday xabar berish')),
      V2Toggle(icon: Icons.volume_up_outlined, tone: Tone.info, title: context.tr('Звук', 'Tovush'), sub: context.tr('Короткий сигнал', 'Qisqa signal'), value: s.beep, onChanged: (v) => n.update((x) => x.copyWith(beep: v))),
      V2Toggle(icon: Icons.record_voice_over_outlined, tone: Tone.smooth, title: context.tr('Голос', 'Ovoz'), sub: context.tr('Холи называет расстояние', 'Holi masofani aytadi'), value: s.voice, onChanged: (v) => n.update((x) => x.copyWith(voice: v))),
    ]);
  }
}

// ───────────────────────── Запись и батарея ─────────────────────────
class RecordingSettings extends ConsumerWidget {
  const RecordingSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final queue = ref.watch(queueSizeProvider);
    final mounts = [PhoneMount.seat, PhoneMount.holder, PhoneMount.hand];
    return V2Screen(title: context.tr('Запись и батарея', 'Yozuv va batareya'), children: [
      V2Toggle(icon: Icons.play_arrow_rounded, tone: Tone.smooth, title: context.tr('Автозапись', 'Avtoyozuv'), sub: context.tr('Начинается сама, когда тронулись', 'Siz yoʻlga chiqqaningizda oʻzi boshlanadi'), value: s.autoRecord, onChanged: (v) => n.update((x) => x.copyWith(autoRecord: v))),
      V2Section(context.tr('Положение телефона', 'Telefon joylashuvi')),
      V2Segments(labels: [context.tr('Сиденье', 'Oʻrindiq'), context.tr('Держатель', 'Tutqich'), context.tr('Рука', 'Qoʻl')], index: mounts.contains(s.mount) ? mounts.indexOf(s.mount) : 1, onChanged: (i) => n.update((x) => x.copyWith(mount: mounts[i]))),
      V2Row(icon: Icons.phone_android_rounded, tone: Tone.amber, title: context.tr('Подробнее о положении', 'Joylashuv haqida batafsil'), value: mountName(context, s.mount), onTap: () => context.push('/mount')),
      V2Section(context.tr('Заряд и данные', 'Zaryad va maʼlumot')),
      V2Toggle(icon: Icons.wifi_rounded, tone: Tone.info, title: context.tr('Отправлять по Wi-Fi', 'Wi-Fi orqali yuborish'), sub: context.tr('Мобильный интернет не тратим', 'Mobil internet sarflanmaydi'), value: s.wifiOnly, onChanged: (v) => n.update((x) => x.copyWith(wifiOnly: v))),
      V2Row(icon: Icons.cloud_upload_outlined, tone: Tone.muted, title: context.tr('Ждёт отправки', 'Yuborilishini kutmoqda'), sub: context.tr('Поездки в очереди', 'Navbatdagi safarlar'), value: '$queue', chevron: false),
    ]);
  }
}

// ───────────────────────── Внешний вид ─────────────────────────
class LookSettings extends ConsumerWidget {
  const LookSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final themes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];
    final lang = switch (s.locale?.languageCode) { 'ru' => 'RU', 'uz' => 'UZ', _ => context.tr('Системный', 'Tizim') };
    return V2Screen(title: context.tr('Внешний вид', 'Koʻrinish'), children: [
      V2Section(context.tr('Тема', 'Mavzu')),
      V2Segments(labels: [context.tr('Светлая', 'Yorugʻ'), context.tr('Тёмная', 'Qorongʻi'), context.tr('Системная', 'Tizim')], index: themes.indexOf(s.themeMode), onChanged: (i) => n.update((x) => x.copyWith(themeMode: themes[i]))),
      V2Row(icon: Icons.language_rounded, tone: Tone.info, title: context.tr('Язык', 'Til'), value: lang, onTap: () => context.push('/settings/language')),
      V2Slider(title: context.tr('Размер текста', 'Matn oʻlchami'), valueText: '${(s.textScale * 100).round()}%', value: s.textScale, min: 0.85, max: 1.4, divisions: 11, onChanged: (v) => n.update((x) => x.copyWith(textScale: (v * 20).round() / 20))),
      V2Toggle(icon: Icons.visibility_outlined, tone: Tone.minor, title: context.tr('Высокая контрастность', 'Yuqori kontrast'), sub: context.tr('Ярче цвета и толще линии', 'Ranglar yorqinroq, chiziqlar qalinroq'), value: s.highContrast, onChanged: (v) => n.update((x) => x.copyWith(highContrast: v))),
      V2Toggle(icon: Icons.bolt_rounded, tone: Tone.muted, title: context.tr('Меньше анимаций', 'Kamroq animatsiya'), sub: context.tr('Для слабых телефонов', 'Zaif telefonlar uchun'), value: s.reduceMotion, onChanged: (v) => n.update((x) => x.copyWith(reduceMotion: v))),
    ]);
  }
}

class LanguageSettings extends ConsumerWidget {
  const LanguageSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final cur = s.locale?.languageCode ?? '';
    Widget row(String code, String name, String sub) => V2Row(
          icon: Icons.language_rounded,
          tone: cur == code ? Tone.amber : Tone.muted,
          title: name,
          sub: sub,
          chevron: false,
          trailing: cur == code ? Icon(Icons.check_rounded, color: context.hp.amberText) : null,
          onTap: () => n.update((x) => x.copyWith(locale: code.isEmpty ? null : Locale(code))),
        );
    return V2Screen(title: context.tr('Язык', 'Til'), children: [
      row('uz', 'Oʻzbekcha', 'Lotin'),
      row('ru', 'Русский', context.tr('По умолчанию', 'Standart')),
      row('', context.tr('Как в системе', 'Tizimdagidek'), context.tr('Русский или узбекский', 'Rus yoki oʻzbek')),
      Text(context.tr('Узбекские тексты ещё проходят проверку носителем языка.', 'Oʻzbekcha matnlar hali ona tili egasi tomonidan tekshirilmoqda.'), style: HpText.s(context.hp.muted, 12, FontWeight.w400, h: 1.4)),
    ]);
  }
}

// ───────────────────────── Данные и приватность ─────────────────────────
class PrivacySettings extends ConsumerWidget {
  const PrivacySettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final tot = ref.watch(totalsProvider);
    return V2Screen(title: context.tr('Данные и приватность', 'Maʼlumotlar va maxfiylik'), children: [
      V2Row(icon: Icons.visibility_off_outlined, tone: Tone.smooth, title: context.tr('Анонимный режим', 'Anonim rejim'), sub: context.tr('Маршруты не привязаны к имени и номеру телефона', 'Yoʻllar ism va telefon raqamiga bogʻlanmagan'), chevron: false, trailing: Icon(Icons.check_circle_rounded, color: c.smooth)),
      V2Section(context.tr('Мои данные', 'Mening maʼlumotlarim')),
      V2Row(icon: Icons.route_outlined, tone: Tone.info, title: context.tr('Поездки на телефоне', 'Telefondagi safarlar'), sub: '${tot.trips} · ${tot.km.toStringAsFixed(1)} ${context.tr('км', 'km')}', chevron: false),
      V2Row(
        icon: Icons.delete_outline_rounded,
        tone: Tone.major,
        title: context.tr('Удалить все поездки', 'Barcha safarlarni oʻchirish'),
        sub: context.tr('С телефона. Это нельзя отменить', 'Telefondan. Buni bekor qilib boʻlmaydi'),
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              backgroundColor: c.surface,
              title: Text(context.tr('Удалить все поездки?', 'Barcha safarlar oʻchirilsinmi?'), style: HpText.s(c.text, 18, FontWeight.w700)),
              content: Text(context.tr('История, очередь вопросов и уведомления на этом телефоне будут стёрты. Подтверждённые ямы на карте останутся — они анонимны.', 'Bu telefondagi tarix, savollar navbati va bildirishnomalar oʻchiriladi. Xaritadagi tasdiqlangan choʻqqilar qoladi — ular anonim.'), style: HpText.s(c.muted, 14, FontWeight.w400)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.tr('Оставить', 'Qoldirish'))),
                TextButton(onPressed: () => Navigator.pop(d, true), child: Text(context.tr('Удалить', 'Oʻchirish'), style: TextStyle(color: c.craterText))),
              ],
            ),
          );
          if (ok == true) {
            ref.read(dbProvider).wipeUserData();
            ref.invalidate(tripsProvider);
            ref.invalidate(totalsProvider);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Удалено', 'Oʻchirildi'))));
          }
        },
      ),
    ]);
  }
}

// ───────────────────────── Режим в машине ─────────────────────────
class CarSettings extends ConsumerWidget {
  const CarSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return V2Screen(title: context.tr('Режим в машине', 'Mashina rejimi'), children: [
      Text(context.tr('Для планшета и штатного монитора. Крупно и без лишнего.', 'Planshet va shtat monitor uchun. Yirik va ortiqchasiz.'), style: HpText.s(context.hp.muted, 13, FontWeight.w400)),
      V2Toggle(icon: Icons.bolt_rounded, tone: Tone.amber, title: context.tr('Крупные кнопки', 'Yirik tugmalar'), sub: context.tr('80 пикселей вместо 48', '48 oʻrniga 80 piksel'), value: s.carBig, onChanged: (v) => n.update((x) => x.copyWith(carBig: v))),
      V2Toggle(icon: Icons.nightlight_outlined, tone: Tone.info, title: context.tr('Ночной режим', 'Tungi rejim'), sub: context.tr('Тёмная тема в этом режиме всегда', 'Bu rejimda qorongʻi mavzu doim'), value: s.carNight, onChanged: (v) => n.update((x) => x.copyWith(carNight: v))),
      V2Toggle(icon: Icons.lock_outline_rounded, tone: Tone.major, title: context.tr('Блокировать ввод на ходу', 'Yurganda kiritishni bloklash'), sub: context.tr('Только голос и кнопки', 'Faqat ovoz va tugmalar'), value: s.carLock, onChanged: (v) => n.update((x) => x.copyWith(carLock: v))),
      V2Toggle(icon: Icons.light_mode_outlined, tone: Tone.minor, title: context.tr('Не гасить экран', 'Ekranni oʻchirmaslik'), sub: context.tr('Пока идёт поездка', 'Safar davomida'), value: s.keepScreenOn, onChanged: (v) => n.update((x) => x.copyWith(keepScreenOn: v))),
      V2Section(context.tr('Подключение', 'Ulanish')),
      V2Row(icon: Icons.directions_car_outlined, tone: Tone.muted, title: context.tr('Автомобиль', 'Avtomobil'), sub: s.carName ?? context.tr('Не указан', 'Koʻrsatilmagan'), onTap: () => context.push('/vehicle')),
      if (!AppConfig.carMonitor) V2Row(icon: Icons.tv_rounded, tone: Tone.info, title: context.tr('Показать экран монитора', 'Monitor ekranini koʻrsatish'), sub: context.tr('Как приложение выглядит на широком экране', 'Keng ekranda ilova qanday koʻrinadi'), onTap: () => context.push('/car')),
    ]);
  }
}

// ───────────────────────── О приложении ─────────────────────────
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return V2Screen(title: context.tr('О приложении', 'Ilova haqida'), children: [
      Column(spacing: 8, children: [
        const SizedBox(height: 8),
        Container(width: 76, height: 76, decoration: BoxDecoration(color: c.amber, borderRadius: BorderRadius.circular(22)), alignment: Alignment.center, child: const HpSvg('logo52', size: 46)),
        Text('Holescope', style: HpText.s(c.text, 24, FontWeight.w800)),
        Text('${context.tr('Версия', 'Versiya')} ${AppConfig.appVersion} · ${context.tr('сборка', 'build')} ${AppConfig.appBuild}${AppConfig.carMonitor ? ' · ${context.tr('для монитора', 'monitor uchun')}' : ''}', style: HpText.s(c.muted, 13, FontWeight.w500)),
        Text(kDebugMode ? 'debug' : 'release', style: HpText.s(c.muted.withValues(alpha: .6), 11, FontWeight.w500)),
        const SizedBox(height: 8),
      ]),
      V2Row(icon: Icons.info_outline_rounded, tone: Tone.info, title: context.tr('Как работает приложение', 'Ilova qanday ishlaydi'), onTap: () => context.push('/onboarding/intro')),
      V2Row(icon: Icons.record_voice_over_outlined, tone: Tone.smooth, title: context.tr('Проверка голоса', 'Ovozni tekshirish'), onTap: () => context.push('/voice-check')),
      V2Row(icon: Icons.notifications_none_rounded, tone: Tone.amber, title: context.tr('Центр уведомлений', 'Bildirishnomalar markazi'), onTap: () => context.push('/notifications')),
    ]);
  }
}
