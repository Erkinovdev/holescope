// ignore_for_file: sort_child_properties_last
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/road_map.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../l10n/tr.dart';
import '../services/ahead_warner.dart';
import '../services/providers.dart';
import '../services/trip_recorder.dart';
import '../voice/holi_widgets.dart';
import 'screens_live.dart' show ProfileScreen, fmtKm;
import 'screens_data.dart' show StreetsScreen;

// «Планшет и автомонитор» (Figma · Flow 12): широкий экран в машине. Слева крупные кнопки, в центре карта, справа скорость и предупреждение.
// Размеры считаются от высоты экрана (за единицу взят экран 720 px), поэтому подходит и монитору 1280×720, и вытянутым 1920×720 / 1280×480.

class CarScreen extends ConsumerStatefulWidget {
  const CarScreen({super.key});
  @override
  ConsumerState<CarScreen> createState() => _CarScreenState();
}

class _CarScreenState extends ConsumerState<CarScreen> {
  final map = RoadMapController();
  int tab = 0; // 0 поездка, 1 карта, 2 улицы, 3 профиль
  Timer? _clock;
  DateTime now = DateTime.now();
  bool centered = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
    if (ref.read(settingsProvider).keepScreenOn) unawaited(_wake(true));
  }

  Future<void> _wake(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {
      // платформа без поддержки (тесты) — не критично
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    map.dispose();
    unawaited(_wake(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final snap = ref.watch(recorderSnapshotProvider);
    final warn = ref.watch(warningProvider);
    if (snap.lat != null && snap.lon != null) {
      map.setMe(snap.lat, snap.lon, snap.heading);
      if (!centered) {
        centered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => map.moveTo(snap.lat!, snap.lon!));
      }
    }
    final moving = snap.speedKmh > 8;
    final locked = s.carLock && moving;
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 700; // телефон стоймя: упрощённая раскладка (основная цель — широкий экран)
      final u = narrow ? 0.7 : (box.maxHeight / 720).clamp(0.55, 1.8); // единица масштаба
      final railW = narrow ? 64.0 : (s.carBig ? 104.0 : 84.0) * u;
      final panelW = math.min(box.maxWidth * 0.34, 440 * u);
      Widget railBtn(int i, IconData icon, String label, {VoidCallback? onTap, bool disabled = false}) {
        final sel = i == tab && onTap == null;
        return Semantics(
          button: true,
          selected: sel,
          label: label,
          child: GestureDetector(
            onTap: disabled ? null : (onTap ?? () => setState(() => tab = i)),
            child: Container(
              width: railW - 16 * u,
              height: narrow ? 52.0 : (s.carBig ? 80.0 : 64.0) * u,
              decoration: BoxDecoration(color: sel ? c.amberDim : c.raised, borderRadius: BorderRadius.circular(20 * u), border: Border.all(color: sel ? c.amber : c.line, width: sel ? 2 : 1)),
              child: Icon(icon, size: 34 * u, color: disabled ? c.muted.withValues(alpha: .4) : (sel ? c.amberText : c.muted)),
            ),
          ),
        );
      }

      final rail = Container(
        width: railW,
        color: c.surface,
        padding: EdgeInsets.symmetric(vertical: 14 * u),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          railBtn(1, Icons.map_outlined, context.tr('Карта', 'Xarita')),
          railBtn(0, Icons.directions_car_filled_outlined, context.tr('Поездка', 'Safar')),
          railBtn(2, Icons.list_alt_rounded, context.tr('Улицы', 'Koʻchalar')),
          railBtn(3, Icons.person_outline_rounded, context.tr('Профиль', 'Profil')),
          railBtn(9, locked ? Icons.lock_outline_rounded : Icons.tune_rounded, context.tr('Настройки', 'Sozlamalar'), disabled: locked, onTap: () => context.push('/settings')),
        ]),
      );

      final mapView = Stack(children: [
        Positioned.fill(child: RoadMapView(controller: map, onClusterTap: (cl) => context.push('/pothole/${cl.id}'))),
        Positioned(left: 12 * u, top: 12 * u, child: Wrap(spacing: 8 * u, children: [
          if (snap.phase == RecorderPhase.driving) _Chip(label: 'REC', color: c.crater, u: u),
          if (snap.lat != null) _Chip(label: 'GPS', color: c.smooth, u: u),
        ])),
        Positioned(right: 14 * u, top: 8 * u, child: Text('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}', style: HpText.s(c.text, 26 * u, FontWeight.w700, ls: -0.3))),
        const Positioned(left: 12, bottom: 12, child: RoughnessLegend()),
      ]);

      Widget body;
      if (tab == 1) {
        body = mapView;
      } else if (tab == 2 || tab == 3) {
        body = Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: tab == 2 ? const StreetsScreen() : const ProfileScreen()));
      } else {
        body = narrow
            ? Column(children: [Expanded(child: mapView), SizedBox(height: box.maxHeight * 0.5, child: _DrivePanel(u: u, snap: snap, warn: warn))])
            : Row(children: [Expanded(child: mapView), SizedBox(width: panelW, child: _DrivePanel(u: u, snap: snap, warn: warn))]);
      }

      return Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Row(children: [rail, Expanded(child: body)]),
            if (warn != null) Positioned.fill(left: railW, child: _FullWarning(item: warn, speed: snap.speedKmh.round(), u: u)),
          ]),
        ),
      );
    });
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.u});
  final String label;
  final Color color;
  final double u;
  @override
  Widget build(BuildContext context) => Container(padding: EdgeInsets.symmetric(horizontal: 12 * u, vertical: 6 * u), decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(12 * u)), child: Text(label, style: HpText.s(color, 14 * u, FontWeight.w800)));
}

/// Правая панель: скорость кольцом, предупреждение, итоги поездки, кнопки.
class _DrivePanel extends ConsumerWidget {
  const _DrivePanel({required this.u, required this.snap, required this.warn});
  final double u;
  final RecorderSnapshot snap;
  final AheadItem? warn;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final eng = ref.read(engineProvider);
    final driving = snap.phase == RecorderPhase.driving;
    final speed = snap.speedKmh.round();
    return Container(
      color: c.bgBase,
      padding: EdgeInsets.all(14 * u),
      child: LayoutBuilder(builder: (context, box) {
        final fixed = (84 + 74 + 64) * u + 70 + 12 * u * 5; // предупреждение, итоги, кнопки, отступы
        final ring = math.max(96.0, math.min(box.maxWidth, box.maxHeight - fixed));
        return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12 * u, children: [
        Center(
          child: SizedBox(
            width: ring,
            height: ring,
              child: CustomPaint(
                painter: _SpeedRing(speed / 140, c.amber, c.line, 12 * u),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(child: Text('$speed', style: HpText.s(c.text, 96 * u, FontWeight.w800, ls: -3, h: 1))),
                  Text(context.tr('км/ч', 'km/soat'), style: HpText.s(c.muted, 18 * u, FontWeight.w500)),
                ])),
              ),
          ),
        ),
        _WarnCard(u: u, item: warn),
        Row(spacing: 10 * u, children: [
          Expanded(child: _Mini(value: fmtKm(snap.distanceKm), label: context.tr('км', 'km'), u: u, color: c.text)),
          Expanded(child: _Mini(value: '${snap.found}', label: context.tr('ям', 'choʻqqi'), u: u, color: c.crater)),
        ]),
        const HoliCallButton(),
        SizedBox(
          height: 64 * u,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: driving ? c.crater : c.amber, foregroundColor: driving ? Colors.white : c.inverse, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18 * u))),
            onPressed: () async {
              if (driving) {
                final t = await eng.stopManual();
                if (context.mounted && t != null) context.push('/trip-summary');
              } else {
                eng.startManual();
              }
            },
            child: Text(driving ? context.tr('Закончить поездку', 'Safarni tugatish') : context.tr('Начать поездку', 'Safarni boshlash'), style: HpText.s(driving ? Colors.white : c.inverse, 20 * u, FontWeight.w800)),
          ),
        ),
      ]));
      }),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.value, required this.label, required this.u, required this.color});
  final String value, label;
  final double u;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10 * u),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18 * u), border: Border.all(color: c.line)),
      child: Column(children: [Text(value, style: HpText.s(color, 30 * u, FontWeight.w800)), Text(label, style: HpText.s(c.muted, 13 * u, FontWeight.w500))]),
    );
  }
}

class _WarnCard extends StatelessWidget {
  const _WarnCard({required this.u, required this.item});
  final double u;
  final AheadItem? item;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final it = item;
    if (it == null) {
      return Container(padding: EdgeInsets.all(14 * u), decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20 * u), border: Border.all(color: c.line)), child: Row(spacing: 10 * u, children: [Icon(Icons.check_circle_outline_rounded, color: c.smooth, size: 28 * u), Expanded(child: Text(context.tr('Впереди чисто', 'Oldinda toza'), style: HpText.s(c.text, 18 * u, FontWeight.w700)))]));
    }
    return Container(
      padding: EdgeInsets.all(12 * u),
      decoration: BoxDecoration(color: c.crater.withValues(alpha: .16), borderRadius: BorderRadius.circular(20 * u), border: Border.all(color: c.crater)),
      child: Row(spacing: 12 * u, children: [
        Container(width: 48 * u, height: 48 * u, decoration: BoxDecoration(color: c.crater, borderRadius: BorderRadius.circular(14 * u)), child: Icon(Icons.panorama_fish_eye_rounded, color: Colors.white, size: 28 * u)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('Яма через ${it.distanceM} м', 'Choʻqqi ${it.distanceM} m dan keyin'), style: HpText.s(c.text, 18 * u, FontWeight.w800)),
          if (it.safeSpeed != null) Text(context.tr('Снизьте до ${it.safeSpeed} км/ч', 'Tezlikni ${it.safeSpeed} km/soatgacha kamaytiring'), style: HpText.s(c.craterText, 14 * u, FontWeight.w600)),
        ])),
        Text('${it.distanceM}', style: HpText.s(c.craterText, 34 * u, FontWeight.w800)),
      ]),
    );
  }
}

/// Предупреждение на весь экран: когда яма глубокая и близко, остальное убираем (Figma · автомонитор).
class _FullWarning extends StatelessWidget {
  const _FullWarning({required this.item, required this.speed, required this.u});
  final AheadItem item;
  final int speed;
  final double u;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final deep = item.level == 'deep' || item.level == 'danger';
    if (!(deep && item.distanceM <= 150)) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(gradient: RadialGradient(colors: [Color.alphaBlend(c.crater.withValues(alpha: .3), c.bgBase), c.bgBase], radius: 0.9)),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 10 * u, children: [
            Container(width: 120 * u, height: 120 * u, decoration: BoxDecoration(color: c.crater, borderRadius: BorderRadius.circular(34 * u)), child: Icon(Icons.panorama_fish_eye_rounded, color: Colors.white, size: 70 * u)),
            Text(context.tr('ЯМА', 'CHOʻQQI'), style: HpText.s(c.craterText, 84 * u, FontWeight.w900, ls: 2)),
            Text(context.tr('через ${item.distanceM} м${item.safeSpeed != null ? ' · снизьте до ${item.safeSpeed} км/ч' : ''}', '${item.distanceM} m dan keyin${item.safeSpeed != null ? ' · ${item.safeSpeed} km/soatgacha kamaytiring' : ''}'), style: HpText.s(c.text, 28 * u, FontWeight.w700)),
            if (item.safeSpeed != null && speed > item.safeSpeed!) Text('$speed › ${item.safeSpeed}', style: HpText.s(c.amberText, 40 * u, FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

class _SpeedRing extends CustomPainter {
  _SpeedRing(this.frac, this.color, this.track, this.w);
  final double frac, w;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(w, w, s.width - 2 * w, s.height - 2 * w);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    canvas.drawArc(r, start, sweep, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round);
    canvas.drawArc(r, start, sweep * frac.clamp(0.0, 1.0), false, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SpeedRing o) => o.frac != frac || o.color != color;
}
