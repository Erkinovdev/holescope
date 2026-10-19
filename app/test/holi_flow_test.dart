import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/services/ahead_warner.dart';
import 'package:holescope/services/announcer.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/device_auth.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/mark_service.dart';
import 'package:holescope/voice/holi_controller.dart';
import 'package:holescope/voice/holi_phrase.dart';
import 'package:holescope/voice/holi_voice.dart';
import 'package:holescope/voice/speech_engine.dart';

class FakePlayer implements HoliPlayer {
  final played = <String>[];
  final failFor = <String>{};
  int overlap = 0, maxOverlap = 0;
  @override
  Future<bool> play(String asset) async {
    played.add(asset);
    if (failFor.contains(asset)) return false;
    overlap++;
    if (overlap > maxOverlap) maxOverlap = overlap;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    overlap--;
    return true;
  }

  @override
  Future<void> stop() async {}
}

class FakeFallback implements HoliFallback {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, String lang) async => spoken.add('$lang:$text');
  @override
  Future<void> stop() async {}
}

class FakeSession implements HoliSession {
  int begins = 0, ends = 0;
  @override
  Future<void> begin() async => begins++;
  @override
  Future<void> end() async => ends++;
}

/// Подставной микрофон: на каждое прослушивание отдаёт следующий заготовленный ответ (пусто = тишина). [prepareFail] — как будто нет разрешения.
class FakeSpeech implements SpeechEngine {
  FakeSpeech(this.answers, {this.prepareFail});
  final List<String> answers;
  final SpeechOutcome? prepareFail;
  int listens = 0, stops = 0;
  @override
  Future<SpeechOutcome?> prepare() async => prepareFail;
  @override
  Future<SpeechOutcome> listenOnce({required String lang, Duration maxDuration = const Duration(seconds: 25), Duration silenceTimeout = const Duration(seconds: 2), Duration noSpeechTimeout = const Duration(seconds: 10), void Function(String text)? onPartial}) async {
    listens++;
    final a = answers.isEmpty ? '' : answers.removeAt(0);
    if (a.isNotEmpty) onPartial?.call(a);
    return SpeechOutcome(text: a, engine: 'fake', error: a.isEmpty ? SpeechErrorKind.noSpeech : SpeechErrorKind.none);
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> cancel() async {}
}

class _FailingSpeech extends FakeSpeech {
  _FailingSpeech(this.fail) : super([]);
  final SpeechOutcome fail;
  @override
  Future<SpeechOutcome> listenOnce({required String lang, Duration maxDuration = const Duration(seconds: 25), Duration silenceTimeout = const Duration(seconds: 2), Duration noSpeechTimeout = const Duration(seconds: 10), void Function(String text)? onPartial}) async => fail;
}

/// Слушает, пока не вызовут stop().
class _BlockingSpeech extends FakeSpeech {
  _BlockingSpeech() : super([]);
  Completer<void>? _c;
  @override
  Future<SpeechOutcome> listenOnce({required String lang, Duration maxDuration = const Duration(seconds: 25), Duration silenceTimeout = const Duration(seconds: 2), Duration noSpeechTimeout = const Duration(seconds: 10), void Function(String text)? onPartial}) async {
    _c = Completer<void>();
    onPartial?.call('яма');
    await _c!.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    return const SpeechOutcome(text: 'яма', engine: 'fake');
  }

  @override
  Future<void> stop() async {
    stops++;
    if (_c != null && !_c!.isCompleted) _c!.complete();
  }
}

class FakeApi extends ApiClient {
  FakeApi() : super('http://localhost');
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> sendMarks(List<Map<String, dynamic>> marks) async => sent.addAll(marks);
}

class FakeAuth extends DeviceAuth {
  FakeAuth() : super(MemoryTokenStore());
  @override
  Future<String> ensureRegistered(ApiClient api, {String platform = '', String phoneModel = '', String lang = 'ru', String role = 'driver'}) async => 'tok';
}

const _keys = [
  'listening', 'wake_yes', 'wake_listen', 'mark_pothole', 'mark_deep', 'mark_bump', 'mark_manhole', 'mark_cancel', 'mark_cancel_none', 'thanks', 'ask_confirm',
  'confirm_yes', 'confirm_no', 'no_answer', 'ahead_deep', 'ahead_bump', 'repeat', 'unknown', 'trip_done', 'ahead_pothole_100', 'ahead_pothole_150',
  'mark_pothole_deep', 'mark_manhole_sunk', 'rate_road_d', 'help', 'ok_end', 'err_mic', 'err_speech', 'err_net', 'mark_not_pothole',
];

Map<String, HoliEntry> _phrases() => {for (final k in _keys) k: HoliEntry(key: k, ru: 'ru $k', uz: 'uz $k', file: k)};
String _ru(String k) => 'assets/holi/audio/${k}_ru.mp3';

void main() {
  late FakePlayer player;
  late FakeFallback fb;
  late FakeSession session;
  late String lang;
  late HoliVoice voice;

  setUp(() {
    player = FakePlayer();
    fb = FakeFallback();
    session = FakeSession();
    lang = 'ru';
    voice = HoliVoice(phrases: _phrases(), assets: {for (final k in _keys) _ru(k)}, player: player, session: session, fallback: fb, lang: () => lang);
  });

  group('HoliVoice', () {
    test('фразы идут по очереди без наложения, музыка приглушается один раз на серию', () async {
      voice.play(HoliPhrase.markPothole);
      voice.play(HoliPhrase.thanks);
      await voice.idle;
      expect(player.played, [_ru('mark_pothole'), _ru('thanks')]);
      expect(player.maxOverlap, 1);
      expect(session.begins, 1);
      expect(session.ends, 1);
    });

    test('подряд одинаковая фраза не дублируется', () async {
      voice.play(HoliPhrase.repeat);
      voice.play(HoliPhrase.repeat);
      await voice.idle;
      expect(player.played.length, 1);
    });

    test('язык берётся из настроек: uz без файла → запасной голос с узбекским текстом', () async {
      lang = 'uz';
      await voice.play(HoliPhrase.thanks);
      expect(player.played, isEmpty);
      expect(fb.spoken, ['uz:uz thanks']);
    });

    test('файл не проигрался → запасной голос', () async {
      player.failFor.add(_ru('unknown'));
      await voice.play(HoliPhrase.unknown);
      expect(fb.spoken, ['ru:ru unknown']);
    });

    test('длинная очередь обрезается: устаревшие предупреждения не копятся', () async {
      for (final p in [HoliPhrase.markPothole, HoliPhrase.markDeep, HoliPhrase.markBump, HoliPhrase.markManhole, HoliPhrase.markCancel]) {
        voice.play(p);
      }
      await voice.idle;
      expect(player.played.length, lessThanOrEqualTo(4));
    });

    test('в диалоге аудио-сессия не отпускается между фразами (hold/release)', () async {
      voice.hold();
      await voice.play(HoliPhrase.wakeListen);
      expect(session.ends, 0, reason: 'сессия держится, пока идёт диалог');
      await voice.play(HoliPhrase.thanks);
      expect(session.begins, 1);
      voice.release();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(session.ends, 1);
    });

    test('hasKey знает только записанные фразы', () {
      expect(voice.hasKey('mark_pothole_deep'), isTrue);
      expect(voice.hasKey('mark_nonexistent'), isFalse);
    });

    test('неизвестный ключ молча пропускается', () async {
      await voice.playKey('no_such_key');
      expect(player.played, isEmpty);
    });
  });

  group('HoliAnnouncer', () {
    AheadItem item({String type = 'pothole', String? level = 'mid', int d = 120}) => AheadItem(id: 1, distanceM: d, side: 'center', level: level, safeSpeed: null, type: type, lat: 0, lon: 0);

    test('фраза подбирается по типу и тяжести', () {
      expect(HoliAnnouncer.phraseFor(item())!.phrase, HoliPhrase.aheadPothole);
      expect(HoliAnnouncer.phraseFor(item())!.distanceM, 120);
      expect(HoliAnnouncer.phraseFor(item(level: 'deep'))!.phrase, HoliPhrase.aheadDeep);
      expect(HoliAnnouncer.phraseFor(item(type: 'bump'))!.phrase, HoliPhrase.aheadBump);
      expect(HoliAnnouncer.phraseFor(item(type: 'manhole')), isNull);
    });

    test('не чаще раза в 10 секунд и только ниже порога скорости', () async {
      var t = DateTime(2026, 1, 1, 12);
      final a = HoliAnnouncer(Future.value(voice), now: () => t, maxSpeedKmh: 100);
      await a.warn(item(), lang: 'ru', speedKmh: 50, voice: true, beep: false);
      t = t.add(const Duration(seconds: 5));
      await a.warn(item(d: 100), lang: 'ru', speedKmh: 50, voice: true, beep: false);
      expect(player.played.length, 1, reason: 'второе предупреждение через 5 с подавлено');
      t = t.add(const Duration(seconds: 6));
      await a.warn(item(), lang: 'ru', speedKmh: 130, voice: true, beep: false);
      expect(player.played.length, 1, reason: 'на 130 км/ч голос молчит');
      await a.warn(item(d: 140), lang: 'ru', speedKmh: 60, voice: true, beep: false);
      expect(player.played, [_ru('ahead_pothole_100'), _ru('ahead_pothole_150')]);
    });

    test('голос выключен в настройках — молчит', () async {
      final a = HoliAnnouncer(Future.value(voice));
      await a.warn(item(), lang: 'ru', speedKmh: 40, voice: false, beep: false);
      expect(player.played, isEmpty);
    });
  });

  group('HoliController', () {
    late FakeApi api;
    late MarkService marks;
    late DateTime now;
    final fix = MarkFix(DateTime(2026, 1, 1, 12), 41.3270, 69.2284, 90);

    HoliController make(List<String> answers, {bool gps = true}) {
      api = FakeApi();
      marks = MarkService(db: LocalDb.memory(), api: api, auth: FakeAuth(), holdFor: const Duration(milliseconds: 30), now: () => now);
      return HoliController(voice: voice, speech: FakeSpeech(answers), marks: marks, fixAt: (t) => gps ? fix : null, lang: () => lang, now: () => now);
    }

    setUp(() => now = DateTime(2026, 1, 1, 12, 0, 5));

    test('кнопка → «яма» → отметка и ответ «Отметила яму»', () async {
      final c = make(['яма']);
      await c.activate();
      expect(player.played, [_ru('wake_listen'), _ru('mark_pothole')]);
      expect(marks.pending, 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.single['kind'], 'pothole');
      expect(api.sent.single['lat'], 41.3270);
    });

    test('«Привет, Холи» → «Да?»; «глубокая яма» → отметка deep', () async {
      final c = make(['глубокая яма']);
      await c.activate(byWake: true);
      expect(player.played.first, _ru('wake_yes'));
      expect(player.played.last, _ru('mark_pothole_deep'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.single['kind'], 'pothole_deep');
    });

    test('«отмена» убирает последнюю отметку до отправки', () async {
      final c = make(['люк', '', 'отмена', '']);
      await c.activate();
      await c.activate();
      expect(player.played.last, _ru('mark_cancel'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent, isEmpty);
    });

    test('«отмена» без отметок — «Отменять нечего»', () async {
      final c = make(['отмена']);
      await c.activate();
      expect(player.played.last, _ru('mark_cancel_none'));
    });

    test('тишина: переспрашивает один раз, потом «не услышала»', () async {
      final c = make(['', '']);
      await c.activate();
      expect(player.played, [_ru('wake_listen'), _ru('repeat'), _ru('no_answer')]);
      expect(marks.pending, 0);
    });

    test('непонятная речь: «не поняла», потом снова слушает', () async {
      final c = make(['какая сегодня погода', 'люк']);
      await c.activate();
      expect(player.played, contains(_ru('unknown')));
      expect(player.played.last, _ru('mark_manhole'));
    });

    test('нет GPS — ничего не отмечаем', () async {
      final c = make(['яма'], gps: false);
      await c.activate();
      expect(marks.pending, 0);
    });

    test('вопрос после кандидата: «да» → отметка ямы в точке события', () async {
      final c = make(['да']);
      await c.askConfirm(HoliCandidate(at: DateTime(2026, 1, 1, 12), lat: 41.33, lon: 69.23, score: 7));
      expect(player.played, [_ru('ask_confirm'), _ru('confirm_yes')]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.single['kind'], 'pothole');
      expect(api.sent.single['lat'], 41.33);
    });

    test('вопрос после кандидата: «нет» → отметка «не яма»', () async {
      final c = make(['нет']);
      await c.askConfirm(HoliCandidate(at: DateTime(2026, 1, 1, 12), lat: 41.33, lon: 69.23));
      expect(player.played.last, _ru('confirm_no'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.single['kind'], 'not_pothole');
    });

    test('вопрос: тишина → «не услышала», отметок нет', () async {
      final c = make(['']);
      await c.askConfirm(HoliCandidate(at: DateTime(2026, 1, 1, 12), lat: 41.33, lon: 69.23));
      expect(player.played.last, _ru('no_answer'));
      expect(marks.pending, 0);
    });

    test('вопросы не чаще раза в минуту и не больше трёх за поездку', () async {
      final c = make(['да', 'да', 'да', 'да', 'да']);
      final cand = HoliCandidate(at: DateTime(2026, 1, 1, 12), lat: 41.33, lon: 69.23);
      await c.askConfirm(cand);
      expect(c.canAsk(), isFalse, reason: 'прошло 0 секунд');
      now = now.add(const Duration(seconds: 61));
      expect(c.canAsk(), isTrue);
      await c.askConfirm(cand);
      now = now.add(const Duration(seconds: 61));
      await c.askConfirm(cand);
      now = now.add(const Duration(seconds: 61));
      expect(c.canAsk(), isFalse, reason: 'лимит 3 за поездку');
      c.resetTrip();
      expect(c.canAsk(), isTrue);
    });

    test('несколько команд подряд в одном диалоге, потом тишина — диалог закрывается сам', () async {
      final c = make(['яма', 'просевший люк', '']);
      await c.activate();
      expect(player.played, [_ru('wake_listen'), _ru('mark_pothole'), _ru('mark_manhole_sunk')]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.map((e) => e['kind']), ['pothole', 'manhole_sunk']);
      expect(c.busy, isFalse);
    });

    test('оценка дороги: «дорога плохая» → отметка road_d', () async {
      final c = make(['дорога плохая']);
      await c.activate();
      expect(player.played.last, _ru('rate_road_d'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.single['kind'], 'road_d');
    });

    test('«это не яма» → отметка not_pothole', () async {
      final c = make(['это не яма']);
      await c.activate();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.single['kind'], 'not_pothole');
    });

    test('«спасибо» заканчивает диалог', () async {
      final c = make(['спасибо', 'яма']);
      await c.activate();
      expect(player.played.last, _ru('ok_end'));
      expect(marks.pending, 0);
    });

    test('помощь: Холи перечисляет команды', () async {
      final c = make(['что ты умеешь']);
      await c.activate();
      expect(player.played, contains(_ru('help')));
    });

    test('нет разрешения на микрофон: причина на экране и голосом, не молча', () async {
      api = FakeApi();
      marks = MarkService(db: LocalDb.memory(), api: api, auth: FakeAuth(), now: () => now);
      final c = HoliController(
        voice: voice,
        speech: FakeSpeech([], prepareFail: const SpeechOutcome(error: SpeechErrorKind.micBlocked, engine: 'device', detail: 'заблокирован')),
        marks: marks,
        fixAt: (t) => fix,
        lang: () => lang,
        now: () => now,
      );
      await c.activate();
      expect(player.played, [_ru('err_mic')]);
      expect(c.ui.value.error, SpeechErrorKind.micBlocked);
      c.clearError();
      expect(c.ui.value.error, isNull);
    });

    test('сбой сети при распознавании — голос и причина', () async {
      final sp = _FailingSpeech(const SpeechOutcome(error: SpeechErrorKind.network, engine: 'cloud', detail: 'нет сети'));
      final c = HoliController(voice: voice, speech: sp, marks: MarkService(db: LocalDb.memory(), api: FakeApi(), auth: FakeAuth()), fixAt: (t) => fix, lang: () => lang, now: () => now);
      await c.activate();
      expect(player.played.last, _ru('err_net'));
      expect(c.ui.value.error, SpeechErrorKind.network);
    });

    test('кнопка во время прослушивания заканчивает фразу, во время речи — перебивает', () async {
      final sp = _BlockingSpeech();
      final c = HoliController(voice: voice, speech: sp, marks: MarkService(db: LocalDb.memory(), api: FakeApi(), auth: FakeAuth()), fixAt: (t) => fix, lang: () => lang, now: () => now);
      final run = c.activate();
      for (var i = 0; i < 100 && c.ui.value.status != HoliStatus.listening; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.ui.value.status, HoliStatus.listening);
      await c.onButton();
      expect(sp.stops, greaterThan(0));
      await run;
    });

    test('вызов по кнопке, когда занято: не запускает второй диалог', () async {
      final c = make(['яма', '']);
      final a = c.activate();
      await c.activate();
      await a;
      expect(player.played.where((p) => p == _ru('wake_listen')).length, 1);
    });

    test('экран: статус и услышанный текст', () async {
      final c = make(['яма']);
      final seen = <String>[];
      c.ui.addListener(() => seen.add('${c.ui.value.status.name}|${c.ui.value.heard}'));
      await c.activate();
      expect(seen.any((s) => s.startsWith('listening')), isTrue);
      expect(seen.any((s) => s.endsWith('|яма')), isTrue);
      expect(c.ui.value.active, isFalse);
    });
  });

  group('MarkService', () {
    test('отметка уходит после паузы; отмена до паузы — не уходит', () async {
      final api = FakeApi();
      final m = MarkService(db: LocalDb.memory(), api: api, auth: FakeAuth(), holdFor: const Duration(milliseconds: 20));
      final fix = MarkFix(DateTime.now(), 41.3, 69.2, null);
      m.add(const MarkKind('bump'), fix);
      expect(m.cancelLast(), isTrue);
      m.add(const MarkKind('manhole'), fix);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.sent.map((e) => e['kind']), ['manhole']);
      expect(m.cancelLast(), isFalse);
    });
  });
}
