import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/event_guess.dart';
import 'package:holescope/algo/taxonomy_data.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/features/comfort.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/ahead_warner.dart';
import 'package:holescope/services/config.dart';
import 'package:holescope/services/device_auth.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/mark_service.dart';
import 'package:holescope/services/notify.dart';
import 'package:holescope/voice/event_ui.dart';
import 'package:holescope/voice/holi_controller.dart';
import 'package:holescope/voice/holi_voice.dart';
import 'package:holescope/voice/speech_engine.dart';

class _NoPlayer implements HoliPlayer {
  @override
  Future<bool> play(String asset) async => true;
  @override
  Future<void> stop() async {}
}

class _NoFallback implements HoliFallback {
  @override
  Future<void> speak(String text, String lang) async {}
  @override
  Future<void> stop() async {}
}

class _NoSession implements HoliSession {
  @override
  Future<void> begin() async {}
  @override
  Future<void> end() async {}
}

class _Speech implements SpeechEngine {
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
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> sendMarks(List<Map<String, dynamic>> marks) async => sent.addAll(marks);
}

class _Auth extends DeviceAuth {
  _Auth() : super(MemoryTokenStore());
  @override
  Future<String> ensureRegistered(ApiClient api, {String platform = '', String phoneModel = '', String lang = 'ru', String role = 'driver'}) async => 'tok';
}

Guess _guess(double score, {double speed = 40, double dur = 400}) => guessEvent(EventFeatures(score: score, speedKmh: speed, durMs: dur, peak: score), const GuessContext());

void main() {
  group('версия приложения', () {
    test('в коде и в pubspec одна и та же', () {
      final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
      expect(line.trim(), 'version: ${AppConfig.appVersion}+${AppConfig.appBuild}');
    });
  });

  group('ответы на вопрос: типы и глубина по силе удара', () {
    test('всегда яма, лежачий, люк и «не знаю»; рельсы/неровность — только если правдоподобны', () {
      final g = groupsFor(_guess(4.0));
      expect(g.first, EvGroup.pothole);
      expect(g.last, EvGroup.unknown);
      expect(g, containsAll([EvGroup.bump, EvGroup.manhole]));
    });

    test('слабый удар: нет «глубокой»; сильный: нет «лёгкой»; всегда минимум две', () {
      final weak = depthKeys(_guess(2.4));
      expect(weak, isNot(contains('pothole_deep')));
      expect(weak.length, greaterThanOrEqualTo(2));
      final strong = depthKeys(_guess(9.0, speed: 60));
      expect(strong, isNot(contains('pothole_light')));
      expect(strong.length, greaterThanOrEqualTo(2));
      expect(strong, contains('pothole_deep'));
    });

    test('resolveGroup: уточнение догадки, иначе значение по умолчанию', () {
      final g = _guess(4.0);
      expect(resolveGroup(EvGroup.manhole, g), anyOf('manhole', 'manhole_sunk', 'manhole_raised'));
      expect(resolveGroup(EvGroup.bump, g), anyOf('bump', 'bump_low', 'bump_high'));
      expect(taxItem(resolveGroup(EvGroup.rails, g)), isNotNull);
    });
  });

  group('окно «что это было?»', () {
    late HoliController c;
    late _Api api;
    final expired = <String>[];
    var window = const Duration(seconds: 20);

    HoliCandidate cand({double score = 6}) => HoliCandidate(
          at: DateTime.now(),
          lat: 41.33,
          lon: 69.23,
          score: score,
          features: EventFeatures(score: score, speedKmh: 40, durMs: 400, pair: 0.4, gyroPeak: 10, hfShare: 0.2, peak: score),
        );

    setUp(() {
      expired.clear();
      api = _Api();
      final marks = MarkService(db: LocalDb.memory(), api: api, auth: _Auth(), holdFor: const Duration(milliseconds: 20));
      final voice = HoliVoice(phrases: const {}, assets: const {}, player: _NoPlayer(), session: _NoSession(), fallback: _NoFallback(), lang: () => 'ru');
      c = HoliController(
        voice: voice,
        speech: _Speech(),
        marks: marks,
        fixAt: (t) => MarkFix(t, 41.33, 69.23, 0),
        lang: () => 'ru',
        speakEnabled: () => false,
        promptWindow: () => window,
        canExtend: () => true,
        onExpired: (cand, g) => expired.add(g.top),
      );
    });

    test('окно живёт заданное время; касание добавляет 5 с, но не больше 30 с от начала', () async {
      window = const Duration(seconds: 20);
      await c.askEvent(cand());
      final p0 = c.prompt!;
      expect(p0.deadline.difference(p0.startedAt), const Duration(seconds: 20));
      expect(c.touchPrompt(), isTrue);
      expect(c.prompt!.deadline.difference(p0.startedAt), const Duration(seconds: 25));
      expect(c.touchPrompt(), isTrue);
      expect(c.prompt!.deadline.difference(p0.startedAt), const Duration(seconds: 30));
      expect(c.touchPrompt(), isFalse, reason: 'больше 30 секунд не бывает');
      c.expirePrompt();
    });

    test('«Яма» открывает глубину; выбор глубины сохраняет отметку и закрывает окно «спасибо»', () async {
      window = const Duration(seconds: 20);
      await c.askEvent(cand());
      await c.pickGroup(EvGroup.pothole);
      expect(c.prompt!.depthStage, isTrue);
      expect(c.prompt!.answered, isFalse);
      final key = depthKeys(c.prompt!.guess).last;
      await c.selectOption(key);
      expect(c.prompt!.answered, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(api.sent.single['kind'], key);
      expect(expired, isEmpty);
    });

    test('«Не знаю» закрывает вопрос и ничего не отправляет в обучение', () async {
      await c.askEvent(cand());
      await c.pickGroup(EvGroup.unknown);
      expect(c.prompt!.chosen, 'unknown');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(api.sent, isEmpty);
    });

    test('не успели: вопрос уходит в очередь', () async {
      window = const Duration(milliseconds: 150);
      await c.askEvent(cand());
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.prompt, isNull);
      expect(expired.length, 1);
    });

    test('отложили крестиком: тоже в очередь; ответ из очереди сохраняет отметку по месту и времени удара', () async {
      window = const Duration(seconds: 20);
      await c.askEvent(cand());
      c.expirePrompt();
      expect(expired.length, 1);
      final q = PendingQuestion(id: 1, at: DateTime(2026, 10, 19, 12).millisecondsSinceEpoch, lat: 41.3, lon: 69.2, peak: 6, speedKmh: 40, guess: 'pothole_mid', wave: const []);
      c.answerQueued(q, 'pothole_deep');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final m = api.sent.single;
      expect(m['kind'], 'pothole_deep');
      expect(m['lat'], 41.3);
      c.answerQueued(q, 'unknown');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(api.sent.length, 1, reason: '«не знаю» ничего не отправляет');
    });
  });

  group('локальная база: уведомления и очередь', () {
    test('заметки: порядок, непрочитанные, скрытые счётчики пушей не видны', () {
      final db = LocalDb.memory();
      db.addNote(at: 1000, kind: 'pothole', title: 'Яма через 150 м');
      db.addNote(at: 2000, kind: 'push', title: 'pothole');
      db.addNote(at: 3000, kind: 'fixed', title: 'Яму заделали');
      expect(db.notes().map((n) => n.title), ['Яму заделали', 'Яма через 150 м']);
      expect(db.unreadNotes(), 2);
      db.readAllNotes();
      expect(db.unreadNotes(), 0);
      expect(db.notesSince(1500, kind: 'push'), 1);
    });

    test('очередь вопросов: не больше 12, фильтр по сроку, удаление, стирание личного', () {
      final db = LocalDb.memory();
      for (var i = 0; i < 15; i++) {
        db.addPending(at: 1000 + i, lat: 41, lon: 69, peak: 5, wave: const [0.1, 0.4]);
      }
      expect(db.pending().length, 12);
      expect(db.pending(notBeforeMs: 1010).length, 5);
      db.removePending(db.pending().first.id);
      expect(db.pending().length, 11);
      db.addTrip(startedAt: 1, endedAt: 2, distanceKm: 3, potholes: 1);
      db.addNote(at: 1, kind: 'fixed', title: 'x');
      db.wipeUserData();
      expect(db.pending(), isEmpty);
      expect(db.notes(), isEmpty);
      expect(db.trips(), isEmpty);
    });
  });

  group('центр уведомлений: правила показа', () {
    late LocalDb db;
    late NoopSystemNotifier sys;
    var s = const AppSettings();
    var now = DateTime(2026, 10, 19, 12);
    final banners = <String>[];
    var fg = false;
    NotificationHub hub() => NotificationHub(db: db, settings: () => s, system: sys, now: () => now, appInForeground: () => fg, onBanner: (k, t, b) => banners.add(t));

    setUp(() {
      db = LocalDb.memory();
      sys = NoopSystemNotifier();
      s = const AppSettings();
      now = DateTime(2026, 10, 19, 12);
      banners.clear();
      fg = false;
    });

    test('выключенный тип не пишется вообще', () async {
      s = const AppSettings(notifFixed: false);
      expect(await hub().post(NoteKind.fixed, 'Яму заделали'), isFalse);
      expect(db.notes(), isEmpty);
    });

    test('лимит в день: после N-го пуша остальное только в центр без шторки', () async {
      s = const AppSettings(maxPerDay: 2);
      final h = hub();
      expect(await h.post(NoteKind.fixed, 'a'), isTrue);
      expect(await h.post(NoteKind.fixed, 'b'), isTrue);
      expect(await h.post(NoteKind.fixed, 'c'), isFalse);
      expect(db.notes().length, 3);
      expect(sys.shown, ['a', 'b']);
    });

    test('срочное проходит сверх лимита и в тихие часы; обычное в тихие часы — только в центр', () async {
      s = const AppSettings(maxPerDay: 1);
      now = DateTime(2026, 10, 19, 23, 30);
      final h = hub();
      expect(await h.post(NoteKind.fixed, 'обычное'), isFalse);
      expect(await h.post(NoteKind.pothole, 'срочное', urgent: true), isTrue);
      expect(db.notes().length, 2);
    });

    test('минимальный интервал одного вида: предупреждения о ямах не засоряют центр', () async {
      final h = hub();
      await h.post(NoteKind.pothole, 'яма 1', minGap: const Duration(minutes: 5));
      await h.post(NoteKind.pothole, 'яма 2', minGap: const Duration(minutes: 5));
      expect(db.notes().length, 1);
      now = now.add(const Duration(minutes: 6));
      await h.post(NoteKind.pothole, 'яма 3', minGap: const Duration(minutes: 5));
      expect(db.notes().length, 2);
    });

    test('приложение открыто: короткая подсказка сверху, шторка не нужна', () async {
      fg = true;
      expect(await hub().post(NoteKind.complaint, 'Статус жалобы'), isFalse);
      expect(banners, ['Статус жалобы']);
      expect(sys.shown, isEmpty);
    });

    test('тихие часы: через полночь и без неё', () {
      const a = AppSettings(quietFromH: 23, quietToH: 7);
      expect(a.inQuietHours(DateTime(2026, 1, 1, 23, 10)), isTrue);
      expect(a.inQuietHours(DateTime(2026, 1, 1, 3)), isTrue);
      expect(a.inQuietHours(DateTime(2026, 1, 1, 12)), isFalse);
      const b = AppSettings(quietFromH: 13, quietToH: 15);
      expect(b.inQuietHours(DateTime(2026, 1, 1, 14)), isTrue);
      expect(b.inQuietHours(DateTime(2026, 1, 1, 16)), isFalse);
      expect(const AppSettings(quietOn: false).inQuietHours(DateTime(2026, 1, 1, 23, 10)), isFalse);
    });

    test('итоги недели: по понедельникам, один раз, только если включено и есть поездки', () async {
      final now0 = DateTime(2026, 10, 19, 9); // понедельник
      db.addTrip(startedAt: now0.subtract(const Duration(days: 2)).millisecondsSinceEpoch, endedAt: now0.millisecondsSinceEpoch, distanceKm: 20, potholes: 5);
      s = const AppSettings(notifWeekly: true);
      final h = hub();
      expect(await postWeeklyDigest(h, db, const AppSettings(notifWeekly: false), now0), isFalse);
      expect(await postWeeklyDigest(h, db, const AppSettings(notifWeekly: true), now0.add(const Duration(days: 1))), isFalse, reason: 'не понедельник');
      expect(await postWeeklyDigest(h, db, const AppSettings(notifWeekly: true), now0), isTrue);
      expect(db.notes().single.body, contains('20 км'));
      expect(await postWeeklyDigest(h, db, const AppSettings(notifWeekly: true), now0), isFalse, reason: 'второй раз за неделю не нужен');
    });
  });

  group('предупреждения: настройки глубины и скорости', () {
    test('AheadConfig.allows и дальность по скорости', () {
      const cfg = AheadConfig(allowLight: false, allowMid: true, allowDeep: true);
      expect(cfg.allows('light'), isFalse);
      expect(cfg.allows('mid'), isTrue);
      expect(cfg.allows('danger'), isTrue);
      expect(cfg.allows(null), isTrue);
    });

    test('чем быстрее едем, тем раньше предупреждаем (но не дальше 350 м)', () {
      final db = LocalDb.memory();
      // яма в 240 м прямо по курсу (север)
      db.replaceClusters([CachedCluster(id: 1, lat: 41.3 + 240 / 111320, lon: 69.2, heading: null, type: 'pothole', level: 'deep', status: 'confirmed', confidence: 1, safeSpeed: 30)], now: 1);
      AheadWarner mk(bool aware) => AheadWarner(db, null, config: () => AheadConfig(warnDistanceM: 150, speedAware: aware));
      expect(mk(true).check(41.3, 69.2, 0, speedKmh: 100), isNull, reason: '100 км/ч → 5 с пути = 139 м, остаётся 150 м');
      expect(mk(false).check(41.3, 69.2, 0, speedKmh: 180), isNull, reason: 'без учёта скорости — всегда 150 м');
      expect(mk(true).check(41.3, 69.2, 0, speedKmh: 180)?.id, 1, reason: '180 км/ч → 250 м');
    });
  });

  group('комфорт', () {
    test('комфорт поездки по классам ровности', () {
      expect(comfortScore({'A': 10}), 100);
      expect(comfortScore({'E': 10}), 0);
      expect(comfortScore({'A': 5, 'C': 5}), 80);
      expect(comfortScore({}), isNull);
    });
  });
}
