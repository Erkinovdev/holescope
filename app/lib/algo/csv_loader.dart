import 'dart:math' as math;
import 'dart:typed_data';

import 'frame.dart';

/// Разбор CSV веб-логгера (формат pothole-logger 0.1) → массивы алгоритма. Порт io.load_csv + gps_frame.
class CsvTrip {
  CsvTrip(this.sensors, this.gps, this.meta);
  final SensorData sensors;
  final GpsData gps;
  final Map<String, String> meta;
}

CsvTrip parseLoggerCsv(String text) {
  final meta = <String, String>{};
  final lines = text.split('\n');
  var i = 0;
  for (; i < lines.length; i++) {
    final l = lines[i];
    if (!l.startsWith('#')) break;
    final body = l.substring(1).trim();
    final eq = body.indexOf('=');
    if (eq > 0) meta[body.substring(0, eq).trim()] = body.substring(eq + 1).trim();
  }
  final header = lines[i].trim().split(',');
  final col = {for (var k = 0; k < header.length; k++) header[k]: k};
  i++;
  double? num(List<String> f, String name) {
    final k = col[name];
    if (k == null || k >= f.length) return null;
    final s = f[k];
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  // первый проход: общий t0 = min(t_ms) по ВСЕМ строкам (как в Python)
  final m = <List<double>>[]; // t_ms, ax, ay, az, rx, ry, rz
  final g = <List<double>>[]; // t_ms, lat, lon, speed(NaN?), heading(NaN?)
  var t0 = double.infinity;
  for (; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final f = line.trim().split(',');
    final t = num(f, 't_ms');
    if (t == null) continue;
    if (t < t0) t0 = t;
    final type = f[col['type']!];
    if (type == 'm') {
      final ax = num(f, 'ax'), ay = num(f, 'ay'), az = num(f, 'az');
      if (ax == null || ay == null || az == null) continue;
      m.add([t, ax, ay, az, num(f, 'rx') ?? 0, num(f, 'ry') ?? 0, num(f, 'rz') ?? 0]);
    } else if (type == 'g') {
      final lat = num(f, 'lat'), lon = num(f, 'lon');
      if (lat == null || lon == null) continue;
      g.add([t, lat, lon, num(f, 'speed_ms') ?? double.nan, num(f, 'heading_deg') ?? double.nan]);
    }
  }
  m.sort((a, b) => a[0].compareTo(b[0]));
  g.sort((a, b) => a[0].compareTo(b[0]));
  Float64List col1(List<List<double>> rows, int k, [double Function(double)? f]) =>
      Float64List.fromList([for (final r in rows) f == null ? r[k] : f(r[k])]);
  final sensors = SensorData(col1(m, 0, (v) => (v - t0) / 1000), col1(m, 1), col1(m, 2), col1(m, 3), col1(m, 4), col1(m, 5), col1(m, 6));
  final gt = col1(g, 0, (v) => (v - t0) / 1000);
  final lat = col1(g, 1), lon = col1(g, 2), hd = col1(g, 4);
  var sp = col1(g, 3);
  var bad = 0;
  for (final v in sp) {
    if (v.isNaN) bad++;
  }
  if (g.isNotEmpty && bad / g.length > 0.5) {
    // скорость не пришла — считаем по координатам
    final calc = Float64List(g.length);
    for (var k = 1; k < g.length; k++) {
      final d = haversine(lat[k - 1], lon[k - 1], lat[k], lon[k]);
      final dt = gt[k] - gt[k - 1];
      calc[k] = dt > 0 ? d / dt : 0.0;
    }
    sp = calc;
  } else {
    for (var k = 0; k < sp.length; k++) {
      if (sp[k].isNaN) sp[k] = 0.0;
    }
  }
  return CsvTrip(sensors, GpsData(gt, lat, lon, sp, hd), meta);
}

/// Вспомогательное: скорость → км/ч среднее (для отчётов).
double meanSpeedKmh(GpsData g) {
  if (g.length == 0) return 0;
  var s = 0.0;
  for (final v in g.speed) {
    s += v;
  }
  return s / g.length * 3.6;
}

double maxOf(Float64List a) => a.fold(-double.infinity, math.max);
