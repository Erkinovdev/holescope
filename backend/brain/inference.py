"""Применение активной версии «мозга» к событиям: вероятность «это дорожное событие» и переобработка старых данных."""
from __future__ import annotations
import pickle
import threading
import numpy as np
from django.db import transaction
from telemetry.models import EventCluster, RoadEvent
from .models import AlgoVersion
from .training import vec

_lock = threading.Lock()
_cache: dict = {}


def active_model():
    """(AlgoVersion, sklearn-модель) активной gbm-версии или (None, None) — тогда работают правила."""
    av = AlgoVersion.objects.filter(active=True, kind="gbm").first()
    if not av or not av.model_blob:
        return None, None
    with _lock:
        if _cache.get("id") != av.pk:
            _cache.clear()
            _cache.update(id=av.pk, model=pickle.loads(bytes(av.model_blob)))
        return av, _cache["model"]


def road_probability(model, features: dict) -> float:
    return float(model.predict_proba(np.array([vec(features)]))[0][1])


@transaction.atomic
def reprocess_events(limit: int | None = None) -> dict:
    """Переобработка старых событий активной версией: обновляет confidence и algo_version, шумовые события отвязывает от кластеров.
    Если активной модели нет — ничего не меняет."""
    av, model = active_model()
    if model is None:
        return dict(version=None, updated=0, demoted=0)
    qs = RoadEvent.objects.exclude(algo_version=av.version).select_related("cluster")
    if limit:
        qs = qs[:limit]
    upd = dem = 0
    clusters = set()
    for e in qs:
        p = road_probability(model, {**(e.features or {}), "peak": e.peak, "score": e.score, "speed_kmh": e.speed_kmh})
        e.confidence = round(p, 3)
        e.algo_version = av.version
        if p < 0.2 and e.type != "noise":
            e.type = "noise"
            dem += 1
            if e.cluster_id:
                clusters.add(e.cluster_id)
        e.save(update_fields=["confidence", "algo_version", "type"])
        upd += 1
    for cid in clusters:
        c = EventCluster.objects.get(pk=cid)
        real = c.events.exclude(type="noise")
        if not real.exists() and c.status in ("candidate", "confirmed"):
            c.status = "false"
            c.save(update_fields=["status"])
    return dict(version=av.version, updated=upd, demoted=dem)
