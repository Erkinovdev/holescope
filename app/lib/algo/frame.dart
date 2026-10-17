import 'dart:math' as math;
import 'dart:typed_data';

import 'numeric.dart';
import 'params.dart';

/// Отсчёты инерциальных датчиков. Время — секунды от общего начала записи (t0).
class SensorData {
  SensorData(this.t, this.ax, this.ay, this.az, this.rx, this.ry, this.rz);
  final Float64List t, ax, ay, az, rx, ry, rz;
  int get length => t.length;
}

/// GPS-фиксы. speed — м/с, heading — градусы (NaN допустим), t — секунды от t0.
class GpsData {
  GpsData(this.t, this.lat, this.lon, this.speed, this.heading);
  final Float64List t, lat, lon, speed, heading;
  int get length => t.length;
}

/// Сигнал в системе координат автомобиля (порт signal.py: vehicle_frame).
class VehicleSignal {
  VehicleSignal(this.t, this.vz, this.vx, this.vy, this.gyroH, this.tilt, this.fwdOk);
  final Float64List t, vz, vx, vy, gyroH, tilt;
  final bool fwdOk;
  int get length => t.length;
}

double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final a = math.pow(math.sin((p2 - p1) / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin((lon2 - lon1) * math.pi / 360), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

List<double> _cross(List<double> a, List<double> b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
double _norm(List<double> a) => math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);

VehicleSignal vehicleFrame(SensorData m, GpsData gps, AlgoParams p) {
  final n = m.length;
  if (n < 100) throw ArgumentError('мало отсчётов датчика');
  final t = m.t;
  final gx = ewm(m.ax, p.gravAlpha), gy = ewm(m.ay, p.gravAlpha), gz = ewm(m.az, p.gravAlpha);
  final vz = Float64List(n);
  final guX = Float64List(n), guY = Float64List(n), guZ = Float64List(n);
  final hX = Float64List(n), hY = Float64List(n), hZ = Float64List(n);
  for (var i = 0; i < n; i++) {
    var gn = math.sqrt(gx[i] * gx[i] + gy[i] * gy[i] + gz[i] * gz[i]);
    if (gn == 0) gn = 1.0;
    final ux = gx[i] / gn, uy = gy[i] / gn, uz = gz[i] / gn;
    guX[i] = ux;
    guY[i] = uy;
    guZ[i] = uz;
    final dx = m.ax[i] - gx[i], dy = m.ay[i] - gy[i], dz = m.az[i] - gz[i];
    final v = dx * ux + dy * uy + dz * uz;
    vz[i] = v;
    hX[i] = dx - v * ux;
    hY[i] = dy - v * uy;
    hZ[i] = dz - v * uz;
  }
  // базис горизонтальной плоскости по средней гравитации
  var gm = [mean(guX), mean(guY), mean(guZ)];
  final gmn = _norm(gm);
  gm = [gm[0] / gmn, gm[1] / gmn, gm[2] / gmn];
  var e1 = _cross(gm, [1, 0, 0]);
  if (_norm(e1) < 0.2) e1 = _cross(gm, [0, 1, 0]);
  final e1n = _norm(e1);
  e1 = [e1[0] / e1n, e1[1] / e1n, e1[2] / e1n];
  final e2 = _cross(gm, e1);
  final h1 = Float64List(n), h2 = Float64List(n);
  for (var i = 0; i < n; i++) {
    h1[i] = hX[i] * e1[0] + hY[i] * e1[1] + hZ[i] * e1[2];
    h2[i] = hX[i] * e2[0] + hY[i] * e2[1] + hZ[i] * e2[2];
  }
  // продольная ось: регрессия на ускорение по GPS
  var fwd = [1.0, 0.0];
  var ok = false;
  if (gps.length > 20) {
    final acc = movavg(gradient(gps.speed, gps.t), 3);
    final aI = interp(t, gps.t, acc);
    final h1s = movavg(h1, 31), h2s = movavg(h2, 31);
    var cnt = 0;
    for (var i = 0; i < n; i++) {
      if (aI[i].abs() > 0.4) cnt++;
    }
    if (cnt > 200) {
      final a = Float64List(cnt), b = Float64List(cnt), y = Float64List(cnt);
      var k = 0;
      for (var i = 0; i < n; i++) {
        if (aI[i].abs() > 0.4) {
          a[k] = h1s[i];
          b[k] = h2s[i];
          y[k] = aI[i];
          k++;
        }
      }
      final c = lstsq2(a, b, y);
      if (c != null) {
        final nn = math.sqrt(c[0] * c[0] + c[1] * c[1]);
        if (nn > 1e-6) {
          fwd = [c[0] / nn, c[1] / nn];
          ok = true;
        }
      }
    }
  }
  final vx = Float64List(n), vy = Float64List(n);
  for (var i = 0; i < n; i++) {
    vx[i] = h1[i] * fwd[0] + h2[i] * fwd[1];
    vy[i] = -h1[i] * fwd[1] + h2[i] * fwd[0];
  }
  // гироскоп: горизонтальная часть
  final gyroH = Float64List(n);
  for (var i = 0; i < n; i++) {
    final rv = m.rx[i] * guX[i] + m.ry[i] * guY[i] + m.rz[i] * guZ[i];
    final a = m.rx[i] - rv * guX[i], b = m.ry[i] - rv * guY[i], c = m.rz[i] - rv * guZ[i];
    gyroH[i] = math.sqrt(a * a + b * b + c * c);
  }
  // изменение направления гравитации за ~3 с
  final rate = n / math.max(t[n - 1] - t[0], 1.0);
  final k = math.max((3.0 * rate).toInt(), 1);
  final sx = movavg(guX, 15), sy = movavg(guY, 15), sz = movavg(guZ, 15);
  final nx = Float64List(n), ny = Float64List(n), nz = Float64List(n);
  for (var i = 0; i < n; i++) {
    final nn = math.max(math.sqrt(sx[i] * sx[i] + sy[i] * sy[i] + sz[i] * sz[i]), 1e-9);
    nx[i] = sx[i] / nn;
    ny[i] = sy[i] / nn;
    nz[i] = sz[i] / nn;
  }
  final tilt = Float64List(n);
  for (var i = k; i < n; i++) {
    final d = (nx[i] * nx[i - k] + ny[i] * ny[i - k] + nz[i] * nz[i - k]).clamp(-1.0, 1.0);
    tilt[i] = math.acos(d) * 180 / math.pi;
  }
  return VehicleSignal(t, movavg(vz, p.smoothSamples), vx, vy, gyroH, tilt, ok);
}

/// Интервалы, где телефон, вероятно, брали в руку (порт hand_segments).
List<(double, double)> handSegments(VehicleSignal sig, {double tiltThr = 30.0, double padS = 1.5}) {
  final t = sig.t;
  final idx = <int>[];
  for (var i = 0; i < sig.length; i++) {
    if (sig.tilt[i] > tiltThr) idx.add(i);
  }
  if (idx.isEmpty) return [];
  final groups = <List<int>>[];
  var cur = <int>[idx.first];
  for (var j = 1; j < idx.length; j++) {
    if (t[idx[j]] - t[idx[j - 1]] > 2.0) {
      groups.add(cur);
      cur = <int>[];
    }
    cur.add(idx[j]);
  }
  groups.add(cur);
  return [
    for (final g in groups)
      if (g.isNotEmpty && t[g.last] - t[g.first] >= 0.8) (t[g.first] - padS, t[g.last] + padS)
  ];
}
