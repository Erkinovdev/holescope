import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/event_guess.dart';

Map<String, dynamic> _load() => jsonDecode(File('test/fixtures/guess_cases.json').readAsStringSync()) as Map<String, dynamic>;

EventFeatures _f(Map<String, dynamic> j) => EventFeatures(
      score: (j['score'] as num).toDouble(),
      speedKmh: (j['speed_kmh'] as num).toDouble(),
      durMs: (j['dur_ms'] as num).toDouble(),
      pair: (j['pair'] as num).toDouble(),
      gyroPeak: (j['gyro_peak'] as num).toDouble(),
      hfShare: (j['hf_share'] as num).toDouble(),
      peak: (j['peak'] as num).toDouble(),
      locHits: (j['loc_hits'] as num).toDouble(),
    );

GuessContext _c(Map<String, dynamic> j) => GuessContext(nearType: j['near_type'] as String?, nearPasses: ((j['near_passes'] ?? 0) as num).toDouble(), tram: j['tram'] == true, crossing: j['crossing'] == true, bridge: j['bridge'] == true);

void main() {
  final data = _load();
  final keys = [for (final k in data['keys'] as List) k as String];
  final cases = data['cases'] as List;

  group('совпадение с сервером (Python)', () {
    test('вероятности всех вариантов на 60 общих примерах совпадают (до 1e-3)', () {
      var worst = 0.0;
      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final params = c['params'] == null ? const GuessParams() : GuessParams.fromJson(c['params'] as Map<String, dynamic>);
        final g = guessEvent(_f(c['f'] as Map<String, dynamic>), _c(c['ctx'] as Map<String, dynamic>), params);
        final want = (c['probs'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
        expect(g.probs.keys.toSet(), want.keys.toSet());
        for (final k in want.keys) {
          final d = (g.probs[k]! - want[k]!).abs();
          if (d > worst) worst = d;
        }
        expect(g.top, c['top']);
      }
      expect(worst, lessThan(1e-3));
    });

    test('отбор вариантов совпадает', () {
      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final params = c['params'] == null ? const GuessParams() : GuessParams.fromJson(c['params'] as Map<String, dynamic>);
        final g = guessEvent(_f(c['f'] as Map<String, dynamic>), _c(c['ctx'] as Map<String, dynamic>), params);
        expect(optionsFor(g, keys), (c['options'] as List).cast<String>());
        expect(optionsFor(g, keys, limit: 3), (c['options3'] as List).cast<String>());
      }
    });
  });

  group('здравый смысл', () {
    EventFeatures ev(double score, {double speed = 50, double dur = 550, double pair = 0.5}) => EventFeatures(score: score, speedKmh: speed, durMs: dur, pair: pair, gyroPeak: 12, hfShare: 0.2);
    test('слабый удар — не глубокая яма', () {
      final g = guessEvent(ev(1.9));
      expect(g.probs['pothole_deep']! + g.probs['pothole_danger']!, lessThan(0.03));
      expect(optionsFor(g, keys), isNot(contains('pothole_deep')));
    });
    test('сильный удар — не мелкая яма, но глубокая доступна', () {
      final g = guessEvent(ev(9));
      expect(g.probs['pothole_light']!, lessThan(0.05));
      final o = optionsFor(g, keys);
      expect(o, isNot(contains('pothole_light')));
      expect(o, contains('pothole_deep'));
    });
    test('«ложное срабатывание» доступно всегда', () => expect(optionsFor(guessEvent(ev(5)), keys), contains('handled')));
    test('вероятности в сумме дают 1', () => expect(guessEvent(ev(3.3)).probs.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 0.01)));
    test('параметры с сервера: неверные заменяются по умолчанию', () {
      final p = GuessParams.fromJson({'level_theta': [5, 3, 1], 'level_tau': 99, 'notroad_prior': 'x'});
      expect(p.levelTheta, const GuessParams().levelTheta);
      expect(p.levelTau, const GuessParams().levelTau);
    });
  });
}
