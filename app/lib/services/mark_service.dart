import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'device_auth.dart';
import 'local_db.dart';

/// Вид отметки для сервера: метка справочника (`pothole_deep`, `manhole_sunk`…), оценка дороги (`road_a`…`road_e`), короткие `pothole`/`deep` или `not_pothole`.
class MarkKind {
  const MarkKind(this.wire);
  final String wire;
  static const pothole = MarkKind('pothole');
  static const deep = MarkKind('deep');
  static const notPothole = MarkKind('not_pothole');
  factory MarkKind.fromKey(String key) => MarkKind(key);
  bool get isRating => wire.startsWith('road_');
  @override
  bool operator ==(Object other) => other is MarkKind && other.wire == wire;
  @override
  int get hashCode => wire.hashCode;
}

/// Точка GPS, по которой привязываем отметку.
class MarkFix {
  const MarkFix(this.at, this.lat, this.lon, this.heading);
  final DateTime at;
  final double lat, lon;
  final double? heading;
}

class MarkRecord {
  MarkRecord({required this.id, required this.kind, required this.fix, required this.createdAt, this.guess});
  final String id;
  final MarkKind kind;
  final MarkFix fix;
  final DateTime createdAt;
  final Map<String, dynamic>? guess; // догадка модели на телефоне в момент вопроса (для оценки точности)

  Map<String, dynamic> toJson() => {'client_id': id, 'kind': kind.wire, 'lat': fix.lat, 'lon': fix.lon, if (fix.heading != null) 'heading': fix.heading, 'at': fix.at.toUtc().toIso8601String(), if (guess != null) 'guess': guess};
}

/// Отметки водителя («яма», «люк», «не яма»). Отметка ждёт [holdFor] — за это время её можно отменить голосом; потом уходит на сервер.
/// Если связи нет, отметки сохраняются в локальной базе и уходят позже.
class MarkService {
  MarkService({required this.db, required this.api, required this.auth, this.holdFor = const Duration(seconds: 10), this.platform = '', DateTime Function()? now}) : _now = now ?? DateTime.now;

  final LocalDb db;
  final ApiClient api;
  final DeviceAuth auth;
  final Duration holdFor;
  final String platform;
  final DateTime Function() _now;
  static const _key = 'marks_pending';
  final _held = <MarkRecord>[];
  final _timers = <String, Timer>{};

  /// Сколько отметок ждёт отправки (отладка/индикатор).
  int get pending => _held.length + _stored().length;

  /// Создаёт отметку в точке [fix]. Возвращает её, чтобы можно было отменить.
  MarkRecord add(MarkKind kind, MarkFix fix, {Map<String, dynamic>? guess}) {
    final r = MarkRecord(id: const Uuid().v4(), kind: kind, fix: fix, createdAt: _now(), guess: guess);
    _held.add(r);
    _timers[r.id] = Timer(holdFor, () => _release(r));
    return r;
  }

  /// Отменяет последнюю отметку, если она ещё не ушла. false — отменять нечего.
  bool cancelLast() {
    if (_held.isEmpty) return false;
    final r = _held.removeLast();
    _timers.remove(r.id)?.cancel();
    return true;
  }

  void _release(MarkRecord r) {
    if (!_held.remove(r)) return;
    _timers.remove(r.id);
    final list = _stored()..add(r.toJson());
    db.kvSet(_key, jsonEncode(list));
    unawaited(flush());
  }

  List<Map<String, dynamic>> _stored() {
    try {
      final raw = db.kvGet(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  bool _flushing = false;

  /// Отправляет сохранённые отметки. Ошибки сети глушатся — повторим при следующем вызове.
  Future<void> flush() async {
    if (_flushing) return;
    final list = _stored();
    if (list.isEmpty) return;
    _flushing = true;
    try {
      await auth.ensureRegistered(api, platform: platform);
      for (var i = 0; i < list.length; i += 50) {
        final chunk = list.sublist(i, (i + 50).clamp(0, list.length));
        await api.sendMarks(chunk);
      }
      db.kvSet(_key, jsonEncode(<Map<String, dynamic>>[]));
    } on ApiException catch (e) {
      if (e.status != null && e.status! >= 400 && e.status! < 500 && e.status != 408 && e.status != 429) {
        db.kvSet(_key, jsonEncode(<Map<String, dynamic>>[])); // сервер отверг навсегда — не копим
      }
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    // не потерять отметки: всё, что ждало, сохраняем
    for (final r in List.of(_held)) {
      final list = _stored()..add(r.toJson());
      db.kvSet(_key, jsonEncode(list));
    }
    _held.clear();
    _timers.clear();
  }
}
