import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/demo.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/l10n/app_localizations.dart';

// Экраны, которых нет в Figma (этап 1, п.6). Сверстаны по токенам бренда.
// TODO: нарисовать их в Figma (MCP) и сверить — сейчас макетов нет.

// ───────────────────────── Профиль машины и подвески ─────────────────────────
class VehicleScreen extends ConsumerStatefulWidget {
  const VehicleScreen({super.key});
  @override
  ConsumerState<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends ConsumerState<VehicleScreen> {
  late final TextEditingController name, wb, tires, pressure;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    name = TextEditingController(text: s.carName ?? '');
    wb = TextEditingController(text: s.wheelbaseMm?.toString() ?? '');
    tires = TextEditingController(text: s.tires ?? '');
    pressure = TextEditingController(text: s.pressureBar?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final t in [name, wb, tires, pressure]) {
      t.dispose();
    }
    super.dispose();
  }

  void save() {
    String? n(String t) => t.trim().isEmpty ? null : t.trim();
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          carName: n(name.text),
          wheelbaseMm: int.tryParse(wb.text.trim()),
          tires: n(tires.text),
          pressureBar: double.tryParse(pressure.text.trim().replaceAll(',', '.')),
        ));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    Widget field(String label, TextEditingController ctl, {TextInputType? type, String? hint, List<TextInputFormatter>? fmt}) => HpCard(
          padding: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: HpText.s(c.muted, 12, FontWeight.w500)),
            TextField(
              controller: ctl,
              keyboardType: type,
              inputFormatters: fmt,
              style: HpText.s(c.text, 16, FontWeight.w500),
              decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: hint ?? l.vehicleNotSet, hintStyle: HpText.s(c.muted, 16, FontWeight.w400)),
            ),
          ]),
        );
    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.vehicleTitle),
        field(l.vehicleModel, name),
        field('${l.vehicleWheelbase}, мм', wb, type: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly]),
        field(l.vehicleTires, tires, hint: '205/60 R16'),
        field('${l.vehiclePressure}, бар', pressure, type: const TextInputType.numberWithOptions(decimal: true)),
        HpSub(l.vehicleUnverified),
        const SizedBox(height: 8),
        Text(l.vehicleSuspension, style: HpText.s(c.text, 18, FontWeight.w600)),
        // Индекс подвески S1–S5: считает сервер (holescope_algo/suspension.py), пока данных нет.
        HpCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Text(l.vehicleSoftness, style: HpText.s(c.muted, 13, FontWeight.w500)),
            Row(spacing: 8, children: [
              for (final s in ['S1', 'S2', 'S3', 'S4', 'S5'])
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Text(s, style: HpText.s(c.muted, 14, FontWeight.w600)),
                  ),
                ),
            ]),
            Text(l.vehicleSoftnessEmpty, style: HpText.s(c.muted, 13, FontWeight.w400, h: 18 / 13)),
          ]),
        ),
        HpSub(l.vehicleSuspensionNote),
        const SizedBox(height: 4),
        HpButton(l.vehicleSave, onPressed: save),
      ]),
    );
  }
}

// ───────────────────────── Вопрос «что это было?» ─────────────────────────
/// Показывается ТОЛЬКО после остановки поездки (нет ввода за рулём).
class QuestionScreen extends StatelessWidget {
  const QuestionScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final opts = [
      (l.optPotholeLight, Tone.minor), (l.optPotholeMid, Tone.minor), (l.optPotholeDeep, Tone.major),
      (l.optBump, Tone.smooth), (l.optManhole, Tone.info), (l.optRail, Tone.amber),
    ];
    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.questionTitle),
        HpSub(l.questionSub),
        const DemoBanner(),
        // TODO(этап 2): настоящая волна события из GET /questions/next (поле wave).
        HpCard(padding: 12, child: SizedBox(height: 120, child: CustomPaint(painter: _WavePainter(c.amber, c.line), size: Size.infinite))),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final o in opts)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - 50) / 2,
              child: HpCard(
                radius: 16,
                border: true,
                padding: 14,
                onTap: () => context.pop(), // TODO(этап 2): POST /questions/{id}/answer
                child: Row(spacing: 10, children: [HpDot(o.$2, size: 10), Expanded(child: Text(o.$1, style: HpText.s(c.text, 14, FontWeight.w600)))]),
              ),
            ),
        ]),
        HpButton(l.optNothing, kind: HpButtonKind.secondary, onPressed: () => context.pop()),
        HpButton(l.optNotSure, kind: HpButtonKind.secondary, onPressed: () => context.pop()),
      ]),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.line, this.axis);
  final Color line, axis;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawLine(Offset(0, s.height / 2), Offset(s.width, s.height / 2), Paint()..color = axis);
    final path = Path();
    for (var i = 0; i <= 200; i++) {
      final t = i / 200;
      final y = t < 0.3 ? 0.0 : math.sin((t - 0.3) * 38) * math.exp(-(t - 0.3) * 7);
      final p = Offset(t * s.width, s.height / 2 - y * s.height * 0.45);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_WavePainter o) => false;
}

// ───────────────────────── Итоги поездки ─────────────────────────
class TripSummaryScreen extends StatelessWidget {
  const TripSummaryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    Widget stat(String v, String t, {Color? color}) => Expanded(
          child: HpCard(
            padding: 16,
            child: Column(spacing: 2, children: [
              Text(v, style: HpText.s(color ?? c.amberText, 26, FontWeight.w700, ls: -0.26)),
              Text(t, style: HpText.s(c.muted, 12, FontWeight.w500), textAlign: TextAlign.center),
            ]),
          ),
        );
    final perKm = (Demo.tripFound / Demo.tripKm).toStringAsFixed(1).replaceAll('.', ',');
    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.tripSummary),
        const DemoBanner(),
        Row(spacing: 10, children: [stat('7,2', l.tripKm), stat('${Demo.tripFound}', l.tripPotholes), stat(perKm, l.tripPerKm)]),
        // TODO(этап 2): худший участок и распределение классов A–E считаются на устройстве (roughness.py).
        HpCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            Text(l.tripRoughness, style: HpText.s(c.muted, 13, FontWeight.w500)),
            Row(spacing: 6, children: [
              for (final k in [('A', c.smooth), ('B', c.smooth), ('C', c.amber), ('D', c.warn), ('E', c.crater)])
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: k.$2.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: Text(k.$1, style: HpText.s(c.text, 14, FontWeight.w700)),
                  ),
                ),
            ]),
          ]),
        ),
        HpButton(l.questionTitle, kind: HpButtonKind.secondary, onPressed: () => context.push('/question')),
        HpButton(l.tripDone, onPressed: () => context.go('/map')),
      ]),
    );
  }
}

// ───────────────────────── Положение телефона / Роль ─────────────────────────
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.title, this.sub, required this.selected, required this.onTap});
  final String title;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Semantics(
      button: true,
      selected: selected,
      child: HpCard(
        padding: 18,
        color: selected ? c.amberDim : c.surface,
        borderColor: selected ? c.amber : c.line,
        borderWidth: selected ? 2 : 1,
        onTap: onTap,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(title, style: HpText.s(c.text, 17, FontWeight.w600)),
              if (sub != null) Text(sub!, style: HpText.s(c.muted, 13, FontWeight.w400)),
            ]),
          ),
          if (selected) Icon(Icons.check_circle_rounded, color: c.amberText),
        ]),
      ),
    );
  }
}

/// [onboarding]=true: после выбора идём дальше по первому запуску.
class MountScreen extends ConsumerWidget {
  const MountScreen({super.key, this.onboarding = false});
  final bool onboarding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final names = {PhoneMount.seat: l.mountSeat, PhoneMount.cupholder: l.mountCupholder, PhoneMount.holder: l.mountHolder};
    return HpPage(
      back: !onboarding,
      child: HpBody(top: 20, children: [
        HpTitle(l.mountTitle),
        HpSub(l.mountSub),
        for (final m in PhoneMount.values)
          _ChoiceCard(
            title: names[m]!,
            selected: s.mount == m,
            onTap: () {
              ref.read(settingsProvider.notifier).update((x) => x.copyWith(mount: m));
              if (onboarding) context.go('/permissions');
            },
          ),
      ]),
    );
  }
}

class RoleScreen extends ConsumerWidget {
  const RoleScreen({super.key, this.onboarding = false});
  final bool onboarding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    return HpPage(
      back: !onboarding,
      child: HpBody(top: 20, children: [
        HpTitle(l.roleTitle),
        _ChoiceCard(
          title: l.roleDriver,
          sub: l.roleDriverSub,
          selected: s.role == DeviceRole.driver,
          onTap: () {
            ref.read(settingsProvider.notifier).update((x) => x.copyWith(role: DeviceRole.driver));
            if (onboarding) context.go('/onboarding/mount');
          },
        ),
        _ChoiceCard(
          title: l.rolePassenger,
          sub: l.rolePassengerSub,
          selected: s.role == DeviceRole.passenger,
          onTap: () {
            ref.read(settingsProvider.notifier).update((x) => x.copyWith(role: DeviceRole.passenger));
            if (onboarding) context.go('/onboarding/mount');
          },
        ),
      ]),
    );
  }
}
