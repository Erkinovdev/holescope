import 'dart:math' as math;

import 'dart:convert';

import 'api_client.dart';
import 'local_db.dart';

/// Яма впереди по ходу движения.
class AheadItem {
  const AheadItem({required this.id, required this.distanceM, required this.side, required this.level, required this.safeSpeed, required this.type, required this.lat, required this.lon, this.span = '', this.advice = ''});
  final int id, distanceM;
  final double lat, lon;
  final String side, type, span, advice; // span: lane|full; advice: avoid (можно объехать) | slow (только сбросить скорость)
  final String? level;
  final int? safeSpeed;
}

class AheadConfig {
  const AheadConfig({this.warnDistanceM = 150, this.corridorM = 25, this.minAlongM = 5, this.headingTolDeg = 70, this.includeCandidates = false, this.refreshEveryM = 800, this.refreshRadiusM = 1500, this.refreshMaxAgeS = 600, this.allowLight = true, this.allowMid = true, this.allowDeep = true, this.speedAware = false});
  final int warnDistanceM;
  final double corridorM, minAlongM, headingTolDeg, refreshEveryM, refreshRadiusM, refreshMaxAgeS;
  final bool includeCandidates; // кандидаты (1 проезд) по умолчанию не озвучиваем: много ложных
  final bool allowLight, allowMid, allowDeep; // какие по глубине ямы озвучивать (настройки)
  final bool speedAware; // чем быстрее едем, тем раньше предупреждаем

  bool allows(String? level) => switch (level) { 'light' => allowLight, 'mid' => allowMid, 'deep' || 'danger' => allowDeep, _ => true };
}

/// Режим Drive («контр-карам»): предупреждения без маршрута — по GPS и направлению.
/// Источник — локальный кэш ям вокруг машины (работает офлайн), кэш пополняется с сервера.
class AheadWarner {
  AheadWarner(this.db, this.api, {AheadConfig Function()? config}) : _cfg = config ?? (() => const AheadConfig());

  final LocalDb db;
  final ApiClient? api;
  final AheadConfig Function() _cfg;
  final Set<int> _warned = {};
  Set<int>? _ever; // ямы, о которых мы когда-либо предупреждали (хранится в кэше): если такую заделали — сообщим
  void Function(CachedCluster)? onFixed;

  Set<int> get _everWarned => _ever ??= {for (final v in (jsonDecode(db.kvGet('warned_ids') ?? '[]') as List)) (v as num).toInt()};
  void _remember(int id) {
    final e = _everWarned;
    if (e.add(id)) {
      if (e.length > 300) e.remove(e.first);
      db.kvSet('warned_ids', jsonEncode(e.toList()));
    }
  }
  double? _refLat, _refLon;
  int _refAtMs = 0;
  bool _refreshing = false;

  /// Забыть уже озвученные ямы (новая поездка).
  void reset() => _warned.clear();

  /// Геометрия совпадает с backend/api/views.ahead.
  static ({double along, double across}) project(double lat, double lon, double heading, double cLat, double cLon) {
    final dx = (cLon - lon) * 111320 * math.cos(lat * math.pi / 180);
    final dy = (cLat - lat) * 111320;
    final h = heading * math.pi / 180;
    return (along: dx * math.sin(h) + dy * math.cos(h), across: dx * math.cos(h) - dy * math.sin(h));
  }

  static double _angDiff(double a, double b) => ((a - b + 180) % 360 + 360) % 360 - 180;

  /// Ближайшая яма в коридоре впереди (из кэша). [markWarned] — запомнить, чтобы не повторять.
  AheadItem? check(double lat, double lon, double heading, {bool markWarned = true, double speedKmh = 0}) {
    final cfg = _cfg();
    // с учётом скорости: не меньше 5 секунд пути до ямы, но не дальше 350 м
    final warnM = cfg.speedAware ? math.min(350.0, math.max(cfg.warnDistanceM.toDouble(), speedKmh / 3.6 * 5)) : cfg.warnDistanceM.toDouble();
    final reach = math.max(warnM, 100);
    AheadItem? best;
    for (final c in db.clustersNear(lat, lon, reach + 50)) {
      if (c.status == 'fixed' || c.status == 'false') continue;
      if (!cfg.includeCandidates && c.status == 'candidate') continue;
      if (!cfg.allows(c.level)) continue;
      if (c.heading != null && _angDiff(c.heading!, heading).abs() >= cfg.headingTolDeg) continue;
      final p = project(lat, lon, heading, c.lat, c.lon);
      if (p.along <= cfg.minAlongM || p.along > warnM || p.across.abs() > cfg.corridorM) continue;
      if (_warned.contains(c.id)) continue;
      if (best == null || p.along < best.distanceM) {
        best = AheadItem(id: c.id, distanceM: p.along.round(), side: (c.side == 'left' || c.side == 'right') ? c.side : (p.across > 6 ? 'right' : (p.across < -6 ? 'left' : 'center')), level: c.level, safeSpeed: c.safeSpeed, type: c.type, lat: c.lat, lon: c.lon, span: c.span, advice: c.advice);
      }
    }
    if (best != null && markWarned) {
      _warned.add(best.id);
      _remember(best.id);
    }
    return best;
  }

  /// Пополняет локальный кэш с сервера, если уехали далеко / кэш устарел. Ошибки сети глушатся (офлайн-режим).
  Future<void> refreshIfNeeded(double lat, double lon, {int? nowMs}) async {
    final a = api;
    if (a == null || _refreshing) return;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final far = _refLat == null || _meters(lat, lon, _refLat!, _refLon!) > _cfg().refreshEveryM;
    final old = (now - _refAtMs) / 1000 > _cfg().refreshMaxAgeS;
    if (!far && !old) return;
    _refreshing = true;
    try {
      final r = _cfg().refreshRadiusM;
      final dLat = r / 111320.0, dLon = r / (111320.0 * math.cos(lat * math.pi / 180));
      final list = await a.mapClusters(minLat: lat - dLat, minLon: lon - dLon, maxLat: lat + dLat, maxLon: lon + dLon);
      final before = db.clusterStatuses();
      final fresh = [
        for (final c in list)
          CachedCluster(id: c.id, lat: c.lat, lon: c.lon, heading: c.heading, type: c.type, level: c.level, status: c.status, confidence: c.confidence, safeSpeed: c.safeSpeed, span: c.span, side: c.side, advice: c.advice)
      ];
      db.replaceClusters(fresh, clear: true, now: now);
      for (final c in fresh) {
        if (c.status == 'fixed' && before.containsKey(c.id) && before[c.id] != 'fixed' && _everWarned.contains(c.id)) onFixed?.call(c);
      }
      _refLat = lat;
      _refLon = lon;
      _refAtMs = now;
    } on ApiException {
      // нет сети — продолжаем по кэшу
    } finally {
      _refreshing = false;
    }
  }

  static double _meters(double la1, double lo1, double la2, double lo2) {
    final dx = (lo2 - lo1) * 111320 * math.cos(la1 * math.pi / 180);
    final dy = (la2 - la1) * 111320;
    return math.sqrt(dx * dx + dy * dy);
  }
}
