import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../algo/frame.dart';
import '../algo/params.dart';
import '../algo/pipeline.dart';
import '../algo/trip_state.dart';
import 'config.dart';
import 'csv_writer.dart';
import 'package:uuid/uuid.dart';

import 'local_db.dart';
import 'samples.dart';

enum RecorderPhase { off, idle, armed, driving }

/// Что рекордер просит у источника датчиков.
abstract class SensorControl {
  /// Датчики движения (≈60 Гц) включаем только при езде — экономия батареи.
  void setMotionSampling(bool on);

  /// GPS: true — точный режим 1 Гц (поездка), false — экономный режим ожидания.
  void setGpsActive(bool on);
}

class RecorderSnapshot {
  const RecorderSnapshot({this.phase = RecorderPhase.off, this.speedKmh = 0, this.distanceKm = 0, this.found = 0, this.tripStart, this.heading, this.lat, this.lon, this.lastTrip});
  final RecorderPhase phase;
  final double speedKmh, distanceKm;
  final int found;
  final DateTime? tripStart;
  final double? heading, lat, lon;
  final FinishedTrip? lastTrip;
}

class FinishedTrip {
  const FinishedTrip({required this.localId, required this.distanceKm, required this.potholes, required this.startedAt, required this.endedAt, required this.reason, required this.uploaded});
  final int localId, potholes;
  final double distanceKm;
  final DateTime startedAt, endedAt;
  final String reason;
  final bool uploaded; // положено в очередь отправки
}

/// Настройки записи.
class RecorderConfig {
  const RecorderConfig({
    this.armSpeedKmh = 10.0,
    this.disarmSpeedKmh = 6.0,
    this.disarmAfterS = 60.0,
    this.liveEveryS = 90.0,
    this.liveWindowS = 600.0,
    this.minUploadDistanceKm = 0.3,
    this.privacyTrimM = 200.0,
    this.runInIsolate = true,
  });
  final double armSpeedKmh, disarmSpeedKmh, disarmAfterS, liveEveryS, liveWindowS, minUploadDistanceKm, privacyTrimM;
  final bool runInIsolate;
}

/// Роль и профиль влияют на то, что отправляется.
class RecorderContext {
  const RecorderContext({this.role = 'driver', this.wheelbaseM = 2.6, this.mount = 'holder', this.rawDir, this.car = ''});
  final String role; // driver | passenger | research
  final double wheelbaseM;
  final String mount, car;
  final String? rawDir; // куда писать сырой CSV (только research)
}

/// Ядро фоновой записи: принимает отсчёты (из реальных датчиков или из воспроизведения CSV),
/// сам стартует/останавливает поездки, считает алгоритм v2 и кладёт результат в очередь отправки.
/// Не зависит от Flutter-плагинов, поэтому тестируется на записях analysis/*.csv.
class TripRecorder {
  TripRecorder({
    required this.db,
    required this.control,
    this.config = const RecorderConfig(),
    RecorderContext Function()? context,
    this.onSnapshot,
    this.onTripQueued,
  }) : _ctx = context ?? (() => const RecorderContext());

  final LocalDb db;
  final SensorControl control;
  final RecorderConfig config;
  final RecorderContext Function() _ctx;
  final void Function(RecorderSnapshot)? onSnapshot;
  final void Function(FinishedTrip)? onTripQueued;

  final TripDetector _det = TripDetector();
  TripBuffer _buf = TripBuffer();
  RecorderPhase _phase = RecorderPhase.off;
  ActivityKind _activity = ActivityKind.unknown;
  double? _t0Ms; // начало буфера
  double? _armedAt, _slowSince; // сек
  double _distanceM = 0, _speedKmh = 0;
  GpsFix? _lastFix;
  int _found = 0;
  double _lastLiveAt = 0;
  bool _liveBusy = false, _skipThisTrip = false;
  FinishedTrip? _lastTrip;
  double? _heading, _lat, _lon;

  RecorderPhase get phase => _phase;
  RecorderSnapshot get snapshot => RecorderSnapshot(
        phase: _phase,
        speedKmh: _speedKmh,
        distanceKm: _distanceM / 1000,
        found: _found,
        tripStart: _det.tripStart == null ? null : DateTime.fromMillisecondsSinceEpoch((_det.tripStart! * 1000).round()),
        heading: _heading,
        lat: _lat,
        lon: _lon,
        lastTrip: _lastTrip,
      );

  void _emit() => onSnapshot?.call(snapshot);

  /// Периодическое сохранение буфера идущей поездки (вызывает движок раз в минуту).
  /// Если процесс будет убит системой, при следующем запуске запись восстановится через [recoverFrom].
  void persist(File f) {
    if (_phase != RecorderPhase.driving || _buf.motionCount < 200) return;
    _buf.saveTo(f);
  }

  /// Обрабатывает оставшийся от прошлого запуска буфер как завершённую поездку (причина «recovered»).
  Future<FinishedTrip?> recoverFrom(File f) async {
    final b = TripBuffer.loadFrom(f);
    try {
      f.deleteSync();
    } catch (_) {}
    if (b == null || b.motionCount < 200 || b.gpsCount < 20) return null;
    final startMs = b.gTMs[0], endMs = b.gTMs[b.gpsCount - 1];
    _buf = b;
    _t0Ms = math.min(b.tMs[0], startMs);
    _distanceM = 0;
    _skipThisTrip = false;
    return _finishTrip(TripEnd(startMs / 1000, endMs / 1000, 'recovered'));
  }

  /// Удалить файл восстановления после штатного завершения.
  void clearPersisted(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Включить автоматическую запись (ждём поездку).
  void enable() {
    if (_phase == RecorderPhase.off) {
      _phase = RecorderPhase.idle;
      _emit();
    }
  }

  void disable() {
    _discard();
    _phase = RecorderPhase.off;
    _emit();
  }

  void onActivity(ActivityKind a) => _activity = a;

  void onMotion(MotionSample s) {
    if (_phase == RecorderPhase.armed || _phase == RecorderPhase.driving) {
      _t0Ms ??= s.tMs.toDouble();
      _buf.addMotion(s);
    }
  }

  /// Скорость фикса: из GPS, при отсутствии — по смещению.
  double _fixSpeed(GpsFix f) {
    if (f.speedMs.isFinite && f.speedMs >= 0) return f.speedMs;
    final p = _lastFix;
    if (p == null) return 0;
    final dt = (f.tMs - p.tMs) / 1000;
    if (dt <= 0) return 0;
    return haversine(p.lat, p.lon, f.lat, f.lon) / dt;
  }

  void onGps(GpsFix f) {
    if (_phase == RecorderPhase.off) return;
    final sp = _fixSpeed(f);
    final kmh = sp * 3.6;
    final t = f.tMs / 1000.0;
    _speedKmh = kmh;
    _heading = f.headingDeg.isNaN || f.headingDeg < 0 ? null : f.headingDeg;
    _lat = f.lat;
    _lon = f.lon;

    if (_phase == RecorderPhase.idle) {
      if (kmh >= config.armSpeedKmh || (_activity == ActivityKind.automotive && kmh >= 8)) {
        _arm(f);
      }
    }
    if (_phase == RecorderPhase.armed || _phase == RecorderPhase.driving) {
      _t0Ms ??= f.tMs.toDouble();
      _buf.addGps(f, sp);
      if (_lastFix != null) {
        final d = haversine(_lastFix!.lat, _lastFix!.lon, f.lat, f.lon);
        if (!d.isNaN && d < 500) _distanceM += d;
      }
    }
    _lastFix = f;

    final before = _det.phase;
    final end = _det.update(t, kmh, _activity);
    if (before != TripPhase.driving && _det.phase == TripPhase.driving) {
      _phase = RecorderPhase.driving;
      _lastLiveAt = t;
    }
    if (end != null) {
      _finishTrip(end);
    } else if (_phase == RecorderPhase.armed) {
      // ложное срабатывание: не набрали скорость старта
      if (kmh < config.disarmSpeedKmh) {
        _slowSince ??= t;
        if (t - _slowSince! >= config.disarmAfterS) _discard();
      } else {
        _slowSince = null;
      }
    } else if (_phase == RecorderPhase.driving) {
      _maybeLive(t);
    }
    _emit();
  }

  void _arm(GpsFix f) {
    _phase = RecorderPhase.armed;
    _armedAt = f.tMs / 1000.0;
    _slowSince = null;
    _buf = TripBuffer();
    _t0Ms = null;
    _distanceM = 0;
    _found = 0;
    _skipThisTrip = false;
    control.setMotionSampling(true);
    control.setGpsActive(true);
  }

  void _discard() {
    control.setMotionSampling(false);
    control.setGpsActive(false);
    _buf = TripBuffer();
    _t0Ms = null;
    _armedAt = _slowSince = null;
    _distanceM = 0;
    _found = 0;
    _det.phase = TripPhase.idle;
    if (_phase != RecorderPhase.off) _phase = RecorderPhase.idle;
  }

  /// Ручной старт («Начать поездку»): обходит порог скорости.
  void startManual(GpsFix? f) {
    if (_phase == RecorderPhase.driving) return;
    enable();
    _arm(f ?? GpsFix(DateTime.now().millisecondsSinceEpoch, 0, 0, 0, double.nan, 0));
    _det.phase = TripPhase.driving;
    _det.tripStart = _armedAt;
    _phase = RecorderPhase.driving;
    _emit();
  }

  /// «Остановить поездку»: завершает и отправляет результат.
  Future<FinishedTrip?> stopManual() async {
    if (_phase != RecorderPhase.driving) {
      _discard();
      _emit();
      return null;
    }
    final t = (_lastFix?.tMs ?? DateTime.now().millisecondsSinceEpoch) / 1000.0;
    final end = _det.finish(t, 'manual');
    return end == null ? null : _finishTrip(end);
  }

  /// «Не записывать эту поездку»: всё, что набрано, удаляется, до остановки записи не ведём.
  void skipCurrentTrip() {
    _skipThisTrip = true;
    final keepDriving = _det.phase == TripPhase.driving;
    _discard();
    if (keepDriving) {
      // поездка продолжается, но мы её игнорируем до полной остановки
      _det.phase = TripPhase.idle;
    }
    _emit();
  }

  Future<FinishedTrip?> _finishTrip(TripEnd end) async {
    final buf = _buf;
    final t0 = _t0Ms ?? end.start * 1000;
    final skip = _skipThisTrip;
    final ctx = _ctx();
    _buf = TripBuffer();
    _t0Ms = null;
    _distanceM = 0;
    _found = 0;
    _phase = RecorderPhase.idle;
    control.setMotionSampling(false);
    control.setGpsActive(false);
    if (skip || buf.motionCount < 200 || buf.gpsCount < 20) {
      _emit();
      return null;
    }
    final (sens, gps) = buf.slice(end.start * 1000, end.end * 1000, t0);
    if (sens.length < 200 || gps.length < 20) {
      _emit();
      return null;
    }
    final params = AlgoParams.current.copyWith(wheelbaseM: ctx.wheelbaseM);
    final startedAt = DateTime.fromMillisecondsSinceEpoch((end.start * 1000).round());
    final endedAt = DateTime.fromMillisecondsSinceEpoch((end.end * 1000).round());
    TripResult res;
    try {
      res = config.runInIsolate ? await Isolate.run(() => processTrip(sens, gps, params)) : processTrip(sens, gps, params);
    } on ArgumentError {
      _emit();
      return null;
    }
    final trimmed = trimForPrivacy(res, gps, trimM: config.privacyTrimM);
    // режим транспорта: не-авто поездки не идут в карту ям
    final speedsKmh = [for (var i = 0; i < gps.length; i++) gps.speed[i] * 3.6];
    final (mode, modeConf) = classifyMode(speedsKmh, _stopsPerKm(speedsKmh, res.distanceKm));
    final potholes = trimmed.events.where((e) => e.type == 'pothole').length;
    final payload = tripPayload(trimmed, startedAt: startedAt, startReason: 'auto', endReason: end.reason, mode: mode, modeConf: modeConf);
    payload['client_id'] = const Uuid().v4(); // повторная отправка не создаст дубль на сервере
    if (ctx.role == 'passenger') {
      payload['suspension'] = <String, dynamic>{}; // подвеска не считается, пока машина не определена
      payload['damping'] = <String, dynamic>{};
    }
    final localId = db.addTrip(
      startedAt: startedAt.millisecondsSinceEpoch,
      endedAt: endedAt.millisecondsSinceEpoch,
      distanceKm: res.distanceKm,
      potholes: potholes,
      summary: {
        'mode': mode,
        'end_reason': end.reason,
        'segments': {for (final c in riLabels) c: trimmed.segments.where((s) => s.cls == c).length},
        'suspension': res.suspension.toJson(),
        'events_total': res.events.length,
      },
    );
    final upload = res.distanceKm >= config.minUploadDistanceKm && (trimmed.events.isNotEmpty || trimmed.segments.isNotEmpty);
    if (upload) {
      payload['_local'] = localId;
      db.enqueue('trip', _encode(payload));
    }
    if (ctx.role == 'research' && ctx.rawDir != null) {
      final csv = buildLoggerCsv(sens, gps, t0EpochMs: t0.round(), mount: ctx.mount, car: ctx.car, appVersion: AppConfig.appVersion);
      final f = writeLoggerCsvGz(ctx.rawDir!, 'trip_${startedAt.millisecondsSinceEpoch}', csv);
      db.enqueue('raw', f.path);
    }
    final ft = FinishedTrip(localId: localId, distanceKm: res.distanceKm, potholes: potholes, startedAt: startedAt, endedAt: endedAt, reason: end.reason, uploaded: upload);
    _lastTrip = ft;
    onTripQueued?.call(ft);
    _emit();
    return ft;
  }

  static const riLabels = ['A', 'B', 'C', 'D', 'E'];

  double _stopsPerKm(List<double> speeds, double km) {
    if (km <= 0) return 0;
    var stops = 0;
    var moving = false;
    for (final s in speeds) {
      if (s >= 5) moving = true;
      if (moving && s < 2) {
        stops++;
        moving = false;
      }
    }
    return stops / km;
  }

  // «живой» счётчик ям: периодически прогоняем алгоритм по хвосту записи
  void _maybeLive(double t) {
    if (_liveBusy || t - _lastLiveAt < config.liveEveryS || _buf.motionCount < 600) return;
    _lastLiveAt = t;
    _liveBusy = true;
    final t0 = _t0Ms ?? 0;
    final nowMs = _lastFix!.tMs.toDouble();
    final from = math.max(t0, nowMs - config.liveWindowS * 1000);
    final (sens, gps) = _buf.slice(from, nowMs, from);
    final params = AlgoParams.current.copyWith(wheelbaseM: _ctx().wheelbaseM);
    Future<TripResult> job() => config.runInIsolate ? Isolate.run(() => processTrip(sens, gps, params)) : Future.value(processTrip(sens, gps, params));
    job().then((r) {
      _found = r.events.where((e) => e.type == 'pothole').length;
      _emit();
    }).catchError((_) {}).whenComplete(() => _liveBusy = false);
  }

  String _encode(Map<String, dynamic> m) => jsonEncode(sanitizeJson(m));
}

/// Заменяет NaN/∞ на null (jsonEncode на них падает).
Object? sanitizeJson(Object? v) {
  if (v is double) return v.isFinite ? v : null;
  if (v is Map) return {for (final e in v.entries) e.key: sanitizeJson(e.value)};
  if (v is List) return [for (final x in v) sanitizeJson(x)];
  return v;
}
