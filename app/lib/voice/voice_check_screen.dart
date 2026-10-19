import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/loaders.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/providers.dart';
import 'holi_commands.dart';
import 'holi_log.dart';
import 'holi_phrase.dart';
import 'speech_engine.dart';

/// Проверка голоса: микрофон, распознавание на телефоне и на сервере, звук Холи и журнал. Нужна, чтобы за минуту понять, где сбой.
class VoiceCheckScreen extends ConsumerStatefulWidget {
  const VoiceCheckScreen({super.key});
  @override
  ConsumerState<VoiceCheckScreen> createState() => _VoiceCheckState();
}

class _VoiceCheckState extends ConsumerState<VoiceCheckScreen> {
  PermissionStatus? _mic;
  bool? _speechOk;
  bool _busy = false;
  SpeechOutcome? _last;
  String _lastCmd = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final m = await Permission.microphone.status;
      if (mounted) setState(() => _mic = m);
      final r = ref.read(voiceRecognizerProvider);
      final prep = await r.device.prepare();
      if (mounted) setState(() => _speechOk = prep == null);
    } catch (_) {
      if (mounted) setState(() => _speechOk = false);
    }
  }

  String get _lang => ref.read(settingsProvider).locale?.languageCode == 'uz' ? 'uz' : 'ru';

  Future<void> _run(Future<SpeechOutcome> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _last = null;
      _lastCmd = '';
    });
    final out = await f();
    final p = HoliCommands.parse(out.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = out;
      _lastCmd = p.command == null ? '' : '${p.command!.name}${p.key == null ? '' : ' · ${p.key}'}';
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final rec = ref.read(voiceRecognizerProvider);
    Widget row(String title, String value, Color color, {Widget? action}) => HpCard(
          padding: 14,
          radius: 16,
          border: true,
          child: Row(spacing: 12, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [Text(title, style: HpText.s(c.muted, 12, FontWeight.w500)), Text(value, style: HpText.s(color, 16, FontWeight.w600))])),
            if (action != null) action,
          ]),
        );
    final micOk = _mic?.isGranted ?? false;
    final blocked = _mic?.isPermanentlyDenied ?? false;
    final o = _last;
    return HpPage(
      child: HpBody(top: 20, children: [
        HpTitle(l.vcTitle),
        row(l.vcMic, _mic == null ? '…' : (micOk ? l.vcMicOk : l.vcMicNo), micOk ? c.smooth : c.craterText,
            action: micOk
                ? null
                : HpButtonSmall(blocked ? l.holiOpenSettings : l.vcAllow, onPressed: () async {
                    if (blocked) {
                      await openAppSettings();
                    } else {
                      await ensureMicPermission();
                    }
                    _refresh();
                  })),
        row(l.vcSpeech, _speechOk == null ? '…' : (_speechOk! ? l.vcSpeechOk : l.vcSpeechNo), _speechOk == true ? c.smooth : c.craterText),
        HpButton(l.vcPlay, kind: HpButtonKind.secondary, onPressed: () async {
          final v = await ref.read(holiVoiceProvider);
          await v.play(HoliPhrase.wakeListen);
        }),
        HpButton(l.vcListen, loading: _busy, onPressed: () => _run(() => rec.listenOnce(lang: _lang, maxDuration: const Duration(seconds: 15)))),
        HpButton(l.vcCloud, kind: HpButtonKind.secondary, loading: _busy, onPressed: () => _run(() => rec.cloud.listenOnce(lang: _lang, maxDuration: const Duration(seconds: 15)))),
        Text(l.vcListenHint, style: HpText.s(c.muted, 13, FontWeight.w400)),
        if (_busy) Center(child: Padding(padding: const EdgeInsets.all(8), child: Column(spacing: 8, children: [const HoliWave(size: 90), Text(l.vcWorking, style: HpText.s(c.muted, 13, FontWeight.w500))]))),
        if (o != null)
          HpCard(
            padding: 16,
            radius: 20,
            border: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              Text('${l.vcHeard}: «${o.text}»', style: HpText.s(c.text, 16, FontWeight.w600)),
              Text('${l.vcCommand}: ${_lastCmd.isEmpty ? l.vcNone : _lastCmd}', style: HpText.s(c.muted, 14, FontWeight.w500)),
              Text('${l.vcEngine}: ${o.engine}  ·  ${l.vcTime}: ${o.ms} ms', style: HpText.s(c.muted, 13, FontWeight.w400)),
              if (o.error != SpeechErrorKind.none) Text('${l.vcError}: ${o.error.name}${o.detail.isEmpty ? '' : ' — ${o.detail}'}', style: HpText.s(c.craterText, 13, FontWeight.w500)),
            ]),
          ),
        Text(l.vcLog, style: HpText.s(c.text, 16, FontWeight.w600)),
        ValueListenableBuilder<int>(
          valueListenable: HoliLog.version,
          builder: (_, __, ___) {
            final lines = HoliLog.lines.reversed.take(40).toList();
            return HpCard(
              padding: 12,
              radius: 16,
              child: SelectableText(lines.isEmpty ? '—' : lines.join('\n'), style: HpText.s(c.muted, 11, FontWeight.w400, h: 1.5)),
            );
          },
        ),
        HpButton(l.vcCopy, kind: HpButtonKind.secondary, onPressed: () async {
          await Clipboard.setData(ClipboardData(text: HoliLog.lines.join('\n')));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.vcCopied)));
        }),
      ]),
    );
  }
}

/// Небольшая кнопка действия в строке.
class HpButtonSmall extends StatelessWidget {
  const HpButtonSmall(this.label, {super.key, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Material(
      color: c.amber,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(label, style: HpText.s(c.inverse, 14, FontWeight.w700))),
      ),
    );
  }
}
