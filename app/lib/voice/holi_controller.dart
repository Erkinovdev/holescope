import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/mark_service.dart';
import 'holi_commands.dart';
import 'holi_phrase.dart';
import 'holi_voice.dart';
import 'speech_engine.dart';

enum HoliStatus { idle, speaking, listening, thinking }

/// Что показывать на экране: имя помощницы, статус и услышанная фраза.
class HoliUi {
  const HoliUi({this.status = HoliStatus.idle, this.heard = '', this.said = ''});
  final HoliStatus status;
  final String heard; // что услышала Холи
  final String said; // что сказала Холи
  bool get active => status != HoliStatus.idle;
  HoliUi copyWith({HoliStatus? status, String? heard, String? said}) => HoliUi(status: status ?? this.status, heard: heard ?? this.heard, said: said ?? this.said);
}

/// Событие, которое алгоритм счёл ямой; по нему Холи спрашивает «да/нет».
class HoliCandidate {
  const HoliCandidate({required this.at, required this.lat, required this.lon, this.heading, this.score = 0});
  final DateTime at;
  final double lat, lon;
  final double? heading;
  final double score;
}

/// Диалог Холи: вызов («Привет, Холи» / кнопка), команды (яма, глубокая, лежачий, люк, отмена) и вопрос «да/нет» после авто-кандидата.
class HoliController {
  HoliController({
    required this.voice,
    required this.speech,
    required this.marks,
    required this.fixAt,
    required this.lang,
    DateTime Function()? now,
    this.commandWindow = const Duration(seconds: 6),
    this.confirmWindow = const Duration(seconds: 5),
    this.markBackSeconds = 2,
    this.askEvery = const Duration(seconds: 60),
    this.maxAsksPerTrip = 3,
  }) : _now = now ?? DateTime.now;

  final HoliVoice voice;
  final SpeechEngine speech;
  final MarkService marks;
  final MarkFix? Function(DateTime t) fixAt;
  final String Function() lang;
  final Duration commandWindow, confirmWindow, askEvery;
  final int markBackSeconds, maxAsksPerTrip;
  final DateTime Function() _now;

  final ui = ValueNotifier<HoliUi>(const HoliUi());
  bool _busy = false;
  bool _wakeOn = false;
  DateTime? _lastAsk;
  int _asks = 0;

  bool get busy => _busy;

  /// Новая поездка: сбросить счётчик вопросов.
  void resetTrip() {
    _asks = 0;
    _lastAsk = null;
  }

  void _set({HoliStatus? status, String? heard}) {
    ui.value = ui.value.copyWith(status: status, heard: heard, said: voice.lastText.value);
  }

  Future<void> _say(HoliPhrase p, {int? distanceM}) async {
    _set(status: HoliStatus.speaking);
    await voice.play(p, distanceM: distanceM);
    await voice.idle;
    _set(status: HoliStatus.speaking);
  }

  /// Один сеанс прослушивания. Возвращает последний услышанный текст ('' — тишина). Останавливается сразу, как только в речи найдена команда.
  Future<String> _listen(Duration window, {required bool confirm}) async {
    _set(status: HoliStatus.listening, heard: '');
    var text = '';
    var stopped = false;
    await speech.listen(
      lang: lang(),
      listenFor: window,
      onText: (t, isFinal) {
        text = t;
        ui.value = ui.value.copyWith(heard: t);
        if (!stopped && HoliCommands.parse(t, confirm: confirm).command != null) {
          stopped = true;
          unawaited(speech.stop());
        }
      },
    );
    _set(status: HoliStatus.thinking);
    return text;
  }

  /// Вызов по кнопке или после «Привет, Холи».
  Future<void> activate({bool byWake = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await speech.init()) {
        await _say(HoliPhrase.unknown);
        return;
      }
      await _say(byWake ? HoliPhrase.wakeYes : HoliPhrase.wakeListen);
      for (var attempt = 0; attempt < 2; attempt++) {
        final heard = await _listen(commandWindow, confirm: false);
        final p = HoliCommands.parse(heard);
        if (p.command != null) {
          await _execute(p.command!);
          return;
        }
        if (attempt == 1) {
          await _say(heard.trim().isEmpty ? HoliPhrase.noAnswer : HoliPhrase.unknown);
          return;
        }
        await _say(heard.trim().isEmpty ? HoliPhrase.repeat : HoliPhrase.unknown);
      }
    } finally {
      await _finish();
    }
  }

  Future<void> _execute(VoiceCommand c) async {
    switch (c) {
      case VoiceCommand.pothole:
        return _mark(MarkKind.pothole, HoliPhrase.markPothole);
      case VoiceCommand.deep:
        return _mark(MarkKind.deep, HoliPhrase.markDeep);
      case VoiceCommand.bump:
        return _mark(MarkKind.bump, HoliPhrase.markBump);
      case VoiceCommand.manhole:
        return _mark(MarkKind.manhole, HoliPhrase.markManhole);
      case VoiceCommand.cancel:
        return _say(marks.cancelLast() ? HoliPhrase.markCancel : HoliPhrase.markCancelNone);
      case VoiceCommand.yes:
      case VoiceCommand.no:
        return _say(HoliPhrase.unknown); // «да/нет» без вопроса ничего не значит
    }
  }

  Future<void> _mark(MarkKind kind, HoliPhrase reply, {MarkFix? at}) async {
    final fix = at ?? fixAt(_now().subtract(Duration(seconds: markBackSeconds)));
    if (fix == null) return _say(HoliPhrase.unknown); // нет GPS — отметить некуда
    marks.add(kind, fix);
    await _say(reply);
  }

  /// Можно ли сейчас задать вопрос про авто-кандидата (не занята, не чаще раза в [askEvery], не больше [maxAsksPerTrip] за поездку).
  bool canAsk() {
    if (_busy || voice.speaking.value) return false;
    if (_asks >= maxAsksPerTrip) return false;
    final last = _lastAsk;
    return last == null || _now().difference(last) >= askEvery;
  }

  /// «Только что была яма? Скажите: да или нет». Тишина = «не услышала», ничего не отмечаем.
  Future<void> askConfirm(HoliCandidate cand) async {
    if (!canAsk() || !await speech.init()) return;
    _busy = true;
    _asks++;
    _lastAsk = _now();
    try {
      await _say(HoliPhrase.askConfirm);
      for (var attempt = 0; attempt < 2; attempt++) {
        final heard = await _listen(confirmWindow, confirm: true);
        final c = HoliCommands.parse(heard, confirm: true).command;
        final fix = MarkFix(cand.at, cand.lat, cand.lon, cand.heading);
        if (c == VoiceCommand.yes) {
          marks.add(MarkKind.pothole, fix);
          await _say(HoliPhrase.confirmYes);
          return;
        }
        if (c == VoiceCommand.no) {
          marks.add(MarkKind.notPothole, fix);
          await _say(HoliPhrase.confirmNo);
          return;
        }
        if (heard.trim().isEmpty || attempt == 1) {
          await _say(HoliPhrase.noAnswer);
          return;
        }
        await _say(HoliPhrase.repeat); // что-то услышала, но не «да/нет»
      }
    } finally {
      await _finish();
    }
  }

  /// Режим «всегда слушаю имя» (экран включён). Распознаёт «Привет, Холи» и сразу команду, если она в той же фразе.
  Future<void> startWakeLoop() async {
    if (_wakeOn) return;
    _wakeOn = true;
    if (!await speech.init()) {
      _wakeOn = false;
      return;
    }
    while (_wakeOn) {
      if (_busy || voice.speaking.value) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      var text = '';
      await speech.listen(lang: lang(), listenFor: const Duration(seconds: 25), onText: (t, f) {
        text = t;
        if (HoliCommands.parse(t).wake) unawaited(speech.stop());
      });
      if (!_wakeOn) break;
      final p = HoliCommands.parse(text);
      if (!p.wake) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }
      if (p.command != null && p.command != VoiceCommand.yes && p.command != VoiceCommand.no && !_busy) {
        _busy = true;
        try {
          await _execute(p.command!);
        } finally {
          await _finish();
        }
      } else {
        await activate(byWake: true);
      }
    }
  }

  Future<void> stopWakeLoop() async {
    _wakeOn = false;
    await speech.stop();
  }

  Future<void> _finish() async {
    await speech.stop();
    _busy = false;
    final shown = ui.value;
    // последние слова остаются на экране ещё на пару секунд
    ui.value = shown.copyWith(status: HoliStatus.idle);
  }

  void dispose() {
    _wakeOn = false;
    ui.dispose();
  }
}
