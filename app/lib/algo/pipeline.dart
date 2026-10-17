import 'dart:math' as math;

import 'classify.dart';
import 'detector.dart';
import 'frame.dart';
import 'params.dart';
import 'roughness.dart';
import 'suspension.dart';
import 'trip_state.dart';

class TripResult {
  TripResult({
    required this.events,
    required this.segments,
    required this.handSegments,
    required this.autoTrips,
    required this.damping,
    required this.suspension,
    required this.durationS,
    required this.distanceKm,
    required this.fwdOk,
  });
  final List<RoadEventData> events;
  final List<RoadSegment> segments;
  final List<(double, double)> handSegments;
  final List<TripEnd> autoTrips;
  final DampingSummary damping;
  final SoftnessScore suspension;
  final double durationS, distanceKm;
  final bool fwdOk;
}

/// Путь по GPS (м) нарастающим итогом на каждом фиксе.
List<double> gpsPathMeters(GpsData gps) {
  final out = List<double>.filled(gps.length, 0);
  for (var i = 1; i < gps.length; i++) {
    final d = haversine(gps.lat[i - 1], gps.lon[i - 1], gps.lat[i], gps.lon[i]);
    out[i] = out[i - 1] + (d.isNaN ? 0 : d);
  }
  return out;
}

/// Полный проход (порт pipeline.process_csv, но на готовых массивах).
TripResult processTrip(SensorData m, GpsData gps, AlgoParams p) {
  final sig = vehicleFrame(m, gps, p);
  final hands = handSegments(sig);
  final events = detect(sig, gps, p, exclude: hands);
  for (final e in events) {
    classify(e);
  }
  final segs = segments(sig, gps, p);
  final td = TripDetector();
  for (var i = 0; i < gps.length; i++) {
    td.update(gps.t[i], gps.speed[i] * 3.6);
  }
  td.finish(gps.t[gps.length - 1]);
  final damp = dampingSummary(events);
  final susp = softnessScore(null, damp.zetaMedian, damp.fBodyMedian);
  final path = gpsPathMeters(gps);
  return TripResult(
    events: events,
    segments: segs,
    handSegments: hands,
    autoTrips: td.trips,
    damping: damp,
    suspension: susp,
    durationS: sig.t.last - sig.t.first,
    distanceKm: path.isEmpty ? 0 : path.last / 1000,
    fwdOk: sig.fwdOk,
  );
}

/// Приватность: убираем события и сегменты в первых/последних [trimM] метрах пути (дом/работа).
/// Вызывать ПЕРЕД отправкой. Возвращает новый результат.
TripResult trimForPrivacy(TripResult r, GpsData gps, {double trimM = 200}) {
  if (gps.length < 2) return r;
  final path = gpsPathMeters(gps);
  final total = path.last;
  if (total < trimM * 2.5) {
    // слишком короткая поездка: отдаём только середину, если она есть, иначе пусто
    return _copy(r, const [], const []);
  }
  double pathAt(double t) {
    // линейная интерполяция пути по времени
    if (t <= gps.t.first) return 0;
    if (t >= gps.t.last) return total;
    var lo = 0, hi = gps.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (gps.t[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final f = (t - gps.t[lo]) / math.max(gps.t[hi] - gps.t[lo], 1e-9);
    return path[lo] + (path[hi] - path[lo]) * f;
  }

  bool keep(double t) {
    final s = pathAt(t);
    return s >= trimM && s <= total - trimM;
  }

  return _copy(r, [for (final e in r.events) if (keep(e.t)) e], [for (final s in r.segments) if (keep(s.t0) && keep(s.t1)) s]);
}

TripResult _copy(TripResult r, List<RoadEventData> ev, List<RoadSegment> sg) => TripResult(
      events: ev,
      segments: sg,
      handSegments: r.handSegments,
      autoTrips: r.autoTrips,
      damping: r.damping,
      suspension: r.suspension,
      durationS: r.durationS,
      distanceKm: r.distanceKm,
      fwdOk: r.fwdOk,
    );

/// Тело POST /api/v1/trips (формат совпадает с backend/api/views.upload_trip).
/// События типов touch/noise не отправляются — сервер их тоже отбрасывает.
Map<String, dynamic> tripPayload(
  TripResult r, {
  required DateTime startedAt,
  required String startReason,
  required String endReason,
  String mode = 'car',
  double modeConf = 0.6,
}) =>
    {
      'started_at': startedAt.toUtc().toIso8601String(),
      'duration_s': r.durationS,
      'distance_km': r.distanceKm,
      'algo_version': algoVersion,
      'start_reason': startReason,
      'end_reason': endReason,
      'mode': mode,
      'mode_conf': modeConf,
      'events': [for (final e in r.events) if (e.type != 'touch' && e.type != 'noise') e.toJson()],
      'segments': [for (final s in r.segments) s.toJson()],
      'damping': r.damping.toJson(),
      'suspension': r.suspension.toJson(),
    };
