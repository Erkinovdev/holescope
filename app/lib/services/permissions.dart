import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermState {
  const PermState({this.motion = false, this.location = false, this.always = false, this.notifications = false, this.permanentlyDenied = false});
  final bool motion, location, always, notifications, permanentlyDenied;

  /// Минимум для записи: геолокация «при использовании». «Всегда» нужна для надёжной фоновой записи.
  bool get canRecord => location;
}

abstract class PermissionService {
  Future<PermState> current();
  Future<PermState> requestAll();
  Future<bool> openSettings();
}

class DevicePermissionService implements PermissionService {
  Permission get _motion => Platform.isIOS ? Permission.sensors : Permission.activityRecognition;

  @override
  Future<PermState> current() async => PermState(
        motion: await _motion.isGranted,
        location: await Permission.locationWhenInUse.isGranted || await Permission.locationAlways.isGranted,
        always: await Permission.locationAlways.isGranted,
        notifications: await Permission.notification.isGranted,
      );

  /// Последовательно: движение → геолокация (при использовании) → «всегда» → уведомления.
  /// Системные диалоги нельзя показывать подряд за один шаг на Android 11+, поэтому «всегда» — отдельным запросом.
  @override
  Future<PermState> requestAll() async {
    final m = await _motion.request();
    final w = await Permission.locationWhenInUse.request();
    var always = await Permission.locationAlways.status;
    if (w.isGranted && !always.isGranted) always = await Permission.locationAlways.request();
    final n = await Permission.notification.request();
    return PermState(
      motion: m.isGranted,
      location: w.isGranted || always.isGranted,
      always: always.isGranted,
      notifications: n.isGranted,
      permanentlyDenied: w.isPermanentlyDenied || always.isPermanentlyDenied,
    );
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}

/// Для тестов.
class FakePermissionService implements PermissionService {
  FakePermissionService(this.state);
  PermState state;
  @override
  Future<PermState> current() async => state;
  @override
  Future<PermState> requestAll() async => state;
  @override
  Future<bool> openSettings() async => true;
}
