@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/csv_loader.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/device_auth.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/outbox.dart';
import 'package:holescope/services/replay.dart';
import 'package:holescope/services/sensor_source.dart';
import 'package:holescope/services/trip_recorder.dart';

/// Сквозная проверка с поднятым backend (docker compose up, порт из backend/.env WEB_PORT=8010).
/// Запуск: flutter test test/e2e_backend_test.dart --dart-define=API_BASE=http://127.0.0.1:8010
/// Если сервер недоступен, тесты пропускаются.
const base = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8010');

Future<bool> _up() async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final r = await (await c.getUrl(Uri.parse('$base/api/v1/map/clusters?bbox=0,0,1,1'))).close();
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<Map<String, dynamic>> _recordTrip() async {
  final f = Directory('../analysis').listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.csv') && f.path.contains('pothole_2026-10-17'));
  final csv = parseLoggerCsv(f.readAsStringSync());
  final db = LocalDb.memory();
  final rec = TripRecorder(db: db, control: FakeSensorSource(), config: const RecorderConfig(runInIsolate: false, liveEveryS: 1e9), context: () => const RecorderContext(wheelbaseM: 2.485));
  rec.enable();
  replayTrip(rec, csv, baseEpochMs: DateTime.now().millisecondsSinceEpoch - 3600000);
  await rec.stopManual();
  final item = db.dueOutbox(DateTime.now().millisecondsSinceEpoch + 1).single;
  return jsonDecode(item.payload) as Map<String, dynamic>;
}

void main() {
  late bool up;
  setUpAll(() async => up = await _up());

  test('полный цикл: регистрация → поездка → подтверждение → ahead → вопросы', () async {
    if (!up) {
      markTestSkipped('backend не запущен: $base');
      return;
    }
    final payload = await _recordTrip();
    final events = (payload['events'] as List).cast<Map<String, dynamic>>();
    expect(events, isNotEmpty);

    // два разных устройства присылают одну и ту же поездку
    final tokens = <String>[];
    final tripIds = <int>[];
    for (var d = 0; d < 2; d++) {
      final api = ApiClient(base);
      final auth = DeviceAuth(MemoryTokenStore());
      tokens.add(await auth.ensureRegistered(api, platform: 'test', lang: 'ru'));
      final db = LocalDb.memory();
      final localId = db.addTrip(startedAt: 1, endedAt: 2, distanceKm: 11, potholes: events.length);
      final body = Map<String, dynamic>.from(payload)..['_local'] = localId;
      db.enqueue('trip', jsonEncode(body));
      final worker = OutboxWorker(db, api);
      expect(await worker.flush(), 1, reason: 'очередь ушла');
      expect(db.outboxCount(), 0);
      final t = db.trips().single;
      expect(t.status, 'sent');
      tripIds.add(t.serverTripId!);
    }
    expect(tokens[0], isNot(tokens[1]));

    // профиль машины
    final api0 = ApiClient(base, token: tokens[0]);
    await api0.patchVehicle({'wheelbase_mm': 2485, 'mount': 'seat', 'tire_pressure_bar': 2.1});

    // карта: у первой отправленной ямы теперь ≥2 устройства → confirmed
    final e = events.first;
    final lat = (e['lat'] as num).toDouble(), lon = (e['lon'] as num).toDouble();
    final clusters = await api0.mapClusters(minLat: lat - 0.001, minLon: lon - 0.001, maxLat: lat + 0.001, maxLon: lon + 0.001);
    final near = clusters.where((c) => (c.lat - lat).abs() < 0.0002 && (c.lon - lon).abs() < 0.0002).toList();
    expect(near, isNotEmpty);
    expect(near.first.devices, greaterThanOrEqualTo(2));
    expect(near.first.status, anyOf('confirmed', 'complaint'));

    // drive/ahead: стоим в 100 м «позади» ямы по её направлению движения
    final hd = (e['heading'] as num?)?.toDouble() ?? 0;
    final h = hd * math.pi / 180;
    final backLat = lat - 100 * math.cos(h) / 111320;
    final backLon = lon - 100 * math.sin(h) / (111320 * math.cos(lat * math.pi / 180));
    final ahead = await api0.ahead(lat: backLat, lon: backLon, heading: hd, dist: 200);
    expect(ahead, isNotEmpty);
    expect(ahead.first.distanceM, inInclusiveRange(60, 140));

    // вопросы «что это было?»: после поездки появились, ответ принимается
    final qs = await api0.questionsNext();
    expect(qs, isNotEmpty);
    expect(qs.length, lessThanOrEqualTo(5));
    expect(qs.first.options, contains('manhole'));
    await api0.answerQuestion(qs.first.id, 'pothole_mid');
    final after = await api0.questionsNext();
    expect(after.any((q) => q.id == qs.first.id), isFalse);

    // без токена — 401, не ретраится
    final anon = ApiClient(base);
    try {
      await anon.uploadTrip(payload);
      fail('ожидали 401');
    } on ApiException catch (ex) {
      expect(ex.status, 401);
      expect(ex.retryable, isFalse);
    }
  });
}
