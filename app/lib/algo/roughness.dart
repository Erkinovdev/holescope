import 'dart:math' as math;
import 'dart:typed_data';

import 'frame.dart';
import 'numeric.dart';
import 'params.dart';

/// Сегмент дороги ~50 м с индексом ровности (порт roughness.segments).
class RoadSegment {
  RoadSegment({required this.seg, required this.latA, required this.lonA, required this.latB, required this.lonB, required this.speedKmh, required this.rms, required this.ri, required this.t0, required this.t1, required this.cls});
  final int seg;
  final double latA, lonA, latB, lonB, speedKmh, rms, ri, t0, t1;
  final String cls;

  Map<String, dynamic> toJson() => {'lat_a': latA, 'lon_a': lonA, 'lat_b': latB, 'lon_b': lonB, 'speed_kmh': speedKmh, 'ri': ri, 'cls': cls, 't0': t0};
}

const riClasses = ['A', 'B', 'C', 'D', 'E'];

String riClass(double ri, AlgoParams p) {
  var k = 0;
  for (final b in p.riBounds) {
    if (b <= ri) k++;
  }
  return riClasses[k];
}

List<RoadSegment> segments(VehicleSignal sig, GpsData gps, AlgoParams p) {
  final t = sig.t, vz = sig.vz;
  final n = t.length;
  final sp = interp(t, gps.t, gps.speed);
  final cum = Float64List(gps.length);
  var acc = 0.0;
  for (var i = 0; i < gps.length; i++) {
    var d = 0.0;
    if (i > 0 && gps.speed[i] >= p.minSpeedRiMs) {
      d = haversine(gps.lat[i - 1], gps.lon[i - 1], gps.lat[i], gps.lon[i]);
      if (d.isNaN) d = 0.0;
    }
    acc += d;
    cum[i] = acc;
  }
  final dist = interp(t, gps.t, cum);
  final lat = interp(t, gps.t, gps.lat), lon = interp(t, gps.t, gps.lon);
  // группировка по индексу сегмента (в порядке возрастания)
  final byId = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    if (sp[i] >= p.minSpeedRiMs) {
      final sid = (dist[i] / p.segLenM).floor();
      byId.putIfAbsent(sid, () => []).add(i);
    }
  }
  final ids = byId.keys.toList()..sort();
  final out = <RoadSegment>[];
  for (final s in ids) {
    final sel = byId[s]!;
    if (sel.length < 30) continue;
    var sv = 0.0, sq = 0.0;
    for (final i in sel) {
      sv += sp[i];
      sq += vz[i] * vz[i];
    }
    final v = sv / sel.length;
    final rms = math.sqrt(sq / sel.length);
    final ri = rms / math.pow(math.max(v, p.minSpeedRiMs), p.riBeta);
    final i0 = sel.first, i1 = sel.last;
    out.add(RoadSegment(seg: s, latA: lat[i0], lonA: lon[i0], latB: lat[i1], lonB: lon[i1], speedKmh: v * 3.6, rms: rms, ri: ri, t0: t[i0], t1: t[i1], cls: riClass(ri, p)));
  }
  return out;
}
