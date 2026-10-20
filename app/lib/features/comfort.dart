// ignore_for_file: sort_child_properties_last
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../core/v2.dart';
import '../core/widgets.dart';
import '../l10n/tr.dart';
import '../services/providers.dart';

// «Функции для комфорта водителя» (Figma · Flow 17): то, что можно честно посчитать по данным телефона.

/// Комфорт поездки 0–100: среднее по участкам с весами A=1, B=0,85, C=0,6, D=0,3, E=0. null — участков нет.
int? comfortScore(Map<String, int> segments) {
  const w = {'A': 1.0, 'B': 0.85, 'C': 0.6, 'D': 0.3, 'E': 0.0};
  var n = 0, sum = 0.0;
  for (final e in segments.entries) {
    n += e.value;
    sum += (w[e.key] ?? 0) * e.value;
  }
  return n == 0 ? null : (100 * sum / n).round();
}

/// Сильный удар: порог ускорения, выше которого советуем осмотреть машину.
const strongHitPeak = 14.0;

// ───────────────────────── Сильный удар ─────────────────────────
class StrongHitScreen extends StatelessWidget {
  const StrongHitScreen({super.key, this.peak = 0, this.speedKmh = 0});
  final double peak, speedKmh;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    Widget tip(IconData i, Tone t, String title, String sub) => V2Row(icon: i, tone: t, title: title, sub: sub, chevron: false);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const SizedBox(height: 20),
              Center(child: Container(width: 92, height: 92, decoration: BoxDecoration(color: c.crater.withValues(alpha: .15), shape: BoxShape.circle), child: Icon(Icons.warning_amber_rounded, color: c.crater, size: 46))),
              const SizedBox(height: 14),
              Text(context.tr('Сильный удар', 'Kuchli zarba'), textAlign: TextAlign.center, style: HpText.s(c.text, 30, FontWeight.w800, ls: -0.5)),
              const SizedBox(height: 6),
              Text(
                peak > 0
                    ? context.tr('${peak.toStringAsFixed(1).replaceAll('.', ',')} м/с²${speedKmh > 0 ? ' · ${speedKmh.round()} км/ч' : ''}. Остановитесь в безопасном месте и осмотрите машину.', '${peak.toStringAsFixed(1)} m/s²${speedKmh > 0 ? ' · ${speedKmh.round()} km/soat' : ''}. Xavfsiz joyda toʻxtab, mashinani koʻzdan kechiring.')
                    : context.tr('Остановитесь в безопасном месте и осмотрите машину.', 'Xavfsiz joyda toʻxtab, mashinani koʻzdan kechiring.'),
                textAlign: TextAlign.center,
                style: HpText.s(c.muted, 14, FontWeight.w400, h: 1.4),
              ),
              const SizedBox(height: 18),
              Column(spacing: 10, children: [
                tip(Icons.visibility_outlined, Tone.minor, context.tr('Осмотрите шину и диск', 'Shina va diskni koʻzdan kechiring'), context.tr('Вздутие, трещины, шум', 'Shishish, yoriq, shovqin')),
                tip(Icons.speed_rounded, Tone.info, context.tr('Проверьте давление', 'Bosimni tekshiring'), context.tr('Сравните с нормой для вашей машины', 'Mashinangiz normasi bilan solishtiring')),
                tip(Icons.description_outlined, Tone.smooth, context.tr('Запишите, где это было', 'Qayerda boʻlganini yozib qoʻying'), context.tr('Место и время удара сохранены в поездке', 'Zarba joyi va vaqti safarda saqlangan')),
              ]),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: HpButton(context.tr('Всё в порядке', 'Hammasi joyida'), kind: HpButtonKind.secondary, onPressed: () => context.canPop() ? context.pop() : context.go('/map'))),
        ]),
      ),
    );
  }
}

// ───────────────────────── Здоровье подвески ─────────────────────────
class SuspensionScreen extends ConsumerWidget {
  const SuspensionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final trips = ref.watch(tripsProvider);
    final car = ref.watch(settingsProvider).carName;
    final now = DateTime.now();
    final days = List<int>.filled(30, 0);
    var total = 0, km = 0.0;
    for (final t in trips) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.startedAt);
      final ago = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
      if (ago >= 0 && ago < 30) {
        days[29 - ago] += t.potholes;
        total += t.potholes;
        km += t.distanceKm;
      }
    }
    final maxDay = math.max(1, days.reduce(math.max));
    return V2Screen(title: context.tr('Подвеска', 'Osma'), children: [
      Text('${car ?? context.tr('Автомобиль не указан', 'Avtomobil koʻrsatilmagan')} · ${context.tr('последние 30 дней', 'oxirgi 30 kun')}', style: HpText.s(c.muted, 13, FontWeight.w500)),
      HpCard(
        radius: 22,
        padding: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Text(context.tr('Ямы на ваших поездках по дням', 'Safarlaringizdagi choʻqqilar kunlar boʻyicha'), style: HpText.s(c.text, 15, FontWeight.w700)),
          SizedBox(
            height: 90,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 3, children: [
              for (final v in days) Expanded(child: Container(height: math.max(3.0, 90 * v / maxDay), decoration: BoxDecoration(color: v == 0 ? c.line : (v / maxDay > .66 ? c.crater : (v / maxDay > .33 ? c.warn : c.amber)), borderRadius: BorderRadius.circular(3)))),
            ]),
          ),
        ]),
      ),
      Row(spacing: 10, children: [
        Expanded(child: _Stat('$total', context.tr('ям за месяц', 'oyda choʻqqi'), c.crater)),
        Expanded(child: _Stat(km.toStringAsFixed(0), context.tr('км за месяц', 'oyda km'), c.amberText)),
        Expanded(child: _Stat(km > 0 ? (total / km).toStringAsFixed(1).replaceAll('.', ',') : '—', context.tr('ям на км', 'km ga choʻqqi'), c.info)),
      ]),
      Text(total == 0 ? context.tr('Пока данных мало: проезжайте больше, и здесь появится картина нагрузки на подвеску.', 'Maʼlumot kam: koʻproq yuring, shunda osmaga tushgan yuk koʻrinadi.') : context.tr('Чем больше ям на километр, тем быстрее изнашиваются амортизаторы и шины. Если ям стало заметно больше обычного — проверьте развал-схождение.', 'Km ga choʻqqi qancha koʻp boʻlsa, amortizator va shinalar shuncha tez eskiradi. Choʻqqilar odatdagidan koʻp boʻlsa — razval-sxojdeniyani tekshiring.'), style: HpText.s(c.muted, 13, FontWeight.w400, h: 1.4)),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.v, this.label, this.color);
  final String v, label;
  final Color color;
  @override
  Widget build(BuildContext context) => HpCard(radius: 18, padding: 14, child: Column(spacing: 2, children: [Text(v, style: HpText.s(color, 26, FontWeight.w800)), Text(label, textAlign: TextAlign.center, style: HpText.s(context.hp.muted, 11, FontWeight.w500))]));
}

// ───────────────────────── Команды Холи ─────────────────────────
class HoliCommandsScreen extends StatelessWidget {
  const HoliCommandsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final rows = [
      (Icons.panorama_fish_eye_rounded, Tone.major, '«${context.tr('Яма', 'Choʻqqi')}»', context.tr('Отметить яму; «глубокая яма», «мелкая яма» — с уточнением', 'Choʻqqini belgilash; «chuqur oʻra» — aniqlik bilan')),
      (Icons.landscape_rounded, Tone.minor, '«${context.tr('Лежачий', 'Yotiq')}»', context.tr('Лежачий полицейский', 'Yotiq politsiyachi')),
      (Icons.adjust_rounded, Tone.info, '«${context.tr('Люк', 'Lyuk')}»', context.tr('Люк; «люк просел», «люк выступает»', 'Lyuk; «lyuk choʻkkan»')),
      (Icons.drag_indicator_rounded, Tone.amber, '«${context.tr('Рельсы', 'Relslar')}»', context.tr('Трамвайные рельсы, переезд, стык', 'Tramvay relslari, oʻtish joyi, chok')),
      (Icons.route_rounded, Tone.smooth, '«${context.tr('Дорога ровная', 'Yoʻl tekis')}»', context.tr('Оценка участка: ровная, хорошая, плохая, разбитая', 'Qismni baholash: tekis, yaxshi, yomon, buzilgan')),
      (Icons.skip_next_rounded, Tone.muted, '«${context.tr('Пропусти', 'Oʻtkazib yubor')}»', context.tr('«Не знаю» — убрать вопрос', '«Bilmayman» — savolni olib tashlash')),
      (Icons.undo_rounded, Tone.muted, '«${context.tr('Отмена', 'Bekor')}»', context.tr('Отменить последнюю отметку', 'Oxirgi belgini bekor qilish')),
    ];
    return V2Screen(title: context.tr('Команды «Холи»', 'Holi buyruqlari'), children: [
      Text(context.tr('Скажите «Привет, Холи» и потом одну из команд. После удара можно сразу назвать ответ.', 'Avval «Salom, Holi» deng, keyin buyruqni ayting. Zarbadan keyin javobni darhol aytish mumkin.'), style: HpText.s(c.muted, 13, FontWeight.w400, h: 1.4)),
      for (final r in rows) V2Row(icon: r.$1, tone: r.$2, title: r.$3, sub: r.$4, chevron: false),
      HpCard(radius: 16, padding: 12, color: c.amberDim, child: Row(spacing: 10, children: [Icon(Icons.mic_none_rounded, color: c.amberText, size: 18), Expanded(child: Text(context.tr('Слушаю и при выключенном экране — только если включено в «Голос Холи».', 'Ekran oʻchiq boʻlganda ham tinglayman — faqat «Ovoz Holi» da yoqilgan boʻlsa.'), style: HpText.s(c.text, 12, FontWeight.w500)))])),
    ]);
  }
}
