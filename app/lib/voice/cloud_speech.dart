import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'holi_log.dart';
import 'speech_engine.dart';

/// Отправка записи на сервер для распознавания. Возвращает текст.
typedef Transcriber = Future<String> Function(File wav, String lang);

/// Распознавание на нашем сервере (Whisper). Работает на любом телефоне, в том числе без службы Google, и лучше понимает узбекский.
/// Записывает с микрофона, сам определяет конец фразы по паузе, отправляет короткий WAV (≈ 100–300 КБ), файл сразу удаляет.
class CloudSpeechEngine implements SpeechEngine {
  CloudSpeechEngine(this._transcribe, {this.dirProvider});
  final Transcriber _transcribe;
  final Future<Directory> Function()? dirProvider;
  final AudioRecorder _rec = AudioRecorder();
  bool _stopRequested = false, _cancelled = false;

  @override
  Future<SpeechOutcome?> prepare() async {
    final perm = await ensureMicPermission();
    if (perm != SpeechErrorKind.none) return SpeechOutcome(error: perm, engine: 'cloud', detail: 'микрофон: $perm');
    try {
      if (!await _rec.hasPermission()) return const SpeechOutcome(error: SpeechErrorKind.micDenied, engine: 'cloud', detail: 'нет доступа к микрофону');
    } catch (e) {
      return SpeechOutcome(error: SpeechErrorKind.failed, engine: 'cloud', detail: 'запись недоступна: $e');
    }
    return null;
  }

  @override
  Future<SpeechOutcome> listenOnce({
    required String lang,
    Duration maxDuration = const Duration(seconds: 25),
    Duration silenceTimeout = const Duration(milliseconds: 1500),
    Duration noSpeechTimeout = const Duration(seconds: 10),
    void Function(String text)? onPartial,
  }) async {
    final sw = Stopwatch()..start();
    final prep = await prepare();
    if (prep != null) return prep;
    _stopRequested = false;
    _cancelled = false;
    final dir = await (dirProvider?.call() ?? getTemporaryDirectory());
    final file = File('${dir.path}/holi_${DateTime.now().millisecondsSinceEpoch}.wav');
    try {
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1, echoCancel: true, noiseSuppress: true, autoGain: true), path: file.path);
    } catch (e) {
      return SpeechOutcome(error: SpeechErrorKind.failed, engine: 'cloud', detail: 'не удалось начать запись: $e', ms: sw.elapsedMilliseconds);
    }
    HoliLog.add('cloud: запись пошла');

    // определение речи по громкости: порог = шум вокруг + запас (в машине фон громкий)
    final floor = <double>[];
    var speech = false, loudRun = 0;
    var lastLoud = sw.elapsedMilliseconds;
    var startedAt = sw.elapsedMilliseconds;
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_cancelled) break;
      final now = sw.elapsedMilliseconds;
      double db;
      try {
        db = (await _rec.getAmplitude()).current;
      } catch (_) {
        db = -60;
      }
      if (floor.length < 6) {
        floor.add(db);
      } else {
        final base = floor.reduce((a, b) => a + b) / floor.length;
        final threshold = (base + 9).clamp(-45.0, -18.0);
        if (db > threshold) {
          loudRun++;
          lastLoud = now;
          if (loudRun >= 2 && !speech) {
            speech = true;
            startedAt = now;
            HoliLog.add('cloud: речь началась (${db.toStringAsFixed(0)} дБ, порог ${threshold.toStringAsFixed(0)})');
          }
        } else {
          loudRun = 0;
        }
      }
      if (_stopRequested) break;
      if (speech && now - lastLoud > silenceTimeout.inMilliseconds && now - startedAt > 500) break;
      if (!speech && now > noSpeechTimeout.inMilliseconds) break;
      if (now > maxDuration.inMilliseconds) break;
    }
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (_cancelled) {
      _safeDelete(file);
      return SpeechOutcome(engine: 'cloud', error: SpeechErrorKind.noSpeech, detail: 'cancel', ms: sw.elapsedMilliseconds);
    }
    if (!speech && !_stopRequested) {
      _safeDelete(file);
      return SpeechOutcome(engine: 'cloud', error: SpeechErrorKind.noSpeech, detail: 'речи не было', ms: sw.elapsedMilliseconds);
    }
    final f = File(path ?? file.path);
    try {
      final size = await f.length();
      HoliLog.add('cloud: отправляю $size байт');
      final text = (await _transcribe(f, lang)).trim();
      HoliLog.add('cloud: ответ "$text" за ${sw.elapsedMilliseconds} мс');
      return SpeechOutcome(text: text, engine: 'cloud', heardSpeech: true, error: text.isEmpty ? SpeechErrorKind.noSpeech : SpeechErrorKind.none, ms: sw.elapsedMilliseconds);
    } on SocketException catch (e) {
      return SpeechOutcome(error: SpeechErrorKind.network, engine: 'cloud', detail: 'нет сети: $e', heardSpeech: true, ms: sw.elapsedMilliseconds);
    } catch (e) {
      final msg = e.toString();
      final net = msg.contains('connection') || msg.contains('timeout') || msg.contains('SocketException');
      return SpeechOutcome(error: net ? SpeechErrorKind.network : SpeechErrorKind.failed, engine: 'cloud', detail: 'сервер: $msg', heardSpeech: true, ms: sw.elapsedMilliseconds);
    } finally {
      _safeDelete(f);
      _safeDelete(file);
    }
  }

  void _safeDelete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  Future<void> stop() async => _stopRequested = true;

  @override
  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _rec.cancel();
    } catch (_) {}
  }
}
