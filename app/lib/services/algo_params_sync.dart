import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:holescope/algo/params.dart';
import 'api_client.dart';

/// Параметры алгоритма с сервера: берём сохранённые при запуске, затем обновляем в фоне. Любая ошибка — остаёмся на текущих.
class AlgoParamsSync {
  static const _key = 'algo_params_json';

  /// Подставляет последние сохранённые параметры (без сети).
  static void loadCached(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_key);
      if (raw != null) AlgoParams.current = AlgoParams.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  /// Скачивает параметры активной версии, применяет и сохраняет. Возвращает true, если обновилось.
  static Future<bool> refresh(ApiClient api, SharedPreferences prefs) async {
    try {
      final data = await api.algoParams();
      final p = data['params'];
      if (p is! Map<String, dynamic>) return false;
      AlgoParams.current = AlgoParams.fromJson(p);
      await prefs.setString(_key, jsonEncode(p));
      return true;
    } catch (_) {
      return false;
    }
  }
}
