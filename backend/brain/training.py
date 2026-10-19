"""Обучение классификатора «дорога / не дорога» на разметке и безопасное включение новой версии.

Принципы (HOLESCOPE_V2 §8.4):
 * проверка честная: «обучились на одних поездках, тест на другой» (GroupKFold по trip_key);
 * новая версия включается только если на отложенных поездках она лучше правил (по F1) и данных достаточно;
 * иначе версия сохраняется неактивной с метриками — её видно в админке «Мозг», но решения принимают правила.
sklearn нужен только здесь.
"""
from __future__ import annotations
import json
import pickle
from pathlib import Path
import numpy as np
from django.db import transaction
from .models import AlgoVersion, Label, TrainingRun

FEATURES = ["peak", "score", "ratio", "first", "dur_ms", "energy", "pair", "hf_share", "lat_share", "long_share", "gyro_peak", "speed_kmh", "noise"]
from .taxonomy import ROAD_KEYS

ROAD = set(ROAD_KEYS) | {"rail", "pothole"}  # дорожные метки: всё из справочника, кроме «шум, телефон трогали, бордюр, торможение»
RULE_ROAD_TYPES = {"pothole", "bump", "manhole", "joint"}

MIN_LABELS = 60
MIN_TRIPS = 2
MIN_PER_TRIP = 20
MIN_F1_GAIN = 0.02


def vec(f: dict) -> list[float]:
    out = []
    for k in FEATURES:
        v = f.get(k, 0)
        out.append(float(v) if isinstance(v, (int, float)) and np.isfinite(v) else 0.0)
    return out


def collect():
    """Матрица признаков, метки «дорога(1)/нет(0)», исходные метки, группы (trip_key), типы по правилам."""
    X, y, raw, groups, rule = [], [], [], [], []
    for l in Label.objects.select_related("event").iterator():
        f = l.features or (l.event.features if l.event else {})
        if not f:
            continue
        X.append(vec(f))
        raw.append(l.label)
        y.append(1 if l.label in ROAD else 0)
        groups.append(l.trip_key or (str(l.event.trip_id) if l.event else "?"))
        rule.append(1 if f.get("type", "pothole") in RULE_ROAD_TYPES else 0)
    return np.array(X, float), np.array(y), np.array(raw), np.array(groups), np.array(rule)


def _prf(y, p):
    from sklearn.metrics import f1_score, precision_score, recall_score
    return dict(precision=float(precision_score(y, p, zero_division=0)), recall=float(recall_score(y, p, zero_division=0)), f1=float(f1_score(y, p, zero_division=0)))


def _candidates():
    """Несколько простых моделей: на малой разметке побеждает не всегда сложная. Выбираем по честной проверке."""
    from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler
    return {
        "gbm": lambda: GradientBoostingClassifier(n_estimators=120, max_depth=3, learning_rate=0.08, random_state=0),
        "forest": lambda: RandomForestClassifier(n_estimators=200, max_depth=5, min_samples_leaf=2, class_weight="balanced", random_state=0),
        "logistic": lambda: make_pipeline(StandardScaler(), LogisticRegression(C=0.5, class_weight="balanced", max_iter=500)),
    }


def _importances(model) -> dict:
    """Какие признаки важнее всего для решения (для объяснения в админке)."""
    est = model[-1] if hasattr(model, "steps") else model
    imp = getattr(est, "feature_importances_", None)
    if imp is None:
        imp = np.abs(getattr(est, "coef_", [np.zeros(len(FEATURES))])[0])
    tot = float(np.sum(imp)) or 1.0
    return {k: round(float(v) / tot, 3) for k, v in sorted(zip(FEATURES, imp), key=lambda kv: -kv[1])}


@transaction.atomic
def train(min_labels: int = MIN_LABELS) -> TrainingRun:
    from sklearn.model_selection import GroupKFold
    X, y, raw, g, rule = collect()
    run = TrainingRun(n_labels=len(y))
    trips = {str(k): int((g == k).sum()) for k in set(g)}
    big = [k for k, n in trips.items() if n >= MIN_PER_TRIP]
    info = dict(n_labels=int(len(y)), trips=trips, positives=int(y.sum()), negatives=int((1 - y).sum()))
    if len(y) < min_labels or y.sum() < 10 or (1 - y).sum() < 10:
        run.log = f"мало данных: {len(y)} меток (+{int(y.sum())}/−{int((1 - y).sum())}), нужно ≥{min_labels} и по ≥10 каждого класса"
        run.metrics = info
        run.save()
        return run
    # честная проверка: группы = поездки; если крупных поездок меньше двух — только отчёт по блокам, без включения
    enough_trips = len(big) >= MIN_TRIPS
    folds = min(5, len(set(g))) if enough_trips else 0
    cv_kind = "leave-trip-out" if (enough_trips and folds >= 2) else "blocks-of-one-trip"
    if cv_kind == "leave-trip-out":
        splits = list(GroupKFold(n_splits=folds).split(X, y, g))
    else:  # одна крупная поездка: оценка по 5 блокам подряд (слабее, не годится для включения)
        blocks = np.arange(len(y)) * 5 // len(y)
        splits = [(np.where(blocks != b)[0], np.where(blocks == b)[0]) for b in range(5)]

    def cv_pred(factory):
        pred = np.zeros(len(y), int)
        for tr, te in splits:
            pred[te] = rule[te] if len(set(y[tr])) < 2 else factory().fit(X[tr], y[tr]).predict(X[te])
        return pred
    scored = {name: _prf(y, cv_pred(f)) for name, f in _candidates().items()}
    best = max(scored, key=lambda n: scored[n]["f1"])
    m_new, m_rule = scored[best], _prf(y, rule)
    final = _candidates()[best]().fit(X, y)
    ver = f"gbm-{AlgoVersion.objects.filter(kind='gbm').count() + 1}"
    gain = m_new["f1"] - m_rule["f1"]
    activate = enough_trips and cv_kind == "leave-trip-out" and gain >= MIN_F1_GAIN
    metrics = dict(info, cv=cv_kind, model_kind=best, candidates=scored, importances=_importances(final), model=m_new, rules=m_rule, f1_gain=gain, activated=bool(activate))
    if activate:
        AlgoVersion.objects.filter(active=True, kind="gbm").update(active=False)
    av = AlgoVersion.objects.create(version=ver, kind="gbm", params={"features": FEATURES}, model_blob=pickle.dumps(final), metrics=metrics, active=bool(activate),
                                    notes="включена автоматически: лучше правил на отложенных поездках" if activate else
                                          f"не включена: cv={cv_kind}, прирост F1 {gain:+.3f} (нужно ≥{MIN_F1_GAIN} и ≥{MIN_TRIPS} поездок по ≥{MIN_PER_TRIP} меток)")
    run.algo, run.metrics = av, metrics
    run.log = "ok: версия " + ver + (" ВКЛЮЧЕНА" if activate else " сохранена неактивной")
    run.save()
    return run


# ───────────────────────── импорт разметки ─────────────────────────
def import_labels_json(json_path: str | Path, csv_dir: str | Path | None = None, wheelbase_m: float = 2.485) -> dict:
    """labels_*.json (разметка review.html) → Label. Признаки берём из событий алгоритма, ближайших по времени (±0.6 с)."""
    from holescope_algo.params import Params
    from holescope_algo.pipeline import process_csv
    jp = Path(json_path)
    d = json.loads(jp.read_text(encoding="utf-8"))
    csv_path = Path(csv_dir or jp.parent) / d["file"]
    res = process_csv(str(csv_path), Params(wheelbase_m=wheelbase_m))
    ev = res["events"]
    times = np.array([e["t"] for e in ev]) if ev else np.array([])
    made = skipped = 0
    for lab in d["labels"]:
        if not len(times):
            skipped += 1
            continue
        k = int(np.argmin(np.abs(times - lab["t"])))
        if abs(times[k] - lab["t"]) > 0.6:
            skipped += 1                                         # метка без события алгоритма: признаков нет
            continue
        f = {kk: vv for kk, vv in ev[k].items() if kk != "wave"}
        Label.objects.create(source="import", label=lab["label"], features=_jsonable(f), trip_key=d["file"])
        made += 1
    return dict(file=d["file"], labels=len(d["labels"]), imported=made, skipped=skipped)


def import_taps_csv(csv_path: str | Path, wheelbase_m: float = 2.485, before_s: float = 3.0, after_s: float = 0.5) -> dict:
    """Ручные отметки «яма» из CSV логгера (строки type=k) → Label('pothole') на ближайшем предшествующем событии.
    Уровень ямы неизвестен, поэтому метка общая («pothole»): годится для «дорога/не дорога», не для уровней."""
    import csv as _csv
    from holescope_algo.io import load_csv
    from holescope_algo.params import Params
    from holescope_algo.pipeline import process_csv
    df, _ = load_csv(str(csv_path))
    taps = df[(df["type"] == "k") & (df["label"] == "pothole")]
    res = process_csv(str(csv_path), Params(wheelbase_m=wheelbase_m))
    ev = res["events"]
    t_base = df["t_ms"].min()
    made = 0
    used = set()
    for _, r in taps.iterrows():
        tt = (r["t_ms"] - t_base) / 1000.0
        cand = [(abs(e["t"] - tt), i) for i, e in enumerate(ev) if tt - before_s <= e["t"] <= tt + after_s and i not in used]
        if not cand:
            continue
        i = min(cand)[1]
        used.add(i)
        Label.objects.create(source="import", label="pothole", features=_jsonable({k: v for k, v in ev[i].items() if k != "wave"}), trip_key=Path(csv_path).name)
        made += 1
    return dict(file=Path(csv_path).name, taps=int(len(taps)), imported=made)


def _jsonable(d):
    out = {}
    for k, v in d.items():
        if isinstance(v, (np.floating, float)):
            out[k] = None if not np.isfinite(v) else float(v)
        elif isinstance(v, np.integer):
            out[k] = int(v)
        elif isinstance(v, np.bool_):
            out[k] = bool(v)
        else:
            out[k] = v
    return out


# ───────────────────────── модель «что это» (тип объекта) ─────────────────────────
TYPE_MIN_PER_CLASS = 6
TYPE_MIN_TOTAL = 30
TYPE_MIN_GAIN = 0.05


def type_vec(features: dict, wave, ctx: dict | None) -> list[float]:
    """Признаки события + форма сигнала + контекст объекта для модели типа."""
    from .intelligence import CONTEXT_KEYS, WAVE_KEYS, wave_features
    w = wave_features(wave) if wave else {k: float((features or {}).get(k, 0) or 0) for k in WAVE_KEYS}
    c = ctx or {}
    return vec(features or {}) + [float(w.get(k, 0)) for k in WAVE_KEYS] + [float(c.get(k, 0) or 0) for k in CONTEXT_KEYS]


def type_feature_names() -> list[str]:
    from .intelligence import CONTEXT_KEYS, WAVE_KEYS
    return FEATURES + WAVE_KEYS + CONTEXT_KEYS


def collect_types():
    """Матрица признаков, классы (тип на карте по метке), группы-поездки, подсказки правил (для сравнения)."""
    from . import intelligence, taxonomy
    X, y, groups, rules = [], [], [], []
    ctx_cache: dict = {}
    for l in Label.objects.select_related("event__cluster__segment").iterator():
        e = l.event
        cls = taxonomy.type_for(l.label) if taxonomy.is_road(l.label) else ""
        if not e or not cls or cls not in intelligence.CLASSES:
            continue
        c = e.cluster
        ctx = None
        if c is not None:
            ctx = ctx_cache.get(c.pk) or ctx_cache.setdefault(c.pk, intelligence.context_features(c))
        feats = {**(e.features or {}), "peak": e.peak, "score": e.score, "speed_kmh": e.speed_kmh}
        X.append(type_vec(feats, e.wave, ctx))
        y.append(cls)
        groups.append(str(e.trip_id))
        rules.append(intelligence.guess_type({**feats}, ctx, e.wave).top)
    return np.array(X, float), np.array(y), np.array(groups), np.array(rules)


@transaction.atomic
def train_types() -> TrainingRun:
    """Многоклассовая модель типа объекта. Включается, только если на отложенных поездках лучше правил (macro-F1 ≥ +0.05) и данных достаточно."""
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, f1_score
    from sklearn.model_selection import GroupKFold
    X, y, g, rules = collect_types()
    counts = {k: int((y == k).sum()) for k in sorted(set(y))} if len(y) else {}
    run = TrainingRun(n_labels=len(y))
    usable = [k for k, n in counts.items() if n >= TYPE_MIN_PER_CLASS]
    if len(y) < TYPE_MIN_TOTAL or len(usable) < 2:
        run.log = f"типы: мало данных ({len(y)} меток; по классам {counts}); нужно ≥{TYPE_MIN_TOTAL} и ≥{TYPE_MIN_PER_CLASS} на каждый из двух и более классов"
        run.metrics = dict(kind="types", counts=counts)
        run.save()
        return run
    keep = np.isin(y, usable)
    X, y, g, rules = X[keep], y[keep], g[keep], rules[keep]
    trips = sorted(set(g))
    enough_trips = len(trips) >= 2

    def model():
        return RandomForestClassifier(n_estimators=250, max_depth=6, min_samples_leaf=2, class_weight="balanced", random_state=0)

    pred = np.empty(len(y), dtype=object)
    if enough_trips:
        splits = list(GroupKFold(n_splits=min(5, len(trips))).split(X, y, g))
    else:
        idx = np.arange(len(y)) * 5 // len(y)
        splits = [(np.where(idx != b)[0], np.where(idx == b)[0]) for b in range(5)]
    for tr, te in splits:
        if len(set(y[tr])) < 2:
            pred[te] = rules[te]
            continue
        pred[te] = model().fit(X[tr], y[tr]).predict(X[te])
    m_acc, m_f1 = float(accuracy_score(y, pred)), float(f1_score(y, pred, average="macro", zero_division=0))
    r_acc, r_f1 = float(accuracy_score(y, rules)), float(f1_score(y, rules, average="macro", zero_division=0))
    final = model().fit(X, y)
    n = AlgoVersion.objects.filter(kind="types").count() + 1
    gain = m_f1 - r_f1
    activate = enough_trips and gain >= TYPE_MIN_GAIN
    importances = {k: round(float(v), 3) for k, v in sorted(zip(type_feature_names(), final.feature_importances_), key=lambda kv: -kv[1])[:12]}
    metrics = dict(kind="types", counts=counts, classes=[str(c) for c in final.classes_], cv="leave-trip-out" if enough_trips else "blocks-of-one-trip",
                   model=dict(acc=m_acc, f1=m_f1), rules=dict(acc=r_acc, f1=r_f1), f1_gain=gain, activated=bool(activate), importances=importances)
    if activate:
        AlgoVersion.objects.filter(kind="types", active=True).update(active=False)
    av = AlgoVersion.objects.create(version=f"types-{n}", kind="types", params={"features": type_feature_names()}, model_blob=pickle.dumps(final), metrics=metrics, active=bool(activate),
                                    notes="включена: лучше правил на отложенных поездках" if activate else f"не включена: прирост macro-F1 {gain:+.3f} (нужно ≥{TYPE_MIN_GAIN} и ≥2 поездки)")
    run.algo, run.metrics = av, metrics
    run.log = f"ok: типы, версия {av.version}" + (" ВКЛЮЧЕНА" if activate else " сохранена неактивной")
    run.save()
    return run
