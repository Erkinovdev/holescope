import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/event_guess.dart';
import 'package:holescope/app.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/device_auth.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/mark_service.dart';
import 'package:holescope/services/providers.dart';
import 'package:holescope/voice/holi_controller.dart';
import 'package:holescope/voice/event_ui.dart';
import 'package:holescope/voice/holi_voice.dart';
import 'package:holescope/voice/speech_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_test.dart' show testOverrides;

class _P implements HoliPlayer {
  @override
  Future<bool> play(String asset) async => true;
  @override
  Future<void> stop() async {}
}

class _F implements HoliFallback {
  @override
  Future<void> speak(String text, String lang) async {}
  @override
  Future<void> stop() async {}
}

class _S implements HoliSession {
  @override
  Future<void> begin() async {}
  @override
  Future<void> end() async {}
}

class _Sp implements SpeechEngine {
  @override
  Future<SpeechOutcome?> prepare() async => null;
  @override
  Future<SpeechOutcome> listenOnce({required String lang, Duration maxDuration = const Duration(seconds: 8), Duration silenceTimeout = const Duration(seconds: 2), Duration noSpeechTimeout = const Duration(seconds: 5), void Function(String)? onPartial}) async => const SpeechOutcome(text: '');
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _Api extends ApiClient {
  _Api() : super('http://localhost');
  @override
  Future<void> sendMarks(List<Map<String, dynamic>> marks) async {}
}

class _Au extends DeviceAuth {
  _Au() : super(MemoryTokenStore());
  @override
  Future<String> ensureRegistered(ApiClient api, {String platform = '', String phoneModel = '', String lang = 'ru', String role = 'driver'}) async => 'tok';
}

void main() {
  setUpAll(() async {
    final bytes = await File('assets/fonts/Inter.ttf').readAsBytes();
    final loader = FontLoader('Inter')..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  Future<HoliController> pumpWith(WidgetTester t, Size size, {String lang = 'ru', String route = '/map', Duration window = const Duration(seconds: 20)}) async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'theme': 'dark', 'locale': lang});
    final prefs = await SharedPreferences.getInstance();
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.resetPhysicalSize);
    final marks = MarkService(db: LocalDb.memory(), api: _Api(), auth: _Au(), holdFor: const Duration(milliseconds: 20));
    final ctrl = HoliController(
      voice: HoliVoice(phrases: const {}, assets: const {}, player: _P(), session: _S(), fallback: _F(), lang: () => lang),
      speech: _Sp(),
      marks: marks,
      fixAt: (t) => MarkFix(t, 41.3, 69.2, 0),
      lang: () => lang,
      speakEnabled: () => false,
      promptWindow: () => window,
      canExtend: () => true,
    );
    addTearDown(ctrl.dispose);
    await t.pumpWidget(ProviderScope(
      retry: (_, __) => null,
      overrides: [...testOverrides(prefs), holiControllerProvider.overrideWith((ref) async => ctrl)],
      child: HoleScopeApp(initialLocation: route),
    ));
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 200));
    return ctrl;
  }

  HoliCandidate cand() => HoliCandidate(at: DateTime.now(), lat: 41.3, lon: 69.2, score: 6, features: const EventFeatures(score: 6, speedKmh: 42, durMs: 400, pair: 0.4, gyroPeak: 10, hfShare: 0.2, peak: 6.2));

  for (final size in const [Size(390, 844), Size(320, 568), Size(1280, 720), Size(1920, 720)]) {
    testWidgets('окно «что это было?» ${size.width.toInt()}×${size.height.toInt()}: сетка → глубина → принято', (t) async {
      final c = await pumpWith(t, size);
      await c.askEvent(cand());
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Что это было?'), findsOneWidget);
      expect(find.text('Яма'), findsWidgets);
      expect(find.text('Не знаю'), findsWidgets);
      expect(t.takeException(), isNull);
      await c.pickGroup(EvGroup.pothole);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('ГЛУБИНА'), findsOneWidget);
      expect(t.takeException(), isNull);
      await c.selectOption('pothole_mid');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Принято, спасибо!'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 3));
      expect(find.text('Принято, спасибо!'), findsNothing);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    });
  }

  testWidgets('последние секунды: две большие кнопки «Яма» / «Не знаю» и текст про очередь; узбекский', (t) async {
    final c = await pumpWith(t, const Size(390, 844), lang: 'uz', window: const Duration(milliseconds: 2500));
    await c.askEvent(cand());
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('navbatga'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 3));
    expect(c.prompt, isNull, reason: 'окно исчезло само');
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  });
}
