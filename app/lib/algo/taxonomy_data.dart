// СГЕНЕРИРОВАНО backend/tools_export_guess_fixtures.py из backend/brain/taxonomy.py — не править вручную.

class TaxItem {
  const TaxItem(this.key, this.group, this.ru, this.uz, this.road, this.level, this.driver);
  final String key, group, ru, uz, level;
  final bool road, driver;
}

const taxonomyItems = <TaxItem>[
  TaxItem('pothole_light', 'holes', 'Мелкая яма', 'Sayoz o‘ra', true, 'light', true),
  TaxItem('pothole_mid', 'holes', 'Яма средняя', 'O‘rtacha o‘ra', true, 'mid', true),
  TaxItem('pothole_deep', 'holes', 'Глубокая яма', 'Chuqur o‘ra', true, 'deep', true),
  TaxItem('pothole_danger', 'holes', 'Опасная яма', 'Xavfli o‘ra', true, 'danger', true),
  TaxItem('broken', 'holes', 'Разбитый участок (россыпь ям)', 'Buzilgan qism (ko‘p o‘ralar)', true, 'deep', true),
  TaxItem('patch', 'holes', 'Заплатка (ямочный ремонт)', 'Yamoq (ta’mirlangan joy)', true, 'light', true),
  TaxItem('crack', 'holes', 'Трещина / разлом', 'Yoriq / darz', true, 'light', true),
  TaxItem('bump_low', 'humps', 'Лежачий пологий', 'Yotiq politsiyachi (past)', true, 'light', true),
  TaxItem('bump', 'humps', 'Лежачий полицейский', 'Yotiq politsiyachi', true, 'mid', true),
  TaxItem('bump_high', 'humps', 'Лежачий крутой', 'Yotiq politsiyachi (baland)', true, 'deep', true),
  TaxItem('manhole', 'manholes', 'Люк', 'Lyuk', true, 'light', true),
  TaxItem('manhole_sunk', 'manholes', 'Люк просел', 'Lyuk cho‘kkan', true, 'mid', true),
  TaxItem('manhole_raised', 'manholes', 'Люк выступает', 'Lyuk ko‘tarilib turibdi', true, 'mid', true),
  TaxItem('rail_tram', 'rails', 'Трамвайные рельсы', 'Tramvay relslari', true, 'mid', true),
  TaxItem('rail_train', 'rails', 'Ж/д переезд', 'Temir yo‘l o‘tish joyi', true, 'mid', true),
  TaxItem('joint', 'rails', 'Стык плит / шов', 'Plita tutashuvi / chok', true, 'light', true),
  TaxItem('washboard', 'surface', 'Волнистость (гребёнка)', 'To‘lqinsimon yo‘l', true, 'mid', true),
  TaxItem('rutting', 'surface', 'Колея', 'Izlar (koleya)', true, 'mid', true),
  TaxItem('cobble', 'surface', 'Брусчатка / плитка', 'Bruschatka / plitka', true, 'light', false),
  TaxItem('curb', 'other', 'Бордюр / съезд', 'Bordyur / tushish joyi', false, '', true),
  TaxItem('braking', 'other', 'Резкое торможение / разгон', 'Keskin tormozlash / tezlashish', false, '', false),
  TaxItem('handled', 'other', 'Ложное срабатывание', 'Yolg‘on signal', false, '', true),
  TaxItem('noise', 'other', 'Ничего', 'Hech narsa', false, '', true),
];

const taxonomyGroups = <String, ({String ru, String uz})>{
  'holes': (ru: 'Ямы и повреждения', uz: 'O‘ralar va shikastlar'),
  'humps': (ru: 'Лежачие полицейские', uz: 'Yotiq politsiyachilar'),
  'manholes': (ru: 'Люки', uz: 'Lyuklar'),
  'rails': (ru: 'Рельсы, переезды, стыки', uz: 'Relslar, o‘tish joylari, choklar'),
  'surface': (ru: 'Покрытие', uz: 'Qoplama'),
  'other': (ru: 'Не дорога', uz: 'Yo‘l emas'),
};

/// Ключи, которые можно предложить водителю после удара.
final driverOptionKeys = <String>[for (final i in taxonomyItems) if (i.driver || i.key == 'handled' || i.key == 'noise') i.key];

TaxItem? taxItem(String key) {
  for (final i in taxonomyItems) {
    if (i.key == key) return i;
  }
  return null;
}
