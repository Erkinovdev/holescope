import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/csv_loader.dart';
import 'package:holescope/algo/frame.dart';
import 'package:holescope/algo/params.dart';
import 'package:holescope/algo/pipeline.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/replay.dart';
import 'package:holescope/services/samples.dart';
import 'package:holescope/services/trip_recorder.dart';

class _Ctl implements SensorControl {
  final calls = <bool>[];
  @override
  void setMotionSampling(bool on) => calls.add(on);
  @override
  void setGpsActive(bool on) {}
}

CsvTrip _load(String name) {
  final f = Directory('../analysis').listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.csv') && f.path.contains('pothole_$name'));
  return parseLoggerCsv(f.readAsStringSync());
}

void main() {
  late CsvTrip trip;
  setUpAll(() => trip = _load('2026-10-17'));

  test('авто-старт, авто-стоп по концу данных, приватность и очередь', () async {
    final db = LocalDb.memory();
    final ctl = _Ctl();
    final snaps = <RecorderPhase>[];
    final rec = TripRecorder(
      db: db,
      control: ctl,
      config: const RecorderConfig(runInIsolate: false, liveEveryS: 1e9),
      context: () => const RecorderContext(wheelbaseM: 2.485),
      onSnapshot: (s) {
        if (snaps.isEmpty || snaps.last != s.phase) snaps.add(s.phase);
      },
    );
    rec.enable();
    replayTrip(rec, trip, baseEpochMs: 1792220990000);
    // старт был автоматическим: idle → armed → driving
    expect(snaps, containsAllInOrder([RecorderPhase.idle, RecorderPhase.armed, RecorderPhase.driving]));
    expect(ctl.calls.first, isTrue, reason: 'датчики включены при превышении порога скорости');
    // запись закончилась без остановки >3 мин → закрываем вручную (как «Остановить поездку»)
    final ft = await rec.stopManual();
    expect(ft, isNotNull);
    expect(ft!.distanceKm, inInclusiveRange(10.5, 13));
    expect(ctl.calls.last, isFalse, reason: 'после поездки датчики выключаются');

    // история и очередь
    expect(db.trips().length, 1);
    expect(db.outboxCount(), 1);
    final item = db.dueOutbox(DateTime.now().millisecondsSinceEpoch + 1).single;
    final body = jsonDecode(item.payload) as Map<String, dynamic>;
    expect(body['_local'], ft.localId);
    expect(body['algo_version'], '2.0.0');
    expect(body['mode'], 'car');
    final events = (body['events'] as List).cast<Map<String, dynamic>>();
    expect(events, isNotEmpty);
    expect(events.every((e) => e['type'] != 'touch' && e['type'] != 'noise'), isTrue);
    for (final e in events) {
      expect((e['lat'] as num).toDouble(), inInclusiveRange(41.0, 41.6));
      expect(e.containsKey('wave'), isTrue);
    }
    // JSON не содержит NaN (он бы не сериализовался), «zeta» либо число, либо null
    expect(item.payload.contains('NaN'), isFalse);

    expect(events.length, inInclusiveRange(15, 27));
  });

  test('приватность: удаляются события и сегменты в первых/последних 200 м пути', () {
    final p = const AlgoParams().copyWith(wheelbaseM: 2.485);
    final res = processTrip(trip.sensors, trip.gps, p);
    final path = gpsPathMeters(trip.gps);
    final total = path.last;
    double at(double t) {
      for (var i = 1; i < trip.gps.length; i++) {
        if (trip.gps.t[i] >= t) return path[i];
      }
      return total;
    }

    // искусственно добавляем события у начала и конца пути
    final first = res.events.first, last = res.events.last;
    final fake = [first, last];
    final r2 = TripResult(events: fake, segments: res.segments, handSegments: const [], autoTrips: const [], damping: res.damping, suspension: res.suspension, durationS: res.durationS, distanceKm: res.distanceKm, fwdOk: true);
    final t = trimForPrivacy(r2, trip.gps, trimM: 200);
    for (final e in t.events) {
      expect(at(e.t), inInclusiveRange(190, total - 190));
    }
    for (final sgm in t.segments) {
      expect(at(sgm.t0), greaterThanOrEqualTo(190));
      expect(at(sgm.t1), lessThanOrEqualTo(total - 190));
    }
    expect(t.segments.length, lessThan(res.segments.length));
    // слишком короткая поездка отдаётся пустой
    final short = trimForPrivacy(res, GpsData(trip.gps.t.sublist(0, 30), trip.gps.lat.sublist(0, 30), trip.gps.lon.sublist(0, 30), trip.gps.speed.sublist(0, 30), trip.gps.heading.sublist(0, 30)), trimM: 5000);
    expect(short.events, isEmpty);
    expect(short.segments, isEmpty);
  });

  test('ложная тревога: короткий разгон без поездки сбрасывается', () async {
    final db = LocalDb.memory();
    final ctl = _Ctl();
    final rec = TripRecorder(db: db, control: ctl, config: const RecorderConfig(runInIsolate: false));
    rec.enable();
    // 8 с езды на 17 км/ч, затем 70 с стоянки: старт (20 с) не набран
    replayTrip(rec, trip, baseEpochMs: 1, untilS: 8);
    expect(rec.phase, RecorderPhase.armed);
    // имитируем стоянку: GPS-фиксы со скоростью 0
    for (var k = 0; k < 80; k++) {
      rec.onGps(GpsFix(10000 + k * 1000, 41.3245, 69.2328, 0.0, 0.0, 3.0));
    }
    expect(rec.phase, RecorderPhase.idle);
    expect(db.outboxCount(), 0);
    expect(ctl.calls.last, isFalse);
  });

  test('«не записывать эту поездку» ничего не отправляет', () async {
    final db = LocalDb.memory();
    final rec = TripRecorder(db: db, control: _Ctl(), config: const RecorderConfig(runInIsolate: false, liveEveryS: 1e9));
    rec.enable();
    replayTrip(rec, trip, baseEpochMs: 1, untilS: 200);
    expect(rec.phase, RecorderPhase.driving);
    rec.skipCurrentTrip();
    expect(rec.phase, RecorderPhase.idle);
    expect(await rec.stopManual(), isNull);
    expect(db.outboxCount(), 0);
    expect(db.trips(), isEmpty);
  });

  test('восстановление: буфер на диске → поездка обработана после «гибели процесса»', () async {
    final db = LocalDb.memory();
    final rec = TripRecorder(db: db, control: _Ctl(), config: const RecorderConfig(runInIsolate: false, liveEveryS: 1e9), context: () => const RecorderContext(wheelbaseM: 2.485));
    rec.enable();
    replayTrip(rec, trip, baseEpochMs: 1792220990000);
    expect(rec.phase, RecorderPhase.driving);
    final f = File('${Directory.systemTemp.path}/hs_cur_${DateTime.now().microsecondsSinceEpoch}.bin');
    rec.persist(f);
    expect(f.existsSync(), isTrue);
    // «новый запуск»: другой экземпляр, пустое состояние
    final db2 = LocalDb.memory();
    final rec2 = TripRecorder(db: db2, control: _Ctl(), config: const RecorderConfig(runInIsolate: false, liveEveryS: 1e9), context: () => const RecorderContext(wheelbaseM: 2.485));
    final ft = await rec2.recoverFrom(f);
    expect(ft, isNotNull);
    expect(ft!.reason, 'recovered');
    expect(ft.distanceKm, inInclusiveRange(10.5, 13));
    expect(db2.outboxCount(), 1);
    expect(f.existsSync(), isFalse, reason: 'файл восстановления удалён');
    // повреждённый файл не ломает запуск
    final bad = File('${Directory.systemTemp.path}/hs_bad_${DateTime.now().microsecondsSinceEpoch}.bin')..writeAsBytesSync([1, 2, 3]);
    expect(await rec2.recoverFrom(bad), isNull);
  });
}
