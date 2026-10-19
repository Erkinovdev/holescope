import 'dart:math' as math;

/// Догадка «что это было» по одному удару — порт backend/brain/guesser.py (те же правила и числа; совпадение проверяет test/event_guess_test.dart).
/// Параметры (границы уровней и т.п.) приходят с сервера в `/algo/params` → `guess` и кэшируются.
class GuessParams {
  const GuessParams({this.levelTheta = const [2.9, 3.9, 6.5], this.levelTau = 0.9, this.notroadPrior = 0.12, this.version = 'guess-0'});
  final List<double> levelTheta;
  final double levelTau, notroadPrior;
  final String version;

  /// Разбор ответа сервера: неизвестное и неправильное заменяется значениями по умолчанию.
  factory GuessParams.fromJson(Map<String, dynamic>? j) {
    const d = GuessParams();
    if (j == null) return d;
    final th = j['level_theta'];
    final theta = th is List && th.length == 3 && th.every((x) => x is num && x.isFinite) ? [for (final x in th) (x as num).toDouble()] : d.levelTheta;
    final sorted = theta[0] < theta[1] && theta[1] < theta[2];
    double pick(String k, double def, double lo, double hi) => j[k] is num && (j[k] as num) >= lo && (j[k] as num) <= hi ? (j[k] as num).toDouble() : def;
    return GuessParams(
      levelTheta: sorted ? theta : d.levelTheta,
      levelTau: pick('level_tau', d.levelTau, 0.2, 3.0),
      notroadPrior: pick('notroad_prior', d.notroadPrior, 0.01, 0.6),
      version: (j['version'] as String?) ?? d.version,
    );
  }

  static GuessParams current = const GuessParams();
}

/// Признаки одного удара (то, что есть у телефона сразу после события).
class EventFeatures {
  const EventFeatures({required this.score, required this.speedKmh, this.durMs = 0, this.pair = 0, this.gyroPeak = 0, this.hfShare = 0, this.peak = 0, this.locHits = 0});
  final double score, speedKmh, durMs, pair, gyroPeak, hfShare, peak, locHits;
}

/// Контекст: известный объект рядом (из локального кэша карты) и особенности дороги.
class GuessContext {
  const GuessContext({this.nearType, this.nearPasses = 0, this.tram = false, this.crossing = false, this.bridge = false});
  final String? nearType;
  final double nearPasses;
  final bool tram, crossing, bridge;
}

class Guess {
  Guess(this.probs, this.reasons) : top = probs.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final Map<String, double> probs;
  final List<String> reasons;
  final String top;
  double get confidence => probs[top] ?? 0;

  List<MapEntry<String, double>> ranked([int? n]) {
    final r = probs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return n == null ? r : r.take(n).toList();
  }
}

const _roadTypes = ['pothole', 'bump', 'manhole', 'rail_tram', 'rail_train', 'joint', 'washboard', 'patch', 'crack', 'broken'];
const _levels = ['pothole_light', 'pothole_mid', 'pothole_deep', 'pothole_danger'];
const minP = 0.03;

/// erf по формуле Абрамовица–Стегуна 7.1.26 — та же, что на сервере.
double erf(double x) {
  final s = x >= 0 ? 1.0 : -1.0;
  x = x.abs();
  final t = 1.0 / (1.0 + 0.3275911 * x);
  final y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x);
  return s * y;
}

double _cdf(double x) => 0.5 * (1.0 + erf(x / math.sqrt(2.0)));

Map<String, double> _softmax(Map<String, double> d) {
  final m = d.values.reduce(math.max);
  final e = {for (final k in d.keys) k: math.exp(d[k]! - m)};
  final s = e.values.fold(0.0, (a, b) => a + b);
  return {for (final k in e.keys) k: e[k]! / s};
}

Map<String, double> levelProbs(double score, List<double> theta, double tau) {
  final c = [for (final t in theta) _cdf((t - score) / tau)];
  return {'light': c[0], 'mid': c[1] - c[0], 'deep': c[2] - c[1], 'danger': 1.0 - c[2]};
}

double _r4(double v) => (v * 10000).roundToDouble() / 10000;

Guess guessEvent(EventFeatures f, [GuessContext c = const GuessContext(), GuessParams? params]) {
  final p = params ?? GuessParams.current;
  final why = <String>[];
  final score = f.score, v = f.speedKmh, dur = f.durMs, pair = f.pair, gyro = f.gyroPeak, hf = f.hfShare, hits = f.locHits;

  var z = math.log(p.notroadPrior / (1 - p.notroadPrior));
  if (gyro > 80 && pair < 0.5) {
    z += 1.8;
    why.add('сильный поворот телефона — похоже, его задели рукой');
  }
  if (dur > 0 && dur < 250 && pair < 0.25) z += 0.8;
  if (hf > 0.55) z += 0.4;
  if (score < 2.0) {
    z += 0.5;
    why.add('слабый удар — почти шум дороги');
  }
  final pNotroad = 1.0 / (1.0 + math.exp(-math.max(-30.0, math.min(30.0, z))));

  final t = {for (final k in _roadTypes) k: 0.0};
  t['pothole'] = 3.3;
  final near = c.nearType;
  final npass = c.nearPasses;
  if (v > 0 && v < 28 && (dur > 450 || score > 4.5)) {
    t['bump'] = t['bump']! + 1.8;
    why.add('удар на малой скорости (${v.toStringAsFixed(0)} км/ч), долгий — вероятен лежачий');
  }
  if (v > 0 && v < 20) t['bump'] = t['bump']! + 1.0;
  if (dur > 0 && dur < 300 && pair < 0.4 && score < 4.5) t['manhole'] = t['manhole']! + 0.7;
  if (c.tram && pair > 0.4) {
    t['rail_tram'] = t['rail_tram']! + 2.2;
    why.add('рядом трамвайные пути');
  }
  if (c.crossing) {
    t['rail_train'] = t['rail_train']! + 2.4;
    why.add('рядом железнодорожный переезд');
  }
  if (c.bridge && dur < 400) {
    t['joint'] = t['joint']! + 1.8;
    why.add('мост или тоннель — вероятен шов');
  }
  if (hits >= 5 && hf > 0.35) {
    t['washboard'] = t['washboard']! + 1.8;
    t['broken'] = t['broken']! + 0.8;
    why.add('много ударов подряд — волнистость или разбитый участок');
  }
  if (near != null && t.containsKey(near) && npass >= 2) {
    t[near] = t[near]! + 2.0 + math.min(npass, 8) * 0.25;
    why.add('здесь уже известен объект «$near» (${npass.toInt()} проездов)');
  }
  final tp = _softmax(t);

  var lv = levelProbs(score, p.levelTheta, p.levelTau);
  if (v > 0 && v < 20) lv = levelProbs(score + 0.5, p.levelTheta, p.levelTau);
  final road = 1.0 - pNotroad;
  final probs = <String, double>{};
  const lvKeys = ['light', 'mid', 'deep', 'danger'];
  for (final k in lvKeys) {
    probs['pothole_$k'] = road * tp['pothole']! * lv[k]!;
  }
  final b = tp['bump']!;
  final bl = _softmax({'low': score >= 3 ? 0.0 : 0.8, 'mid': 0.6, 'high': 0.2 + 0.25 * math.max(0.0, score - 5)});
  probs['bump_low'] = road * b * bl['low']!;
  probs['bump'] = road * b * bl['mid']!;
  probs['bump_high'] = road * b * bl['high']!;
  final m = tp['manhole']!;
  probs['manhole'] = road * m * 0.70;
  probs['manhole_sunk'] = road * m * 0.15;
  probs['manhole_raised'] = road * m * 0.15;
  probs['rail_tram'] = road * tp['rail_tram']!;
  probs['rail_train'] = road * tp['rail_train']!;
  probs['joint'] = road * tp['joint']!;
  probs['washboard'] = road * tp['washboard']!;
  probs['patch'] = road * tp['patch']! * 0.5;
  probs['crack'] = road * tp['crack']! * 0.5;
  probs['broken'] = road * tp['broken']!;
  probs['handled'] = pNotroad * (gyro > 60 ? 0.65 : 0.4);
  probs['noise'] = pNotroad - probs['handled']!;
  final s = probs.values.fold(0.0, (a, b2) => a + b2);
  return Guess({for (final e in probs.entries) e.key: _r4(e.value / s)}, why.take(5).toList());
}

/// Какие варианты показать: правдоподобные по этому удару, по убыванию (минимум 3, максимум [limit]); соседние уровни ямы и «ложное» всегда доступны.
List<String> optionsFor(Guess g, List<String> taxonomyKeys, {int limit = 6, double minProb = minP}) {
  final ranked = [for (final e in g.ranked()) if (taxonomyKeys.contains(e.key)) e.key];
  final keep = [for (final k in ranked) if (g.probs[k]! >= minProb) k].take(limit).toList();
  for (final k in ranked) {
    if (keep.length >= 3 || g.probs[k]! < 0.005) break;
    if (!keep.contains(k)) keep.add(k);
  }
  final topLv = keep.cast<String?>().firstWhere((k) => _levels.contains(k), orElse: () => null);
  if (topLv != null) {
    final i = _levels.indexOf(topLv);
    for (final j in [i - 1, i + 1]) {
      if (j >= 0 && j < 4 && !keep.contains(_levels[j]) && taxonomyKeys.contains(_levels[j])) keep.add(_levels[j]);
    }
  }
  if (!keep.contains('handled')) keep.add('handled');
  return keep;
}
