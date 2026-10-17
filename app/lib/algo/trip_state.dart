/// Автоматический старт/стоп поездки (порт trip_state.py). Состояния: IDLE → ARMED → DRIVING → IDLE.
enum TripPhase { idle, armed, driving }

enum ActivityKind { automotive, walking, stationary, unknown }

class TripConfig {
  const TripConfig({
    this.startSpeedKmh = 15.0,
    this.startHoldS = 20.0,
    this.stopSpeedKmh = 3.0,
    this.stopHoldS = 180.0,
    this.walkStopHoldS = 45.0,
    this.lostSignalS = 300.0,
    this.trimS = 60.0,
  });
  final double startSpeedKmh, startHoldS, stopSpeedKmh, stopHoldS, walkStopHoldS, lostSignalS, trimS;
}

/// Событие конца поездки: интервал [start, end] в секундах.
class TripEnd {
  const TripEnd(this.start, this.end, this.reason);
  final double start, end;
  final String reason; // stopped | walking | signal_lost | manual
}

class TripDetector {
  TripDetector([this.cfg = const TripConfig()]);
  final TripConfig cfg;
  TripPhase phase = TripPhase.idle;
  double? _tFast, _tSlow, _tWalk, _lastT;
  double? tripStart;
  final List<TripEnd> trips = [];

  /// speedKmh == null — нет GPS-скорости. Возвращает завершённую поездку (если она закончилась на этом шаге).
  TripEnd? update(double t, double? speedKmh, [ActivityKind activity = ActivityKind.unknown]) {
    final c = cfg;
    if (speedKmh == null) {
      if (phase == TripPhase.driving && _lastT != null && t - _lastT! > c.lostSignalS) {
        return _end(_lastT!, 'signal_lost');
      }
      return null;
    }
    _lastT = t;
    if (phase == TripPhase.idle || phase == TripPhase.armed) {
      if (speedKmh >= c.startSpeedKmh || (activity == ActivityKind.automotive && speedKmh >= 8)) {
        _tFast ??= t;
        phase = TripPhase.armed;
        if (t - _tFast! >= c.startHoldS) {
          phase = TripPhase.driving;
          tripStart = _tFast;
          _tSlow = _tWalk = null;
        }
      } else {
        _tFast = null;
        phase = TripPhase.idle;
      }
    } else if (phase == TripPhase.driving) {
      final slow = speedKmh < c.stopSpeedKmh;
      _tSlow = slow ? (_tSlow ?? t) : null;
      final walking = slow && activity == ActivityKind.walking;
      _tWalk = walking ? (_tWalk ?? t) : null;
      if (_tWalk != null && t - _tWalk! >= c.walkStopHoldS) {
        return _end(_tSlow ?? t, 'walking');
      } else if (_tSlow != null && t - _tSlow! >= c.stopHoldS) {
        return _end(_tSlow!, 'stopped');
      }
    }
    return null;
  }

  TripEnd _end(double tEnd, String reason) {
    final r = TripEnd(tripStart!, tEnd, reason);
    trips.add(r);
    phase = TripPhase.idle;
    _tFast = _tSlow = _tWalk = null;
    tripStart = null;
    return r;
  }

  /// Принудительное завершение (кнопка «Остановить» / конец файла).
  TripEnd? finish(double t, [String reason = 'manual']) {
    if (phase == TripPhase.driving) return _end(_tSlow ?? t, reason);
    return null;
  }
}

/// Грубое правило «не легковая поездка» (порт classify_mode). Возвращает (режим, уверенность).
(String, double) classifyMode(List<double> speedsKmh, double stopsPerKm) {
  if (speedsKmh.isEmpty) return ('unknown', 0.0);
  final s = List<double>.from(speedsKmh)..sort();
  double pct(double q) {
    // numpy percentile, линейная интерполяция
    final pos = (s.length - 1) * q / 100;
    final lo = pos.floor(), hi = pos.ceil();
    return s[lo] + (s[hi] - s[lo]) * (pos - lo);
  }

  final p90 = pct(90);
  if (p90 < 9) return ('walk_or_bike', 0.7);
  if (stopsPerKm >= 3.0 && p90 < 55) return ('bus_or_tram', 0.5);
  if (p90 > 110) return ('train_or_highway', 0.4);
  return ('car', 0.6);
}
