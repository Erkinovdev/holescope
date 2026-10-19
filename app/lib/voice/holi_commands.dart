/// Распознавание голосовых команд водителя в тексте (ru/uz). Чистая функция — проверяется тестами без микрофона.
enum VoiceCommand { pothole, deep, bump, manhole, cancel, yes, no }

class ParsedVoice {
  const ParsedVoice({this.wake = false, this.command});
  final bool wake;
  final VoiceCommand? command;
  bool get isEmpty => !wake && command == null;
}

class HoliCommands {
  const HoliCommands._();

  static final _punct = RegExp(r"[^\p{L}\p{N}']+", unicode: true);
  // распознаватель пишет имя по-разному: «Холи», «Холли», «Холе», «Хоули», holi, xoli
  static final _wake = RegExp(r"^(хол+и|холе|хоули|холь|holi|holly|xoli|xo'li|xoli)$");

  static String normalize(String s) {
    var t = s.toLowerCase().replaceAll('ё', 'е');
    t = t.replaceAll(RegExp(r"[’‘ʻʼ`´]"), "'");
    return t.replaceAll(_punct, ' ').trim();
  }

  static bool _word(List<String> tokens, Iterable<String> words) => tokens.any(words.contains);
  static bool _prefix(List<String> tokens, Iterable<String> prefixes) => tokens.any((t) => prefixes.any(t.startsWith));

  /// [confirm] — идёт вопрос «да/нет»: «нет»/«не было»/«отмена» = нет.
  static ParsedVoice parse(String text, {bool confirm = false}) {
    final t = normalize(text);
    if (t.isEmpty) return const ParsedVoice();
    final tokens = t.split(' ');
    final wake = tokens.any(_wake.hasMatch);

    // да / нет (ru, uz)
    final no = _word(tokens, ['нет', 'неа', "yo'q", 'yoq']) || t.contains('не было') || t.contains('не надо');
    final yes = _word(tokens, ['да', 'ага', 'угу', 'верно', 'точно', 'ha', 'xa', "to'g'ri", 'albatta']) || t.contains('так точно');
    if (confirm) {
      if (no || _prefix(tokens, ['отмен', 'bekor'])) return ParsedVoice(wake: wake, command: VoiceCommand.no);
      if (yes) return ParsedVoice(wake: wake, command: VoiceCommand.yes);
    }

    final cancel = _prefix(tokens, ['отмен', 'убер', 'удал', 'bekor', "o'chir", 'ochir']);
    if (cancel) return ParsedVoice(wake: wake, command: VoiceCommand.cancel);

    final deep = _prefix(tokens, ['глубок', 'chuqur']);
    final hole = _prefix(tokens, ['ям', 'выбоин', "o'ra", 'ora', 'chuqurlik']);
    final bump = _prefix(tokens, ['лежач', 'полицейск', 'бугор', 'yotiq', 'politsiya', "to'siq", 'tezlik']);
    final manhole = _prefix(tokens, ['люк', 'lyuk', 'lyuq', 'quduq']);

    if (manhole) return ParsedVoice(wake: wake, command: VoiceCommand.manhole);
    if (bump) return ParsedVoice(wake: wake, command: VoiceCommand.bump);
    if (deep) return ParsedVoice(wake: wake, command: VoiceCommand.deep); // «глубокая яма», «chuqur o'ra», просто «глубокая»
    if (hole) return ParsedVoice(wake: wake, command: VoiceCommand.pothole);
    if (no) return ParsedVoice(wake: wake, command: VoiceCommand.no);
    if (yes) return ParsedVoice(wake: wake, command: VoiceCommand.yes);
    return ParsedVoice(wake: wake);
  }
}
