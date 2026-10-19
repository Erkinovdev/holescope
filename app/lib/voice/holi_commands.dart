import 'holi_lexicon.dart' as lex;

/// Что понял Холи: отметка объекта, оценка дороги или управление диалогом.
enum VoiceCommand { mark, rating, cancel, yes, no, stop, help }

class ParsedVoice {
  const ParsedVoice({this.wake = false, this.command, this.key});
  final bool wake;
  final VoiceCommand? command;

  /// Для [VoiceCommand.mark] — метка справочника (`pothole_deep`, `manhole_sunk`…), `pothole` — «яма» без уточнения, `not_pothole` — «это не яма».
  /// Для [VoiceCommand.rating] — `road_a`…`road_e`.
  final String? key;
  bool get isEmpty => !wake && command == null;
  @override
  String toString() => 'ParsedVoice(wake: $wake, $command, $key)';
}

/// Разбор фразы водителя: русский и узбекский вместе, склонения и мелкие ошибки распознавания прощаем.
class HoliCommands {
  const HoliCommands._();

  static const _translit = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo', 'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
    'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'x', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ъ': '', 'ы': 'i', 'ь': '',
    'э': 'e', 'ю': 'yu', 'я': 'ya', 'ў': "o'", 'ғ': "g'", 'қ': 'q', 'ҳ': 'h',
  };
  static final _apos = RegExp(r"[’‘ʻʼ`´']");
  static final _punct = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
  static final _cyr = RegExp(r'[а-яёўғқҳ]');

  /// Строчные буквы, «ё»→«е», апострофы убраны, знаки препинания → пробелы.
  static String normalize(String s) {
    var t = s.toLowerCase().replaceAll('ё', 'е').replaceAll(_apos, '');
    t = t.replaceAll(_punct, ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Узбекская кириллица («ўра») → латиница («ora»), чтобы сравнивать с латинским словарём.
  static String _latin(String w) => w.split('').map((c) => _translit[c] ?? c).join().replaceAll(_apos, '');

  static final _vowelEnd = RegExp(r'[аяуюыиеоьйaiouy]+$');

  /// Основа слова: без падежных окончаний («ямы», «яму» → «ям»; «глубокую» → «глубок»).
  static String _stem(String w) {
    if (w.length <= 3) return w;
    final m = _vowelEnd.firstMatch(w);
    if (m == null) return w;
    final cut = w.length - m.group(0)!.length;
    return cut >= 3 || (cut >= 2 && w.length >= 4) ? w.substring(0, cut) : w;
  }

  static int _lev(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Одно ли это слово (с учётом окончаний и опечаток распознавателя).
  static bool sameWord(String a, String b) {
    if (a == b) return true;
    if (a.length <= 2 || b.length <= 2) return false;
    // «яма / яму / ямы»: короткие слова с разным окончанием
    if (a.length == 3 && b.length == 3 && a.substring(0, 2) == b.substring(0, 2) && _vowelEnd.hasMatch(a) && _vowelEnd.hasMatch(b)) return true;
    final sa = _stem(a), sb = _stem(b);
    if (sa == sb) return true;
    final minLen = sa.length < sb.length ? sa.length : sb.length;
    if (minLen >= 3 && (sa.startsWith(sb) || sb.startsWith(sa)) && (sa.length - sb.length).abs() <= 1 && minLen >= 4) return true;
    if (minLen >= 5 && _lev(sa, sb) <= 1) return true;
    return false;
  }

  /// Слова фразы после нормализации (латиница без апострофов).
  static List<String> _words(String phrase) => normalize(phrase).split(' ').where((w) => w.isNotEmpty).toList();

  static final List<_Compiled> _compiled = [
    for (final e in lex.marks) _Compiled(e.key, VoiceCommand.mark, [for (final p in e.phrases) _words(p)]),
    for (final e in lex.ratings) _Compiled(e.key, VoiceCommand.rating, [for (final p in e.phrases) _words(p)]),
    for (final e in lex.controls) _Compiled(e.key, VoiceCommand.values.byName(e.key), [for (final p in e.phrases) _words(p)]),
  ];

  static bool _tokenMatches(List<String> forms, String w) => forms.any((f) => sameWord(f, w));

  /// [confirm] — идёт вопрос «да/нет»: тогда «нет», «не было», «отмена», «стоп» = нет.
  static ParsedVoice parse(String text, {bool confirm = false}) {
    final tokens = normalize(text).split(' ').where((w) => w.isNotEmpty).toList();
    if (tokens.isEmpty) return const ParsedVoice();
    // каждое слово — и как есть, и транслитерацией (узбекская кириллица)
    final forms = [for (final t in tokens) _cyr.hasMatch(t) ? [t, _latin(t)] : [t]];
    final wake = forms.any((f) => lex.wakeWords.any((w) {
          final ww = normalize(w);
          return _tokenMatches(f, ww) || (ww.length >= 4 && f.any((x) => _lev(x, ww) <= 1));
        }));

    _Hit? best;
    int score(_Compiled c, List<String> phrase, List<int> idx) => phrase.fold<int>(0, (a, w) => a + w.length) * 10 + phrase.length;
    for (final c in _compiled) {
      for (final p in c.phrases) {
        if (p.isEmpty) continue;
        final idx = <int>[];
        var ok = true;
        for (final w in p) {
          final i = [for (var k = 0; k < forms.length; k++) k].firstWhere((k) => !idx.contains(k) && _tokenMatches(forms[k], w), orElse: () => -1);
          if (i < 0) {
            ok = false;
            break;
          }
          idx.add(i);
        }
        if (!ok) continue;
        final s = score(c, p, idx);
        if (best == null || s > best.score) best = _Hit(c, s, idx);
      }
    }
    // «не яма» / «это не люк»: отрицание перед объектом — отметка «не яма»
    final negated = best != null && best.c.command == VoiceCommand.mark && best.idx.any((i) => i > 0 && (tokens[i - 1] == 'не' || tokens[i - 1] == 'emas'));
    if (confirm) {
      // в вопросе «да/нет» важнее всего ответ: ищем его отдельно
      final yn = _best(forms, {VoiceCommand.yes, VoiceCommand.no, VoiceCommand.cancel, VoiceCommand.stop});
      if (yn != null) {
        final cmd = yn.c.command == VoiceCommand.yes ? VoiceCommand.yes : VoiceCommand.no;
        return ParsedVoice(wake: wake, command: cmd);
      }
    }
    if (best == null) return ParsedVoice(wake: wake);
    if (negated) return ParsedVoice(wake: wake, command: VoiceCommand.mark, key: 'not_pothole');
    return ParsedVoice(wake: wake, command: best.c.command, key: best.c.command == VoiceCommand.mark || best.c.command == VoiceCommand.rating ? best.c.key : null);
  }

  static _Hit? _best(List<List<String>> forms, Set<VoiceCommand> only) {
    _Hit? best;
    for (final c in _compiled.where((c) => only.contains(c.command))) {
      for (final p in c.phrases) {
        if (p.isEmpty) continue;
        final idx = <int>[];
        var ok = true;
        for (final w in p) {
          final i = [for (var k = 0; k < forms.length; k++) k].firstWhere((k) => !idx.contains(k) && _tokenMatches(forms[k], w), orElse: () => -1);
          if (i < 0) {
            ok = false;
            break;
          }
          idx.add(i);
        }
        if (!ok) continue;
        final s = p.fold<int>(0, (a, w) => a + w.length);
        if (best == null || s > best.score) best = _Hit(c, s, idx);
      }
    }
    return best;
  }
}

class _Compiled {
  _Compiled(this.key, this.command, this.phrases);
  final String key;
  final VoiceCommand command;
  final List<List<String>> phrases;
}

class _Hit {
  _Hit(this.c, this.score, this.idx);
  final _Compiled c;
  final int score;
  final List<int> idx;
}
