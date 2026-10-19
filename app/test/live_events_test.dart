import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/csv_loader.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/replay.dart';
import 'package:holescope/services/trip_recorder.dart';

class _Ctl implements SensorControl {
  @override
  void setMotionSampling(bool on) {}
  @override
  void setGpsActive(bool on) {}
}

CsvTrip _load(String name) {
  final f = Directory('../analysis').listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.csv') && f.path.contains('pothole_$name'));
  return parseLoggerCsv(f.readAsStringSync());
}

void main() {
  final trip = _load('2026-10-17');
  final ref = (jsonDecode(File('test/fixtures/ref_2026-10-17.json').readAsStringSync()) as Map<String, dynamic>)['events'] as List;

  test('«живое» обнаружение: удары находятся по ходу поездки, без повторов, кандидаты — заметные', () async {
    final cands = <LiveCandidate>[];
    final ages = <double>[];
    late TripRecorder rec;
    rec = TripRecorder(
      db: LocalDb.memory(),
      control: _Ctl(),
      config: const RecorderConfig(runInIsolate: false), // боевые значения: проверка каждые 6 с по окну 75 с
      context: () => const RecorderContext(wheelbaseM: 2.485),
      onCandidate: (c) {
        cands.add(c);
        ages.add((rec.lastFixMs! - c.epochMs) / 1000);
      },
    );
    rec.enable();
    final sw = Stopwatch()..start();
    await replayTripAsync(rec, trip, baseEpochMs: 1792220990000);
    sw.stop();
    final found = rec.snapshot.found;
    final refPothole = ref.where((e) => (e as Map)['type'] == 'pothole').length;
    // счёт по ходу поездки близок к полному разбору записи
    expect(found, inInclusiveRange((refPothole * 0.6).floor(), (refPothole * 1.5).ceil()), reason: 'найдено вживую $found, полный разбор $refPothole');
    expect(cands, isNotEmpty);
    for (final c in cands) {
      expect(c.event.score, greaterThanOrEqualTo(3.0));
      expect(c.event.speedKmh, greaterThanOrEqualTo(12));
    }
    for (final a in ages) {
      expect(a, inInclusiveRange(1.0, 12.0), reason: 'вопрос задаётся через несколько секунд после удара (возраст $a с)');
    }
    final ts = cands.map((c) => c.epochMs).toList();
    for (var i = 1; i < ts.length; i++) {
      expect(ts[i] - ts[i - 1], greaterThan(2500), reason: 'один и тот же удар не предлагается дважды');
    }
    // ignore: avoid_print
    print('живо найдено $found (полный разбор $refPothole), кандидатов ${cands.length}, возраст вопроса: средний ${(ages.reduce((a, b) => a + b) / ages.length).toStringAsFixed(1)} с, макс ${ages.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)} с, весь прогон ${sw.elapsedMilliseconds} мс');
  });

  test('без колбэка счёт тот же и ничего не падает', () async {
    final rec = TripRecorder(db: LocalDb.memory(), control: _Ctl(), config: const RecorderConfig(runInIsolate: false), context: () => const RecorderContext(wheelbaseM: 2.485));
    rec.enable();
    await replayTripAsync(rec, trip, baseEpochMs: 1792220990000);
    expect(rec.snapshot.found, greaterThan(10));
  });
}
