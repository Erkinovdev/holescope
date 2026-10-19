import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/loaders.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/providers.dart';
import 'holi_controller.dart';

/// Панель Холи на экране поездки: имя, статус («слушает» / «говорит»), что услышала. Пока Холи молчит — подсказка с командами.
class HoliPanel extends ConsumerWidget {
  const HoliPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final ctrl = ref.watch(holiControllerProvider).value;
    if (ctrl == null) return const SizedBox.shrink();
    return ValueListenableBuilder<HoliUi>(
      valueListenable: ctrl.ui,
      builder: (context, ui, _) {
        final status = switch (ui.status) {
          HoliStatus.listening => l.holiListening,
          HoliStatus.speaking => l.holiSpeaking,
          HoliStatus.thinking => l.holiThinking,
          HoliStatus.idle => '',
        };
        if (!ui.active) {
          return Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.holiHint, textAlign: TextAlign.center, style: HpText.s(c.muted, 13, FontWeight.w400)));
        }
        return Semantics(
          liveRegion: true,
          label: '${l.holiName} $status',
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: HpCard(
              padding: 16,
              radius: 24,
              border: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                if (ui.status == HoliStatus.listening) const Center(child: HoliWave(size: 96)),
                Row(spacing: 10, children: [
                  HpDot(ui.status == HoliStatus.listening ? Tone.smooth : Tone.amber, size: 12),
                  Text(l.holiName, style: HpText.s(c.text, 18, FontWeight.w700)),
                  Text(status, style: HpText.s(c.muted, 15, FontWeight.w500)),
                ]),
                if (ui.said.isNotEmpty && ui.status == HoliStatus.speaking) Text(ui.said, style: HpText.s(c.text, 16, FontWeight.w500)),
                if (ui.heard.isNotEmpty) Text(l.holiHeard(ui.heard), style: HpText.s(c.muted, 14, FontWeight.w400)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Кнопка вызова Холи вручную.
class HoliCallButton extends ConsumerWidget {
  const HoliCallButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctrl = ref.watch(holiControllerProvider).value;
    return HpButton(l.holiCall, kind: HpButtonKind.secondary, onPressed: ctrl == null ? null : () => ctrl.activate());
  }
}
