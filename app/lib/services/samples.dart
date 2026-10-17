import 'dart:io';
import 'dart:typed_data';

import '../algo/frame.dart';

/// Отсчёт датчиков движения: ускорение с гравитацией (м/с²) и угловая скорость (град/с).
class MotionSample {
  const MotionSample(this.tMs, this.ax, this.ay, this.az, this.rx, this.ry, this.rz);
  final int tMs; // epoch ms
  final double ax, ay, az, rx, ry, rz;
}

class GpsFix {
  const GpsFix(this.tMs, this.lat, this.lon, this.speedMs, this.headingDeg, this.accuracyM);
  final int tMs;
  final double lat, lon, speedMs, headingDeg, accuracyM;
}

/// Растущий массив double без лишних копий.
class GrowableF64 {
  GrowableF64([int cap = 4096]) : _a = Float64List(cap);
  Float64List _a;
  int length = 0;

  void add(double v) {
    if (length == _a.length) {
      final n = Float64List(_a.length * 2)..setRange(0, length, _a);
      _a = n;
    }
    _a[length++] = v;
  }

  double operator [](int i) => _a[i];
  Float64List view() => Float64List.sublistView(_a, 0, length);
  void clear() => length = 0;
}

/// Буфер записи поездки: датчики и GPS в общей шкале времени (epoch ms).
class TripBuffer {
  final tMs = GrowableF64(), ax = GrowableF64(), ay = GrowableF64(), az = GrowableF64(), rx = GrowableF64(), ry = GrowableF64(), rz = GrowableF64();
  final gTMs = GrowableF64(512), glat = GrowableF64(512), glon = GrowableF64(512), gsp = GrowableF64(512), ghd = GrowableF64(512), gacc = GrowableF64(512);

  int get motionCount => tMs.length;
  int get gpsCount => gTMs.length;
  bool get isEmpty => motionCount == 0 && gpsCount == 0;

  void addMotion(MotionSample s) {
    tMs.add(s.tMs.toDouble());
    ax.add(s.ax);
    ay.add(s.ay);
    az.add(s.az);
    rx.add(s.rx);
    ry.add(s.ry);
    rz.add(s.rz);
  }

  void addGps(GpsFix f, double speedMs) {
    gTMs.add(f.tMs.toDouble());
    glat.add(f.lat);
    glon.add(f.lon);
    gsp.add(speedMs);
    ghd.add(f.headingDeg);
    gacc.add(f.accuracyM);
  }

  void clear() {
    for (final g in [tMs, ax, ay, az, rx, ry, rz, gTMs, glat, glon, gsp, ghd, gacc]) {
      g.clear();
    }
  }

  List<GrowableF64> get _all => [tMs, ax, ay, az, rx, ry, rz, gTMs, glat, glon, gsp, ghd, gacc];

  /// Сохранение на диск (защита от гибели процесса): [motionCount, gpsCount] + массивы Float64.
  void saveTo(File f) {
    final header = Float64List.fromList([motionCount.toDouble(), gpsCount.toDouble()]);
    final sink = f.openSync(mode: FileMode.write);
    try {
      sink.writeFromSync(header.buffer.asUint8List());
      for (final g in _all) {
        final v = g.view();
        sink.writeFromSync(v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes));
      }
    } finally {
      sink.closeSync();
    }
  }

  static TripBuffer? loadFrom(File f) {
    if (!f.existsSync()) return null;
    final bytes = f.readAsBytesSync();
    if (bytes.length < 16) return null;
    final all = bytes.buffer.asFloat64List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 8);
    final m = all[0].toInt(), g = all[1].toInt();
    if (all.length != 2 + 7 * m + 6 * g) return null;
    final b = TripBuffer();
    var o = 2;
    for (final target in [b.tMs, b.ax, b.ay, b.az, b.rx, b.ry, b.rz]) {
      for (var i = 0; i < m; i++) {
        target.add(all[o + i]);
      }
      o += m;
    }
    for (final target in [b.gTMs, b.glat, b.glon, b.gsp, b.ghd, b.gacc]) {
      for (var i = 0; i < g; i++) {
        target.add(all[o + i]);
      }
      o += g;
    }
    return b;
  }

  /// Срез [fromMs, toMs] → массивы алгоритма; время — секунды от t0Ms.
  (SensorData, GpsData) slice(double fromMs, double toMs, double t0Ms) {
    List<int> range(Float64List t) {
      var lo = 0, hi = t.length;
      while (lo < hi) {
        final m = (lo + hi) >> 1;
        t[m] < fromMs ? lo = m + 1 : hi = m;
      }
      final a = lo;
      lo = a;
      hi = t.length;
      while (lo < hi) {
        final m = (lo + hi) >> 1;
        t[m] <= toMs ? lo = m + 1 : hi = m;
      }
      return [a, lo];
    }

    Float64List cut(GrowableF64 g, List<int> r, [double Function(double)? f]) {
      final out = Float64List(r[1] - r[0]);
      for (var i = r[0]; i < r[1]; i++) {
        out[i - r[0]] = f == null ? g[i] : f(g[i]);
      }
      return out;
    }

    final rm = range(tMs.view()), rg = range(gTMs.view());
    double rel(double v) => (v - t0Ms) / 1000;
    return (
      SensorData(cut(tMs, rm, rel), cut(ax, rm), cut(ay, rm), cut(az, rm), cut(rx, rm), cut(ry, rm), cut(rz, rm)),
      GpsData(cut(gTMs, rg, rel), cut(glat, rg), cut(glon, rg), cut(gsp, rg), cut(ghd, rg)),
    );
  }
}
