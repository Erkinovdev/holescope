/// Словарь голосовых команд Холи (русский и узбекский вместе: распознаватель может ответить на любом языке, а водитель смешивает слова).
/// Ключ — метка из справочника сервера (brain/taxonomy.py): отметка объекта или оценка ровности дороги (`road_a`…`road_e`).
/// Фразы — как их говорят и как их часто пишет распознаватель; склонения и мелкие ошибки ловит сопоставление по основе слова.
library;

class LexEntry {
  const LexEntry(this.key, this.phrases);
  final String key;
  final List<String> phrases;
}

/// Отметки объектов на дороге.
const marks = <LexEntry>[
  LexEntry('pothole', ['яма', 'ямка', 'выбоина', 'ухаб', "o'ra", 'chuqurlik']),
  LexEntry('pothole_light', ['мелкая яма', 'маленькая яма', 'небольшая яма', 'неглубокая яма', 'легкая яма', 'мелкая', "sayoz o'ra", "kichik o'ra"]),
  LexEntry('pothole_mid', ['средняя яма', 'обычная яма', 'нормальная яма', "o'rtacha o'ra"]),
  LexEntry('pothole_deep', ['глубокая яма', 'глубокая', 'большая яма', "chuqur o'ra", 'chuqur']),
  LexEntry('pothole_danger', ['опасная яма', 'опасная', 'очень глубокая яма', 'страшная яма', 'жуть', "xavfli o'ra", 'xavfli', "juda chuqur"]),
  LexEntry('broken', ['разбитый участок', 'россыпь ям', 'много ям', 'ямы подряд', 'сплошные ямы', 'buzilgan qism', "ko'p o'ralar", "o'ralar"]),
  LexEntry('patch', ['заплатка', 'латка', 'залатанная яма', 'ямочный ремонт', 'yamoq', "ta'mirlangan"]),
  LexEntry('crack', ['трещина', 'трещины', 'разлом', 'yoriq', 'darz']),
  LexEntry('bump_low', ['пологий лежачий', 'низкий лежачий', 'пологая горка', 'past yotiq', 'past politsiyachi']),
  LexEntry('bump', ['лежачий', 'лежачий полицейский', 'полицейский', 'бугор', 'горка', 'yotiq politsiyachi', 'yotiq', 'politsiyachi', "to'siq"]),
  LexEntry('bump_high', ['крутой лежачий', 'высокий лежачий', 'высокая горка', 'baland yotiq', 'baland politsiyachi']),
  LexEntry('manhole', ['люк', 'колодец', 'lyuk', 'lyuq', 'quduq']),
  LexEntry('manhole_sunk', ['просевший люк', 'люк просел', 'провалившийся люк', 'люк провал', 'люк ниже', "cho'kkan lyuk", "lyuk cho'kkan", 'lyuk past']),
  LexEntry('manhole_raised', ['выступающий люк', 'люк выступает', 'люк выше', 'люк торчит', 'торчащий люк', "lyuk baland", "lyuk ko'tarilgan", "ko'tarilgan lyuk"]),
  LexEntry('rail_tram', ['рельсы', 'трамвайные рельсы', 'трамвай', 'relslar', 'rels', 'tramvay']),
  LexEntry('rail_train', ['переезд', 'железная дорога', 'жд переезд', 'железнодорожный переезд', "o'tish joyi", "temir yo'l", 'pereyezd']),
  LexEntry('joint', ['стык', 'стыки', 'шов', 'деформационный шов', 'chok', 'tutashuv']),
  LexEntry('washboard', ['волнистая дорога', 'волнистость', 'гребенка', 'волны', 'волнистая', "to'lqinsimon", "to'lqin"]),
  LexEntry('rutting', ['колея', 'колеи', 'koleya', 'izlar']),
  LexEntry('cobble', ['брусчатка', 'плитка', 'bruschatka', 'plitka']),
  LexEntry('curb', ['бордюр', 'бордюра', 'bordyur']),
  LexEntry('handled', ['телефон упал', 'телефон трогал', 'трогали телефон', 'telefon tushdi']),
  LexEntry('noise', ['ничего особенного', 'ничего', 'alohida narsa yoq']),
];

/// Оценка ровности участка, который только что проехали.
const ratings = <LexEntry>[
  LexEntry('road_a', ['дорога ровная', 'ровная дорога', 'ровно', 'идеальная дорога', "yo'l tekis", "tekis yo'l", 'tekis']),
  LexEntry('road_b', ['дорога хорошая', 'хорошая дорога', 'хорошо', "yo'l yaxshi", "yaxshi yo'l", 'yaxshi']),
  LexEntry('road_c', ['дорога нормальная', 'нормальная дорога', 'так себе', 'удовлетворительно', 'немного неровная', 'чуть неровная', "yo'l qoniqarli", 'qoniqarli']),
  LexEntry('road_d', ['дорога плохая', 'плохая дорога', 'неровная дорога', 'неровно', "yo'l yomon", "yomon yo'l", "notekis yo'l", 'notekis']),
  LexEntry('road_e', ['дорога разбитая', 'разбитая дорога', 'очень неровная', 'ужасная дорога', 'кошмар', "yo'l buzilgan", "buzilgan yo'l", 'juda notekis', 'dahshat']),
];

/// Управление диалогом.
const controls = <LexEntry>[
  LexEntry('cancel', ['отмена', 'отмени', 'отменить', 'убери', 'убрать', 'удали', 'bekor', 'bekor qil', "o'chir"]),
  LexEntry('yes', ['да', 'ага', 'угу', 'верно', 'точно', 'так точно', 'конечно', 'ha', 'xa', "to'g'ri", 'albatta']),
  LexEntry('no', ['нет', 'неа', 'не было', 'не надо', "yo'q", 'yoq', 'yok', "bo'lmadi"]),
  LexEntry('stop', ['все', 'хватит', 'стоп', 'спасибо', 'достаточно', 'закончили', "bo'ldi", 'yetarli', 'rahmat']),
  LexEntry('help', ['помощь', 'что ты умеешь', 'команды', 'что сказать', 'yordam', 'nima deyman']),
];

/// Имя помощницы: так её пишут распознаватели.
const wakeWords = ['холи', 'холли', 'холе', 'хоули', 'холь', 'holi', 'holly', 'xoli', "xo'li", 'holy', 'хули', 'холи холи'];
