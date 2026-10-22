import 'package:flutter/foundation.dart';

/// Конфигурация сборки. Адрес API задаётся при запуске: `--dart-define=API_BASE=https://api.example.com`.
/// По умолчанию — локальный Docker-бэкенд (порт 8010, см. backend/.env WEB_PORT); в эмуляторе Android хост = 10.0.2.2.
class AppConfig {
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: '');

  static String resolveApiBase() {
    if (apiBase.isNotEmpty) return apiBase;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8010';
    return 'http://127.0.0.1:8010';
  }

  /// Версия приложения (совпадает с pubspec.yaml: 2.2.0+23; проверяется тестом).
  static const appVersion = '2.2.0';
  static const appBuild = 23;

  /// Сборка для штатного монитора автомобиля (широкий экран, Android 9): `--dart-define=CAR_MONITOR=true`.
  static const carMonitor = bool.fromEnvironment('CAR_MONITOR');
}
