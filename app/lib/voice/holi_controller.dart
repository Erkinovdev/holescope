import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../algo/event_guess.dart';
import '../algo/taxonomy_data.dart';
import '../services/local_db.dart' show PendingQuestion;
import '../services/mark_service.dart';
import 'event_ui.dart';
import 'holi_commands.dart';
import 'holi_log.dart';
import 'holi_phrase.dart';
import 'holi_voice.dart';
import 'speech_engine.dart';

enum HoliStatus { idle, speaking, listening, thinking }

/// Что показывать на экране: имя помощницы, статус, услышанная и сказанная фраза, причина сбоя.
class HoliUi {
  const HoliUi({this.status = HoliStatus.idle, this.heard = '', this.said = '', this.error, this.engine = '', this.detail = '', this.prompt});
  final HoliStatus status;
  final String heard; // что услышала Холи
  final String said; // что сказала Холи
  final SpeechErrorKind? error; // почему не вышло (null — всё хорошо)
  final String engine; // device | cloud
  final String detail;
  final EventPrompt? prompt; // вопрос «что это было?» по свежему удару (виден на экране с вариантами)
  bool get active => status != HoliStatus.idle;
  HoliUi copyWith({HoliStatus? status, String? heard, String? said, Object? error = _keep, String? engine, String? detail, Object? prompt = _keep}) => HoliUi(
        status: status ?? this.status,
        heard: heard ?? this.heard,
        said: said ?? this.said,
        error: identical(error, _keep) ? this.error : error as SpeechErrorKind?,
        engine: engine ?? this.engine,
        detail: detail ?? this.detail,
        prompt: identical(prompt, _keep) ? this.prompt : prompt as EventPrompt?,
      );
}

const _keep = Object();

/// Событие, которое алгоритм счёл ямой; по нему Холи спрашивает «да/нет».
class HoliCandidate {
  const HoliCandidate({required this.at, required this.lat, required this.lon, this.heading, this.score = 0, this.features});
  final DateTime at;
  final double lat, lon;
  final double? heading;
  final double score;
  final EventFeatures? features; // показатели удара: по ним строится догадка и отбор вариантов
}

/// Вопрос «что это было?»: варианты, догадка модели и выбор водителя.
class EventPrompt {
  const EventPrompt({required this.cand, required this.guess, required this.options, required this.startedAt, required this.deadline, this.chosen, this.via = '', this.dismissed = false, this.depthStage = false});
  final HoliCandidate cand;
  final Guess guess;
  final List<String> options; // правдоподобные варианты по этому удару
  final DateTime startedAt, deadline; // окно живёт до deadline (касание продлевает, но не дольше 30 с от начала)
  final String? chosen; // ключ выбранного варианта
  final String via; // voice | tap
  final bool dismissed;
  final bool depthStage; // второй шаг: после «Яма» выбираем глубину
  bool get answered => chosen != null;
  EventPrompt copyWith({String? chosen, String? via, bool? dismissed, DateTime? deadline, bool? depthStage}) =>
      EventPrompt(cand: cand, guess: guess, options: options, startedAt: startedAt, deadline: deadline ?? this.deadline, chosen: chosen ?? this.chosen, via: via ?? this.via, dismissed: dismissed ?? this.dismissed, depthStage: depthStage ?? this.depthStage);
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
    this.askEvery = const Duration(seconds: 25),
    this.maxAsksPerTrip = 20,
    this.maxTurns = 4,
    this.contextFor,
    this.speakEnabled,
    this.eventWindow = const Duration(seconds: 9),
    this.eventNoSpeech = const Duration(seconds: 6),
    this.cardHold = const Duration(seconds: 10),
    this.confirmThreshold = 0.5,
    this.promptWindow,
    this.canExtend,
    this.vibrate,
    this.voiceReply,
    this.onExpired,
    this.extendBy = const Duration(seconds: 5),
    this.maxWindow = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final HoliVoice voice;
  final SpeechEngine speech;
  final MarkService marks;
  final MarkFix? Function(DateTime t) fixAt;
  final String Function() lang;
  final Duration firstWindow, firstNoSpeech, followWindow, followNoSpeech, confirmWindow, confirmNoSpeech, silence, settle, askEvery, eventWindow, eventNoSpeech, cardHold;
  final double confirmThreshold;
  final Duration Function()? promptWindow; // сколько живёт окно «что это было?» (настройки: 10/20/30 с); по умолчанию — cardHold
  final bool Function()? canExtend; // касание продлевает окно
  final bool Function()? vibrate; // тик при показе и при ответе
  final bool Function()? voiceReply; // спрашивать голосом и слушать ответ
  final void Function(HoliCandidate cand, Guess guess)? onExpired; // не успели ответить: вопрос уходит в очередь
  final Duration extendBy, maxWindow;
  final GuessContext Function(HoliCandidate cand)? contextFor; // известный объект рядом (из кэша карты)
  final bool Function()? speakEnabled; // голос выключен в настройках: вопрос остаётся на экране без звука
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
      case VoiceCommand.skip:
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

  // ── вопрос «что это было?» сразу после удара ──
  Timer? _cardTimer;
  EventPrompt? get prompt => ui.value.prompt;

  void _setPrompt(EventPrompt? p) => ui.value = ui.value.copyWith(prompt: p);

  /// Какой ключ сохранить по сказанному: «яма» без уточнения → уровень по догадке; «это не яма» → «ничего».
  String _mapKey(String key, Guess g) {
    if (key == 'pothole') return g.top.startsWith('pothole_') ? g.top : 'pothole_mid';
    if (key == 'not_pothole') return 'noise';
    return key;
  }

  /// Спросить про свежий удар: сигнал, экран с вариантами и голос. Ответить можно голосом или нажатием на вариант.
  Future<void> askEvent(HoliCandidate cand) async {
    if (!canAsk() || cand.features == null) return;
    final ctx = contextFor?.call(cand) ?? const GuessContext();
    final guess = guessEvent(cand.features!, ctx);
    final options = optionsFor(guess, driverOptionKeys, limit: 5);
    _busy = true;
    voice.hold();
    _asks++;
    _lastAsk = _now();
    _cardTimer?.cancel();
    final now = _now();
    _setPrompt(EventPrompt(cand: cand, guess: guess, options: options, startedAt: now, deadline: now.add(promptWindow?.call() ?? cardHold)));
    _armExpiry();
    if (vibrate?.call() ?? false) unawaited(HapticFeedback.lightImpact());
    HoliLog.add('вопрос по удару: догадка ${guess.top} ${(guess.confidence * 100).round()}%, варианты $options');
    try {
      if (!(speakEnabled?.call() ?? true) || !(voiceReply?.call() ?? true)) return; // тихий режим: выбор нажатием
      await voice.chime();
      if (prompt?.answered == true) return;
      var confirm = guess.confidence >= confirmThreshold && guess.top != 'handled' && guess.top != 'noise';
      final askKey = confirm ? 'ask_guess_${guess.top}' : 'ask_what';
      if (voice.hasKey(askKey)) {
        await _sayKey(askKey);
      } else {
        await _say(HoliPhrase.askWhat);
      }
      for (var attempt = 0; attempt < 2 && prompt?.answered != true && prompt?.dismissed != true; attempt++) {
        // окно настраивается: слушаем не дольше, чем осталось до конца окна (без настройки — как раньше)
        var listenFor = eventWindow;
        if (promptWindow != null) {
          final left = prompt == null ? Duration.zero : prompt!.deadline.difference(_now());
          if (left < const Duration(seconds: 2)) break;
          if (left - const Duration(seconds: 1) < listenFor) listenFor = left - const Duration(seconds: 1);
        }
        final out = await _listen(listenFor, eventNoSpeech, confirm: confirm);
        if (prompt?.answered == true) return; // нажали вариант на экране
        if (out.failed) {
          _set(error: out.error, engine: out.engine, detail: out.detail);
          break; // микрофон не работает — остаётся выбор на экране
        }
        final p = HoliCommands.parse(out.text, confirm: confirm);
        HoliLog.add('вопрос по удару: услышала "${out.text}" → ${p.command} ${p.key ?? ''}');
        if (p.command == null) {
          if (out.text.trim().isEmpty) break; // тишина: не докучаем, ждём нажатия
          await _say(HoliPhrase.unknown);
          continue;
        }
        switch (p.command!) {
          case VoiceCommand.yes:
            if (confirm) return _choose(guess.top, 'voice');
          case VoiceCommand.no:
            if (confirm) {
              confirm = false;
              await _say(HoliPhrase.askWhat);
              continue;
            }
          case VoiceCommand.mark:
            return _choose(_mapKey(p.key!, guess), 'voice');
          case VoiceCommand.skip:
          case VoiceCommand.stop:
          case VoiceCommand.cancel:
            _setPrompt(prompt?.copyWith(dismissed: true));
            return;
          case VoiceCommand.rating:
          case VoiceCommand.help:
            break;
        }
      }
    } finally {
      voice.release();
      await _finish();
      if (prompt?.answered == true || prompt?.dismissed == true) _scheduleCardClear();
    }
  }

  /// Выбор варианта нажатием на экране (или голосом): сохраняет отметку, показывает выбранное и говорит «спасибо».
  Future<void> selectOption(String key) async {
    final pr = prompt;
    if (pr == null || pr.answered) return;
    await speech.cancel();
    await voice.stop();
    await _choose(key, 'tap');
  }

  Future<void> _choose(String key, String via) async {
    final pr = prompt;
    if (pr == null || pr.answered) return;
    _cardTimer?.cancel();
    _setPrompt(pr.copyWith(chosen: key, via: via));
    if (vibrate?.call() ?? false) unawaited(HapticFeedback.mediumImpact());
    final c = pr.cand;
    final top = pr.guess.ranked(3);
    if (key == 'unknown') {
      // «Не знаю» — тоже ответ: вопрос закрыт, но в обучение ничего не уходит
      HoliLog.add('ответ по удару: не знаю ($via)');
      _scheduleCardClear(after: const Duration(milliseconds: 1500));
      return;
    }
    marks.add(MarkKind(key), MarkFix(c.at, c.lat, c.lon, c.heading), guess: {'top': pr.guess.top, 'p': pr.guess.confidence, 'v': GuessParams.current.version, 'top3': {for (final e in top) e.key: e.value}, 'via': via});
    HoliLog.add('ответ по удару: $key ($via), догадка была ${pr.guess.top}');
    _set(status: HoliStatus.speaking);
    await voice.playKey('thanks_short');
    await voice.idle;
    _scheduleCardClear(after: const Duration(milliseconds: 2500));
  }

  /// Окно «что это было?» исчезает само в [EventPrompt.deadline]: не успели — вопрос уходит в очередь до остановки.
  void _armExpiry() {
    _cardTimer?.cancel();
    final pr = prompt;
    if (pr == null || pr.answered) return;
    final left = pr.deadline.difference(_now());
    _cardTimer = Timer(left.isNegative ? Duration.zero : left, expirePrompt);
  }

  /// Любое касание окна добавляет [extendBy] (не больше [maxWindow] от начала). Возвращает, продлилось ли окно.
  bool touchPrompt() {
    final pr = prompt;
    if (pr == null || pr.answered || !(canExtend?.call() ?? false)) return false;
    final cap = pr.startedAt.add(maxWindow);
    var next = pr.deadline.add(extendBy);
    if (next.isAfter(cap)) next = cap;
    if (!next.isAfter(pr.deadline)) return false;
    _setPrompt(pr.copyWith(deadline: next));
    _armExpiry();
    return true;
  }

  /// Выбран крупный тип: «Яма» открывает выбор глубины, «Не знаю» закрывает вопрос, остальные сохраняются сразу.
  Future<void> pickGroup(EvGroup g) async {
    final pr = prompt;
    if (pr == null || pr.answered) return;
    if (g == EvGroup.pothole) {
      touchPrompt();
      _setPrompt(prompt?.copyWith(depthStage: true));
      return;
    }
    await speech.cancel();
    await voice.stop();
    await _choose(g == EvGroup.unknown ? 'unknown' : resolveGroup(g, pr.guess), 'tap');
  }

  /// Ответ на вопрос из очереди (на остановке): сохраняется отметка по времени и месту удара. [key] == 'unknown' — просто закрыть.
  void answerQueued(PendingQuestion q, String key) {
    if (key == 'unknown') return;
    marks.add(MarkKind(key), MarkFix(DateTime.fromMillisecondsSinceEpoch(q.at), q.lat, q.lon, q.heading), guess: {'top': q.guess, 'via': 'queue'});
    HoliLog.add('ответ из очереди: $key (догадка была ${q.guess})');
  }

  /// «Ложное срабатывание» (телефон тронули, не дорога).
  Future<void> pickFalse() => selectOption('handled');

  /// Окно истекло или водитель отложил: сохраняем вопрос в очередь (на остановке можно ответить).
  void expirePrompt() {
    final pr = prompt;
    _cardTimer?.cancel();
    if (pr == null) return;
    unawaited(speech.cancel());
    if (!pr.answered && !pr.dismissed) onExpired?.call(pr.cand, pr.guess);
    _setPrompt(null);
  }

  void _scheduleCardClear({Duration? after}) {
    _cardTimer?.cancel();
    final pr = prompt;
    if (pr == null) return;
    _cardTimer = Timer(after ?? (pr.answered ? const Duration(milliseconds: 2500) : cardHold), () => _setPrompt(null));
  }

  /// Закрыть вопрос без ответа.
  void dismissPrompt() {
    _cardTimer?.cancel();
    unawaited(speech.cancel());
    _setPrompt(null);
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
    _cardTimer?.cancel();
    _wakeOn = false;
    ui.dispose();
  }
}

/// Ключ справочника → вид отметки для сервера.
MarkKind markKindOf(String key) => MarkKind.fromKey(key);
