import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../algo/trip_state.dart';
import '../core/settings.dart';
import 'ahead_warner.dart';
import 'announcer.dart';
import 'api_client.dart';
import 'device_auth.dart';
import 'local_db.dart';
import 'outbox.dart';
import 'samples.dart';
import 'sensor_source.dart';
import 'trip_recorder.dart';

/// Оркестратор фоновой записи: датчики → рекордер → предупреждения/озвучка → очередь отправки.
class RecorderEngine {
  RecorderEngine({
    required this.db,
    required this.source,
    required this.api,
    required this.announcer,
    required this.auth,
    required this.settings,
    this.rawDir,
    this.recoveryFile,
    this.platform = '',
    RecorderConfig config = const RecorderConfig(),
  }) {
    recorder = TripRecorder(
      db: db,
      control: source,
      config: config,
      context: _context,
      onSnapshot: (s) => snapshot.value = s,
      onTripQueued: (t) {
        if (recoveryFile != null) recorder.clearPersisted(recoveryFile!);
        unawaited(flushOutbox());
      },
    );
    warner = AheadWarner(db, api, config: () => AheadConfig(warnDistanceM: settings().warnDistanceM));
    outbox = OutboxWorker(db, api);
  }

  final LocalDb db;
  final SensorSource source;
  final ApiClient api;
  final Announcer announcer;
  final DeviceAuth auth;
  final AppSettings Function() settings;
  final String? rawDir;
  final File? recoveryFile; // буфер идущей поездки на диске
  final String platform;

  late final TripRecorder recorder;
  late final AheadWarner warner;
  late final OutboxWorker outbox;

  final snapshot = ValueNotifier<RecorderSnapshot>(const RecorderSnapshot());
  final warning = ValueNotifier<AheadItem?>(null);
  final queueSize = ValueNotifier<int>(0);

  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _flushTimer, _clearWarn, _persistTimer;
  bool _running = false;

  RecorderContext _context() {
    final s = settings();
    return RecorderContext(
      role: s.role.name,
      wheelbaseM: (s.wheelbaseMm ?? 2600) / 1000.0, // TODO(этап 3): колёсная база из справочника CarModel
      mount: s.mount.name,
      rawDir: rawDir,
      car: s.carName ?? '',
    );
  }

  bool get running => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final rf = recoveryFile;
    if (rf != null && rf.existsSync()) await recorder.recoverFrom(rf); // поездка, прерванная гибелью процесса
    await source.start();
    recorder.enable();
    _subs
      ..add(source.motion.listen(recorder.onMotion))
      ..add(source.activity.listen(recorder.onActivity))
      ..add(source.gps.listen(_onGps));
    _flushTimer = Timer.periodic(const Duration(minutes: 3), (_) => flushOutbox());
    _persistTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (recoveryFile != null) recorder.persist(recoveryFile!);
    });
    queueSize.value = db.outboxCount();
    unawaited(flushOutbox());
  }

  Future<void> stop() async {
    _running = false;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _flushTimer?.cancel();
    _persistTimer?.cancel();
    recorder.disable();
    await source.stop();
  }

  void _onGps(GpsFix f) {
    final before = recorder.phase;
    recorder.onGps(f);
    if (recorder.phase == RecorderPhase.idle && before != RecorderPhase.idle) warner.reset();
    final s = settings();
    final speedKmh = recorder.snapshot.speedKmh;
    final hd = f.headingDeg;
    if (recorder.phase == RecorderPhase.off || speedKmh < 10 || hd.isNaN) return;
    unawaited(warner.refreshIfNeeded(f.lat, f.lon));
    // обновляем расстояние до уже озвученной ямы
    final cur = warning.value;
    if (cur != null) {
      final p = AheadWarner.project(f.lat, f.lon, hd, cur.lat, cur.lon);
      if (p.along <= 5) {
        warning.value = null;
      } else {
        warning.value = AheadItem(id: cur.id, distanceM: p.along.round(), side: cur.side, level: cur.level, safeSpeed: cur.safeSpeed, type: cur.type, lat: cur.lat, lon: cur.lon);
      }
    }
    final item = warner.check(f.lat, f.lon, hd);
    if (item != null) {
      warning.value = item;
      _clearWarn?.cancel();
      _clearWarn = Timer(const Duration(seconds: 12), () => warning.value = null);
      unawaited(announcer.warn(item, lang: s.locale?.languageCode ?? 'ru', speedKmh: speedKmh, voice: s.voice, beep: s.beep));
    }
  }

  // ── ручное управление ──
  void startManual() => recorder.startManual(null);
  Future<FinishedTrip?> stopManual() async {
    final t = await recorder.stopManual();
    queueSize.value = db.outboxCount();
    return t;
  }

  void skipTrip() => recorder.skipCurrentTrip();

  /// Регистрация (при первой отправке) и отправка очереди. Безопасно вызывать часто.
  Future<void> flushOutbox() async {
    queueSize.value = db.outboxCount();
    if (queueSize.value == 0) return;
    try {
      final s = settings();
      await auth.ensureRegistered(api, platform: platform, lang: s.locale?.languageCode ?? 'ru', role: s.role == DeviceRole.passenger ? 'passenger' : (s.role == DeviceRole.research ? 'research' : 'driver'));
      if (auth.lastNickname != null) db.kvSet('nickname', auth.lastNickname!);
      await outbox.flush();
    } on ApiException {
      // нет сети — повторим по таймеру
    } finally {
      queueSize.value = db.outboxCount();
    }
  }

  /// Обновляет профиль машины на сервере (колёсная база, положение телефона и т.д.).
  Future<void> syncVehicle() async {
    final s = settings();
    try {
      await auth.ensureRegistered(api, platform: platform);
      await api.patchVehicle({
        if (s.carName != null) 'name': s.carName,
        if (s.wheelbaseMm != null) 'wheelbase_mm': s.wheelbaseMm,
        if (s.pressureBar != null) 'tire_pressure_bar': s.pressureBar,
        'mount': s.mount.name,
      });
    } on ApiException {
      // повторится при следующем запуске
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _persistTimer?.cancel();
    _clearWarn?.cancel();
    snapshot.dispose();
    warning.dispose();
    queueSize.dispose();
  }
}

/// ActivityKind из строки (для отладки).
ActivityKind activityFromName(String n) => ActivityKind.values.firstWhere((e) => e.name == n, orElse: () => ActivityKind.unknown);
