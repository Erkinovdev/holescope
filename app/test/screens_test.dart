import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/app.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/services/announcer.dart';
import 'package:holescope/services/device_auth.dart';
import 'package:holescope/services/engine.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/permissions.dart';
import 'package:holescope/services/providers.dart';
import 'package:holescope/services/sensor_source.dart';
import 'support/fake_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

const routes = [
  '/map', '/drive', '/streets', '/profile', '/my-map', '/pothole/1', '/warning', '/settings', '/complaint/1', '/complaint/status/1',
  '/route', '/notifications', '/city', '/challenges', '/weekly', '/vehicle', '/question', '/trip-summary', '/mount', '/role',
  '/permissions', '/onboarding/role', '/onboarding/mount', '/trips', '/voice-check',
];

Future<void> _loadInter() async {
  final bytes = await File('assets/fonts/Inter.ttf').readAsBytes();
  final loader = FontLoader('Inter')..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

List<Override> testOverrides(SharedPreferences prefs, {bool offline = false}) {
  final api = fakeApi(fail: offline);
  final db = LocalDb.memory();
  // одна поездка в истории, чтобы экраны итогов/истории показывали данные
  db.addTrip(startedAt: DateTime(2026, 10, 17, 12).millisecondsSinceEpoch, endedAt: DateTime(2026, 10, 17, 12, 24).millisecondsSinceEpoch, distanceKm: 11.7, potholes: 27, summary: {'segments': {'A': 76, 'B': 106, 'C': 38, 'D': 8, 'E': 3}});
  return [
    prefsProvider.overrideWithValue(prefs),
    dbProvider.overrideWithValue(db),
    engineProvider.overrideWith((ref) => RecorderEngine(
          db: db,
          source: FakeSensorSource(),
          api: api,
          announcer: SilentAnnouncer(),
          auth: DeviceAuth(MemoryTokenStore()),
          settings: () => ref.read(settingsProvider),
        )),
    permissionServiceProvider.overrideWithValue(FakePermissionService(const PermState())),
    apiProvider.overrideWithValue(api),
  ];
}

Future<void> _pump(WidgetTester t, String route, {required String lang, required ThemeMode mode, Size size = const Size(390, 844)}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'theme': mode.name, 'locale': lang});
  final prefs = await SharedPreferences.getInstance();
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(ProviderScope(retry: (_, __) => null, overrides: testOverrides(prefs), child: HoleScopeApp(initialLocation: route)));
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(_loadInter);

  group('экраны рендерятся без ошибок и overflow', () {
    for (final lang in ['ru', 'uz']) {
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        for (final r in routes) {
          testWidgets('$r · $lang · ${mode.name}', (t) async {
            await _pump(t, r, lang: lang, mode: mode);
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });

  testWidgets('малый экран 320×568 без overflow', (t) async {
    for (final r in routes) {
      await _pump(t, r, lang: 'ru', mode: ThemeMode.dark, size: const Size(320, 568));
      expect(t.takeException(), isNull, reason: r);
    }
  });

  testWidgets('splash доходит до конца и уходит в онбординг/карту', (t) async {
    await _pump(t, '/splash', lang: 'ru', mode: ThemeMode.dark);
    await t.pump(const Duration(milliseconds: 3200));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(find.text('Карта'), findsWidgets); // onboarded=true → /map с вкладками
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200)); // дождаться ответов поддельного сервера (иначе висят таймеры Dio)
    }
  });

  testWidgets('splash в режиме reduce motion короче', (t) async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'reduceMotion': true});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(ProviderScope(retry: (_, __) => null, overrides: testOverrides(prefs), child: const HoleScopeApp()));
    await t.pump(const Duration(milliseconds: 900));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Карта'), findsWidgets);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  });

  testWidgets('смена языка в настройках применяется', (t) async {
    await _pump(t, '/settings', lang: 'ru', mode: ThemeMode.dark);
    expect(find.text('Настройки'), findsWidgets);
    final c = t.element(find.byType(Scaffold).first);
    ProviderScope.containerOf(c).read(settingsProvider.notifier).update((s) => s.copyWith(locale: const Locale('uz')));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Sozlamalar'), findsWidgets);
  });
}
