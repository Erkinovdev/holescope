import 'dart:async';

import 'holi_log.dart';
import 'speech_engine.dart';

/// Как слушать: сам выбрать (сначала телефон, при сбое — сервер), только телефон или только сервер.
enum RecognizerMode { auto, device, cloud }

/// Единый «слух» Холи: телефонное распознавание и серверное с автоматическим запасным вариантом.
/// Если системное распознавание не работает (нет службы Google, нет языка, нет сети), то в этой сессии дальше слушаем сервером.
class VoiceRecognizer implements SpeechEngine {
  VoiceRecognizer({required this.device, required this.cloud, required this.mode, this.cloudAvailable});
  final SpeechEngine device;
  final SpeechEngine cloud;
  final RecognizerMode Function() mode;
  final bool Function()? cloudAvailable; // есть ли смысл ходить на сервер (адрес задан)

  bool _preferCloud = false;
  int _deviceFails = 0;
  SpeechEngine? _active;

  /// Какой движок отвечал в последний раз (для экрана проверки).
  String lastEngine = '';

  static const _fallbackKinds = {SpeechErrorKind.unavailable, SpeechErrorKind.languageUnsupported, SpeechErrorKind.failed, SpeechErrorKind.network, SpeechErrorKind.startTimeout, SpeechErrorKind.busy};

  @override
  Future<SpeechOutcome?> prepare() async {
    final m = mode();
    if (m == RecognizerMode.cloud || _preferCloud) return cloud.prepare();
    final d = await device.prepare();
    if (d == null) return null;
    if (m == RecognizerMode.auto && _fallbackKinds.contains(d.error) && (cloudAvailable?.call() ?? true)) {
      HoliLog.add('слух: телефон недоступен (${d.error}), перехожу на сервер');
      _preferCloud = true;
      return cloud.prepare();
    }
    return d;
  }

  @override
  Future<SpeechOutcome> listenOnce({
    required String lang,
    Duration maxDuration = const Duration(seconds: 25),
    Duration silenceTimeout = const Duration(milliseconds: 2500),
    Duration noSpeechTimeout = const Duration(seconds: 10),
    void Function(String text)? onPartial,
  }) async {
    final m = mode();
    final useCloudFirst = m == RecognizerMode.cloud || (m == RecognizerMode.auto && _preferCloud);
    final first = useCloudFirst ? cloud : device;
    _active = first;
    var r = await first.listenOnce(lang: lang, maxDuration: maxDuration, silenceTimeout: first == cloud ? const Duration(milliseconds: 1600) : silenceTimeout, noSpeechTimeout: noSpeechTimeout, onPartial: onPartial);
    lastEngine = r.engine;
    HoliLog.add('слух: $r');
    if (first == device && r.failed) {
      _deviceFails++;
      if (m == RecognizerMode.auto && _fallbackKinds.contains(r.error) && (cloudAvailable?.call() ?? true)) {
        if (_deviceFails >= 2 || r.error == SpeechErrorKind.unavailable || r.error == SpeechErrorKind.languageUnsupported) _preferCloud = true;
        HoliLog.add('слух: пробую сервер вместо телефона');
        _active = cloud;
        r = await cloud.listenOnce(lang: lang, maxDuration: maxDuration, silenceTimeout: const Duration(milliseconds: 1600), noSpeechTimeout: noSpeechTimeout, onPartial: onPartial);
        lastEngine = r.engine;
        HoliLog.add('слух: $r');
      }
    } else if (first == device && !r.failed) {
      _deviceFails = 0;
    }
    return r;
  }

  @override
  Future<void> stop() async => _active?.stop();

  @override
  Future<void> cancel() async {
    await device.cancel();
    await cloud.cancel();
  }
}
