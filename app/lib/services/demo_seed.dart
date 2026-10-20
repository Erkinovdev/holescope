import 'dart:math' as math;

import 'local_db.dart';

/// Только для веба и проверки экранов: ?seed=1 добавляет в пустую историю поездку с треком и событиями (Ташкент).
void seedDemoTrip(LocalDb db) {
  if (db.trips().isNotEmpty) return;
  const la0 = 41.3103, lo0 = 69.2401;
  final track = <List<Object>>[];
  const cls = ['A', 'A', 'B', 'B', 'B', 'C', 'B', 'A', 'B', 'C', 'D', 'D', 'C', 'B', 'B', 'A'];
  var la = la0, lo = lo0;
  for (var i = 0; i < 64; i++) {
    final a = i / 64 * math.pi * 1.1;
    final la1 = la0 + 0.0042 * math.sin(a * 1.2) + i * 0.00006, lo1 = lo0 + i * 0.00092 + 0.0007 * math.sin(a * 2);
    track.add([la, lo, la1, lo1, cls[(i ~/ 4) % cls.length]]);
    la = la1;
    lo = lo1;
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  final start = now - 24 * 60000;
  Map<String, Object> ev(int k, String type, String level, int el) {
    final s = track[k];
    return {'at': start + k * 20000, 'lat': s[2], 'lon': s[3], 'type': type, 'level': level, 'speed': 38 + k % 12, 'el': el};
  }

  db.addTrip(startedAt: start, endedAt: now, distanceKm: 11.7, potholes: 3, summary: {
    'mode': 'car',
    'segments': {'A': 14, 'B': 26, 'C': 12, 'D': 8, 'E': 2},
    'suspension': {'score': 58.0, 'cls': 'S3', 'confidence': 0.6},
    'track': track,
    'events': [ev(10, 'pothole', 'deep', 1), ev(24, 'bump', 'mid', 1), ev(37, 'pothole', 'danger', 1), ev(14, 'pothole', 'light', 0), ev(30, 'pothole', 'mid', 0), ev(48, 'pothole', 'light', 0)],
  });
}
