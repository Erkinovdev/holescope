import '../algo/event_guess.dart';

/// Крупные ответы на вопрос «что это было?» (Figma · Flow 8): шесть типов вместо двух десятков вариантов справочника.
/// Яма уточняется глубиной. Какие типы и какие глубины показывать, решает догадка модели по силе удара.
enum EvGroup { pothole, bump, manhole, rails, uneven, unknown }

const _groupKeys = <EvGroup, List<String>>{
  EvGroup.pothole: ['pothole_light', 'pothole_mid', 'pothole_deep', 'pothole_danger', 'broken', 'patch', 'crack'],
  EvGroup.bump: ['bump_low', 'bump', 'bump_high'],
  EvGroup.manhole: ['manhole', 'manhole_sunk', 'manhole_raised'],
  EvGroup.rails: ['rail_tram', 'rail_train', 'joint'],
  EvGroup.uneven: ['washboard', 'rutting'],
};

const _defaultKey = <EvGroup, String>{EvGroup.bump: 'bump', EvGroup.manhole: 'manhole', EvGroup.rails: 'rail_tram', EvGroup.uneven: 'washboard'};

double groupProb(Guess g, EvGroup grp) => [for (final k in _groupKeys[grp] ?? const <String>[]) g.probs[k] ?? 0.0].fold(0.0, (a, b) => a + b);

/// Какие типы показать: яма, лежачий, люк — всегда; рельсы и неровность — только если по удару они правдоподобны (≥ 10 %); «Не знаю» — последним.
List<EvGroup> groupsFor(Guess g) => [
      EvGroup.pothole,
      EvGroup.bump,
      EvGroup.manhole,
      if (groupProb(g, EvGroup.rails) >= 0.10) EvGroup.rails,
      if (groupProb(g, EvGroup.uneven) >= 0.10) EvGroup.uneven,
      EvGroup.unknown,
    ];

/// Глубины ямы для второго шага: слабый удар — без «глубокой», сильный — без «лёгкой»; всегда минимум две соседние.
List<String> depthKeys(Guess g) {
  const keys = ['pothole_light', 'pothole_mid', 'pothole_deep'];
  final p = [g.probs['pothole_light'] ?? 0.0, g.probs['pothole_mid'] ?? 0.0, (g.probs['pothole_deep'] ?? 0.0) + (g.probs['pothole_danger'] ?? 0.0)];
  var top = 0;
  for (var i = 1; i < 3; i++) {
    if (p[i] > p[top]) top = i;
  }
  final out = <String>[for (var i = 0; i < 3; i++) if (p[i] >= 0.05 || ((i - top).abs() == 1 && p[i] >= 0.01)) keys[i]];
  if (!out.contains(keys[top])) out.add(keys[top]);
  if (out.length < 2) {
    final n = top == 0 ? 1 : top - 1;
    out.add(keys[n]);
  }
  out.sort((a, b) => keys.indexOf(a).compareTo(keys.indexOf(b)));
  return out;
}

/// Ключ справочника для выбранного типа: если догадка уже указывает на этот тип — её уточнение, иначе значение по умолчанию.
String resolveGroup(EvGroup grp, Guess g) {
  final keys = _groupKeys[grp];
  if (keys == null) return 'noise';
  if (keys.contains(g.top)) return g.top;
  return _defaultKey[grp] ?? 'pothole_mid';
}
