import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'db_open_native.dart' if (dart.library.js_interop) 'db_open_web.dart';

/// Подготовка базы на платформе (в вебе — загрузка sqlite3.wasm). Вызывать один раз до первого открытия.
Future<void> initLocalDb() => initDbPlatform();

/// Запись очереди отправки.
class OutboxItem {
  OutboxItem(this.id, this.kind, this.payload, this.createdAt, this.attempts, this.nextAt);
  final int id;
  final String kind; // trip | raw
  final String payload; // JSON (trip) или путь к файлу (raw)
  final int createdAt, attempts, nextAt;
}

/// Итог поездки в локальной истории.
class LocalTrip {
  LocalTrip({required this.id, required this.startedAt, required this.endedAt, required this.distanceKm, required this.potholes, required this.status, this.serverTripId, required this.summary});
  final int id;
  final int startedAt, endedAt; // epoch ms
  final double distanceKm;
  final int potholes;
  final String status; // queued | sent
  final int? serverTripId;
  final Map<String, dynamic> summary;
}

/// Кэш ям вокруг пользователя (для офлайн-предупреждений).
class CachedCluster {
  const CachedCluster({required this.id, required this.lat, required this.lon, required this.heading, required this.type, required this.level, required this.status, required this.confidence, required this.safeSpeed});
  final int id;
  final double lat, lon, confidence;
  final double? heading;
  final String type, status;
  final String? level;
  final int? safeSpeed;
}

class LocalNote {
  const LocalNote({required this.id, required this.at, required this.kind, required this.title, required this.body, required this.unread, required this.ref});
  final int id, at;
  final String kind, title, body, ref;
  final bool unread;
}

class PendingQuestion {
  const PendingQuestion({required this.id, required this.at, required this.lat, required this.lon, this.heading, required this.peak, required this.speedKmh, required this.guess, required this.wave});
  final int id, at;
  final double lat, lon, peak, speedKmh;
  final double? heading;
  final String guess;
  final List<double> wave;
}

/// Локальная БД на sqlite3 (очередь отправки, история поездок, кэш ям, настройки-значения).
/// Выбран sqlite3 напрямую: drift_dev несовместим с версиями test, закреплёнными Flutter 3.35.
class LocalDb {
  LocalDb(this._db) {
    _migrate();
  }

  factory LocalDb.open(String path) => LocalDb(openDbFile(path));
  factory LocalDb.memory() => LocalDb(openDbMemory());

  final CommonDatabase _db;

  static const _schemaVersion = 2;

  void _migrate() {
    final v = _db.select('PRAGMA user_version').first.values.first as int;
    if (v < 1) {
      _db.execute('''
        CREATE TABLE outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, payload TEXT NOT NULL,
          created_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_at INTEGER NOT NULL DEFAULT 0, last_error TEXT);
        CREATE TABLE trips(id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL,
          distance_km REAL NOT NULL, potholes INTEGER NOT NULL, status TEXT NOT NULL, server_trip_id INTEGER, summary TEXT NOT NULL);
        CREATE TABLE clusters(id INTEGER PRIMARY KEY, lat REAL NOT NULL, lon REAL NOT NULL, heading REAL, type TEXT NOT NULL,
          level TEXT, status TEXT NOT NULL, confidence REAL NOT NULL, safe_speed INTEGER, fetched_at INTEGER NOT NULL);
        CREATE INDEX clusters_pos ON clusters(lat, lon);
        CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT NOT NULL);
        PRAGMA user_version = 1;
      ''');
    }
    if (v < 2) {
      // центр уведомлений и очередь неотвеченных вопросов «что это было?»
      _db.execute('''
        CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
          body TEXT NOT NULL DEFAULT '', unread INTEGER NOT NULL DEFAULT 1, ref TEXT NOT NULL DEFAULT '');
        CREATE INDEX notes_at ON notes(at);
        CREATE TABLE pending(id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
          heading REAL, peak REAL NOT NULL DEFAULT 0, speed_kmh REAL NOT NULL DEFAULT 0, guess TEXT NOT NULL DEFAULT '', wave TEXT NOT NULL DEFAULT '[]');
        PRAGMA user_version = $_schemaVersion;
      ''');
    }
  }

  // ── центр уведомлений ──
  int addNote({required int at, required String kind, required String title, String body = '', String ref = ''}) {
    _db.execute('INSERT INTO notes(at,kind,title,body,ref,unread) VALUES(?,?,?,?,?,?)', [at, kind, title, body, ref, kind == 'push' ? 0 : 1]);
    _db.execute('DELETE FROM notes WHERE id NOT IN (SELECT id FROM notes ORDER BY at DESC LIMIT 300)');
    return _db.lastInsertRowId;
  }

  List<LocalNote> notes({int limit = 100}) => [
        for (final r in _db.select("SELECT * FROM notes WHERE kind<>'push' ORDER BY at DESC LIMIT ?", [limit]))
          LocalNote(id: r['id'] as int, at: r['at'] as int, kind: r['kind'] as String, title: r['title'] as String, body: r['body'] as String, unread: (r['unread'] as int) == 1, ref: r['ref'] as String)
      ];

  int unreadNotes() => _db.select('SELECT COUNT(*) n FROM notes WHERE unread=1').first['n'] as int;
  void readAllNotes() => _db.execute('UPDATE notes SET unread=0');

  /// Сколько уведомлений данного вида (или любых) создано с момента [sinceMs] — для лимита «не больше N в день».
  int notesSince(int sinceMs, {String? kind}) =>
      _db.select(kind == null ? 'SELECT COUNT(*) n FROM notes WHERE at>=?' : 'SELECT COUNT(*) n FROM notes WHERE at>=? AND kind=?', kind == null ? [sinceMs] : [sinceMs, kind]).first['n'] as int;

  // ── очередь вопросов ──
  int addPending({required int at, required double lat, required double lon, double? heading, double peak = 0, double speedKmh = 0, String guess = '', List<double> wave = const []}) {
    _db.execute('INSERT INTO pending(at,lat,lon,heading,peak,speed_kmh,guess,wave) VALUES(?,?,?,?,?,?,?,?)', [at, lat, lon, heading, peak, speedKmh, guess, jsonEncode(wave)]);
    _db.execute('DELETE FROM pending WHERE id NOT IN (SELECT id FROM pending ORDER BY at DESC LIMIT 12)');
    return _db.lastInsertRowId;
  }

  List<PendingQuestion> pending({int? notBeforeMs}) => [
        for (final r in _db.select('SELECT * FROM pending WHERE at>=? ORDER BY at DESC', [notBeforeMs ?? 0]))
          PendingQuestion(
            id: r['id'] as int,
            at: r['at'] as int,
            lat: (r['lat'] as num).toDouble(),
            lon: (r['lon'] as num).toDouble(),
            heading: (r['heading'] as num?)?.toDouble(),
            peak: (r['peak'] as num).toDouble(),
            speedKmh: (r['speed_kmh'] as num).toDouble(),
            guess: r['guess'] as String,
            wave: [for (final v in jsonDecode(r['wave'] as String) as List) (v as num).toDouble()],
          )
      ];

  void removePending(int id) => _db.execute('DELETE FROM pending WHERE id=?', [id]);
  void clearPending() => _db.execute('DELETE FROM pending');

  /// Удаляет с телефона всё личное: историю поездок, очередь вопросов и уведомления (кэш карты и очередь отправки не трогаем).
  void wipeUserData() => _db.execute('DELETE FROM trips; DELETE FROM pending; DELETE FROM notes;');

  void close() => _db.dispose();

  // ── очередь отправки ──
  int enqueue(String kind, String payload, {int? now}) {
    _db.execute('INSERT INTO outbox(kind,payload,created_at,next_at) VALUES(?,?,?,0)', [kind, payload, now ?? DateTime.now().millisecondsSinceEpoch]);
    return _db.lastInsertRowId;
  }

  List<OutboxItem> dueOutbox(int now, {int limit = 10}) => [
        for (final r in _db.select('SELECT * FROM outbox WHERE next_at <= ? ORDER BY id LIMIT ?', [now, limit]))
          OutboxItem(r['id'] as int, r['kind'] as String, r['payload'] as String, r['created_at'] as int, r['attempts'] as int, r['next_at'] as int)
      ];

  int outboxCount() => _db.select('SELECT COUNT(*) c FROM outbox').first['c'] as int;

  void outboxDone(int id) => _db.execute('DELETE FROM outbox WHERE id=?', [id]);

  void outboxFailed(int id, int nextAt, String error) =>
      _db.execute('UPDATE outbox SET attempts=attempts+1, next_at=?, last_error=? WHERE id=?', [nextAt, error, id]);

  /// Окончательно отбрасывает запись (например, сервер ответил 4xx — повтор бессмыслен).
  void outboxDrop(int id) => outboxDone(id);

  // ── история поездок ──
  int addTrip({required int startedAt, required int endedAt, required double distanceKm, required int potholes, Map<String, dynamic> summary = const {}}) {
    _db.execute('INSERT INTO trips(started_at,ended_at,distance_km,potholes,status,summary) VALUES(?,?,?,?,?,?)',
        [startedAt, endedAt, distanceKm, potholes, 'queued', jsonEncode(summary)]);
    return _db.lastInsertRowId;
  }

  void markTripSent(int id, int serverTripId) => _db.execute("UPDATE trips SET status='sent', server_trip_id=? WHERE id=?", [serverTripId, id]);

  List<LocalTrip> trips({int limit = 50}) => [
        for (final r in _db.select('SELECT * FROM trips ORDER BY started_at DESC LIMIT ?', [limit]))
          LocalTrip(
            id: r['id'] as int,
            startedAt: r['started_at'] as int,
            endedAt: r['ended_at'] as int,
            distanceKm: (r['distance_km'] as num).toDouble(),
            potholes: r['potholes'] as int,
            status: r['status'] as String,
            serverTripId: r['server_trip_id'] as int?,
            summary: jsonDecode(r['summary'] as String) as Map<String, dynamic>,
          )
      ];

  /// Суммарная статистика для профиля.
  ({int trips, double km, int potholes}) totals() {
    final r = _db.select('SELECT COUNT(*) n, COALESCE(SUM(distance_km),0) km, COALESCE(SUM(potholes),0) p FROM trips').first;
    return (trips: r['n'] as int, km: (r['km'] as num).toDouble(), potholes: (r['p'] as num).toInt());
  }

  /// Состояния ям в кэше (id → статус): чтобы заметить, что яма стала «заделана».
  Map<int, String> clusterStatuses() => {for (final r in _db.select('SELECT id, status FROM clusters')) r['id'] as int: r['status'] as String};

  // ── кэш ям ──
  void replaceClusters(List<CachedCluster> list, {int? now, bool clear = false}) {
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN');
    try {
      if (clear) _db.execute('DELETE FROM clusters');
      final st = _db.prepare('INSERT OR REPLACE INTO clusters(id,lat,lon,heading,type,level,status,confidence,safe_speed,fetched_at) VALUES(?,?,?,?,?,?,?,?,?,?)');
      for (final c in list) {
        st.execute([c.id, c.lat, c.lon, c.heading, c.type, c.level, c.status, c.confidence, c.safeSpeed, t]);
      }
      st.dispose();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<CachedCluster> clustersNear(double lat, double lon, double radiusM) {
    final dLat = radiusM / 111320.0;
    final dLon = radiusM / (111320.0 * 0.75);
    return [
      for (final r in _db.select('SELECT * FROM clusters WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?', [lat - dLat, lat + dLat, lon - dLon, lon + dLon]))
        CachedCluster(
          id: r['id'] as int,
          lat: (r['lat'] as num).toDouble(),
          lon: (r['lon'] as num).toDouble(),
          heading: (r['heading'] as num?)?.toDouble(),
          type: r['type'] as String,
          level: r['level'] as String?,
          status: r['status'] as String,
          confidence: (r['confidence'] as num).toDouble(),
          safeSpeed: r['safe_speed'] as int?,
        )
    ];
  }

  int clusterCount() => _db.select('SELECT COUNT(*) c FROM clusters').first['c'] as int;

  // ── key-value ──
  String? kvGet(String k) {
    final r = _db.select('SELECT v FROM kv WHERE k=?', [k]);
    return r.isEmpty ? null : r.first['v'] as String;
  }

  void kvSet(String k, String v) => _db.execute('INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)', [k, v]);
}
