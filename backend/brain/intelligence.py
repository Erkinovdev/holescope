"""Что это за неровность — разбор по форме сигнала и по контексту (повторяемость на многих проездах, дорога, скорость).

Опора на исследования смартфонной диагностики дорог: лучше всего различают объекты признаки во времени и по частотам (энергия по диапазонам,
эксцесс, пик-фактор, число и затухание пиков), скорость нужно учитывать, а повторяемость на проездах отличает постоянные объекты
(люк, лежачий, рельсы, стык) от ям, которые зависят от полосы. Здесь это сделано прозрачно: правила дают вероятности и причины,
а обученная модель (`train_types`) заменит их, когда накопится разметка.
"""
from __future__ import annotations
import math
from dataclasses import dataclass, field
import numpy as np

# классы объектов (как тип на карте)
CLASSES = ["pothole", "bump", "manhole", "rail_tram", "rail_train", "joint", "rough_patch", "broken", "patch", "crack", "rutting"]
NAMES = {"pothole": "яма", "bump": "лежачий", "manhole": "люк", "rail_tram": "трамвайные рельсы", "rail_train": "ж/д переезд", "joint": "стык / шов", "rough_patch": "волнистость",
         "broken": "разбитый участок", "patch": "заплатка", "crack": "трещина", "rutting": "колея"}


# ───────────────────────── признаки формы сигнала ─────────────────────────
WAVE_KEYS = ["w_p2p", "w_crest", "w_kurt", "w_peaks", "w_zc", "w_decay", "w_lf", "w_mf", "w_hf", "w_asym", "w_first_down"]


def wave_features(wave) -> dict:
    """Признаки по записи вертикальных ускорений вокруг события (±2 с). Пустая запись → нули."""
    out = {k: 0.0 for k in WAVE_KEYS}
    try:
        x = np.asarray([v for v in (wave or []) if v is not None], dtype=float)
    except (TypeError, ValueError):
        return out
    if x.size < 12 or not np.isfinite(x).all():
        return out
    x = x - np.median(x)
    n = x.size
    fs = n / 4.0  # окно ±2 с
    a = np.abs(x)
    peak = float(a.max()) or 1e-9
    rms = float(np.sqrt(np.mean(x ** 2))) or 1e-9
    out["w_p2p"] = float(x.max() - x.min())
    out["w_crest"] = peak / rms
    m2 = float(np.mean(x ** 2)) or 1e-9
    out["w_kurt"] = float(np.mean(x ** 4) / (m2 ** 2))  # «острота»: одиночный удар → большое значение
    # значимые пики: локальные максимумы модуля выше 35 % главного, не ближе 0.12 с друг к другу
    thr = 0.35 * peak
    idx = [i for i in range(1, n - 1) if a[i] >= thr and a[i] >= a[i - 1] and a[i] >= a[i + 1]]
    keep: list[int] = []
    for i in sorted(idx, key=lambda j: -a[j]):
        if all(abs(i - k) / fs >= 0.12 for k in keep):
            keep.append(i)
    keep.sort()
    out["w_peaks"] = float(len(keep))
    out["w_zc"] = float(np.sum(np.signbit(x[1:]) != np.signbit(x[:-1]))) / 4.0  # пересечений нуля в секунду
    # затухание: время от главного пика до падения ниже 20 %
    ip = int(a.argmax())
    tail = np.where(a[ip:] < 0.2 * peak)[0]
    out["w_decay"] = float(tail[0] / fs) if tail.size else float((n - ip) / fs)
    # энергия по частотным диапазонам (доли): <3 Гц кузов, 3–8 Гц подвеска, >8 Гц колесо/мелкая тряска
    spec = np.abs(np.fft.rfft(x * np.hanning(n))) ** 2
    f = np.fft.rfftfreq(n, d=1.0 / fs)
    tot = float(spec[1:].sum()) or 1e-9
    out["w_lf"] = float(spec[(f > 0) & (f < 3)].sum() / tot)
    out["w_mf"] = float(spec[(f >= 3) & (f < 8)].sum() / tot)
    out["w_hf"] = float(spec[f >= 8].sum() / tot)
    out["w_asym"] = float(abs(x.max()) / (abs(x.min()) + 1e-9))  # вверх / вниз: яма — сначала вниз, горка — сначала вверх
    out["w_first_down"] = 1.0 if (keep and x[keep[0]] < 0) else 0.0
    return {k: (0.0 if not math.isfinite(v) else round(v, 4)) for k, v in out.items()}


# ───────────────────────── контекст объекта ─────────────────────────
CONTEXT_KEYS = ["c_hit_rate", "c_score_cv", "c_speed_slope", "c_passes", "c_devices", "c_tram", "c_crossing", "c_bridge", "c_low_speed"]


def context_features(cluster) -> dict:
    """Признаки по всем проездам через объект. Постоянные объекты бьют на каждом проезде и примерно одинаково; яма зависит от полосы и колеса."""
    from telemetry.models import RoadEvent
    evs = list(RoadEvent.objects.filter(cluster=cluster).values_list("score", "speed_kmh")[:200])
    passes = max(cluster.passes, len(evs))
    quiet = cluster.quiet_passes
    out = {k: 0.0 for k in CONTEXT_KEYS}
    out["c_passes"] = float(passes)
    out["c_devices"] = float(cluster.devices)
    out["c_hit_rate"] = passes / (passes + quiet) if passes + quiet else 1.0
    if len(evs) >= 3:
        sc = np.array([e[0] for e in evs], float)
        sp = np.array([e[1] for e in evs], float)
        out["c_score_cv"] = float(sc.std() / (sc.mean() + 1e-9))
        if sp.std() > 3:
            out["c_speed_slope"] = float(np.polyfit(sp, sc, 1)[0])  # сила удара на каждый км/ч
        out["c_low_speed"] = float(np.mean(sp < 35))
    seg = cluster.segment
    if seg is not None:
        out["c_tram"], out["c_crossing"], out["c_bridge"] = float(seg.tram), float(seg.level_crossing), float(seg.bridge or seg.tunnel)
    return {k: round(v, 4) for k, v in out.items()}


# ───────────────────────── объяснимые правила ─────────────────────────
@dataclass
class TypeGuess:
    probs: dict[str, float]
    reasons: list[str] = field(default_factory=list)
    top: str = "pothole"

    def ranked(self, n: int = 4) -> list[tuple[str, float]]:
        return sorted(self.probs.items(), key=lambda kv: -kv[1])[:n]


def guess_type(features: dict, ctx: dict | None = None, wave: list | None = None) -> TypeGuess:
    """Вероятности типа по правилам (пока нет обученной модели). features — признаки события, ctx — контекст объекта (если есть)."""
    f = dict(features or {})
    w = wave_features(wave) if wave else {k: f.get(k, 0.0) for k in WAVE_KEYS}
    c = ctx or {}
    dur = float(f.get("dur_ms") or 0)
    pair = float(f.get("pair") or 0)
    speed = float(f.get("speed_kmh") or 0)
    s = {k: 1.0 for k in CLASSES}  # равные «очки» до правил
    why: list[str] = []

    hit = c.get("c_hit_rate")
    cv = c.get("c_score_cv")
    passes = c.get("c_passes", 0)
    persistent = hit is not None and passes >= 3 and hit >= 0.85
    if persistent:
        for k in ("manhole", "bump", "rail_tram", "rail_train", "joint"):
            s[k] += 1.4
        s["pothole"] -= 0.5
        why.append(f"удар на {hit:.0%} проездов — постоянный объект, а не яма на одной полосе")
    elif hit is not None and passes >= 3 and hit < 0.6:
        s["pothole"] += 1.2
        s["crack"] += 0.4
        why.append(f"удар лишь на {hit:.0%} проездов — зависит от полосы, похоже на яму")
    if cv is not None and passes >= 4:
        if cv < 0.25:
            for k in ("manhole", "bump", "joint"):
                s[k] += 0.6
            why.append("сила удара почти одинаковая на всех проездах")
        elif cv > 0.6:
            s["pothole"] += 0.6
            why.append("сила удара сильно скачет между проездами")
    if c.get("c_tram"):
        s["rail_tram"] += 2.2
        why.append("рядом трамвайные пути")
    if c.get("c_crossing"):
        s["rail_train"] += 2.2
        why.append("рядом железнодорожный переезд")
    if c.get("c_bridge"):
        s["joint"] += 1.6
        why.append("мост или тоннель: вероятен деформационный шов")
    if pair >= 0.5:
        s["bump"] += 0.8
        s["rail_tram"] += 0.4
        s["rail_train"] += 0.4
        why.append("удар парой: колёса переднее и заднее прошли один и тот же объект")
    elif pair < 0.2:
        s["manhole"] += 0.5
        s["crack"] += 0.3
        why.append("одиночный удар без пары")
    if dur >= 300:
        s["bump"] += 0.9
        s["broken"] += 0.4
        why.append(f"удар длится {dur:.0f} мс — протяжённая неровность")
    elif 0 < dur < 180:
        s["manhole"] += 0.6
        s["joint"] += 0.4
        s["pothole"] += 0.2
        why.append(f"удар короткий ({dur:.0f} мс)")
    if w.get("w_peaks", 0) >= 5:
        s["rough_patch"] += 1.6
        s["broken"] += 0.8
        why.append(f"{int(w['w_peaks'])} заметных ударов подряд — волнистость или разбитый участок")
    if w.get("w_first_down"):
        s["pothole"] += 0.6
        s["manhole"] += 0.2
        why.append("сначала провал вниз — признак ямы")
    elif w.get("w_peaks", 0) >= 1 and w.get("w_asym", 1) > 1.4:
        s["bump"] += 0.7
        why.append("сначала подброс вверх — признак горки")
    if w.get("w_kurt", 0) > 12:
        s["manhole"] += 0.3
        s["pothole"] += 0.3
    if w.get("w_hf", 0) > 0.5:
        s["rough_patch"] += 0.4
    if 0 < speed < 25 and persistent:
        s["bump"] += 0.5
        why.append("постоянный объект на малой скорости — типично для лежачего")
    # softmax со «спокойной» температурой: правила — мягкая подсказка, а не приговор
    arr = np.array([s[k] for k in CLASSES])
    e = np.exp((arr - arr.max()) / 1.1)
    p = e / e.sum()
    probs = {k: round(float(v), 3) for k, v in zip(CLASSES, p)}
    top = max(probs, key=probs.get)
    return TypeGuess(probs=probs, reasons=why[:6], top=top)


# ───────────────────────── границы уровней по разметке ─────────────────────────
LEVELS = ["light", "mid", "deep", "danger"]


def suggest_level_bounds(pairs: list[tuple[float, str]], current=(5.0, 8.0, 14.0)) -> dict:
    """pairs: [(score, level)] по размеченным ямам. Подбирает три границы (между light|mid, mid|deep, deep|danger), максимизируя долю верных уровней.
    Возвращает предложение и точность до/после; без достаточной разметки — только текущие значения."""
    data = [(s, LEVELS.index(l)) for s, l in pairs if l in LEVELS and s is not None and math.isfinite(s)]
    counts = {l: sum(1 for _, i in data if i == k) for k, l in enumerate(LEVELS)}
    out = dict(n=len(data), counts=counts, current=list(current), suggested=None, acc_current=None, acc_suggested=None)
    if len(data) < 12:
        return out

    def acc(b):
        ok = sum(1 for s, i in data if (0 if s < b[0] else 1 if s < b[1] else 2 if s < b[2] else 3) == i)
        return ok / len(data)

    out["acc_current"] = round(acc(current), 3)
    scores = sorted({round(s, 2) for s, _ in data})
    cand = scores if len(scores) <= 40 else [float(q) for q in np.quantile([s for s, _ in data], np.linspace(0.02, 0.98, 40))]
    best, bacc = tuple(current), acc(current)
    for i, a in enumerate(cand):
        for j in range(i + 1, len(cand)):
            for k in range(j + 1, len(cand)):
                v = acc((a, cand[j], cand[k]))
                if v > bacc + 1e-9:
                    best, bacc = (a, cand[j], cand[k]), v
    out["suggested"] = [round(float(x), 2) for x in best]
    out["acc_suggested"] = round(bacc, 3)
    return out


# ───────────────────────── границы классов ровности по оценкам водителей ─────────────────────────
def suggest_ri_bounds(ratings: dict[str, list[float]], current=(0.03, 0.05, 0.08, 0.13)) -> dict:
    """ratings: {'A': [ri…], … 'E': [ri…]} — индекс ровности участков, которые водители оценили. Границы — на стыке соседних классов
    (середина между медианами; если классы перепутаны — по общей средней). Нужно ≥8 оценок на класс, иначе только текущее."""
    names = ["A", "B", "C", "D", "E"]
    stats = {}
    for n in names:
        v = np.array([x for x in ratings.get(n, []) if x is not None and math.isfinite(x)], float)
        stats[n] = dict(n=int(v.size), median=round(float(np.median(v)), 4) if v.size else None, p25=round(float(np.percentile(v, 25)), 4) if v.size else None,
                        p75=round(float(np.percentile(v, 75)), 4) if v.size else None)
    out = dict(stats=stats, current=list(current), suggested=None, enough=all(stats[n]["n"] >= 8 for n in names))
    meds = [stats[n]["median"] for n in names]
    if out["enough"] and all(m is not None for m in meds):
        if all(meds[i] < meds[i + 1] for i in range(4)):
            out["suggested"] = [round((meds[i] + meds[i + 1]) / 2, 4) for i in range(4)]
        else:  # оценки перепутаны: порядок классов по RI не сохраняется — доверять нельзя
            out["suggested"] = None
            out["warning"] = "оценки водителей не растут вместе с индексом ровности: нужна проверка"
    return out
