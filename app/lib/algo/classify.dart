import 'dart:math' as math;

import 'detector.dart';

/// Слой 5–6 (порт classify.py): тип и тяжесть по правилам v2.
/// ВАЖНО: на разметке 16.10 уровни ям по этим правилам совпадают с разметкой в 53% случаев (27/51),
/// тогда как «всё лёгкая» даёт 78% — уровни провизорные, заменить моделью после накопления разметки.
void classify(RoadEventData e) {
  if (e.pair < 0.2 && e.durMs < 250 && e.peak > 6 && e.gyroPeak > 60) {
    e.type = 'touch';
    e.level = null;
    e.confidence = 0.7;
    e.safeSpeedKmh = null;
    return;
  }
  if (e.score < 2.4 && e.ratio < 5) {
    e.type = 'noise';
    e.level = null;
    e.confidence = 0.6;
    e.safeSpeedKmh = null;
    return;
  }
  e.type = 'pothole';
  e.confidence = 0.6;
  final s = e.score;
  e.level = s < 5.0 ? 'light' : s < 8.0 ? 'mid' : s < 14.0 ? 'deep' : 'danger';
  e.safeSpeedKmh = safeSpeed(e);
}

/// Скорость, при которой ожидаемый пик ≤ 3 м/с² (комфорт).
int? safeSpeed(RoadEventData e) {
  if (e.score <= 0) return null;
  const comfort = 3.0;
  if (e.score <= comfort) return null;
  final v = 40.0 * math.pow(comfort / e.score, 1.0 / 0.8);
  return math.max(10, math.min(60, (v / 5.0).round() * 5));
}
