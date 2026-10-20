import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:holescope/app.dart';
import 'package:holescope/core/nav.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/services/algo_params_sync.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/config.dart';
import 'package:holescope/services/demo_seed.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/notify.dart';
import 'package:holescope/services/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.carMonitor && !kIsWeb) {
    // штатный монитор: только горизонтально, без системных панелей
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  final prefs = await SharedPreferences.getInstance();
  final notifier = DeviceSystemNotifier(onTap: (p) => openRoute(p == 'question' ? '/queue' : '/notifications'));
  if (!kIsWeb) await notifier.init(); // в браузере системных уведомлений нет
  await initLocalDb(); // в вебе загружает sqlite3.wasm
  final dir = kIsWeb ? null : await getApplicationSupportDirectory();
  final db = LocalDb.open(dir == null ? 'holescope.db' : p.join(dir.path, 'holescope.db'));
  if (kIsWeb && Uri.base.queryParameters['seed'] == '1') seedDemoTrip(db); // проверка экранов итогов в браузере
  AlgoParamsSync.loadCached(prefs);
  AlgoParamsSync.refresh(ApiClient(AppConfig.resolveApiBase()), prefs); // в фоне: параметры алгоритма с сервера
  runApp(ProviderScope(
    retry: (_, __) => null, // ошибки сети показываем сразу («нет связи» + кнопка «Повторить»), без скрытых повторов
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      dbProvider.overrideWithValue(db),
      supportDirProvider.overrideWithValue(dir?.path),
      systemNotifierProvider.overrideWithValue(notifier),
    ],
    child: const HoleScopeApp(),
  ));
}
