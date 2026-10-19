import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/voice/holi_commands.dart';
import 'package:holescope/voice/holi_phrase.dart';

ParsedVoice p(String s, {bool confirm = false}) => HoliCommands.parse(s, confirm: confirm);
String? mark(String s) => p(s).command == VoiceCommand.mark ? p(s).key : null;

void main() {
  group('вызов по имени', () {
    for (final s in ['Привет, Холи', 'Эй, Холи!', 'холли', 'Хоули', 'Hey Holi', 'Xoli']) {
      test(s, () => expect(p(s).wake, isTrue));
    }
    test('обычная речь — не вызов', () => expect(p('поехали домой').wake, isFalse));
    test('вызов и команда в одной фразе', () {
      final r = p('Эй Холи, глубокая яма');
      expect(r.wake, isTrue);
      expect(r.key, 'pothole_deep');
    });
  });

  group('ямы и их уровни', () {
    final cases = {
      'яма': 'pothole', 'яму': 'pothole', 'ямы': 'pothole', 'вот яма была': 'pothole',
      'мелкая яма': 'pothole_light', 'небольшая яма': 'pothole_light',
      'средняя яма': 'pothole_mid',
      'глубокая яма': 'pothole_deep', 'Глубокая!': 'pothole_deep', 'глубокую яму': 'pothole_deep',
      'опасная яма': 'pothole_danger', 'очень опасная': 'pothole_danger',
      'разбитый участок': 'broken', 'много ям': 'broken',
      'заплатка': 'patch', 'трещина': 'crack',
    };
    cases.forEach((say, key) => test('«$say» → $key', () => expect(mark(say), key)));
  });

  group('лежачие, люки, рельсы, покрытие', () {
    final cases = {
      'лежачий': 'bump', 'лежачий полицейский': 'bump', 'пологий лежачий': 'bump_low', 'крутой лежачий': 'bump_high',
      'люк': 'manhole', 'это люк': 'manhole', 'просевший люк': 'manhole_sunk', 'люк просел': 'manhole_sunk', 'выступающий люк': 'manhole_raised', 'люк торчит': 'manhole_raised',
      'рельсы': 'rail_tram', 'трамвайные рельсы': 'rail_tram', 'переезд': 'rail_train', 'железнодорожный переезд': 'rail_train', 'стык': 'joint',
      'волнистая дорога': 'washboard', 'гребёнка': 'washboard', 'колея': 'rutting', 'брусчатка': 'cobble', 'бордюр': 'curb',
    };
    cases.forEach((say, key) => test('«$say» → $key', () => expect(mark(say), key)));
  });

  group('оценка дороги', () {
    final cases = {
      'дорога ровная': 'road_a', 'ровная дорога': 'road_a', 'дорога хорошая': 'road_b', 'так себе': 'road_c', 'немного неровная': 'road_c',
      'дорога плохая': 'road_d', 'неровная дорога': 'road_d', 'разбитая дорога': 'road_e', 'очень неровная': 'road_e', 'кошмар': 'road_e',
    };
    cases.forEach((say, key) {
      test('«$say» → $key', () {
        final r = p(say);
        expect(r.command, VoiceCommand.rating);
        expect(r.key, key);
      });
    });
  });

  group('узбекский (латиница и кириллица)', () {
    final cases = {
      "o'ra": 'pothole', 'O‘ra': 'pothole', "chuqur o'ra": 'pothole_deep', "xavfli o'ra": 'pothole_danger', "sayoz o'ra": 'pothole_light',
      'yotiq politsiyachi': 'bump', 'lyuk': 'manhole', "cho'kkan lyuk": 'manhole_sunk', 'relslar': 'rail_tram', "o'tish joyi": 'rail_train',
      'ўра': 'pothole', 'чуқур ўра': 'pothole_deep',
    };
    cases.forEach((say, key) => test('«$say» → $key', () => expect(mark(say), key)));
    test('оценка по-узбекски', () {
      expect(p("yo'l tekis").key, 'road_a');
      expect(p("buzilgan yo'l").key, 'road_e');
    });
  });

  group('управление', () {
    test('отмена', () => expect(p('отмена').command, VoiceCommand.cancel));
    test('убери отметку', () => expect(p('убери отметку').command, VoiceCommand.cancel));
    test('bekor', () => expect(p('bekor qil').command, VoiceCommand.cancel));
    test('стоп / спасибо', () {
      expect(p('спасибо').command, VoiceCommand.stop);
      expect(p('хватит').command, VoiceCommand.stop);
    });
    test('помощь', () => expect(p('что ты умеешь').command, VoiceCommand.help));
    test('шум', () => expect(p('какая-то погода').command, isNull));
    test('пусто', () => expect(p('   ').isEmpty, isTrue));
  });

  group('да / нет в вопросе', () {
    for (final s in ['да', 'ага', 'конечно', 'ha', 'to‘g‘ri']) {
      test('«$s» = да', () => expect(p(s, confirm: true).command, VoiceCommand.yes));
    }
    for (final s in ['нет', 'не было', 'отмена', 'стоп', 'yo‘q', 'bekor']) {
      test('«$s» = нет', () => expect(p(s, confirm: true).command, VoiceCommand.no));
    }
    test('«да, яма» в вопросе = да', () => expect(p('да яма', confirm: true).command, VoiceCommand.yes));
  });

  group('отрицание', () {
    test('«это не яма» → отметка «не яма»', () {
      final r = p('это не яма');
      expect(r.command, VoiceCommand.mark);
      expect(r.key, 'not_pothole');
    });
  });

  group('ошибки распознавания', () {
    test('«ямка» ≈ яма', () => expect(mark('ямка'), isNotNull));
    test('«лежачьий» ≈ лежачий', () => expect(mark('лежачьий полицейский'), 'bump'));
    test('«глубокие ямы»', () => expect(mark('глубокие ямы'), 'pothole_deep'));
  });

  group('расстояния для фраз', () {
    test('округление к записанным', () {
      expect(HoliPhrase.nearestDistance(10), 50);
      expect(HoliPhrase.nearestDistance(120), 100);
      expect(HoliPhrase.nearestDistance(130), 150);
      expect(HoliPhrase.nearestDistance(999), 300);
    });
    test('ключ файла', () => expect(HoliPhrase.aheadPothole.distanceKey(170), 'ahead_pothole_150'));
  });
}
