import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/l10n/tr.dart';
import 'package:holescope/services/providers.dart';

// Итоги поездки и «Что было на пути» — экраны после того, как машина остановилась.

String _two(int v) => v.toString().padLeft(2, '0');
String _hm(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

String _km(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

Color _clsColor(HpColors c, String cls) => switch (cls) { 'A' => c.smooth, 'B' => Color.lerp(c.smooth, c.amber, 0.45)!, 'C' => c.amber, 'D' => c.warn, 'E' => c.crater, _ => c.line };

/// Средний класс ровности маршрута A–E по числу сегментов.
String routeClass(Map<String, int> seg) {
  final total = seg.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return '—';
  var s = 0.0;
  for (var i = 0; i < 5; i++) {
    s += i * (seg['ABCDE'[i]] ?? 0);
  }
  return 'ABCDE'[(s / total).round().clamp(0, 4)];
}

String routeClassName(BuildContext context, String cls) => switch (cls) {
      'A' => context.tr('ровная', 'tekis'),
      'B' => context.tr('нормальная', 'yaxshi'),
      'C' => context.tr('средняя', 'oʻrtacha'),
      'D' => context.tr('плохая', 'yomon'),
      'E' => context.tr('разбитая', 'buzilgan'),
      _ => '',
    };

/// Трек поездки: цветная линия по классу ровности и точки элементов на схематичной подложке (без загрузки карты — работает офлайн).
class TrackMap extends StatelessWidget {
  const TrackMap({super.key, required this.summary, this.height = 210});
  final Map<String, dynamic> summary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final track = ((summary['track'] as List?) ?? const []).whereType<List>().toList();
    final events = ((summary['events'] as List?) ?? const []).whereType<Map>().toList();
    return Container(
      height: height,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: track.isEmpty
          ? Center(child: Text(context.tr('Трек появится после первой записанной поездки', 'Trek birinchi yozilgan safardan keyin paydo boʻladi'), style: HpText.s(c.muted, 13, FontWeight.w400), textAlign: TextAlign.center))
          : CustomPaint(painter: _TrackPainter(track, events, c), size: Size.infinite),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.track, this.events, this.c);
  final List<List> track;
  final List<Map> events;
  final HpColors c;

  @override
  void paint(Canvas canvas, Size size) {
    // схематичная подложка: сетка кварталов
    final grid = Paint()..color = c.line.withValues(alpha: 0.55)..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    var minLa = 90.0, maxLa = -90.0, minLo = 180.0, maxLo = -180.0;
    for (final s in track) {
      for (final i in [0, 2]) {
        minLa = math.min(minLa, (s[i] as num).toDouble());
        maxLa = math.max(maxLa, (s[i] as num).toDouble());
        minLo = math.min(minLo, (s[i + 1] as num).toDouble());
        maxLo = math.max(maxLo, (s[i + 1] as num).toDouble());
      }
    }
    final k = math.cos((minLa + maxLa) / 2 * math.pi / 180);
    final w = math.max((maxLo - minLo) * k, 1e-6), h = math.max(maxLa - minLa, 1e-6);
    const pad = 26.0;
    final scale = math.min((size.width - pad * 2) / w, (size.height - pad * 2) / h);
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    Offset pt(double la, double lo) => Offset(ox + (lo - minLo) * k * scale, size.height - oy - (la - minLa) * scale);
    final casing = Paint()..color = c.surface..strokeWidth = 9..strokeCap = StrokeCap.round;
    final line = Paint()..strokeWidth = 5..strokeCap = StrokeCap.round;
    for (final s in track) {
      final a = pt((s[0] as num).toDouble(), (s[1] as num).toDouble()), b = pt((s[2] as num).toDouble(), (s[3] as num).toDouble());
      canvas.drawLine(a, b, casing);
    }
    for (final s in track) {
      final a = pt((s[0] as num).toDouble(), (s[1] as num).toDouble()), b = pt((s[2] as num).toDouble(), (s[3] as num).toDouble());
      line.color = _clsColor(c, s[4] as String);
      canvas.drawLine(a, b, line);
    }
    for (final e in events) {
      final p = pt((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble());
      final el = (e['el'] as num?) == 1;
      if (!el) {
        canvas.drawCircle(p, 2.6, Paint()..color = c.muted.withValues(alpha: 0.7));
        continue;
      }
      canvas.drawCircle(p, 15, Paint()..color = c.crater.withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(p, 7.5, Paint()..color = c.crater);
      canvas.drawCircle(p, 7.5, Paint()..color = c.bgBase..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawCircle(p, 2.6, Paint()..color = c.bgBase);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter o) => o.track != track || o.events != events || o.c != c;
}

String _softName(BuildContext context, String? cls) => switch (cls) {
      'S1' => context.tr('очень мягкая', 'juda yumshoq'),
      'S2' => context.tr('мягкая', 'yumshoq'),
      'S3' => context.tr('средняя', 'oʻrtacha'),
      'S4' => context.tr('жёсткая', 'qattiq'),
      'S5' => context.tr('очень жёсткая', 'juda qattiq'),
      _ => '',
    };

// ───────────────────────── Поездка завершена ─────────────────────────
class TripSummaryScreen extends ConsumerWidget {
  const TripSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final trips = ref.watch(tripsProvider);
    final s = ref.watch(settingsProvider);
    final t = trips.isEmpty ? null : trips.first;
    final seg = <String, int>{for (final e in ((t?.summary['segments'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt()};
    final cls = routeClass(seg);
    final susp = (t?.summary['suspension'] as Map?) ?? const {};
    final soft = susp['cls'] as String?;
    final mins = t == null ? 0 : math.max(1, ((t.endedAt - t.startedAt) / 60000).round());
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(label, style: HpText.s(c.muted, 12, FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: HpText.s(color ?? c.text, 26, FontWeight.w800, ls: -0.4))),
            ]),
          ),
        );
    Widget pill(String text, Color col) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: col.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
            Text(text, style: HpText.s(col, 13, FontWeight.w700)),
          ]),
        );
    return HpPage(
      child: HpBody(top: 20, children: [
        Text(context.tr('Поездка завершена', 'Safar yakunlandi'), style: HpText.s(c.text, 30, FontWeight.w800, ls: -0.6)),
        if (t != null)
          Text('${context.tr('Сегодня', 'Bugun')} · ${_hm(t.startedAt)} – ${_hm(t.endedAt)}${s.carName == null ? '' : ' · ${s.carName}'}', style: HpText.s(c.muted, 14, FontWeight.w400)),
        if (t == null) HpSub(context.tr('Поездок пока нет: включите запись на вкладке «Поездка».', 'Hozircha safarlar yoʻq: «Safar» boʻlimida yozuvni yoqing.')) else ...[
          TrackMap(summary: t.summary),
          Row(spacing: 10, children: [
            stat(context.tr('Расстояние', 'Masofa'), '${_km(t.distanceKm)} ${context.tr('км', 'km')}'),
            stat(context.tr('Время', 'Vaqt'), '$mins ${context.tr('мин', 'daq')}'),
            stat(context.tr('Ям найдено', 'Choʻqqi topildi'), '${t.potholes}', color: t.potholes > 0 ? c.crater : c.text),
          ]),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.line)),
            child: Column(spacing: 14, children: [
              Row(children: [
                Expanded(child: Text(context.tr('Ровность маршрута', 'Yoʻl tekisligi'), style: HpText.s(c.text, 16, FontWeight.w600))),
                if (cls != '—') pill('$cls · ${routeClassName(context, cls)}', _clsColor(c, cls)),
              ]),
              HpProgress(const {'A': 1.0, 'B': 0.8, 'C': 0.6, 'D': 0.35, 'E': 0.15}[cls] ?? 0.0, _clsColor(c, cls)),
              Row(children: [
                Expanded(child: Text(context.tr('Мягкость подвески', 'Osma yumshoqligi'), style: HpText.s(c.text, 16, FontWeight.w600))),
                if (soft != null && soft.isNotEmpty) pill('$soft · ${_softName(context, soft)}', c.amber) else Text('—', style: HpText.s(c.muted, 15, FontWeight.w500)),
              ]),
            ]),
          ),
        ],
        Row(spacing: 12, children: [
          Expanded(
            child: HpButton(context.tr('Поделиться', 'Ulashish'), kind: HpButtonKind.secondary, onPressed: () {
              final txt = t == null ? 'Holescope' : '${_km(t.distanceKm)} ${context.tr('км', 'km')}, $mins ${context.tr('мин', 'daq')}, ${context.tr('ям найдено', 'choʻqqi topildi')}: ${t.potholes}. ${context.tr('Ровность', 'Tekislik')}: $cls. holescop.duckdns.org';
              Clipboard.setData(ClipboardData(text: txt));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Итоги скопированы — вставьте в любой чат', 'Natijalar nusxalandi — istalgan chatga qoʻying'))));
            }),
          ),
          Expanded(child: HpButton(context.tr('Готово', 'Tayyor'), onPressed: () => context.go('/map'))),
        ]),
        if (t != null) TextButton(onPressed: () => context.push('/trip-review'), child: Text(context.tr('Что было на пути →', 'Yoʻlda nima boʻldi →'), style: HpText.s(c.amberText, 15, FontWeight.w700))),
      ]),
    );
  }
}

// ───────────────────────── Что было на пути ─────────────────────────
class TripReviewScreen extends ConsumerWidget {
  const TripReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final trips = ref.watch(tripsProvider);
    final t = trips.isEmpty ? null : trips.first;
    final db = ref.read(dbProvider);
    final events = ((t?.summary['events'] as List?) ?? const []).whereType<Map>().toList();
    final elements = events.where((e) => (e['el'] as num?) == 1).toList();
    final quality = events.length - elements.length;
    // подтверждено ранее — рядом с элементом уже есть известное место в кэше карты
    bool known(Map e) => db.clustersNear((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble(), 30).isNotEmpty;
    final prior = elements.where(known).length;
    final fresh = elements.length - prior;
    // ровность по километрам: средняя оценка сегментов в каждом километре
    final bars = <double>[];
    final track = ((t?.summary['track'] as List?) ?? const []).whereType<List>().toList();
    if (track.isNotEmpty) {
      var acc = 0.0, dist = 0.0, n = 0;
      for (final s in track) {
        final la = ((s[0] as num).toDouble() + (s[2] as num).toDouble()) / 2;
        final dy = ((s[2] as num).toDouble() - (s[0] as num).toDouble()) * 111320, dx = ((s[3] as num).toDouble() - (s[1] as num).toDouble()) * 111320 * math.cos(la * math.pi / 180);
        dist += math.sqrt(dx * dx + dy * dy);
        acc += 'ABCDE'.indexOf(s[4] as String).clamp(0, 4);
        n++;
        if (dist >= 1000) {
          bars.add(acc / n);
          acc = 0;
          dist = 0;
          n = 0;
        }
      }
      if (n > 0 && (bars.isEmpty || dist > 300)) bars.add(acc / n);
    }
    String levelName(String lv) => switch (lv) { 'light' => context.tr('Лёгкая', 'Yengil'), 'mid' => context.tr('Средняя', 'Oʻrtacha'), 'danger' => context.tr('Опасная', 'Xavfli'), 'deep' => context.tr('Глубокая', 'Chuqur'), _ => '' };
    String typeName(String ty) => switch (ty) { 'bump' => context.tr('Лежачий', 'Yotiq'), 'manhole' => context.tr('Люк', 'Lyuk'), 'rail_tram' || 'rail_train' => context.tr('Рельсы', 'Relslar'), _ => context.tr('Яма', 'Choʻqqi') };
    Widget chip(String text, Color col) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)), Text(text, style: HpText.s(col, 13, FontWeight.w700))]),
        );
    return HpPage(
      child: HpBody(top: 20, children: [
        Text(context.tr('Что было на пути', 'Yoʻlda nima boʻldi'), style: HpText.s(c.text, 30, FontWeight.w800, ls: -0.6)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          chip('${context.tr('Новых', 'Yangi')} $fresh', c.crater),
          chip('${context.tr('Подтверждено ранее', 'Oldin tasdiqlangan')} $prior', c.smooth),
          if (quality > 0) chip('${context.tr('В качество дороги', 'Yoʻl sifatiga')} $quality', c.info),
        ]),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
            Text(context.tr('Ровность по километрам', 'Kilometrlar boʻyicha tekislik'), style: HpText.s(c.text, 16, FontWeight.w700)),
            SizedBox(
              height: 130,
              child: bars.isEmpty
                  ? Center(child: Text(context.tr('Нет данных об участках', 'Qismlar haqida maʼlumot yoʻq'), style: HpText.s(c.muted, 13, FontWeight.w400)))
                  : Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 6, children: [
                      for (final b in bars)
                        Expanded(child: Container(height: 24 + b / 4 * 100, decoration: BoxDecoration(color: _clsColor(c, 'ABCDE'[b.round().clamp(0, 4)]), borderRadius: BorderRadius.circular(8)))),
                    ]),
            ),
            Row(children: [Text('0 ${context.tr('км', 'km')}', style: HpText.s(c.muted, 12, FontWeight.w400)), const Spacer(), Text('${_km(t?.distanceKm ?? 0)} ${context.tr('км', 'km')}', style: HpText.s(c.muted, 12, FontWeight.w400))]),
          ]),
        ),
        Text(context.tr('События', 'Hodisalar'), style: HpText.s(c.text, 18, FontWeight.w700)),
        if (events.isEmpty) HpSub(context.tr('На этом пути ничего не отмечено — ровная дорога.', 'Bu yoʻlda hech narsa belgilanmadi — tekis yoʻl.')),
        for (final e in elements.take(12))
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
            child: Row(spacing: 14, children: [
              Container(width: 46, height: 46, decoration: BoxDecoration(color: c.crater.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)), child: Icon(e['type'] == 'bump' ? Icons.show_chart_rounded : (e['type'] == 'manhole' ? Icons.circle_outlined : Icons.trip_origin_rounded), color: c.crater)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(typeName(e['type'] as String), style: HpText.s(c.text, 16, FontWeight.w700)),
                Text('${_hm((e['at'] as num).toInt())} · ${known(e) ? context.tr('подтверждена', 'tasdiqlangan') : context.tr('новая', 'yangi')} · ${e['speed']} ${context.tr('км/ч', 'km/s')}', style: HpText.s(c.muted, 13, FontWeight.w400)),
              ])),
              if ((e['level'] as String).isNotEmpty) chip(levelName(e['level'] as String), c.crater),
            ]),
          ),
        if (elements.length > 12) HpSub(context.tr('И ещё ${elements.length - 12}.', 'Yana ${elements.length - 12} ta.')),
        HpButton(context.tr('Ответить на вопросы', 'Savollarga javob berish'), kind: HpButtonKind.secondary, onPressed: () => context.push('/question')),
        HpButton(context.tr('Готово', 'Tayyor'), onPressed: () => context.go('/map')),
      ]),
    );
  }
}
