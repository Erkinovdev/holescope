import 'dart:math' as math;
import 'dart:typed_data';

import 'frame.dart';
import 'numeric.dart';
import 'params.dart';

/// Событие-«толчок» (порт detector.Event). Поля и единицы те же, что в Python и на сервере.
class RoadEventData {
  RoadEventData({
    required this.t,
    required this.lat,
    required this.lon,
    required this.speedKmh,
    required this.heading,
    required this.peak,
    required this.score,
    required this.noise,
    required this.ratio,
    required this.first,
    required this.durMs,
    required this.energy,
    required this.pair,
    required this.pairDt,
    required this.hfShare,
    required this.latShare,
    required this.longShare,
    required this.gyroPeak,
    required this.zeta,
    required this.fBody,
    required this.lowConf,
    required this.wave,
  });

  final double t, lat, lon, speedKmh, heading, peak, score, noise, ratio, energy, pair, pairDt, hfShare, latShare, longShare, gyroPeak, zeta, fBody;
  final int first, durMs;
  final bool lowConf;
  final List<double> wave;

  // результат классификации
  String type = 'pothole';
  String? level;
  double confidence = 0.0;
  int? safeSpeedKmh;

  static double? _n(double v) => v.isNaN ? null : v;

  Map<String, dynamic> toJson() => {
        't': t,
        'lat': lat,
        'lon': lon,
        'speed_kmh': speedKmh,
        'heading': _n(heading),
        'peak': peak,
        'score': score,
        'noise': noise,
        'ratio': ratio,
        'first': first,
        'dur_ms': durMs,
        'energy': energy,
        'pair': pair,
        'pair_dt': pairDt,
        'hf_share': hfShare,
        'lat_share': latShare,
        'long_share': longShare,
        'gyro_peak': gyroPeak,
        'zeta': _n(zeta),
        'f_body': _n(fBody),
        'low_conf': lowConf,
        'wave': wave,
        'type': type,
        'level': level,
        'confidence': confidence,
        'safe_speed_kmh': safeSpeedKmh,
        'algo_version': algoVersion,
      };
}

int lowerBound(Float64List t, double v) {
  var lo = 0, hi = t.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (t[mid] < v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

int upperBound(Float64List t, double v) {
  var lo = 0, hi = t.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (t[mid] <= v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Фоновый шум по скользящему окну 21 с (порт background_noise).
Float64List backgroundNoise(Float64List t, Float64List vz) {
  final n = t.length;
  final s0 = t[0].floor(), s1 = t[n - 1].floor();
  final count = s1 - s0 + 1;
  final sum = List<double>.filled(count, 0);
  final cnt = List<int>.filled(count, 0);
  for (var i = 0; i < n; i++) {
    final s = t[i].floor() - s0;
    sum[s] += vz[i] * vz[i];
    cnt[s]++;
  }
  final rms = List<double>.filled(count, double.nan);
  for (var s = 0; s < count; s++) {
    if (cnt[s] > 0) rms[s] = math.sqrt(sum[s] / cnt[s]);
  }
  // линейная интерполяция пропущенных секунд (pandas interpolate: только внутри)
  var prev = -1;
  for (var s = 0; s < count; s++) {
    if (!rms[s].isNaN) {
      if (prev >= 0 && s - prev > 1) {
        for (var q = prev + 1; q < s; q++) {
          rms[q] = rms[prev] + (rms[s] - rms[prev]) * (q - prev) / (s - prev);
        }
      }
      prev = s;
    }
  }
  // скользящая медиана 21 по центру, min_periods=5
  final ns = List<double>.filled(count, double.nan);
  for (var s = 0; s < count; s++) {
    final w = <double>[];
    for (var q = math.max(0, s - 10); q <= math.min(count - 1, s + 10); q++) {
      if (!rms[q].isNaN) w.add(rms[q]);
    }
    if (w.length >= 5) ns[s] = median(w);
  }
  // bfill, затем ffill
  for (var s = count - 2; s >= 0; s--) {
    if (ns[s].isNaN) ns[s] = ns[s + 1];
  }
  for (var s = 1; s < count; s++) {
    if (ns[s].isNaN) ns[s] = ns[s - 1];
  }
  final xp = Float64List(count), fp = Float64List(count);
  for (var s = 0; s < count; s++) {
    xp[s] = (s0 + s) + 0.5;
    fp[s] = ns[s].isNaN ? 0.0 : ns[s];
  }
  return interp(t, xp, fp);
}

/// Оценка затухания кузова после удара (порт _decay): (zeta, f_body) или (NaN, NaN).
(double, double) _decay(Float64List t, Float64List vz, double te) {
  final i0 = upperBound(t, te + 0.1), i1 = upperBound(t, te + 1.6);
  if (i1 - i0 < 30) return (double.nan, double.nan);
  final seg = movavg(Float64List.sublistView(vz, i0, i1), 9);
  final ts = Float64List.sublistView(t, i0, i1);
  final ext = <int>[];
  // d = diff(sign(diff(seg))) != 0  → индекс +1
  for (var i = 0; i + 2 < seg.length; i++) {
    final d = sign(seg[i + 2] - seg[i + 1]) - sign(seg[i + 1] - seg[i]);
    if (d != 0) ext.add(i + 1);
  }
  if (ext.length < 3) return (double.nan, double.nan);
  final a0 = seg[ext[0]].abs(), a1 = seg[ext[1]].abs();
  if (a1 < 1e-3 || a0 <= a1 || a0 < 0.4) return (double.nan, double.nan);
  final delta = math.log(a0 / a1);
  final zeta = delta / math.sqrt(4 * math.pi * math.pi + delta * delta);
  final half = ((ts[ext[1]] - ts[ext[0]]) + (ts[ext[2]] - ts[ext[1]])) / 2;
  final f = half > 0 ? 1.0 / (2 * half) : double.nan;
  return (zeta, f);
}

List<RoadEventData> detect(VehicleSignal sig, GpsData gps, AlgoParams p, {List<(double, double)> exclude = const []}) {
  final t = sig.t, vz = sig.vz, vx = sig.vx, vy = sig.vy, gy = sig.gyroH;
  final n = t.length;
  final sp = interp(t, gps.t, gps.speed);
  final lat = interp(t, gps.t, gps.lat), lon = interp(t, gps.t, gps.lon);
  final hdSrc = Float64List(gps.length);
  for (var i = 0; i < gps.length; i++) {
    hdSrc[i] = gps.heading[i].isNaN ? 0.0 : gps.heading[i];
  }
  final hd = interp(t, gps.t, hdSrc);
  final noise = backgroundNoise(t, vz);

  final idx = <int>[];
  for (var i = 0; i < n; i++) {
    final vfacThr = math.max(p.floor, p.kNoise * noise[i]);
    if (vz[i].abs() > vfacThr && sp[i] >= p.minSpeedMs) {
      var ex = false;
      for (final e in exclude) {
        if (t[i] >= e.$1 && t[i] <= e.$2) {
          ex = true;
          break;
        }
      }
      if (!ex) idx.add(i);
    }
  }
  if (idx.isEmpty) return [];
  final groups = <List<int>>[];
  var cur = <int>[idx.first];
  for (var j = 1; j < idx.length; j++) {
    if (t[idx[j]] - t[idx[j - 1]] > p.mergeGapS) {
      groups.add(cur);
      cur = <int>[];
    }
    cur.add(idx[j]);
  }
  groups.add(cur);

  final diffs = <double>[for (var i = 1; i < n; i++) t[i] - t[i - 1]];
  final dts = median(diffs);
  final out = <RoadEventData>[];
  for (final gi in groups) {
    var j = gi.first;
    for (final q in gi) {
      if (vz[q].abs() > vz[j].abs()) j = q;
    }
    final te = t[j];
    final v = math.max(sp[j], 0.5);
    final w0 = lowerBound(t, te - 0.5), w1 = upperBound(t, te + 0.5);
    final peak = vz[j].abs();
    // длительность на половине пика, энергия, знак первого удара
    var tMin = double.infinity, tMax = -double.infinity;
    var energy = 0.0;
    var first = 0;
    var firstFound = false;
    final wv = <double>[];
    var gyroPeak = 0.0, latMax = 0.0, lonMax = 0.0;
    for (var q = w0; q < w1; q++) {
      final a = vz[q];
      wv.add(a);
      energy += a * a;
      if (a.abs() >= 0.5 * peak) {
        if (t[q] < tMin) tMin = t[q];
        if (t[q] > tMax) tMax = t[q];
        if (!firstFound) {
          firstFound = true;
          first = sign(a).toInt();
        }
      }
      if (gy[q] > gyroPeak) gyroPeak = gy[q];
      if (vy[q].abs() > latMax) latMax = vy[q].abs();
      if (vx[q].abs() > lonMax) lonMax = vx[q].abs();
    }
    energy *= dts;
    final dur = tMax >= tMin ? tMax - tMin : 0.0;
    // второй удар
    final dt2 = p.wheelbaseM / v;
    final lo = te + 0.6 * dt2, hi = math.min(te + 1.6 * dt2, te + 0.6);
    var pair = 0.0;
    final a0 = upperBound(t, lo), a1 = upperBound(t, hi);
    if (a1 > a0) {
      var mx = 0.0;
      for (var q = a0; q < a1; q++) {
        if (vz[q].abs() > mx) mx = vz[q].abs();
      }
      pair = mx / peak;
    }
    // спектр
    var hf = 0.0;
    if (wv.length > 16) {
      final mu = mean(wv);
      final pw = rfftPower([for (final x in wv) x - mu]);
      final tot = pw.fold<double>(0, (a, b) => a + b) + 1e-9;
      var band = 0.0;
      for (var k = 0; k < pw.length; k++) {
        final f = k / (wv.length * dts);
        if (f >= 8 && f <= 25) band += pw[k];
      }
      hf = band / tot;
    }
    final (zeta, fb) = _decay(t, vz, te);
    final s0 = lowerBound(t, te - 2), s1 = upperBound(t, te + 2);
    final wave = <double>[for (var q = s0; q < s1; q += 2) rnd(vz[q], 1)];
    final vfac = math.pow((sp[j] / p.v0Ms).clamp(0.35, 3.0), p.speedAlpha).toDouble();
    out.add(RoadEventData(
      t: rnd(te, 3),
      lat: lat[j],
      lon: lon[j],
      speedKmh: rnd(v * 3.6, 1),
      heading: hd[j],
      peak: rnd(peak, 3),
      score: rnd(peak / vfac, 3),
      noise: rnd(noise[j], 3),
      ratio: rnd(peak / math.max(noise[j], 0.05), 2),
      first: first,
      durMs: (dur * 1000).round(),
      energy: rnd(energy, 3),
      pair: rnd(pair, 3),
      pairDt: rnd(dt2, 3),
      hfShare: rnd(hf, 3),
      latShare: rnd(latMax / peak, 3),
      longShare: rnd(lonMax / peak, 3),
      gyroPeak: rnd(gyroPeak, 1),
      zeta: zeta,
      fBody: fb,
      lowConf: v < p.lowConfSpeedMs,
      wave: wave,
    ));
  }
  return out;
}
