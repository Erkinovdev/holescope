import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../l10n/app_localizations.dart';
import '../voice/holi_controller.dart';
import '../voice/holi_phrase.dart';
import '../voice/holi_voice.dart';
import '../algo/event_guess.dart';
import '../voice/cloud_speech.dart';
import '../voice/speech_engine.dart';
import '../voice/voice_recognizer.dart';
import 'ahead_warner.dart';
import 'local_db.dart';
import 'announcer.dart';
import 'api_client.dart';
import 'config.dart';
import 'device_auth.dart';
import 'engine.dart';
import 'mark_service.dart';
import 'permissions.dart';
import 'sensor_source.dart';
import 'trip_recorder.dart';

/// Все три переопределяются в main() (или в тестах).
final dbProvider = Provider<LocalDb>((ref) => throw UnimplementedError('override dbProvider'));
/// Каталог для сырых записей (исследовательский режим); переопределяется в main().
final supportDirProvider = Provider<String?>((ref) => null);

final engineProvider = Provider<RecorderEngine>((ref) {
  final e = RecorderEngine(
    db: ref.watch(dbProvider),
    source: RealSensorSource(texts: () {
      final code = ref.read(settingsProvider).locale?.languageCode ?? PlatformDispatcher.instance.locale.languageCode;
      final l = lookupAppLocalizations(Locale(code == 'uz' ? 'uz' : 'ru'));
      return ForegroundTexts(title: l.appName, recording: l.notifRecording, waiting: l.notifWaiting);
    }),
    api: ref.watch(apiProvider),
    announcer: HoliAnnouncer(ref.watch(holiVoiceProvider)),
    auth: DeviceAuth(SecureTokenStore()),
    settings: () => ref.read(settingsProvider),
    rawDir: ref.watch(supportDirProvider) == null ? null : '${ref.watch(supportDirProvider)}/raw',
    recoveryFile: ref.watch(supportDirProvider) == null ? null : File('${ref.watch(supportDirProvider)}/current_trip.bin'),
    platform: Platform.isIOS ? 'ios' : 'android',
  );
  ref.onDispose(e.dispose);
  return e;
});
/// Язык голоса: настройки приложения (ru/uz), иначе язык системы.
String _voiceLang(Ref ref) {
  final code = ref.read(settingsProvider).locale?.languageCode ?? PlatformDispatcher.instance.locale.languageCode;
  return code == 'uz' ? 'uz' : 'ru';
}

/// Озвучка Холи (файлы mp3, запасной вариант — системный голос).
final holiVoiceProvider = Provider<Future<HoliVoice>>((ref) => HoliVoice.load(lang: () => _voiceLang(ref)));

/// Что телефон уже знает о месте удара: известный объект рядом (из локального кэша ям) — подсказка для догадки.
GuessContext _contextFor(RecorderEngine eng, HoliCandidate c) {
  CachedCluster? best;
  var bd = 25.0;
  for (final k in eng.db.clustersNear(c.lat, c.lon, 30)) {
    if (k.status == 'false' || k.status == 'fixed') continue;
    final p = AheadWarner.project(c.lat, c.lon, 0, k.lat, k.lon);
    final d = math.sqrt(p.along * p.along + p.across * p.across);
    if (d < bd) {
      bd = d;
      best = k;
    }
  }
  if (best == null) return const GuessContext();
  final type = switch (best.type) { 'rough_patch' => 'washboard', final t => t };
  return GuessContext(nearType: type, nearPasses: best.status == 'confirmed' ? 3 : 1);
}

/// «Слух» Холи: распознавание на телефоне с запасным вариантом на сервере (режим выбирается в настройках).
final voiceRecognizerProvider = Provider<VoiceRecognizer>((ref) {
  final eng = ref.read(engineProvider);
  return VoiceRecognizer(
    device: DeviceSpeechEngine(),
    cloud: CloudSpeechEngine((wav, lang) async {
      await eng.auth.ensureRegistered(eng.api, platform: eng.platform);
      return eng.api.transcribe(wav, lang);
    }),
    mode: () => switch (ref.read(settingsProvider).holiEngine) {
      'device' => RecognizerMode.device,
      'cloud' => RecognizerMode.cloud,
      _ => RecognizerMode.auto,
    },
  );
});

/// Диалог Холи: команды, вопрос «да/нет» после удара, отметки. Подключается к движку записи.
final holiControllerProvider = FutureProvider<HoliController>((ref) async {
  final voice = await ref.watch(holiVoiceProvider);
  final eng = ref.read(engineProvider);
  final marks = MarkService(db: eng.db, api: eng.api, auth: eng.auth, platform: eng.platform);
  final ctrl = HoliController(
    voice: voice,
    speech: ref.read(voiceRecognizerProvider),
    marks: marks,
    fixAt: eng.fixAt,
    lang: () => _voiceLang(ref),
    speakEnabled: () => ref.read(settingsProvider).voice,
    contextFor: (c) => _contextFor(eng, c),
  );
  eng.onCandidate = (c) {
    if (ref.read(settingsProvider).holiAsk) unawaited(ctrl.askEvent(c));
  };
  eng.onTripDone = (t) {
    ctrl.resetTrip();
    if (ref.read(settingsProvider).voice) unawaited(voice.play(HoliPhrase.tripDone));
    unawaited(marks.flush());
  };
  final flush = Timer.periodic(const Duration(minutes: 3), (_) => unawaited(marks.flush()));
  unawaited(marks.flush());
  ref.listen(settingsProvider.select((s) => s.holiWake), (_, on) => on ? unawaited(ctrl.startWakeLoop()) : unawaited(ctrl.stopWakeLoop()));
  if (ref.read(settingsProvider).holiWake) unawaited(ctrl.startWakeLoop());
  ref.onDispose(() {
    flush.cancel();
    eng.onCandidate = null;
    eng.onTripDone = null;
    marks.dispose();
    ctrl.dispose();
  });
  return ctrl;
});

final permissionServiceProvider = Provider<PermissionService>((ref) => DevicePermissionService());

final apiProvider = Provider<ApiClient>((ref) => ApiClient(AppConfig.resolveApiBase()));

/// Подписка на ValueNotifier движка.
class _Listenable<T> extends Notifier<T> {
  _Listenable(this._pick);
  final ValueListenable<T> Function(RecorderEngine) _pick;
  @override
  T build() {
    final l = _pick(ref.watch(engineProvider));
    void cb() => state = l.value;
    l.addListener(cb);
    ref.onDispose(() => l.removeListener(cb));
    return l.value;
  }
}

final recorderSnapshotProvider = NotifierProvider<_Listenable<RecorderSnapshot>, RecorderSnapshot>(() => _Listenable((e) => e.snapshot));
final warningProvider = NotifierProvider<_Listenable<AheadItem?>, AheadItem?>(() => _Listenable((e) => e.warning));
final queueSizeProvider = NotifierProvider<_Listenable<int>, int>(() => _Listenable((e) => e.queueSize));

/// Локальная история поездок и итоги (перечитывается при смене состояния рекордера).
final tripsProvider = Provider<List<LocalTrip>>((ref) {
  ref.watch(recorderSnapshotProvider.select((s) => s.lastTrip?.localId));
  return ref.watch(dbProvider).trips();
});

final totalsProvider = Provider<({int trips, double km, int potholes})>((ref) {
  ref.watch(recorderSnapshotProvider.select((s) => s.lastTrip?.localId));
  return ref.watch(dbProvider).totals();
});

final nicknameProvider = Provider<String?>((ref) => ref.watch(dbProvider).kvGet('nickname'));
