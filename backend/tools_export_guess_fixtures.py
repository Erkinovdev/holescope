"""Эталонные примеры для проверки совпадения догадки на сервере (Python) и в приложении (Dart): python tools_export_guess_fixtures.py
Пишет app/test/fixtures/guess_cases.json."""
import json
import os
import random

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()
from brain import guesser, taxonomy  # noqa: E402

rng = random.Random(7)
cases = []
for i in range(60):
    f = dict(score=round(rng.uniform(0.8, 11), 2), speed_kmh=round(rng.uniform(4, 90), 1), dur_ms=round(rng.uniform(60, 1000)), pair=round(rng.uniform(0, 1), 2),
             gyro_peak=round(rng.choice([8, 12, 20, 60, 120, 250]) * rng.uniform(0.8, 1.2), 1), hf_share=round(rng.uniform(0, 0.8), 2), peak=round(rng.uniform(1, 9), 2),
             loc_hits=rng.choice([0, 1, 2, 3, 6]))
    ctx = {}
    r = rng.random()
    if r < 0.25:
        ctx = dict(near_type=rng.choice(["pothole", "bump", "manhole", "rail_tram", "joint"]), near_passes=rng.choice([1, 2, 5, 9]))
    elif r < 0.4:
        ctx = dict(tram=True)
    elif r < 0.5:
        ctx = dict(crossing=True)
    elif r < 0.6:
        ctx = dict(bridge=True)
    params = None if i % 3 else dict(level_theta=[2.7, 4.2, 6.9], level_tau=1.1, notroad_prior=0.2)
    g = guesser.guess_event(f, ctx, params)
    keys = taxonomy.driver_option_keys()
    cases.append(dict(f=f, ctx=ctx, params=params, probs=g.probs, top=g.top, options=guesser.options_for(g, keys), options3=guesser.options_for(g, keys, limit=3)))
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "test", "fixtures", "guess_cases.json")
json.dump(dict(keys=taxonomy.driver_option_keys(), cases=cases), open(out, "w", encoding="utf-8"), ensure_ascii=False)
print(len(cases), "cases ->", os.path.normpath(out))


# справочник вариантов для приложения (офлайн): app/lib/algo/taxonomy_data.dart
def _q(t: str) -> str:
    return "'" + t.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


lines = ["// СГЕНЕРИРОВАНО backend/tools_export_guess_fixtures.py из backend/brain/taxonomy.py — не править вручную.", "",
         "class TaxItem {", "  const TaxItem(this.key, this.group, this.ru, this.uz, this.road, this.level, this.driver);",
         "  final String key, group, ru, uz, level;", "  final bool road, driver;", "}", "", "const taxonomyItems = <TaxItem>["]
for it in taxonomy.ITEMS:
    lines.append(f"  TaxItem({_q(it.key)}, {_q(it.group)}, {_q(it.ru)}, {_q(it.uz)}, {str(it.road).lower()}, {_q(it.level)}, {str(it.driver).lower()}),")
lines += ["];", "", "const taxonomyGroups = <String, ({String ru, String uz})>{"]
for k, (ru, uz) in taxonomy.GROUPS.items():
    lines.append(f"  {_q(k)}: (ru: {_q(ru)}, uz: {_q(uz)}),")
lines += ["};", "", "/// Ключи, которые можно предложить водителю после удара.", "final driverOptionKeys = <String>[for (final i in taxonomyItems) if (i.driver || i.key == 'handled' || i.key == 'noise') i.key];", "",
          "TaxItem? taxItem(String key) {", "  for (final i in taxonomyItems) {", "    if (i.key == key) return i;", "  }", "  return null;", "}", ""]
dart_out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "lib", "algo", "taxonomy_data.dart")
open(dart_out, "w", encoding="utf-8").write("\n".join(lines))
print("taxonomy ->", os.path.normpath(dart_out))
