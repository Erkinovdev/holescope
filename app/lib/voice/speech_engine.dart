import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Распознавание речи (подменяется в тестах). Записи звука не сохраняем: наружу выходит только распознанный текст.
abstract class SpeechEngine {
  Future<bool> init();

  /// Слушает до [listenFor]; [onText] вызывается с промежуточным и итоговым текстом. Завершается, когда прослушивание закончилось.
  Future<void> listen({required String lang, required Duration listenFor, required void Function(String text, bool isFinal) onText});
  Future<void> stop();
  bool get available;
}

class DeviceSpeechEngine implements SpeechEngine {
  final SpeechToText _stt = SpeechToText();
  bool _ok = false;
  Set<String> _locales = {};

  @override
  bool get available => _ok;

  @override
  Future<bool> init() async {
    if (_ok) return true;
    try {
      _ok = await _stt.initialize(onError: (_) {});
      if (_ok) _locales = (await _stt.locales()).map((l) => l.localeId.replaceAll('-', '_')).toSet();
    } catch (_) {
      _ok = false;
    }
    return _ok;
  }

  /// Узбекский распознаётся не на всех телефонах: если его нет — слушаем по-русски (названия «яма/люк» команды всё равно похожи).
  String _locale(String lang) {
    final want = lang == 'uz' ? 'uz_UZ' : 'ru_RU';
    return _locales.isEmpty || _locales.contains(want) ? want : 'ru_RU';
  }

  @override
  Future<void> listen({required String lang, required Duration listenFor, required void Function(String text, bool isFinal) onText}) async {
    if (!await init()) return;
    final done = Completer<void>();
    await _stt.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: _locale(lang),
        listenFor: listenFor,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
    // стоп придёт сам по таймеру/паузе; ждём статус «не слушаем»
    Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!_stt.isListening) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future.timeout(listenFor + const Duration(seconds: 3), onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
