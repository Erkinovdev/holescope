
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
// ───────────────────────── Положение телефона / Роль ─────────────────────────
