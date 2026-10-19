import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/mark_service.dart';
import 'holi_commands.dart';
import 'holi_log.dart';
import 'holi_phrase.dart';
import 'holi_voice.dart';
import 'speech_engine.dart';

enum HoliStatus { idle, speaking, listening, thinking }

/// Что показывать на экране: имя помощницы, статус, услышанная и сказанная фраза, причина сбоя.
class HoliUi {
  const HoliUi({this.status = HoliStatus.idle, this.heard = '', this.said = '', this.error, this.engine = '', this.detail = ''});
  final HoliStatus status;
  final String heard; // что услышала Холи
  final String said; // что сказала Холи
  final SpeechErrorKind? error; // почему не вышло (null — всё хорошо)
  final String engine; // device | cloud
  final String detail;
  bool get active => status != HoliStatus.idle;
  HoliUi copyWith({HoliStatus? status, String? heard, String? said, Object? error = _keep, String? engine, String? detail}) =>
      HoliUi(status: status ?? this.status, heard: heard ?? this.heard, said: said ?? this.said, error: identical(error, _keep) ? this.error : error as SpeechErrorKind?, engine: engine ?? this.engine, detail: detail ?? this.detail);
}

const _keep = Object();

/// Событие, которое алгоритм счёл ямой; по нему Холи спрашивает «да/нет».
class HoliCandidate {
  const HoliCandidate({required this.at, required this.lat, required this.lon, this.heading, this.score = 0});
  final DateTime at;
  final double lat, lon;
  final double? heading;
  final double score;
}

/// Диалог Холи: вызов («Привет, Холи» / кнопка), команды (любой вариант из справочника, оценка дороги, отмена) и вопрос «да/нет» после авто-кандидата.
/// Слушает без спешки: ждёт начала фразы до 12 с, после речи заканчивает по паузе, ответ можно закончить нажатием. После команды слушает дальше (до 4 подряд).
class HoliController {
  HoliController({
    required this.voice,
    required this.speech,
    required this.marks,
    required this.fixAt,
    required this.lang,
    DateTime Function()? now,
    this.firstWindow = const Duration(seconds: 25),
    this.firstNoSpeech = const Duration(seconds: 12),
    this.followWindow = const Duration(seconds: 12),
    this.followNoSpeech = const Duration(seconds: 5),
    this.confirmWindow = const Duration(seconds: 8),
    this.confirmNoSpeech = const Duration(seconds: 6),
    this.silence = const Duration(milliseconds: 2200),
    this.settle = const Duration(milliseconds: 700),
    this.markBackSeconds = 2,
    this.askEvery = const Duration(seconds: 60),
    this.maxAsksPerTrip = 3,
    this.maxTurns = 4,
  }) : _now = now ?? DateTime.now;

  final HoliVoice voice;
  final SpeechEngine speech;
  final MarkService marks;
  final MarkFix? Function(DateTime t) fixAt;
  final String Function() lang;
  final Duration firstWindow, firstNoSpeech, followWindow, followNoSpeech, confirmWindow, confirmNoSpeech, silence, settle, askEvery;
  final int markBackSeconds, maxAsksPerTrip, maxTurns;
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

  void _set({HoliStatus? status, String? heard, Object? error = _keep, String? engine, String? detail}) {
    ui.value = ui.value.copyWith(status: status, heard: heard, said: voice.lastText.value, error: error, engine: engine, detail: detail);
  }

  Future<void> _say(HoliPhrase p, {int? distanceM}) => _sayKey(distanceM == null ? p.key : p.distanceKey(distanceM));

  Future<void> _sayKey(String key) async {
    _set(status: HoliStatus.speaking);
    await voice.playKey(key);
    await voice.idle;
    _set(status: HoliStatus.speaking);
  }

  /// Нажатие на кнопку Холи: позвать, закончить фразу досрочно (пока слушает) или перебить (пока говорит).
  Future<void> onButton() async {
    if (!_busy) return activate();
    switch (ui.value.status) {
      case HoliStatus.listening:
        HoliLog.add('кнопка: закончить фразу');
        await speech.stop();
      case HoliStatus.speaking:
        HoliLog.add('кнопка: перебить Холи');
        await voice.stop();
      case HoliStatus.thinking:
      case HoliStatus.idle:
        await speech.cancel();
    }
  }

  /// Одно прослушивание. Если в услышанном уже есть команда и текст перестал меняться, заканчивает не дожидаясь паузы.
  Future<SpeechOutcome> _listen(Duration window, Duration noSpeech, {required bool confirm}) async {
    _set(status: HoliStatus.listening, heard: '', error: null);
    Timer? settleTimer;
    String last = '';
    final out = await speech.listenOnce(
      lang: lang(),
      maxDuration: window,
      silenceTimeout: silence,
      noSpeechTimeout: noSpeech,
      onPartial: (t) {
        if (t == last) return;
        last = t;
        _set(heard: t);
        settleTimer?.cancel();
        if (HoliCommands.parse(t, confirm: confirm).command != null) {
          settleTimer = Timer(settle, () => unawaited(speech.stop()));
        }
      },
    );
    settleTimer?.cancel();
    _set(status: HoliStatus.thinking, heard: out.text.isEmpty ? ui.value.heard : out.text, engine: out.engine, detail: out.detail);
    return out;
  }

  /// Причина сбоя → на экран и голосом.
  Future<void> _fail(SpeechOutcome out) async {
    HoliLog.add('сбой: $out');
    _set(error: out.error, engine: out.engine, detail: out.detail);
    switch (out.error) {
      case SpeechErrorKind.micDenied:
      case SpeechErrorKind.micBlocked:
        await _say(HoliPhrase.errMic);
      case SpeechErrorKind.network:
        await _say(HoliPhrase.errNet);
      default:
        await _say(HoliPhrase.errSpeech);
    }
  }

  /// Вызов по кнопке или после «Привет, Холи».
  Future<void> activate({bool byWake = false}) async {
    if (_busy) return;
    _busy = true;
    voice.hold();
    HoliLog.add('Холи: вызов (${byWake ? 'по имени' : 'кнопка'})');
    try {
      final prep = await speech.prepare();
      if (prep != null && prep.failed) {
        await _fail(prep);
        return;
      }
      await _say(byWake ? HoliPhrase.wakeYes : HoliPhrase.wakeListen);
      var turn = 0, misses = 0;
      while (turn < maxTurns) {
        final first = turn == 0;
        final out = await _listen(first ? firstWindow : followWindow, first ? firstNoSpeech : followNoSpeech, confirm: false);
        if (out.failed) {
          await _fail(out);
          return;
        }
        final text = out.text.trim();
        final parsed = HoliCommands.parse(text);
        HoliLog.add('Холи: услышала "$text" → ${parsed.command} ${parsed.key ?? ''}');
        if (parsed.command == null) {
          if (!first && text.isEmpty) return; // в продолжении диалога тишина — просто заканчиваем
          if (text.isEmpty) {
            if (misses++ >= 1) {
              await _say(HoliPhrase.noAnswer);
              return;
            }
            await _say(HoliPhrase.repeat);
            continue;
          }
          if (parsed.wake) continue; // сказали только имя
          if (misses++ >= 1) {
            await _say(HoliPhrase.unknown);
            return;
          }
          await _say(HoliPhrase.unknown);
          continue;
        }
        misses = 0;
        final keepGoing = await _execute(parsed);
        turn++;
        if (!keepGoing) return;
      }
    } finally {
      voice.release();
      await _finish();
    }
  }

  /// Выполняет команду. true — слушать дальше.
  Future<bool> _execute(ParsedVoice p) async {
    switch (p.command!) {
      case VoiceCommand.mark:
        await _mark(p.key!);
        return true;
      case VoiceCommand.rating:
        await _rate(p.key!);
        return true;
      case VoiceCommand.cancel:
        await _say(marks.cancelLast() ? HoliPhrase.markCancel : HoliPhrase.markCancelNone);
        return true;
      case VoiceCommand.stop:
        await _say(HoliPhrase.okEnd);
        return false;
      case VoiceCommand.help:
        await _say(HoliPhrase.help);
        return true;
      case VoiceCommand.yes:
      case VoiceCommand.no:
        await _say(HoliPhrase.unknown); // «да/нет» без вопроса ничего не значит
        return false;
    }
  }

  MarkFix? _fixNow() => fixAt(_now().subtract(Duration(seconds: markBackSeconds)));

  Future<void> _mark(String key) async {
    final fix = _fixNow();
    if (fix == null) return _say(HoliPhrase.unknown); // нет GPS — отметить некуда
    marks.add(markKindOf(key), fix);
    HoliLog.add('отметка: $key');
    if (voice.hasKey('mark_$key')) {
      await _sayKey('mark_$key');
    } else {
      await _say(HoliPhrase.thanks);
    }
  }

  Future<void> _rate(String key) async {
    final fix = _fixNow();
    if (fix == null) return _say(HoliPhrase.unknown);
    marks.add(markKindOf(key), fix);
    HoliLog.add('оценка дороги: $key');
    if (voice.hasKey('rate_$key')) {
      await _sayKey('rate_$key');
    } else {
      await _say(HoliPhrase.thanks);
    }
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
    if (!canAsk()) return;
    final prep = await speech.prepare();
    if (prep != null && prep.failed) {
      HoliLog.add('вопрос «да/нет» пропущен: ${prep.detail}');
      return;
    }
    _busy = true;
    voice.hold();
    _asks++;
    _lastAsk = _now();
    try {
      await _say(HoliPhrase.askConfirm);
      for (var attempt = 0; attempt < 2; attempt++) {
        final out = await _listen(confirmWindow, confirmNoSpeech, confirm: true);
        if (out.failed) {
          await _fail(out);
          return;
        }
        final c = HoliCommands.parse(out.text, confirm: true).command;
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
        if (out.text.trim().isEmpty || attempt == 1) {
          await _say(HoliPhrase.noAnswer);
          return;
        }
        await _say(HoliPhrase.repeat); // что-то услышала, но не «да/нет»
      }
    } finally {
      voice.release();
      await _finish();
    }
  }

  /// Режим «всегда слушаю имя» (экран включён). Распознаёт «Привет, Холи» и сразу команду, если она в той же фразе.
  Future<void> startWakeLoop() async {
    if (_wakeOn) return;
    _wakeOn = true;
    final prep = await speech.prepare();
    if (prep != null && prep.failed) {
      HoliLog.add('имя: слушать нельзя (${prep.detail})');
      _wakeOn = false;
      return;
    }
    while (_wakeOn) {
      if (_busy || voice.speaking.value) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      final out = await speech.listenOnce(lang: lang(), maxDuration: const Duration(seconds: 25), silenceTimeout: const Duration(seconds: 2), noSpeechTimeout: const Duration(seconds: 25), onPartial: (t) {
        if (HoliCommands.parse(t).wake) unawaited(speech.stop());
      });
      if (!_wakeOn) break;
      if (out.failed) {
        HoliLog.add('имя: сбой ${out.error}, остановлено');
        _wakeOn = false;
        break;
      }
      final p = HoliCommands.parse(out.text);
      if (!p.wake) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }
      final withCommand = p.command != null && p.command != VoiceCommand.yes && p.command != VoiceCommand.no;
      if (withCommand && !_busy) {
        _busy = true;
        voice.hold();
        try {
          await _execute(p);
        } finally {
          voice.release();
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
    try {
      await speech.stop();
    } catch (_) {}
    _busy = false;
    // последние слова остаются на экране; ошибка тоже — пока водитель её не закроет новым вызовом
    ui.value = ui.value.copyWith(status: HoliStatus.idle, said: voice.lastText.value);
  }

  /// Скрыть сообщение об ошибке.
  void clearError() => ui.value = ui.value.copyWith(error: null, detail: '');

  void dispose() {
    _wakeOn = false;
    ui.dispose();
  }
}

/// Ключ справочника → вид отметки для сервера.
MarkKind markKindOf(String key) => MarkKind.fromKey(key);
