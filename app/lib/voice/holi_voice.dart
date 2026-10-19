import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'holi_phrase.dart';

/// Одна фраза из assets/holi/holi_phrases.json.
class HoliEntry {
  const HoliEntry({
    required this.key,
    required this.ru,
    required this.uz,
    required this.file,
  });
  final String key, ru, uz, file;

  factory HoliEntry.fromJson(Map<String, dynamic> j) => HoliEntry(
    key: j['key'] as String,
    ru: j['ru'] as String,
    uz: j['uz'] as String,
    file: (j['file'] ?? j['key']) as String,
  );
  String text(String lang) => lang == 'uz' ? uz : ru;
  String assetPath(String lang) =>
      'assets/holi/audio/${file}_${lang == 'uz' ? 'uz' : 'ru'}.mp3';
}

/// Проигрыватель файла (подменяется в тестах).
abstract class HoliPlayer {
  /// Играет файл до конца. false — не удалось (тогда включится запасной голос).
  Future<bool> play(String asset);
  Future<void> stop();
}

/// Запасной вариант: системная озвучка текстом из JSON.
abstract class HoliFallback {
  Future<void> speak(String text, String lang);
  Future<void> stop();
}

/// Аудио-сессия: пока звучит Холи, музыка и навигация приглушаются (ducking), потом возвращаются.
abstract class HoliSession {
  Future<void> begin();
  Future<void> end();
}

class HoliVoice {
  HoliVoice({
    required this.phrases,
    required this.assets,
    required this.player,
    required this.session,
    this.fallback,
    required this.lang,
    this.maxQueue = 3,
  });

  final Map<String, HoliEntry> phrases;
  final Set<String> assets;
  final HoliPlayer player;
  final HoliSession session;
  final HoliFallback? fallback;
  final String Function() lang;
  final int maxQueue;

  final _queue = <String>[];
  bool _running = false;
  Completer<void>? _idle;
  int _holds = 0;
  bool _sessionOn = false;

  /// Есть ли такая фраза (для необязательных вариантов, например озвучка конкретного уровня ямы).
  bool hasKey(String key) => phrases.containsKey(key);

  /// Пока идёт диалог, аудио-сессия не отпускается между фразами и прослушиванием: иначе музыка «дёргается», а на iPhone голос теряет громкость.
  void hold() => _holds++;

  /// Конец диалога: отпустить сессию, если нет других удержаний и ничего не говорится.
  void release() {
    if (_holds > 0) _holds--;
    if (_holds == 0 && !_running && _sessionOn) unawaited(_endSession());
  }

  Future<void> _endSession() async {
    _sessionOn = false;
    try {
      await session.end();
    } catch (_) {}
  }

  /// true, пока Холи говорит (микрофон в это время не слушаем, чтобы она не услышала саму себя).
  final speaking = ValueNotifier<bool>(false);

  /// Последняя произнесённая фраза (для показа на экране).
  final lastText = ValueNotifier<String>('');

  /// Короткий мягкий сигнал: «сейчас спрошу про удар».
  Future<void> chime() async {
    const asset = 'assets/holi/chime.wav';
    try {
      await session.begin();
      _sessionOn = true;
      await player.play(asset);
    } catch (_) {
      // не критично: вопрос прозвучит и без сигнала
    }
  }

  /// Фразы из ресурсов приложения.
  static Future<HoliVoice> load({required String Function() lang}) async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/holi/holi_phrases.json'))
            as List;
    final entries = {
      for (final e in raw)
        (e as Map<String, dynamic>)['key'] as String: HoliEntry.fromJson(e),
    };
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return HoliVoice(
      phrases: entries,
      assets: manifest
          .listAssets()
          .where((a) => a.startsWith('assets/holi/audio/'))
          .toSet(),
      player: JustAudioHoliPlayer(),
      session: AudioSessionHoli(),
      fallback: TtsHoliFallback(),
      lang: lang,
    );
  }

  /// Поставить фразу в очередь. Одинаковая подряд идущая фраза не дублируется; очередь короткая — устаревшее предупреждение не нужно.
  Future<void> play(HoliPhrase p, {int? distanceM}) =>
      playKey(distanceM == null ? p.key : p.distanceKey(distanceM));

  Future<void> playKey(String key, {bool priority = false}) {
    if (!phrases.containsKey(key)) return Future.value();
    if (_queue.isNotEmpty && _queue.last == key) return idle;
    if (priority) {
      _queue.insert(0, key);
    } else {
      _queue.add(key);
    }
    while (_queue.length > maxQueue) {
      _queue.removeAt(priority ? _queue.length - 1 : 0);
    }
    _idle ??= Completer<void>();
    if (!_running) unawaited(_drain());
    return _idle!.future;
  }

  /// Завершается, когда очередь пуста и ничего не звучит.
  Future<void> get idle => _idle?.future ?? Future.value();

  /// Остановить звук и очистить очередь.
  Future<void> stop() async {
    _queue.clear();
    await player.stop();
    await fallback?.stop();
  }

  Future<void> _drain() async {
    _running = true;
    speaking.value = true;
    try {
      if (!_sessionOn) {
        await session.begin();
        _sessionOn = true;
      }
      while (_queue.isNotEmpty) {
        final key = _queue.removeAt(0);
        final e = phrases[key]!;
        final l = lang();
        lastText.value = e.text(l);
        var ok = false;
        final path = e.assetPath(l);
        if (assets.contains(path)) {
          try {
            ok = await player.play(path);
          } catch (_) {
            ok = false;
          }
        }
        if (!ok) {
          try {
            await fallback?.speak(e.text(l), l);
          } catch (_) {}
        }
      }
    } finally {
      if (_holds == 0) await _endSession();
      _running = false;
      speaking.value = false;
      final c = _idle;
      _idle = null;
      c?.complete();
    }
  }
}

class JustAudioHoliPlayer implements HoliPlayer {
  // Сессию ведём сами (HoliSession), прерывания от других приложений не должны обрывать фразу на полуслове: при паузе дожидаемся и продолжаем.
  final AudioPlayer _p = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );

  @override
  Future<bool> play(String asset) async {
    final dur = await _p.setAsset(asset);
    final done = _p.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed,
    );
    unawaited(_p.play());
    final limit =
        (dur ?? const Duration(seconds: 8)) + const Duration(seconds: 4);
    final sw = Stopwatch()..start();
    while (sw.elapsed < limit * 2) {
      final finished = await Future.any<bool>([
        done.then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 400), () => false),
      ]);
      if (finished) return true;
      if (!_p.playing && _p.processingState != ProcessingState.completed) {
        unawaited(
          _p.play(),
        ); // фразу прервали (звонок, навигация) — продолжаем с того же места
      }
    }
    await _p.stop();
    return true;
  }

  @override
  Future<void> stop() => _p.stop();
}

class TtsHoliFallback implements HoliFallback {
  final FlutterTts _tts = FlutterTts();
  String? _lang;

  @override
  Future<void> speak(String text, String lang) async {
    if (_lang != lang) {
      final code = lang == 'uz' ? 'uz-UZ' : 'ru-RU';
      final ok = await _tts.isLanguageAvailable(code);
      await _tts.setLanguage(ok == true ? code : 'ru-RU');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(true);
      _lang = lang;
    }
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async => _tts.stop();
}

class AudioSessionHoli implements HoliSession {
  Future<AudioSession> _s() async {
    final s = await AudioSession.instance;
    // настройки применяем при каждом включении: распознавание речи меняет режим сессии, и без этого голос после него тише
    await s.configure(
      AudioSessionConfiguration(
        // playAndRecord: чтобы после фразы можно было сразу слушать команду; duckOthers: музыка и навигация тише, а не выключаются
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.duckOthers |
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistanceNavigationGuidance,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
    return s;
  }

  @override
  Future<void> begin() async => (await _s()).setActive(true);

  @override
  Future<void> end() async => (await _s()).setActive(
    false,
    avAudioSessionSetActiveOptions:
        AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
  );
}
