import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../l10n/app_localizations.dart';
import '../voice/holi_phrase.dart';
import '../voice/holi_voice.dart';
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

/// Предупреждения «впереди яма» голосом Холи: не чаще раза в [minGap], только на скорости не выше [maxSpeedKmh], без наложения фраз.
/// Выше порога остаётся только сигнал: на большой скорости голос мешает, а до ямы всё равно не затормозить.
class HoliAnnouncer implements Announcer {
  HoliAnnouncer(this._voice, {this.minGap = const Duration(seconds: 10), this.maxSpeedKmh = 100, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Future<HoliVoice> _voice;
  final Duration minGap;
  final double maxSpeedKmh;
  final DateTime Function() _now;
  DateTime? _last;

  /// Какую фразу сказать об этой яме: глубокая и лежачий — отдельные, обычная — с расстоянием. null — молчать (люки, рельсы, стыки).
  static ({HoliPhrase phrase, int? distanceM})? phraseFor(AheadItem item) {
    if (item.type == 'bump') return (phrase: HoliPhrase.aheadBump, distanceM: null);
    if (!item.type.startsWith('pothole')) return null;
    if (item.level == 'deep' || item.level == 'danger') return (phrase: HoliPhrase.aheadDeep, distanceM: null);
    return (phrase: HoliPhrase.aheadPothole, distanceM: item.distanceM);
  }

  @override
  Future<void> warn(AheadItem item, {required String lang, required double speedKmh, required bool voice, required bool beep}) async {
    if (beep) {
      await SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }
    final p = phraseFor(item);
    if (!voice || p == null || speedKmh > maxSpeedKmh) return;
    final now = _now();
    if (_last != null && now.difference(_last!) < minGap) return;
    _last = now;
    final v = await _voice;
    await v.play(p.phrase, distanceM: p.distanceM);
  }
}
