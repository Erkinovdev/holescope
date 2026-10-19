import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/voice/holi_commands.dart';
import 'package:holescope/voice/holi_phrase.dart';

VoiceCommand? cmd(String s, {bool confirm = false}) => HoliCommands.parse(s, confirm: confirm).command;

void main() {
  group('вызов по имени', () {
    for (final s in ['Привет, Холи', 'Эй, Холи!', 'холли', 'Хоули', 'Hey Holi', 'Xoli']) {
      test(s, () => expect(HoliCommands.parse(s).wake, isTrue));
    }
    test('обычная речь — не вызов', () => expect(HoliCommands.parse('поехали домой').wake, isFalse));
    test('вызов и команда в одной фразе', () {
      final p = HoliCommands.parse('Эй Холи, яма');
      expect(p.wake, isTrue);
      expect(p.command, VoiceCommand.pothole);
    });
  });

  group('команды ru', () {
    test('яма', () => expect(cmd('яма'), VoiceCommand.pothole));
    test('яму', () => expect(cmd('вот яму проехали'), VoiceCommand.pothole));
    test('глубокая яма', () => expect(cmd('глубокая яма'), VoiceCommand.deep));
    test('глубокая', () => expect(cmd('Глубокая!'), VoiceCommand.deep));
    test('лежачий', () => expect(cmd('лежачий полицейский'), VoiceCommand.bump));
    test('люк', () => expect(cmd('это люк'), VoiceCommand.manhole));
    test('отмена', () => expect(cmd('отмена'), VoiceCommand.cancel));
    test('убери', () => expect(cmd('убери отметку'), VoiceCommand.cancel));
    test('шум', () => expect(cmd('какая-то погода'), isNull));
    test('пусто', () => expect(HoliCommands.parse('   ').isEmpty, isTrue));
  });

  group('команды uz', () {
    test("o'ra", () => expect(cmd("o'ra"), VoiceCommand.pothole));
    test("chuqur o'ra", () => expect(cmd("Chuqur o‘ra"), VoiceCommand.deep));
    test('yotiq politsiyachi', () => expect(cmd('yotiq politsiyachi'), VoiceCommand.bump));
    test('lyuk', () => expect(cmd('lyuk'), VoiceCommand.manhole));
    test('bekor', () => expect(cmd('bekor qil'), VoiceCommand.cancel));
  });

  group('да / нет', () {
    test('да', () => expect(cmd('да', confirm: true), VoiceCommand.yes));
    test('ага', () => expect(cmd('ага', confirm: true), VoiceCommand.yes));
    test('нет', () => expect(cmd('нет', confirm: true), VoiceCommand.no));
    test('не было', () => expect(cmd('не было', confirm: true), VoiceCommand.no));
    test('отмена = нет при вопросе', () => expect(cmd('отмена', confirm: true), VoiceCommand.no));
    test('ha / yoq', () {
      expect(cmd('ha', confirm: true), VoiceCommand.yes);
      expect(cmd("yo'q", confirm: true), VoiceCommand.no);
    });
    test('«да» вне вопроса тоже распознаётся, но «отмена» остаётся отменой', () {
      expect(cmd('да'), VoiceCommand.yes);
      expect(cmd('отмена'), VoiceCommand.cancel);
    });
    test('«не надо» вне вопроса — отмена или нет, но не яма', () => expect(cmd('не надо'), VoiceCommand.no));
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
