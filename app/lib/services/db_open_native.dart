import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// Телефон и тесты: настоящий sqlite3 (нативная библиотека).
Future<void> initDbPlatform() async {}

CommonDatabase openDbFile(String path) => sqlite3.open(path);
CommonDatabase openDbMemory() => sqlite3.openInMemory();
