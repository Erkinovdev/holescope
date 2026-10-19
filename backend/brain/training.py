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
ROAD = {"pothole", "pothole_light", "pothole_mid", "pothole_deep", "bump", "manhole", "rail", "joint"}
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
        AlgoVersion.objects.filter(active=True).update(active=False)
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
