import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../l10n/app_localizations.dart';
import 'ahead_warner.dart';
import 'announcer.dart';
import 'api_client.dart';
import 'config.dart';
import 'device_auth.dart';
import 'engine.dart';
import 'local_db.dart';
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
    announcer: TtsAnnouncer(),
    auth: DeviceAuth(SecureTokenStore()),
    settings: () => ref.read(settingsProvider),
    rawDir: ref.watch(supportDirProvider) == null ? null : '${ref.watch(supportDirProvider)}/raw',
    recoveryFile: ref.watch(supportDirProvider) == null ? null : File('${ref.watch(supportDirProvider)}/current_trip.bin'),
    platform: Platform.isIOS ? 'ios' : 'android',
  );
  ref.onDispose(e.dispose);
  return e;
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
