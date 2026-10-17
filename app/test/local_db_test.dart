import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/outbox.dart';

void main() {
  test('очередь: добавление, due, ошибка с задержкой, удаление', () {
    final db = LocalDb.memory();
    final id = db.enqueue('trip', '{"a":1}', now: 1000);
    expect(db.outboxCount(), 1);
    expect(db.dueOutbox(2000).single.id, id);
    db.outboxFailed(id, 50000, 'нет сети');
    expect(db.dueOutbox(2000), isEmpty, reason: 'после ошибки ждём next_at');
    final again = db.dueOutbox(60000).single;
    expect(again.attempts, 1);
    db.outboxDone(id);
    expect(db.outboxCount(), 0);
  });

  test('история поездок и итоги', () {
    final db = LocalDb.memory();
    final a = db.addTrip(startedAt: 1, endedAt: 2, distanceKm: 3.5, potholes: 4, summary: {'mode': 'car'});
    db.addTrip(startedAt: 3, endedAt: 4, distanceKm: 1.5, potholes: 1);
    expect(db.totals().km, closeTo(5.0, 1e-9));
    expect(db.totals().potholes, 5);
    expect(db.trips().first.startedAt, 3, reason: 'новые сверху');
    db.markTripSent(a, 77);
    expect(db.trips().firstWhere((t) => t.id == a).serverTripId, 77);
    expect(db.trips().firstWhere((t) => t.id == a).summary['mode'], 'car');
  });

  test('кэш ям: замена и поиск рядом', () {
    final db = LocalDb.memory();
    db.replaceClusters([
      const CachedCluster(id: 1, lat: 41.3270, lon: 69.2284, heading: 90, type: 'pothole', level: 'deep', status: 'confirmed', confidence: 0.9, safeSpeed: 30),
      const CachedCluster(id: 2, lat: 41.4000, lon: 69.3000, heading: null, type: 'pothole', level: null, status: 'candidate', confidence: 0.2, safeSpeed: null),
    ]);
    expect(db.clusterCount(), 2);
    final near = db.clustersNear(41.3270, 69.2284, 300);
    expect(near.map((c) => c.id), [1]);
    expect(near.single.heading, 90);
  });

  test('kv и схема на диске сохраняются между открытиями', () {
    final f = File('${Directory.systemTemp.path}/hs_test_${DateTime.now().microsecondsSinceEpoch}.db');
    addTearDown(() {
      if (f.existsSync()) f.deleteSync();
    });
    var db = LocalDb.open(f.path);
    db.kvSet('x', 'y');
    db.enqueue('trip', '{}');
    db.close();
    db = LocalDb.open(f.path);
    expect(db.kvGet('x'), 'y');
    expect(db.outboxCount(), 1);
    db.close();
  });

  test('backoff растёт и ограничен часом', () {
    expect(OutboxWorker.backoffMs(0), 15000);
    expect(OutboxWorker.backoffMs(1), 30000);
    expect(OutboxWorker.backoffMs(3), 120000);
    expect(OutboxWorker.backoffMs(20), 3600000);
  });
}
