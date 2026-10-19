import '../algo/csv_loader.dart';
import 'samples.dart';
import 'trip_recorder.dart';

/// Воспроизводит записанную поездку как поток отсчётов (тесты, демо-режим исследователя).
/// [baseEpochMs] — абсолютное время начала записи.
void replayTrip(TripRecorder rec, CsvTrip trip, {required int baseEpochMs, double? untilS, bool Function()? stop}) {
  final s = trip.sensors, g = trip.gps;
  var i = 0, j = 0;
  while (i < s.length || j < g.length) {
    final takeMotion = j >= g.length || (i < s.length && s.t[i] <= g.t[j]);
    if (takeMotion) {
      if (untilS != null && s.t[i] > untilS) break;
      rec.onMotion(MotionSample(baseEpochMs + (s.t[i] * 1000).round(), s.ax[i], s.ay[i], s.az[i], s.rx[i], s.ry[i], s.rz[i]));
      i++;
    } else {
      if (untilS != null && g.t[j] > untilS) break;
      rec.onGps(GpsFix(baseEpochMs + (g.t[j] * 1000).round(), g.lat[j], g.lon[j], g.speed[j], g.heading[j], 3.0));
      j++;
    }
    if (stop != null && stop()) break;
  }
}

/// То же, но отдаёт управление циклу событий каждые [yieldEveryS] секунд записи — как в реальном времени:
/// без этого фоновые проходы «живого» обнаружения не успевают завершиться (тесты, демо).
Future<void> replayTripAsync(TripRecorder rec, CsvTrip trip, {required int baseEpochMs, double yieldEveryS = 0.5}) async {
  final s = trip.sensors, g = trip.gps;
  var i = 0, j = 0;
  var nextYield = yieldEveryS;
  while (i < s.length || j < g.length) {
    final takeMotion = j >= g.length || (i < s.length && s.t[i] <= g.t[j]);
    final t = takeMotion ? s.t[i] : g.t[j];
    if (t >= nextYield) {
      await Future<void>.delayed(Duration.zero);
      nextYield = t + yieldEveryS;
    }
    if (takeMotion) {
      rec.onMotion(MotionSample(baseEpochMs + (s.t[i] * 1000).round(), s.ax[i], s.ay[i], s.az[i], s.rx[i], s.ry[i], s.rz[i]));
      i++;
    } else {
      rec.onGps(GpsFix(baseEpochMs + (g.t[j] * 1000).round(), g.lat[j], g.lon[j], g.speed[j], g.heading[j], 3.0));
      j++;
    }
  }
  await Future<void>.delayed(Duration.zero);
}
