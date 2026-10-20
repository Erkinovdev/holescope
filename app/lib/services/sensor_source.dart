import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart' as ar;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../algo/trip_state.dart';
import 'samples.dart';
import 'trip_recorder.dart';

/// Источник данных: реальные датчики телефона или воспроизведение (тесты).
abstract class SensorSource implements SensorControl {
  Stream<MotionSample> get motion;
  Stream<GpsFix> get gps;
  Stream<ActivityKind> get activity;
  Future<void> start();
  Future<void> stop();
}

/// Тексты уведомления foreground-сервиса Android (локализуются вызывающим).
class ForegroundTexts {
  const ForegroundTexts({this.title = 'Holescope', this.recording = 'Holescope записывает дорогу', this.waiting = 'Holescope ждёт поездку'});
  final String title, recording, waiting;
}

/// Реальные датчики: акселерометр + гироскоп (merge на частоте акселерометра), GPS, распознавание активности.
/// Android: геолокация работает как foreground service (уведомление). iOS: UIBackgroundModes=location.
class RealSensorSource implements SensorSource {
  RealSensorSource({ForegroundTexts Function()? texts}) : _texts = texts ?? (() => const ForegroundTexts());

  final ForegroundTexts Function() _texts;
  final _motion = StreamController<MotionSample>.broadcast();
  final _gps = StreamController<GpsFix>.broadcast();
  final _act = StreamController<ActivityKind>.broadcast();

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyrSub;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<ar.Activity>? _actSub;
  double _rx = 0, _ry = 0, _rz = 0; // град/с
  bool _gpsActive = false, _started = false;

  static const _rad2deg = 180 / math.pi;
  static const _period = Duration(milliseconds: 16); // ≈60 Гц (реально зависит от устройства)

  @override
  Stream<MotionSample> get motion => _motion.stream;
  @override
  Stream<GpsFix> get gps => _gps.stream;
  @override
  Stream<ActivityKind> get activity => _act.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _startGps(active: false);
    if (!kIsWeb) try {
      _actSub = ar.FlutterActivityRecognition.instance.activityStream.listen((a) {
        _act.add(switch (a.type) {
          ar.ActivityType.IN_VEHICLE => ActivityKind.automotive,
          ar.ActivityType.WALKING || ar.ActivityType.RUNNING => ActivityKind.walking,
          ar.ActivityType.STILL => ActivityKind.stationary,
          _ => ActivityKind.unknown,
        });
      }, onError: (_) {});
    } catch (_) {
      // распознавание активности недоступно — работаем только по GPS-скорости
    }
  }

  @override
  Future<void> stop() async {
    _started = false;
    setMotionSampling(false);
    await _posSub?.cancel();
    await _actSub?.cancel();
    _posSub = _actSub = null;
  }

  @override
  void setMotionSampling(bool on) {
    if (on && _accSub == null) {
      _gyrSub = gyroscopeEventStream(samplingPeriod: _period).listen((e) {
        _rx = e.x * _rad2deg;
        _ry = e.y * _rad2deg;
        _rz = e.z * _rad2deg;
      }, onError: (_) {});
      _accSub = accelerometerEventStream(samplingPeriod: _period).listen((e) {
        _motion.add(MotionSample(e.timestamp.millisecondsSinceEpoch, e.x, e.y, e.z, _rx, _ry, _rz));
      }, onError: (_) {});
    } else if (!on) {
      _accSub?.cancel();
      _gyrSub?.cancel();
      _accSub = _gyrSub = null;
    }
  }

  @override
  void setGpsActive(bool on) {
    if (on == _gpsActive && _posSub != null) return;
    _startGps(active: on);
  }

  void _startGps({required bool active}) {
    _gpsActive = active;
    _posSub?.cancel();
    final t = _texts();
    final LocationSettings settings;
    if (!kIsWeb && Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: active ? LocationAccuracy.best : LocationAccuracy.medium,
        distanceFilter: active ? 0 : 20,
        intervalDuration: Duration(seconds: active ? 1 : 3),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: t.title,
          notificationText: active ? t.recording : t.waiting,
          notificationChannelName: 'Holescope',
          setOngoing: true,
          enableWakeLock: active,
        ),
      );
    } else if (!kIsWeb && Platform.isIOS) {
      settings = AppleSettings(
        accuracy: active ? LocationAccuracy.best : LocationAccuracy.medium,
        distanceFilter: active ? 0 : 25,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: active,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = LocationSettings(accuracy: active ? LocationAccuracy.best : LocationAccuracy.medium, distanceFilter: active ? 0 : 20);
    }
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      if (p.accuracy > 60) return; // грубый фикс (дом/метро) — не используем
      _gps.add(GpsFix(p.timestamp.millisecondsSinceEpoch, p.latitude, p.longitude, p.speed, p.heading < 0 ? double.nan : p.heading, p.accuracy));
    }, onError: (_) {});
  }
}

/// Источник-пустышка для тестов и режима без плагинов.
class FakeSensorSource implements SensorSource {
  final motionCtl = StreamController<MotionSample>.broadcast();
  final gpsCtl = StreamController<GpsFix>.broadcast();
  final activityCtl = StreamController<ActivityKind>.broadcast();
  final motionCalls = <bool>[];
  final gpsCalls = <bool>[];
  @override
  Stream<MotionSample> get motion => motionCtl.stream;
  @override
  Stream<GpsFix> get gps => gpsCtl.stream;
  @override
  Stream<ActivityKind> get activity => activityCtl.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void setMotionSampling(bool on) => motionCalls.add(on);
  @override
  void setGpsActive(bool on) => gpsCalls.add(on);
}
