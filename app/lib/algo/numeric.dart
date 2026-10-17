import 'dart:math' as math;
import 'dart:typed_data';

/// Числовые примитивы, поведение которых совпадает с numpy/pandas (нужно для паритета с Python-алгоритмом).

/// np.convolve(x, ones(n)/n, mode="same"): окно x[i+s-(n-1) .. i+s], s=(n-1)~/2, за краями нули.
Float64List movavg(Float64List x, int n) {
  if (n <= 1) return x;
  final m = x.length;
  final out = Float64List(m);
  final s = (n - 1) ~/ 2;
  // префиксные суммы
  final ps = Float64List(m + 1);
  for (var i = 0; i < m; i++) {
    ps[i + 1] = ps[i] + x[i];
  }
  for (var i = 0; i < m; i++) {
    final hi = math.min(i + s, m - 1);
    final lo = math.max(i + s - (n - 1), 0);
    out[i] = hi >= lo ? (ps[hi + 1] - ps[lo]) / n : 0.0;
  }
  return out;
}

/// pandas ewm(alpha, adjust=False).mean() для одной колонки.
Float64List ewm(Float64List x, double alpha) {
  final out = Float64List(x.length);
  if (x.isEmpty) return out;
  out[0] = x[0];
  for (var i = 1; i < x.length; i++) {
    out[i] = (1 - alpha) * out[i - 1] + alpha * x[i];
  }
  return out;
}

/// np.interp(x, xp, fp): xp возрастает; за краями — крайние значения.
Float64List interp(Float64List x, Float64List xp, Float64List fp) {
  final out = Float64List(x.length);
  final n = xp.length;
  var j = 0;
  for (var i = 0; i < x.length; i++) {
    final v = x[i];
    if (v <= xp[0]) {
      out[i] = fp[0];
      continue;
    }
    if (v >= xp[n - 1]) {
      out[i] = fp[n - 1];
      continue;
    }
    // x тоже возрастает — двигаем указатель; при откате ищем заново
    if (j >= n - 1 || xp[j] > v) j = 0;
    while (j < n - 2 && xp[j + 1] <= v) {
      j++;
    }
    final dx = xp[j + 1] - xp[j];
    out[i] = dx == 0 ? fp[j] : fp[j] + (fp[j + 1] - fp[j]) * (v - xp[j]) / dx;
  }
  return out;
}

/// np.gradient(f, x) для неравномерной сетки (edge_order=1).
Float64List gradient(Float64List f, Float64List x) {
  final n = f.length;
  final g = Float64List(n);
  if (n < 2) return g;
  g[0] = (f[1] - f[0]) / (x[1] - x[0]);
  g[n - 1] = (f[n - 1] - f[n - 2]) / (x[n - 1] - x[n - 2]);
  for (var i = 1; i < n - 1; i++) {
    final hs = x[i] - x[i - 1];
    final hd = x[i + 1] - x[i];
    g[i] = (hs * hs * f[i + 1] + (hd * hd - hs * hs) * f[i] - hd * hd * f[i - 1]) / (hs * hd * (hd + hs));
  }
  return g;
}

double median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = List<double>.from(v)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double mean(List<double> v) {
  if (v.isEmpty) return double.nan;
  var s = 0.0;
  for (final x in v) {
    s += x;
  }
  return s / v.length;
}

/// Python round(x, d) приблизительно (round half away; расхождение только на точных «половинках»).
double rnd(double x, int d) {
  if (x.isNaN || x.isInfinite) return x;
  final k = math.pow(10, d).toDouble();
  return (x * k).roundToDouble() / k;
}

double sign(double x) => x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0);

/// Метод наименьших квадратов для 2 переменных без свободного члена: X(n×2)·c ≈ y.
/// Возвращает null, если система вырождена.
List<double>? lstsq2(Float64List a, Float64List b, Float64List y) {
  var saa = 0.0, sab = 0.0, sbb = 0.0, say = 0.0, sby = 0.0;
  for (var i = 0; i < y.length; i++) {
    saa += a[i] * a[i];
    sab += a[i] * b[i];
    sbb += b[i] * b[i];
    say += a[i] * y[i];
    sby += b[i] * y[i];
  }
  final det = saa * sbb - sab * sab;
  if (det.abs() < 1e-12) return null;
  return [(say * sbb - sby * sab) / det, (sby * saa - say * sab) / det];
}

/// Квадраты модуля rfft для окна из n точек (наивный DFT; окна ≈ 1 с, n ≈ 60–120).
List<double> rfftPower(List<double> x) {
  final n = x.length;
  final bins = n ~/ 2 + 1;
  final out = List<double>.filled(bins, 0);
  for (var k = 0; k < bins; k++) {
    var re = 0.0, im = 0.0;
    final w = -2 * math.pi * k / n;
    for (var t = 0; t < n; t++) {
      re += x[t] * math.cos(w * t);
      im += x[t] * math.sin(w * t);
    }
    out[k] = re * re + im * im;
  }
  return out;
}
