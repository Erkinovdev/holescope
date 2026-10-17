import 'dart:io';

import '../algo/frame.dart';

/// Пишет запись в формате веб-логгера (pothole-logger 0.1.0): тот же CSV читают Python (io.load_csv) и Dart (csv_loader).
/// Используется для «исследовательских» устройств: сырые данные уходят на сервер для обучения.
String buildLoggerCsv(SensorData s, GpsData g, {required int t0EpochMs, String mount = '', String car = '', String appVersion = ''}) {
  final b = StringBuffer()
    ..writeln('# pothole-logger 0.1.0 (holescope-app $appVersion)')
    ..writeln('# started=${DateTime.fromMillisecondsSinceEpoch(t0EpochMs, isUtc: true).toIso8601String()}')
    ..writeln('# car=$car')
    ..writeln('# mount=$mount')
    ..writeln('type,t_ms,lat,lon,gps_acc_m,speed_ms,heading_deg,ax,ay,az,lx,ly,lz,rx,ry,rz,label,note');
  var i = 0, j = 0;
  String ms(double t) => (t0EpochMs + t * 1000).round().toString();
  while (i < s.length || j < g.length) {
    if (j >= g.length || (i < s.length && s.t[i] <= g.t[j])) {
      b.writeln('m,${ms(s.t[i])},,,,,,${s.ax[i]},${s.ay[i]},${s.az[i]},,,,${s.rx[i]},${s.ry[i]},${s.rz[i]},,');
      i++;
    } else {
      final hd = g.heading[j].isNaN ? '' : g.heading[j].toString();
      b.writeln('g,${ms(g.t[j])},${g.lat[j]},${g.lon[j]},,${g.speed[j]},$hd,,,,,,,,,,,');
      j++;
    }
  }
  return b.toString();
}

/// Сохраняет CSV в gzip-файл и возвращает его.
File writeLoggerCsvGz(String dir, String name, String csv) {
  final f = File('$dir/$name.csv.gz');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(gzip.encode(csv.codeUnits));
  return f;
}
