import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../algo/taxonomy_data.dart';
import '../core/loaders.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/providers.dart';
import 'holi_controller.dart';
import 'holi_widgets.dart';

/// Карточка «Что это было?» поверх любого экрана: свежий удар, варианты по догадке, выбор нажатием или голосом, показ выбранного.
class EventPromptOverlay extends ConsumerWidget {
  const EventPromptOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(holiControllerProvider).value;
    if (ctrl == null) return const SizedBox.shrink();
    return ValueListenableBuilder<HoliUi>(
      valueListenable: ctrl.ui,
      builder: (context, ui, _) {
        final pr = ui.prompt;
        if (pr == null) return const SizedBox.shrink();
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: _Card(ctrl: ctrl, ui: ui, pr: pr)),
          ),
        );
      },
    );
  }
}

String itemName(String key, bool uz) {
  final it = taxItem(key);
  if (it == null) return key;
  return uz ? it.uz : it.ru;
}

class _Card extends StatelessWidget {
  const _Card({required this.ctrl, required this.ui, required this.pr});
  final HoliController ctrl;
  final HoliUi ui;
  final EventPrompt pr;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final uz = Localizations.localeOf(context).languageCode == 'uz';
    final f = pr.cand.features;
    final ago = DateTime.now().difference(pr.cand.at).inSeconds.clamp(0, 99);
    final listening = ui.status == HoliStatus.listening;
    final err = ui.error;
    return Semantics(
      liveRegion: true,
      label: l.eventAskTitle,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: pr.answered ? c.smooth : c.amber, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Row(spacing: 10, children: [
              if (listening) const SizedBox(width: 36, height: 36, child: HoliWave(size: 36)) else HpDot(pr.answered ? Tone.smooth : Tone.amber, size: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pr.answered ? l.eventChosen(itemName(pr.chosen!, uz)) : l.eventAskTitle, style: HpText.s(c.text, 18, FontWeight.w700)),
                  if (f != null) Text(l.eventAgo(f.speedKmh.round(), ago), style: HpText.s(c.muted, 12, FontWeight.w500)),
                ]),
              ),
              IconButton(tooltip: l.eventClose, onPressed: ctrl.dismissPrompt, icon: Icon(Icons.close, color: c.muted)),
            ]),
            if (pr.answered)
              Text(pr.via == 'voice' ? l.eventViaVoice : l.eventViaTap, style: HpText.s(c.smooth, 14, FontWeight.w600))
            else ...[
              if (pr.guess.confidence >= 0.35 && pr.guess.top != 'handled' && pr.guess.top != 'noise')
                Text(l.eventGuessHint(itemName(pr.guess.top, uz), (pr.guess.confidence * 100).round()), style: HpText.s(c.muted, 13, FontWeight.w500)),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in pr.options) _Chip(label: itemName(k, uz), top: k == pr.guess.top, onTap: () => ctrl.selectOption(k)),
              ]),
              if (ui.heard.isNotEmpty && listening) Text(l.holiHeard(ui.heard), style: HpText.s(c.muted, 13, FontWeight.w400)),
              if (err != null) Text(holiErrorText(l, err), style: HpText.s(c.craterText, 13, FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.top = false});
  final String label;
  final VoidCallback onTap;
  final bool top;

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: top ? c.amber.withValues(alpha: 0.18) : c.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: top ? c.amber : c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Text(label, style: HpText.s(c.text, 15, FontWeight.w600))),
        ),
      ),
    );
  }
}
