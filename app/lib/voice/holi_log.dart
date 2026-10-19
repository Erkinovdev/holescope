import 'package:flutter/foundation.dart';

/// Короткий журнал работы голоса (последние записи): показывается на экране «Проверка голоса», чтобы было видно, где сбой.
class HoliLog {
  HoliLog._();
  static final _lines = <String>[];
  static final version = ValueNotifier<int>(0);

  static List<String> get lines => List.unmodifiable(_lines);

  static void add(String msg) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $msg');
    if (_lines.length > 300) _lines.removeRange(0, _lines.length - 300);
    version.value++;
    if (kDebugMode) debugPrint('[holi] $msg');
  }

  static void clear() {
    _lines.clear();
    version.value++;
  }
}
