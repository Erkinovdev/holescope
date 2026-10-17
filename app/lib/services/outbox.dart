import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'api_client.dart';
import 'local_db.dart';

/// Отправка очереди с экспоненциальной задержкой (офлайн-устойчиво).
class OutboxWorker {
  OutboxWorker(this.db, this.api, {int Function()? now, math.Random? rnd})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _rnd = rnd ?? math.Random();

  final LocalDb db;
  final ApiClient api;
  final int Function() _now;
  final math.Random _rnd;
  bool _busy = false;

  static int backoffMs(int attempts, [math.Random? r]) {
    final base = math.min(15000 * math.pow(2, attempts).toInt(), 3600000);
    return base + (r == null ? 0 : (base * 0.1 * r.nextDouble()).round());
  }

  /// Отправляет всё, что пора. Возвращает число успешно отправленных элементов.
  Future<int> flush() async {
    if (_busy) return 0;
    _busy = true;
    var sent = 0;
    try {
      for (final item in db.dueOutbox(_now())) {
        try {
          if (item.kind == 'trip') {
            final body = jsonDecode(item.payload) as Map<String, dynamic>;
            final localId = body.remove('_local') as int?;
            final r = await api.uploadTrip(body);
            if (localId != null) db.markTripSent(localId, r.tripId);
          } else if (item.kind == 'raw') {
            final f = File(item.payload);
            if (f.existsSync()) {
              await api.uploadRaw(f, f.uri.pathSegments.last);
              f.deleteSync();
            }
          }
          db.outboxDone(item.id);
          sent++;
        } on ApiException catch (e) {
          if (!e.retryable) {
            db.outboxDrop(item.id); // 4xx: данные отвергнуты сервером, повтор не поможет
          } else {
            db.outboxFailed(item.id, _now() + backoffMs(item.attempts, _rnd), e.message);
            break; // нет сети/сервер лежит — остальные пробовать рано
          }
        }
      }
    } finally {
      _busy = false;
    }
    return sent;
  }
}
