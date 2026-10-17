import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/csv_loader.dart';
import 'package:holescope/algo/frame.dart';
import 'package:holescope/algo/params.dart';
import 'package:holescope/algo/pipeline.dart';

/// Паритет Dart ↔ Python (backend/holescope_algo) на записях analysis/*.csv.
/// Допуски из CLAUDE_CODE_PROMPT: время события ±0.1 с, пик ±5 %.
/// Эталон: python backend/tools_export_fixtures.py → test/fixtures/ref_*.json
void main() {
  for (final name in ['2026-10-17', '2026-10-16']) {
    group('паритет $name', () {
      late Map<String, dynamic> ref;
      late TripResult res;
      late CsvTrip trip;
      late VehicleSignal sig;

      setUpAll(() {
        ref = jsonDecode(File('test/fixtures/ref_$name.json').readAsStringSync()) as Map<String, dynamic>;
        final csv = Directory('../analysis').listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.csv') && f.path.contains('pothole_$name'));
        trip = parseLoggerCsv(csv.readAsStringSync());
        final p = const AlgoParams().copyWith(wheelbaseM: 2.485);
        sig = vehicleFrame(trip.sensors, trip.gps, p);
        res = processTrip(trip.sensors, trip.gps, p);
      });

      test('сигнал vz/vx/vy/gyro/tilt совпадает в пробах', () {
        expect(sig.length, ref['n_samples']);
        expect(sig.fwdOk, ref['fwd_axis_ok']);
        var worst = 0.0;
        for (final pr in ref['sig_probe'] as List) {
          final i = pr['i'] as int;
          for (final (k, got) in [('vz', sig.vz[i]), ('vx', sig.vx[i]), ('vy', sig.vy[i]), ('gyro_h', sig.gyroH[i]), ('tilt', sig.tilt[i])]) {
            final want = (pr[k] as num).toDouble();
            final err = (got - want).abs();
            if (err > worst) worst = err;
            expect(err, lessThan(1e-3 + 1e-4 * want.abs()), reason: '$k[$i]: dart=$got py=$want');
          }
        }
        // ignore: avoid_print
        print('  наибольшее расхождение сигнала: ${worst.toStringAsExponential(2)}');
      });

      test('участки «в руке» совпадают', () {
        final want = (ref['hand_segments'] as List).map((e) => [(e[0] as num).toDouble(), (e[1] as num).toDouble()]).toList();
        expect(res.handSegments.length, want.length);
        for (var i = 0; i < want.length; i++) {
          expect(res.handSegments[i].$1, closeTo(want[i][0], 0.05));
          expect(res.handSegments[i].$2, closeTo(want[i][1], 0.05));
        }
      });

      test('события: число, время ±0.1 с, пик ±5 %, тип и уровень', () {
        final want = (ref['events'] as List).cast<Map<String, dynamic>>();
        expect(res.events.length, want.length, reason: 'число событий');
        var typeMismatch = 0, levelMismatch = 0;
        for (var i = 0; i < want.length; i++) {
          final w = want[i], g = res.events[i];
          expect(g.t, closeTo((w['t'] as num).toDouble(), 0.1), reason: 'событие $i: время');
          final peak = (w['peak'] as num).toDouble();
          expect(g.peak, closeTo(peak, 0.05 * peak + 0.002), reason: 'событие $i: пик');
          expect(g.speedKmh, closeTo((w['speed_kmh'] as num).toDouble(), 0.2), reason: 'событие $i: скорость');
          final score = (w['score'] as num).toDouble();
          expect(g.score, closeTo(score, 0.05 * score + 0.002), reason: 'событие $i: score');
          if (g.type != w['type']) typeMismatch++;
          if (g.level != w['level']) levelMismatch++;
        }
        // классификация детерминирована по признакам: допускаем ≤2 % расхождений из-за округлений на границах
        expect(typeMismatch, lessThanOrEqualTo((want.length * 0.02).ceil()), reason: 'тип');
        expect(levelMismatch, lessThanOrEqualTo((want.length * 0.02).ceil()), reason: 'уровень');
      });

      test('признаки формы: pair, dur_ms, hf_share, zeta', () {
        final want = (ref['events'] as List).cast<Map<String, dynamic>>();
        var n = 0, bad = 0;
        for (var i = 0; i < want.length; i++) {
          final w = want[i], g = res.events[i];
          n++;
          final okPair = (g.pair - (w['pair'] as num).toDouble()).abs() < 0.03;
          final okDur = (g.durMs - (w['dur_ms'] as num)).abs() <= 20;
          final okHf = (g.hfShare - (w['hf_share'] as num).toDouble()).abs() < 0.03;
          final wz = w['zeta'] as num?;
          final okZ = wz == null ? g.zeta.isNaN : (!g.zeta.isNaN && (g.zeta - wz).abs() < 0.02);
          if (!(okPair && okDur && okHf && okZ)) bad++;
        }
        expect(bad, lessThanOrEqualTo((n * 0.05).ceil()), reason: 'события с расхождением признаков: $bad из $n');
      });

      test('сегменты ровности: число, классы, RI', () {
        final want = (ref['segments'] as List).cast<Map<String, dynamic>>();
        expect(res.segments.length, want.length);
        var clsBad = 0;
        for (var i = 0; i < want.length; i++) {
          final w = want[i], g = res.segments[i];
          expect(g.ri, closeTo((w['ri'] as num).toDouble(), 0.02 * (w['ri'] as num).toDouble() + 1e-4), reason: 'сегмент $i RI');
          if (g.cls != w['cls']) clsBad++;
        }
        expect(clsBad, lessThanOrEqualTo((want.length * 0.01).ceil()));
      });

      test('авто-поездки и сводка подвески', () {
        final want = (ref['auto_trips'] as List).map((e) => [(e[0] as num).toDouble(), (e[1] as num).toDouble()]).toList();
        expect(res.autoTrips.length, want.length);
        for (var i = 0; i < want.length; i++) {
          expect(res.autoTrips[i].start, closeTo(want[i][0], 1.0));
          expect(res.autoTrips[i].end, closeTo(want[i][1], 1.0));
        }
        final d = ref['damping'] as Map<String, dynamic>;
        expect(res.damping.n, d['n']);
        expect(res.damping.zetaMedian!, closeTo((d['zeta_median'] as num).toDouble(), 0.01));
        expect(res.damping.fBodyMedian!, closeTo((d['f_body_median'] as num).toDouble(), 0.1));
        final s = ref['suspension'] as Map<String, dynamic>;
        expect(res.suspension.cls, s['cls']);
      });
    });
  }
}
