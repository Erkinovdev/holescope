import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/loaders.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/providers.dart';
import 'holi_controller.dart';
import 'speech_engine.dart';

/// Понятный текст причины сбоя.
String holiErrorText(AppLocalizations l, SpeechErrorKind k) => switch (k) {
      SpeechErrorKind.micDenied => l.holiErrMic,
      SpeechErrorKind.micBlocked => l.holiErrMicBlocked,
      SpeechErrorKind.unavailable => l.holiErrUnavailable,
      SpeechErrorKind.languageUnsupported => l.holiErrLang,
      SpeechErrorKind.busy => l.holiErrBusy,
      SpeechErrorKind.network => l.holiErrNet,
      SpeechErrorKind.startTimeout => l.holiErrTimeout,
      _ => l.holiErrFailed,
    };

/// Панель Холи на экране поездки: имя, статус («слушает» / «говорит»), что услышала, причина сбоя. Пока Холи молчит — подсказка с командами.
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
        final err = ui.error;
        if (!ui.active && err == null) {
          return Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.holiHint, textAlign: TextAlign.center, style: HpText.s(c.muted, 13, FontWeight.w400)));
        }
        final blocked = err == SpeechErrorKind.micBlocked || err == SpeechErrorKind.micDenied;
        return Semantics(
          liveRegion: true,
          label: '${l.holiName} $status',
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: HpCard(
              padding: 16,
              radius: 24,
              border: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                if (ui.status == HoliStatus.listening) const Center(child: HoliWave(size: 96)),
                Row(spacing: 10, children: [
                  HpDot(err != null ? Tone.major : (ui.status == HoliStatus.listening ? Tone.smooth : Tone.amber), size: 12),
                  Text(l.holiName, style: HpText.s(c.text, 18, FontWeight.w700)),
                  Text(status, style: HpText.s(c.muted, 15, FontWeight.w500)),
                ]),
                if (ui.said.isNotEmpty && ui.status == HoliStatus.speaking) Text(ui.said, style: HpText.s(c.text, 16, FontWeight.w500)),
                if (ui.heard.isNotEmpty) Text(l.holiHeard(ui.heard), style: HpText.s(c.muted, 14, FontWeight.w400)),
                if (err != null) ...[
                  Text(holiErrorText(l, err), style: HpText.s(c.craterText, 14, FontWeight.w600)),
                  Row(spacing: 10, children: [
                    if (blocked) Expanded(child: HpButton(l.holiOpenSettings, kind: HpButtonKind.secondary, onPressed: openAppSettings)),
                    Expanded(child: HpButton(l.holiCheck, kind: HpButtonKind.secondary, onPressed: () => context.push('/voice-check'))),
                  ]),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Кнопка Холи: позвать → «Готово» (закончить фразу) → «Пропустить» (перебить) → «Отмена».
class HoliCallButton extends ConsumerWidget {
  const HoliCallButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctrl = ref.watch(holiControllerProvider).value;
    if (ctrl == null) return HpButton(l.holiCall, kind: HpButtonKind.secondary, onPressed: null);
    return ValueListenableBuilder<HoliUi>(
      valueListenable: ctrl.ui,
      builder: (_, ui, __) {
        final label = switch (ui.status) {
          HoliStatus.idle => l.holiCall,
          HoliStatus.listening => l.holiBtnDone,
          HoliStatus.speaking => l.holiBtnSkip,
          HoliStatus.thinking => l.holiBtnCancel,
        };
        return HpButton(label, kind: ui.status == HoliStatus.idle ? HpButtonKind.secondary : HpButtonKind.primary, onPressed: ctrl.onButton);
      },
    );
  }
}
