"""Догадка «что это было» для каждого события: вероятности по всем вариантам справочника, с причинами.

Прозрачная модель: разумные правила + порядковая кривая уровня ямы по силе удара, которая подстраивается под разметку.
Пока меток мало, параметры ближе к значениям по умолчанию (подобранным по первым 50 размеченным событиям); с ростом разметки они смещаются к данным.
Те же правила работают в приложении (Dart, `app/lib/algo/event_guess.dart`): параметры приложению отдаёт сервер, совпадение проверяется общими примерами.
"""
from __future__ import annotations
import math
from dataclasses import dataclass, field

# значения по умолчанию: уровни по силе удара (score с поправкой на скорость). По данным: лёгкая ≈2.6, средняя ≈3.3, глубокая ≈4.3, опасная — выше ≈6.5
DEFAULTS = dict(
    level_theta=[2.9, 3.9, 6.5],   # границы light|mid, mid|deep, deep|danger
    level_tau=0.9,                 # размытость границ (σ нормальной кривой): чем больше, тем осторожнее
    notroad_prior=0.12,            # доля «не дорога» среди срабатываний
    version="guess-0",
)

ROAD_TYPES = ["pothole", "bump", "manhole", "rail_tram", "rail_train", "joint", "washboard", "patch", "crack", "broken"]
MIN_P = 0.03  # варианты ниже этой вероятности в опроснике не показываем


def _sig(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, x))))


def erf(x: float) -> float:
    """erf по формуле Абрамовица–Стегуна 7.1.26 (погрешность ≈1.5e-7). Та же формула в приложении, чтобы результаты совпадали."""
    s = 1.0 if x >= 0 else -1.0
    x = abs(x)
    t = 1.0 / (1.0 + 0.3275911 * x)
    y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x)
    return s * y


def _cdf(x: float) -> float:
    return 0.5 * (1.0 + erf(x / math.sqrt(2.0)))


def _softmax(d: dict[str, float]) -> dict[str, float]:
    m = max(d.values())
    e = {k: math.exp(v - m) for k, v in d.items()}
    s = sum(e.values())
    return {k: v / s for k, v in e.items()}


@dataclass
class Guess:
    probs: dict[str, float]
    reasons: list[str] = field(default_factory=list)
    top: str = ""

    def ranked(self, n: int | None = None) -> list[tuple[str, float]]:
        r = sorted(self.probs.items(), key=lambda kv: -kv[1])
        return r[:n] if n else r

    @property
    def confidence(self) -> float:
        return self.probs.get(self.top, 0.0)


def level_probs(score: float, theta, tau: float) -> dict[str, float]:
    """Порядковая модель уровня с нормальными хвостами: P(≤k) = Φ((θk − s)/τ). Слабый удар почти не оставляет шансов глубокой яме, сильный — мелкой."""
    c = [_cdf((t - score) / tau) for t in theta]
    return {"light": c[0], "mid": c[1] - c[0], "deep": c[2] - c[1], "danger": 1.0 - c[2]}


def guess_event(f: dict, ctx: dict | None = None, params: dict | None = None) -> Guess:
    """f: score, speed_kmh, dur_ms, pair, gyro_peak, hf_share, peak, (loc_hits). ctx: near_type/near_passes (известный объект рядом), tram, crossing, bridge."""
    p = {**DEFAULTS, **(params or {})}
    c = ctx or {}
    score = float(f.get("score") or 0)
    v = float(f.get("speed_kmh") or 0)
    dur = float(f.get("dur_ms") or 0)
    pair = float(f.get("pair") or 0)
    gyro = float(f.get("gyro_peak") or 0)
    hf = float(f.get("hf_share") or 0)
    hits = float(f.get("loc_hits") or 0)
    why: list[str] = []

    # 1) не дорога: телефон тронули (сильный поворот без пары), очень короткий одиночный стук
    z = math.log(p["notroad_prior"] / (1 - p["notroad_prior"]))
    if gyro > 80 and pair < 0.5:
        z += 1.8
        why.append("сильный поворот телефона — похоже, его задели рукой")
    if 0 < dur < 250 and pair < 0.25:
        z += 0.8
    if hf > 0.55:
        z += 0.4
    if score < 2.0:
        z += 0.5
        why.append("слабый удар — почти шум дороги")
    p_notroad = _sig(z)

    # 2) тип объекта
    t = {k: 0.0 for k in ROAD_TYPES}
    t["pothole"] = 3.3  # в городе до трёх четвертей срабатываний — ямы (по первым данным 41 из 44 дорожных)
    near = c.get("near_type")
    npass = float(c.get("near_passes") or 0)
    if v and v < 28 and (dur > 450 or score > 4.5):
        t["bump"] += 1.8
        why.append(f"удар на малой скорости ({v:.0f} км/ч), долгий — вероятен лежачий")
    if v and v < 20:
        t["bump"] += 1.0
    if dur and dur < 300 and pair < 0.4 and score < 4.5:
        t["manhole"] += 0.7
    if c.get("tram") and pair > 0.4:
        t["rail_tram"] += 2.2
        why.append("рядом трамвайные пути")
    if c.get("crossing"):
        t["rail_train"] += 2.4
        why.append("рядом железнодорожный переезд")
    if c.get("bridge") and dur < 400:
        t["joint"] += 1.8
        why.append("мост или тоннель — вероятен шов")
    if hits >= 5 and hf > 0.35:
        t["washboard"] += 1.8
        t["broken"] += 0.8
        why.append("много ударов подряд — волнистость или разбитый участок")
    if near in t and npass >= 2:
        t[near] += 2.0 + min(npass, 8) * 0.25
        why.append(f"здесь уже известен объект «{near}» ({int(npass)} проездов)")
    tp = _softmax(t)

    # 3) уровни и детали
    lv = level_probs(score, p["level_theta"], p["level_tau"])
    if v and v < 20:  # на малой скорости удар слабее, чем сказал бы тот же объект на ходу — не занижаем
        lv = level_probs(score + 0.5, p["level_theta"], p["level_tau"])
    road = 1.0 - p_notroad
    probs: dict[str, float] = {}
    for lvl, pr in lv.items():
        probs[f"pothole_{lvl}"] = road * tp["pothole"] * pr
    b = tp["bump"]
    bl = _softmax({"low": 0.0 if score >= 3 else 0.8, "mid": 0.6, "high": 0.2 + 0.25 * max(0.0, score - 5)})
    probs["bump_low"], probs["bump"], probs["bump_high"] = road * b * bl["low"], road * b * bl["mid"], road * b * bl["high"]
    m = tp["manhole"]
    probs["manhole"], probs["manhole_sunk"], probs["manhole_raised"] = road * m * 0.70, road * m * 0.15, road * m * 0.15
    probs["rail_tram"], probs["rail_train"], probs["joint"] = road * tp["rail_tram"], road * tp["rail_train"], road * tp["joint"]
    probs["washboard"], probs["patch"], probs["crack"], probs["broken"] = road * tp["washboard"], road * tp["patch"] * 0.5, road * tp["crack"] * 0.5, road * tp["broken"]
    # не дорога: «ложное срабатывание» (телефон) и «ничего особенного»
    probs["handled"] = p_notroad * (0.65 if gyro > 60 else 0.4)
    probs["noise"] = p_notroad - probs["handled"]
    s = sum(probs.values())
    probs = {k: round(v / s, 4) for k, v in probs.items()}
    top = max(probs, key=probs.get)
    return Guess(probs=probs, reasons=why[:5], top=top)


def options_for(g: Guess, taxonomy_keys: list[str], limit: int = 6, min_p: float = MIN_P) -> list[str]:
    """Какие варианты показать водителю: правдоподобные по этому удару, по убыванию вероятности (минимум 3, максимум [limit])."""
    ranked = [k for k, _ in g.ranked() if k in taxonomy_keys]
    keep = [k for k in ranked if g.probs[k] >= min_p][:limit]
    for k in ranked:
        if len(keep) >= 3 or g.probs[k] < 0.005:
            break
        if k not in keep:
            keep.append(k)
    # соседние уровни ямы всегда доступны: водитель может поправить догадку на один уровень (но не на два)
    levels = ["pothole_light", "pothole_mid", "pothole_deep", "pothole_danger"]
    top_lv = next((k for k in keep if k in levels), None)
    if top_lv:
        i = levels.index(top_lv)
        for j in (i - 1, i + 1):
            if 0 <= j < 4 and levels[j] not in keep and levels[j] in taxonomy_keys:
                keep.append(levels[j])
    if "handled" not in keep:
        keep.append("handled")  # «ложное срабатывание» всегда доступно
    return keep


# ───────────────────────── подгонка и оценка по разметке ─────────────────────────
LEVEL_OF = {"pothole_light": 0, "pothole_mid": 1, "pothole_deep": 2, "pothole_danger": 3}


def fit_level_params(scores_levels: list[tuple[float, int]], prior=DEFAULTS, shrink: float = 40.0) -> dict:
    """Подбор границ θ и размытости τ по размеченным ямам с «усадкой» к значениям по умолчанию: чем меньше меток, тем ближе к ним."""
    n = len(scores_levels)
    if n < 15:
        return dict(level_theta=list(prior["level_theta"]), level_tau=prior["level_tau"], n=n, fitted=False)
    import numpy as np

    def nll(theta, tau):
        tot = 0.0
        for s, k in scores_levels:
            pr = level_probs(s, theta, tau)[["light", "mid", "deep", "danger"][k]]
            tot -= math.log(max(pr, 1e-4))
        return tot

    base = np.array(prior["level_theta"], float)
    best, bt = (list(base), prior["level_tau"]), nll(base, prior["level_tau"])
    grid = np.linspace(-1.0, 1.5, 11)
    for d1 in grid:
        for d2 in grid:
            th = [base[0] + d1, base[1] + d2, base[2] + (d1 + d2) / 2]
            if not (th[0] < th[1] < th[2]):
                continue
            for tau in (0.5, 0.7, 0.9, 1.2, 1.6):
                v = nll(th, tau)
                if v < bt - 1e-9:
                    best, bt = (th, tau), v
    w = n / (n + shrink)
    theta = [float(w * b + (1 - w) * d) for b, d in zip(best[0], base)]
    tau = float(w * best[1] + (1 - w) * prior["level_tau"])
    return dict(level_theta=[round(x, 3) for x in theta], level_tau=round(tau, 3), n=n, fitted=True, weight=round(w, 2))


def _speed_bin(v: float) -> str:
    return "<20" if v < 20 else "20–40" if v < 40 else "40–60" if v < 60 else "60+"


def _score_bin(x: float) -> str:
    return "<2.5" if x < 2.5 else "2.5–3.5" if x < 3.5 else "3.5–5" if x < 5 else "5+"


def evaluate(rows: list[dict], folds: int = 5, params: dict | None = None) -> dict:
    """Честная оценка догадки на размеченных событиях. rows: [{truth, f, ctx, group}]. Параметры уровней подбираются на обучающей части и проверяются на отложенной
    (части — по поездкам, если их ≥2, иначе подряд). Возвращает точность top-1/top-3, log-loss, сравнение с «всегда самое частое» и разбивки."""
    n = len(rows)
    out = dict(n=n)
    if n < 8:
        return out
    groups = sorted({r.get("group", 0) for r in rows}, key=str)
    if len(groups) >= 2:
        k = min(folds, len(groups))
        gid = {g: i % k for i, g in enumerate(groups)}
        fold_of = [gid[r.get("group", 0)] for r in rows]
    else:
        k = min(folds, max(2, n // 6))
        fold_of = [i * k // n for i in range(n)]
    base_params = {**DEFAULTS, **(params or {})}
    preds: list[Guess | None] = [None] * n
    preds_default: list[Guess | None] = [None] * n
    for fold in range(k):
        train = [(float(r["f"].get("score") or 0), LEVEL_OF[r["truth"]]) for i, r in enumerate(rows) if fold_of[i] != fold and r["truth"] in LEVEL_OF]
        fp = fit_level_params(train, base_params)
        for i, r in enumerate(rows):
            if fold_of[i] == fold:
                preds[i] = guess_event(r["f"], r.get("ctx"), {**base_params, **fp})
                preds_default[i] = guess_event(r["f"], r.get("ctx"), base_params)
    truth = [r["truth"] for r in rows]

    def metrics(ps):
        top1 = sum(1 for p, t in zip(ps, truth) if p.top == t) / n
        top3 = sum(1 for p, t in zip(ps, truth) if t in [k_ for k_, _ in p.ranked(3)]) / n
        ll = -sum(math.log(max(p.probs.get(t, 0.0), 1e-3)) for p, t in zip(ps, truth)) / n
        brier = sum(sum((p.probs.get(k_, 0.0) - (1.0 if k_ == t else 0.0)) ** 2 for k_ in p.probs) for p, t in zip(ps, truth)) / n
        return dict(top1=round(top1, 3), top3=round(top3, 3), logloss=round(ll, 3), brier=round(brier, 3))

    from collections import Counter
    major, cnt = Counter(truth).most_common(1)[0]
    out["majority"] = dict(label=major, acc=round(cnt / n, 3))
    out["guess"] = metrics(preds)
    out["guess_default_params"] = metrics(preds_default)
    # «дорога / не дорога» и «уровень» отдельно
    isroad = lambda t: t not in ("noise", "handled")
    road_ok = sum(1 for p, t in zip(preds, truth) if isroad(p.top) == isroad(t)) / n
    lvl_rows = [(p, t) for p, t in zip(preds, truth) if t in LEVEL_OF]
    lvl_ok = sum(1 for p, t in lvl_rows if p.top == t) / len(lvl_rows) if lvl_rows else None
    lvl_near = sum(1 for p, t in lvl_rows if p.top in LEVEL_OF and abs(LEVEL_OF[p.top] - LEVEL_OF[t]) <= 1) / len(lvl_rows) if lvl_rows else None
    out["road_vs_not"] = round(road_ok, 3)
    out["level"] = dict(n=len(lvl_rows), exact=None if lvl_ok is None else round(lvl_ok, 3), within_one=None if lvl_near is None else round(lvl_near, 3))
    out["by_label"] = {t: dict(n=c, top1=round(sum(1 for p, tt in zip(preds, truth) if tt == t and p.top == tt) / c, 3), mean_p=round(sum(p.probs.get(t, 0.0) for p, tt in zip(preds, truth) if tt == t) / c, 3))
                       for t, c in Counter(truth).items()}

    def split(binf, keyf):
        bins: dict[str, list[int]] = {}
        for i, r in enumerate(rows):
            bins.setdefault(binf(keyf(r)), []).append(i)
        return {b: dict(n=len(ix), top1=round(sum(1 for i in ix if preds[i].top == truth[i]) / len(ix), 3)) for b, ix in sorted(bins.items())}
    out["by_speed"] = split(_speed_bin, lambda r: float(r["f"].get("speed_kmh") or 0))
    out["by_score"] = split(_score_bin, lambda r: float(r["f"].get("score") or 0))
    # калибровка: средняя уверенность против доли верных
    conf = [(p.confidence, 1.0 if p.top == t else 0.0) for p, t in zip(preds, truth)]
    out["calibration"] = dict(mean_confidence=round(sum(c for c, _ in conf) / n, 3), accuracy=round(sum(a for _, a in conf) / n, 3))
    return out


# ───────────────────────── подключение к базе ─────────────────────────
def active_params() -> dict:
    """Параметры догадки: подобранные по разметке (активная версия «guess») или по умолчанию."""
    from .models import AlgoVersion
    av = AlgoVersion.objects.filter(active=True, kind="guess").first()
    return {**DEFAULTS, **(av.params or {}), "version": av.version} if av else dict(DEFAULTS)


def context_of(cluster) -> dict:
    """Контекст объекта для догадки: известный объект рядом (если там уже ≥2 проезда) и особенности дороги."""
    if cluster is None:
        return {}
    seg = cluster.segment
    return dict(near_type=cluster.type if cluster.passes >= 2 else None, near_passes=cluster.passes,
                tram=bool(seg and seg.tram), crossing=bool(seg and seg.level_crossing), bridge=bool(seg and (seg.bridge or seg.tunnel)))


def event_features(e) -> dict:
    f = dict(e.features or {})
    f.update(score=e.score, speed_kmh=e.speed_kmh, peak=e.peak)
    return f


def guess_for_event(e, params: dict | None = None) -> dict:
    p = params or active_params()
    g = guess_event(event_features(e), context_of(e.cluster), p)
    return dict(v=p.get("version", "guess-0"), top=g.top, probs=g.probs, reasons=g.reasons)


def labeled_rows() -> list[dict]:
    """Размеченные события: [{truth, f, ctx, group, event_id, at}] — последняя метка события считается истиной."""
    from .models import Label
    last: dict[int, tuple] = {}
    for l in Label.objects.exclude(event=None).select_related("event__cluster__segment").order_by("created"):
        last[l.event_id] = (l.label, l.event, l.source, l.created)
    from . import taxonomy
    rows = []
    for eid, (lab, e, src, created) in last.items():
        truth = taxonomy.norm(lab)
        rows.append(dict(truth=truth, f=event_features(e), ctx=context_of(e.cluster), group=e.trip_id, event_id=eid, at=e.at, source=src, labeled_at=created,
                         stored=(e.guess or {}).get("top"), stored_p=((e.guess or {}).get("probs") or {}).get(truth), speed=e.speed_kmh, score=e.score,
                         road_class=(e.cluster.segment.road.road_class if e.cluster and e.cluster.segment_id else None), vehicle=(e.device.vehicle.name if e.device_id and getattr(e.device, "vehicle", None) else None)))
    return rows


def train_guess():
    """Подгонка границ уровней по разметке; новая версия включается, только если на отложенных поездках точнее параметров по умолчанию (log-loss)."""
    from .models import AlgoVersion, TrainingRun
    rows = labeled_rows()
    lv = [(float(r["f"].get("score") or 0), LEVEL_OF[r["truth"]]) for r in rows if r["truth"] in LEVEL_OF]
    fit = fit_level_params(lv)
    res = evaluate(rows)
    run = TrainingRun(n_labels=len(rows))
    if not fit.get("fitted") or not res.get("guess"):
        run.log = f"догадка: мало данных ({len(rows)} меток, из них ям с уровнем {len(lv)}); нужно ≥15 ям с уровнем"
        run.metrics = dict(kind="guess", n=len(rows))
        run.save()
        return run
    better = res["guess"]["logloss"] < res["guess_default_params"]["logloss"] - 0.01
    n = AlgoVersion.objects.filter(kind="guess").count() + 1
    if better:
        AlgoVersion.objects.filter(kind="guess", active=True).update(active=False)
    av = AlgoVersion.objects.create(version=f"guess-{n}", kind="guess", params={k: fit[k] for k in ("level_theta", "level_tau")}, metrics=dict(kind="guess", fit=fit, eval=res, activated=better),
                                    active=better, notes="включена: log-loss на отложенных поездках лучше" if better else "не включена: не лучше параметров по умолчанию на отложенных поездках")
    run.algo, run.metrics = av, av.metrics
    run.log = f"ok: догадка {av.version} " + ("ВКЛЮЧЕНА" if better else "сохранена неактивной")
    run.save()
    return run
