import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'holi_log.dart';

/// Почему не получилось услышать. Каждая причина показывается водителю понятным текстом и попадает в журнал проверки голоса.
enum SpeechErrorKind { none, noSpeech, micDenied, micBlocked, unavailable, languageUnsupported, busy, network, startTimeout, failed }

class SpeechOutcome {
  const SpeechOutcome({this.text = '', this.error = SpeechErrorKind.none, this.engine = '', this.detail = '', this.heardSpeech = false, this.ms = 0});
  final String text;
  final SpeechErrorKind error;
  final String engine; // device | cloud
  final String detail; // техническая подробность для журнала
  final bool heardSpeech;
  final int ms;

  /// Тишина — не ошибка: водитель просто ничего не сказал.
  bool get failed => error != SpeechErrorKind.none && error != SpeechErrorKind.noSpeech;
  @override
  String toString() => 'SpeechOutcome($engine, "$text", $error $detail, $ms мс)';
}

/// Распознавание речи (подменяется в тестах). Звук не сохраняется: наружу выходит только текст.
abstract class SpeechEngine {
  /// Проверка перед первым прослушиванием: разрешения и наличие распознавателя. null — всё в порядке.
  Future<SpeechOutcome?> prepare();

  /// Слушает одну фразу. Ждёт речь до [noSpeechTimeout], после речи заканчивает через [silenceTimeout] тишины, но не дольше [maxDuration].
  Future<SpeechOutcome> listenOnce({
    required String lang,
    Duration maxDuration = const Duration(seconds: 25),
    Duration silenceTimeout = const Duration(milliseconds: 2500),
    Duration noSpeechTimeout = const Duration(seconds: 10),
    void Function(String text)? onPartial,
  });

  /// Закончить прослушивание досрочно, но вернуть то, что уже услышано.
  Future<void> stop();

  /// Прервать без результата.
  Future<void> cancel();
}

/// Разрешение на микрофон (и распознавание речи на iOS) с понятным результатом.
Future<SpeechErrorKind> ensureMicPermission() async {
  try {
    var st = await Permission.microphone.status;
    if (!st.isGranted) st = await Permission.microphone.request();
    if (st.isPermanentlyDenied || st.isRestricted) return SpeechErrorKind.micBlocked;
    if (!st.isGranted) return SpeechErrorKind.micDenied;
    return SpeechErrorKind.none;
  } catch (e) {
    HoliLog.add('permission error: $e');
    return SpeechErrorKind.none; // не смогли спросить — пусть решает сам движок
  }
}

/// Системное распознавание (Android: сервис Google; iOS: Speech framework).
class DeviceSpeechEngine implements SpeechEngine {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  Set<String> _locales = {};
  _Session? _s;

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(onStatus: _onStatus, onError: _onError);
      if (_ready) {
        _locales = (await _stt.locales()).map((l) => l.localeId.replaceAll('-', '_')).toSet();
        HoliLog.add('speech: готов, языков ${_locales.length}: ${_locales.where((l) => l.startsWith('ru') || l.startsWith('uz')).join(', ')}');
      } else {
        HoliLog.add('speech: initialize вернул false');
      }
    } catch (e) {
      HoliLog.add('speech: initialize упал: $e');
      _ready = false;
    }
    return _ready;
  }

  /// Язык распознавания: узбекский, если он есть в телефоне; иначе русский.
  String? localeFor(String lang) {
    final want = lang == 'uz' ? 'uz_UZ' : 'ru_RU';
    if (_locales.isEmpty || _locales.contains(want)) return want;
    return lang == 'uz' ? null : _locales.firstWhere((l) => l.startsWith('ru'), orElse: () => 'ru_RU');
  }

  bool supportsLang(String lang) => localeFor(lang) != null;

  @override
  Future<SpeechOutcome?> prepare() async {
    final perm = await ensureMicPermission();
    if (perm != SpeechErrorKind.none) return SpeechOutcome(error: perm, engine: 'device', detail: 'микрофон: $perm');
    if (!await _init()) return const SpeechOutcome(error: SpeechErrorKind.unavailable, engine: 'device', detail: 'на телефоне нет службы распознавания речи (нужно приложение Google)');
    return null;
  }

  void _onStatus(String status) {
    HoliLog.add('speech статус: $status');
    _s?.onStatus(status);
  }

  void _onError(SpeechRecognitionError e) {
    HoliLog.add('speech ошибка: ${e.errorMsg} (постоянная: ${e.permanent})');
    _s?.onError(e.errorMsg);
  }

  @override
  Future<SpeechOutcome> listenOnce({
    required String lang,
    Duration maxDuration = const Duration(seconds: 25),
    Duration silenceTimeout = const Duration(milliseconds: 2500),
    Duration noSpeechTimeout = const Duration(seconds: 10),
    void Function(String text)? onPartial,
  }) async {
    final sw = Stopwatch()..start();
    final prep = await prepare();
    if (prep != null) return prep;
    final locale = localeFor(lang);
    if (locale == null) return const SpeechOutcome(error: SpeechErrorKind.languageUnsupported, engine: 'device', detail: 'узбекский язык не установлен в распознавании телефона');
    // предыдущая сессия могла не закрыться
    if (_stt.isListening) {
      await _stt.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final s = _Session(maxDuration, silenceTimeout, noSpeechTimeout, onPartial);
      _s = s;
      try {
        await _stt.listen(
          onResult: s.onResult,
          listenOptions: SpeechListenOptions(localeId: locale, listenFor: maxDuration, pauseFor: silenceTimeout, partialResults: true, cancelOnError: false, listenMode: ListenMode.dictation),
        );
      } catch (e) {
        _s = null;
        return SpeechOutcome(error: SpeechErrorKind.failed, engine: 'device', detail: 'listen упал: $e', ms: sw.elapsedMilliseconds);
      }
      final r = await s.done.future;
      _s = null;
      if (r.error == SpeechErrorKind.busy && attempt == 0) {
        HoliLog.add('speech: занят, пробую ещё раз');
        await _stt.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      return SpeechOutcome(text: r.text, error: r.error, engine: 'device', detail: r.detail, heardSpeech: r.text.isNotEmpty, ms: sw.elapsedMilliseconds);
    }
    return SpeechOutcome(error: SpeechErrorKind.busy, engine: 'device', detail: 'распознаватель занят', ms: sw.elapsedMilliseconds);
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
    _s?.requestFinish('stop');
  }

  @override
  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    _s?.finish('', SpeechErrorKind.noSpeech, 'cancel');
  }
}

/// Одно прослушивание: собирает статусы и результаты платформы в один итог.
class _Session {
  _Session(this.maxDuration, this.silenceTimeout, this.noSpeechTimeout, this.onPartial) {
    _startTimer = Timer(const Duration(seconds: 6), () => finish('', SpeechErrorKind.startTimeout, 'распознаватель не начал слушать за 6 с'));
    _maxTimer = Timer(maxDuration + const Duration(seconds: 4), () => finish(text, text.isEmpty ? SpeechErrorKind.noSpeech : SpeechErrorKind.none, 'таймаут'));
  }
  final Duration maxDuration, silenceTimeout, noSpeechTimeout;
  final void Function(String text)? onPartial;
  final done = Completer<({String text, SpeechErrorKind error, String detail})>();
  String text = '';
  bool listening = false;
  Timer? _startTimer, _maxTimer, _graceTimer;

  void onResult(dynamic r) {
    text = (r.recognizedWords as String).trim();
    if (text.isNotEmpty) onPartial?.call(text);
    if (r.finalResult == true) requestFinish('final');
  }

  void onStatus(String s) {
    if (s == 'listening') {
      listening = true;
      _startTimer?.cancel();
    } else if ((s == 'done' || s == 'notListening') && listening) {
      requestFinish(s);
    }
  }

  void onError(String msg) {
    switch (msg) {
      case 'error_no_match':
      case 'error_speech_timeout':
        finish(text, text.isEmpty ? SpeechErrorKind.noSpeech : SpeechErrorKind.none, msg);
      case 'error_busy':
        finish(text, SpeechErrorKind.busy, msg);
      case 'error_permission':
        finish('', SpeechErrorKind.micDenied, msg);
      case 'error_network':
      case 'error_network_timeout':
        finish(text, text.isEmpty ? SpeechErrorKind.network : SpeechErrorKind.none, msg);
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        finish('', SpeechErrorKind.languageUnsupported, msg);
      default:
        // например error_client / error_audio: если текст уже есть — берём его
        finish(text, text.isEmpty ? SpeechErrorKind.failed : SpeechErrorKind.none, msg);
    }
  }

  /// Платформа закончила: ждём чуть-чуть, вдруг ещё придёт итоговый результат.
  void requestFinish(String why) {
    _graceTimer ??= Timer(const Duration(milliseconds: 350), () => finish(text, text.isEmpty ? SpeechErrorKind.noSpeech : SpeechErrorKind.none, why));
  }

  void finish(String t, SpeechErrorKind e, String detail) {
    if (done.isCompleted) return;
    _startTimer?.cancel();
    _maxTimer?.cancel();
    _graceTimer?.cancel();
    done.complete((text: t, error: e, detail: detail));
  }
}
