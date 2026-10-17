import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../l10n/app_localizations.dart';
import 'ahead_warner.dart';

/// Озвучивание предупреждения (голос и/или короткий сигнал).
abstract class Announcer {
  Future<void> warn(AheadItem item, {required String lang, required double speedKmh, required bool voice, required bool beep});
}

/// Текст голосового предупреждения (ru/uz). Если безопасная скорость известна и мы едем быстрее — добавляем совет.
String warningText(AheadItem item, String lang, double speedKmh) {
  final l = lookupAppLocalizations(Locale(lang == 'uz' ? 'uz' : 'ru'));
  final safe = item.safeSpeed;
  if (safe != null && speedKmh > safe + 5) return l.ttsAheadSlow(item.distanceM, safe);
  return l.ttsAhead(item.distanceM);
}

class TtsAnnouncer implements Announcer {
  final FlutterTts _tts = FlutterTts();
  String? _lang;

  Future<void> _ensureLang(String lang) async {
    if (_lang == lang) return;
    final code = lang == 'uz' ? 'uz-UZ' : 'ru-RU';
    final ok = await _tts.isLanguageAvailable(code);
    // если узбекского голоса нет в системе — читаем русским голосом, но текст остаётся узбекским (лучше, чем тишина)
    await _tts.setLanguage(ok == true ? code : 'ru-RU');
    await _tts.setSpeechRate(0.5);
    _lang = lang;
  }

  @override
  Future<void> warn(AheadItem item, {required String lang, required double speedKmh, required bool voice, required bool beep}) async {
    if (beep) {
      await SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }
    if (voice) {
      await _ensureLang(lang);
      await _tts.speak(warningText(item, lang, speedKmh));
    }
  }
}

class SilentAnnouncer implements Announcer {
  final calls = <AheadItem>[];
  @override
  Future<void> warn(AheadItem item, {required String lang, required double speedKmh, required bool voice, required bool beep}) async => calls.add(item);
}
