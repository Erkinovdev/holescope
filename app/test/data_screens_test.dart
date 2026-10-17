import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens_test.dart' show testOverrides;

/// Экраны показывают данные сервера (поддельный адаптер повторяет форматы backend/api) и корректно ведут себя без сети.
Future<void> open(WidgetTester t, String route, {bool offline = false, String lang = 'ru'}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'locale': lang, 'theme': 'dark'});
  final prefs = await SharedPreferences.getInstance();
  t.view.physicalSize = const Size(780, 1688);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(const SizedBox()); // сбросить прежнее приложение (иначе роутер остаётся прежним)
  await t.pumpWidget(ProviderScope(retry: (_, __) => null, overrides: testOverrides(prefs, offline: offline), child: HoleScopeApp(initialLocation: route)));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('рейтинг улиц показывает данные сервера', (t) async {
    await open(t, '/streets');
    expect(find.text('ул. Бабура'), findsOneWidget);
    expect(find.text('14,2'), findsOneWidget);
    expect(find.text('Кичик халка йули'), findsOneWidget);
    // вкладка «Район» → рейтинг районов
    await t.tap(find.text('Район'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Юнусабадский район'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
  });

  testWidgets('дашборд города: оценка и районы', (t) async {
    await open(t, '/city');
    expect(find.text('62'), findsOneWidget);
    expect(find.text('Сергелийский район'), findsOneWidget);
  });

  testWidgets('отчёт недели: 31 яма исправлена', (t) async {
    await open(t, '/weekly');
    expect(find.text('31 яма'), findsOneWidget);
    expect(find.textContaining('исправлена'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('47'), findsOneWidget);
  });

  testWidgets('карточка ямы: улица, район, подтверждения, действия', (t) async {
    await open(t, '/pothole/1');
    expect(find.text('ул. Навои'), findsOneWidget);
    expect(find.textContaining('Юнусабадский район'), findsOneWidget);
    expect(find.text('7 водителей'), findsOneWidget);
    expect(find.text('Яма на месте'), findsOneWidget);
    expect(find.text('Заделана'), findsOneWidget);
  });

  testWidgets('жалоба: черновик с сервера, отправка ведёт к цепочке статусов', (t) async {
    await open(t, '/complaint/1');
    expect(find.textContaining('обнаружена глубокая яма'), findsOneWidget);
    await t.tap(find.text('Отправить жалобу'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Нашли → Подали → Исправили'), findsOneWidget);
    expect(find.textContaining('48217'), findsOneWidget);
    expect(find.text('Исправили'), findsOneWidget);
  });

  testWidgets('живая карта: ближайшая яма, легенда, поиск', (t) async {
    await open(t, '/map');
    expect(find.text('ул. Навои'), findsOneWidget);                // карточка ближайшей ямы с улицей
    expect(find.text('A'), findsOneWidget);                        // легенда A–E
    await t.tap(find.text('Поиск улицы или района'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    await t.enterText(find.byType(TextField), 'баб');
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('ул. Бабура'), findsOneWidget);
    await t.tap(find.text('ул. Бабура'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('профиль: подтверждено с сервера и ник', (t) async {
    await open(t, '/profile');
    expect(find.text('342'), findsOneWidget);
  });

  testWidgets('без сети: понятное сообщение и кнопка «Повторить»', (t) async {
    await open(t, '/pothole/1', offline: true);
    expect(find.text('Нет связи с сервером'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    await open(t, '/streets', offline: true);
    expect(find.text('Нет связи с сервером'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('узбекский: заголовки экранов с данными', (t) async {
    await open(t, '/streets', lang: 'uz');
    expect(find.text('Eng yomon ko‘chalar'), findsOneWidget);
    expect(t.takeException(), isNull);
    await open(t, '/weekly', lang: 'uz');
    expect(find.text('31 ta chuqur'), findsOneWidget);
  });
}
