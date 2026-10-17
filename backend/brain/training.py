"""Обучение классификатора на разметке. Запускается командой `manage.py train_brain` (ночью / по накоплению ≥ N новых меток).

Проверка честная: «обучились на одних поездках, тест на другой» (GroupKFold по trip_key). sklearn нужен только здесь.
"""
from __future__ import annotations
import pickle
import numpy as np
from django.db import transaction
from .models import Label, AlgoVersion, TrainingRun

FEATURES = ["peak", "score", "ratio", "first", "dur_ms", "energy", "pair", "hf_share", "lat_share", "long_share",
            "gyro_peak", "speed_kmh", "noise"]
ROAD = {"pothole_light", "pothole_mid", "pothole_deep", "bump", "manhole", "rail", "joint"}


def _vec(f: dict):
    return [float(f.get(k, 0) or 0) for k in FEATURES]


def collect():
    X, y, g = [], [], []
    for l in Label.objects.select_related("event").iterator():
        f = l.features or (l.event.features if l.event else {})
        if not f:
            continue
        X.append(_vec(f)); y.append(l.label); g.append(l.trip_key or (str(l.event.trip_id) if l.event else "?"))
    return np.array(X), np.array(y), np.array(g)


@transaction.atomic
def train(min_labels: int = 60) -> TrainingRun:
    from sklearn.ensemble import GradientBoostingClassifier
    from sklearn.model_selection import GroupKFold
    from sklearn.metrics import precision_score, recall_score
    X, y, g = collect()
    run = TrainingRun(n_labels=len(y))
    if len(y) < min_labels or len(set(g)) < 2:
        run.log = f"мало данных: {len(y)} меток, {len(set(g))} поездок — нужно ≥{min_labels} и ≥2 поездки"
        run.save(); return run
    yb = np.array([1 if v in ROAD else 0 for v in y])
    ps, rs = [], []
    for tr, te in GroupKFold(n_splits=min(5, len(set(g)))).split(X, yb, g):
        m = GradientBoostingClassifier(n_estimators=120, max_depth=3, learning_rate=0.08).fit(X[tr], yb[tr])
        pr = m.predict(X[te])
        ps.append(precision_score(yb[te], pr, zero_division=0)); rs.append(recall_score(yb[te], pr, zero_division=0))
    final = GradientBoostingClassifier(n_estimators=120, max_depth=3, learning_rate=0.08).fit(X, yb)
    ver = f"gbm-{AlgoVersion.objects.count() + 1}"
    av = AlgoVersion.objects.create(version=ver, kind="gbm", params={"features": FEATURES},
                                    model_blob=pickle.dumps(final), metrics=dict(precision=float(np.mean(ps)), recall=float(np.mean(rs))))
    run.algo = av; run.metrics = av.metrics; run.log = "ok"; run.save()
    return run
