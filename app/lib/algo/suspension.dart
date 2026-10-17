import 'dart:math' as math;

import 'detector.dart';
import 'numeric.dart';

/// Порт suspension.py: затухание кузова (резервный абсолютный показатель).
/// ВНИМАНИЕ: f_body/ζ с одного телефона на сиденье — это резонанс телефона, а не подвеска (HOLESCOPE_V2 §8.1);
/// основной показатель — относительная мягкость, считается на сервере по сегментам с ≥3 машинами.
class DampingSummary {
  const DampingSummary(this.n, this.zetaMedian, this.fBodyMedian);
  final int n;
  final double? zetaMedian, fBodyMedian;
  Map<String, dynamic> toJson() => {'n': n, 'zeta_median': zetaMedian, 'f_body_median': fBodyMedian};
}

DampingSummary dampingSummary(List<RoadEventData> events) {
  final z = [for (final e in events) if (!e.zeta.isNaN && e.zeta > 0.02 && e.zeta < 0.9) e.zeta];
  final f = [for (final e in events) if (!e.fBody.isNaN && e.fBody > 0.4 && e.fBody < 4.0) e.fBody];
  return DampingSummary(z.length, z.isEmpty ? null : median(z), f.isEmpty ? null : median(f));
}

class SoftnessScore {
  const SoftnessScore(this.score, this.cls, this.confidence);
  final double? score;
  final String? cls;
  final double confidence;
  Map<String, dynamic> toJson() => {'score': score, 'cls': cls, 'confidence': confidence};
}

SoftnessScore softnessScore(double? rel, double? zeta, double? fBody) {
  final parts = <double>[], w = <double>[];
  if (rel != null) {
    parts.add(50 + 50 * ((math.exp(2 * rel / 0.5) - 1) / (math.exp(2 * rel / 0.5) + 1)));
    w.add(0.6);
  }
  if (fBody != null) {
    parts.add(((2.2 - fBody) / (2.2 - 0.9) * 100).clamp(0.0, 100.0));
    w.add(0.25);
  }
  if (zeta != null) {
    parts.add(((0.45 - zeta) / 0.35 * 100).clamp(0.0, 100.0) * 0.5 + 25);
    w.add(0.15);
  }
  if (parts.isEmpty) return const SoftnessScore(null, null, 0.0);
  var num = 0.0, den = 0.0;
  for (var i = 0; i < parts.length; i++) {
    num += parts[i] * w[i];
    den += w[i];
  }
  final sc = num / den;
  final cls = sc < 20 ? 'S1' : sc < 40 ? 'S2' : sc < 60 ? 'S3' : sc < 80 ? 'S4' : 'S5';
  return SoftnessScore(rnd(sc, 1), cls, rnd(math.min(1.0, w.fold(0.0, (a, b) => a + b)), 2));
}
