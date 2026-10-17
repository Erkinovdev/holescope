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

  static const appVersion = '0.2.0';
}
