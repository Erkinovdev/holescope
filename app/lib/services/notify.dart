import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/settings.dart';
import 'local_db.dart';

/// Виды уведомлений (Figma · Flow 9, «Каталог типов»).
enum NoteKind { pothole, question, fixed, complaint, weekly, service }

/// Отправка системного уведомления (шторка/экран блокировки). В тестах — пустая.
abstract class SystemNotifier {
  Future<void> show({required int id, required String title, required String body, required bool urgent, String payload = ''});
}

class NoopSystemNotifier implements SystemNotifier {
  final shown = <String>[];
  @override
  Future<void> show({required int id, required String title, required String body, required bool urgent, String payload = ''}) async => shown.add(title);
}

/// Настоящие уведомления Android/iOS через flutter_local_notifications. Нажатие открывает приложение на нужном экране ([onTap] получает payload).
class DeviceSystemNotifier implements SystemNotifier {
  DeviceSystemNotifier({this.onTap});
  final void Function(String payload)? onTap;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload ?? ''),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notifications init: $e');
    }
  }

  @override
  Future<void> show({required int id, required String title, required String body, required bool urgent, String payload = ''}) async {
    if (!_ready) return;
    try {
      final android = AndroidNotificationDetails(
        urgent ? 'holescope_alerts' : 'holescope_info',
        urgent ? 'Предупреждения и вопросы' : 'Сообщения',
        importance: urgent ? Importance.high : Importance.defaultImportance,
        priority: urgent ? Priority.high : Priority.defaultPriority,
        playSound: urgent,
      );
      await _plugin.show(id: id, title: title, body: body, notificationDetails: NotificationDetails(android: android, iOS: DarwinNotificationDetails(presentSound: urgent)), payload: payload);
    } catch (e) {
      debugPrint('notification: $e');
    }
  }
}

/// Решает, что и как показать: записывает в центр уведомлений, а «пушем» (системным уведомлением) — только если тип включён,
/// не тихие часы (кроме срочного) и не исчерпан лимит в день. Остальное остаётся в центре без звука.
class NotificationHub {
  NotificationHub({required this.db, required this.settings, required this.system, DateTime Function()? now, this.appInForeground, this.onChange, this.onBanner}) : _now = now ?? DateTime.now;
  final LocalDb db;
  final AppSettings Function() settings;
  final SystemNotifier system;
  final DateTime Function() _now;
  final bool Function()? appInForeground;
  final VoidCallback? onChange;
  final void Function(String kind, String title, String body)? onBanner;
  int _seq = 0;

  bool _enabled(NoteKind k, AppSettings s) => switch (k) {
        NoteKind.pothole => s.notifPothole,
        NoteKind.question => s.notifQuestion,
        NoteKind.fixed => s.notifFixed,
        NoteKind.complaint => s.notifComplaint,
        NoteKind.weekly => s.notifWeekly,
        NoteKind.service => true,
      };

  /// Записать уведомление. [minGap] — не чаще одного такого вида за этот промежуток (чтобы центр не засорялся предупреждениями).
  /// Возвращает true, если показано системное уведомление.
  Future<bool> post(NoteKind kind, String title, {String body = '', String ref = '', bool urgent = false, Duration? minGap}) async {
    final s = settings();
    if (!_enabled(kind, s)) return false;
    final now = _now();
    if (minGap != null && db.notesSince(now.subtract(minGap).millisecondsSinceEpoch, kind: kind.name) > 0) return false;
    final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final pushedToday = db.notesSince(dayStart, kind: 'push');
    db.addNote(at: now.millisecondsSinceEpoch, kind: kind.name, title: title, body: body, ref: ref);
    onChange?.call();
    final quiet = s.inQuietHours(now) && !urgent;
    final overLimit = pushedToday >= s.maxPerDay && !urgent;
    final foreground = appInForeground?.call() ?? false;
    if (foreground && !quiet) onBanner?.call(kind.name, title, body); // приложение открыто — короткая подсказка сверху
    if (quiet || overLimit || foreground) return false; // в центре уже есть; звук и шторка — только если приложение не на экране
    db.addNote(at: now.millisecondsSinceEpoch, kind: 'push', title: kind.name, ref: ref); // счётчик отправленных пушей (скрытая запись)
    await system.show(id: ++_seq + 1000, title: title, body: body, urgent: urgent || kind == NoteKind.pothole || kind == NoteKind.question, payload: kind.name);
    return true;
  }
}

/// Итоги недели: по понедельникам (если включено) один раз кладём в центр уведомлений сводку по поездкам за 7 дней.
Future<bool> postWeeklyDigest(NotificationHub hub, LocalDb db, AppSettings s, DateTime now, {bool uz = false}) async {
  if (!s.notifWeekly || now.weekday != DateTime.monday) return false;
  final week = '${now.year}-${(now.difference(DateTime(now.year)).inDays ~/ 7)}';
  if (db.kvGet('weekly_posted') == week) return false;
  final since = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
  final trips = db.trips(limit: 200).where((t) => t.startedAt >= since).toList();
  db.kvSet('weekly_posted', week);
  if (trips.isEmpty) return false;
  final km = trips.fold<double>(0, (a, t) => a + t.distanceKm);
  final holes = trips.fold<int>(0, (a, t) => a + t.potholes);
  await hub.post(NoteKind.weekly, uz ? 'Hafta yakunlari tayyor' : 'Итоги недели готовы', body: uz ? '${km.toStringAsFixed(0)} km, $holes ta choʻqqi.' : '${km.toStringAsFixed(0)} км, $holes ям.');
  return true;
}

/// Приложение сейчас на экране?
bool appIsForeground() => WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

bool get platformSupportsNotifications => Platform.isAndroid || Platform.isIOS;
