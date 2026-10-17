import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/services/ahead_warner.dart';
import 'package:holescope/services/announcer.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/device_auth.dart';
import 'package:holescope/services/engine.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/samples.dart';
import 'package:holescope/services/sensor_source.dart';
import 'package:holescope/services/trip_recorder.dart';

const lat0 = 41.3270, lon0 = 69.2284;
double dLon(double meters) => meters / (111320 * math.cos(lat0 * math.pi / 180));

void main() {
  late LocalDb db;
  late FakeSensorSource src;
  late SilentAnnouncer ann;
  late RecorderEngine eng;

  setUp(() {
    db = LocalDb.memory();
    // яма в 400 м к востоку от старта, подтверждённая; вторая — встречное направление; третья — кандидат
    db.replaceClusters([
      CachedCluster(id: 1, lat: lat0, lon: lon0 + dLon(400), heading: 90, type: 'pothole', level: 'deep', status: 'confirmed', confidence: 0.9, safeSpeed: 30),
      CachedCluster(id: 2, lat: lat0, lon: lon0 + dLon(300), heading: 270, type: 'pothole', level: 'mid', status: 'confirmed', confidence: 0.9, safeSpeed: null),
      CachedCluster(id: 3, lat: lat0, lon: lon0 + dLon(250), heading: 90, type: 'pothole', level: 'light', status: 'candidate', confidence: 0.4, safeSpeed: null),
    ]);
    src = FakeSensorSource();
    ann = SilentAnnouncer();
    eng = RecorderEngine(
      db: db,
      source: src,
      api: ApiClient('http://127.0.0.1:1'), // недоступен: проверяем офлайн-режим
      announcer: ann,
      auth: DeviceAuth(MemoryTokenStore()),
      settings: () => const AppSettings(warnDistanceM: 150, locale: Locale('ru')),
      config: const RecorderConfig(runInIsolate: false, liveEveryS: 1e9),
    );
  });

  tearDown(() async {
    await eng.stop();
    eng.dispose();
  });

  test('предупреждение об яме впереди: один раз, по ходу, только подтверждённая, офлайн', () async {
    await eng.start();
    var t = 1000000;
    final seen = <int>[];
    eng.warning.addListener(() {
      final w = eng.warning.value;
      if (w != null) seen.add(w.distanceM);
    });
    // едем на восток 12 м/с (43 км/ч), фикс раз в секунду
    for (var k = 0; k <= 40; k++) {
      src.gpsCtl.add(GpsFix(t + k * 1000, lat0, lon0 + dLon(12.0 * k), 12.0, 90, 3));
      await Future<void>.delayed(Duration.zero);
    }
    expect(ann.calls.length, 1, reason: 'озвучена одна яма');
    expect(ann.calls.single.id, 1, reason: 'не встречная (270°) и не кандидат');
    expect(ann.calls.single.distanceM, inInclusiveRange(100, 150));
    expect(ann.calls.single.side, 'center');
    expect(seen, isNotEmpty);
    // после проезда яма не мигает
    for (var k = 41; k <= 50; k++) {
      src.gpsCtl.add(GpsFix(t + k * 1000, lat0, lon0 + dLon(12.0 * k), 12.0, 90, 3));
      await Future<void>.delayed(Duration.zero);
    }
    expect(ann.calls.length, 1);
    expect(eng.warning.value, isNull);
  });

  test('без направления (heading NaN) предупреждений нет; на стоянке — тоже', () async {
    await eng.start();
    for (var k = 0; k < 30; k++) {
      src.gpsCtl.add(GpsFix(2000000 + k * 1000, lat0, lon0 + dLon(12.0 * k), 12.0, double.nan, 3));
      await Future<void>.delayed(Duration.zero);
    }
    expect(ann.calls, isEmpty);
  });

  test('датчики движения включаются только при езде и выключаются после', () async {
    await eng.start();
    expect(src.motionCalls, isEmpty);
    src.gpsCtl.add(GpsFix(3000000, lat0, lon0, 0.0, 90, 3));
    await Future<void>.delayed(Duration.zero);
    expect(src.motionCalls, isEmpty, reason: 'на стоянке датчики выключены');
    src.gpsCtl.add(GpsFix(3001000, lat0, lon0, 4.0, 90, 3)); // 14.4 км/ч ≥ 10
    await Future<void>.delayed(Duration.zero);
    expect(src.motionCalls, [true]);
    expect(src.gpsCalls, [true], reason: 'GPS переходит в точный режим');
    expect(eng.recorder.phase, RecorderPhase.armed);
  });

  test('geometry: project совпадает с серверной формулой', () {
    final p = AheadWarner.project(lat0, lon0, 90, lat0, lon0 + dLon(150));
    expect(p.along, closeTo(150, 0.5));
    expect(p.across.abs(), lessThan(0.5));
    final q = AheadWarner.project(lat0, lon0, 0, lat0 + 100 / 111320, lon0 + dLon(10));
    expect(q.along, closeTo(100, 0.5));
    expect(q.across, closeTo(10, 0.5));
  });

  test('warningText: ru/uz и совет по скорости', () {
    const item = AheadItem(id: 1, distanceM: 120, side: 'center', level: 'deep', safeSpeed: 30, type: 'pothole', lat: 0, lon: 0);
    expect(warningText(item, 'ru', 50), contains('Снизьте скорость до 30'));
    expect(warningText(item, 'ru', 28), 'Впереди яма, 120 метров');
    expect(warningText(item, 'uz', 50), contains('pasaytiring'));
  });
}
