"""Модель «что это»: обучение на размеченных событиях, честная проверка, включение только при приросте над правилами."""
import numpy as np
import pytest
from django.utils import timezone
from brain import inference, training
from brain.models import AlgoVersion, Label
from fleet.models import Device
from telemetry.models import EventCluster, RoadEvent, Trip

pytestmark = pytest.mark.django_db


def wave(kind, rng):
    t = np.arange(120)
    if kind == "manhole":
        w = 9 * np.exp(-((t - 60) / 1.6) ** 2) * np.cos((t - 60) * 1.2)
    elif kind == "bump":
        w = 6 * np.exp(-((t - 55) / 6) ** 2) * np.sin((t - 55) * 0.4) + 5 * np.exp(-((t - 75) / 6) ** 2) * np.sin((t - 75) * 0.4)
    else:  # яма: сначала вниз
        w = -8 * np.exp(-((t - 60) / 3) ** 2) * np.cos((t - 60) * 0.8)
    return list(w + rng.normal(0, 0.25, 120))


LABEL = {"manhole": "manhole", "bump": "bump", "pothole": "pothole_mid"}
FEAT = {"manhole": dict(pair=0.1, dur_ms=120), "bump": dict(pair=0.9, dur_ms=380), "pothole": dict(pair=0.3, dur_ms=200)}


def make(n_per=14, trips=3):
    rng = np.random.default_rng(0)
    dev = Device.objects.create(token="t", nickname="x")
    ts = [Trip.objects.create(device=dev, started_at=timezone.now()) for _ in range(trips)]
    i = 0
    for kind in LABEL:
        for k in range(n_per):
            trip = ts[k % trips]
            cl = EventCluster.objects.create(lat=41.3 + i * 1e-3, lon=69.2, type="pothole")
            feats = {**FEAT[kind], "pair": FEAT[kind]["pair"] + float(rng.normal(0, 0.05))}
            e = RoadEvent.objects.create(trip=trip, device=dev, cluster=cl, t_offset=i, at=timezone.now(), lat=41.3, lon=69.2, speed_kmh=35 + float(rng.normal(0, 4)), peak=8,
                                         score=8 + float(rng.normal(0, 1)), features=feats, wave=wave(kind, rng), algo_version="2.0.0")
            Label.objects.create(event=e, source="admin", label=LABEL[kind], features=e.features, trip_key=str(trip.pk))
            i += 1


def test_too_little_data_is_reported_not_trained():
    run = training.train_types()
    assert "мало данных" in run.log and not AlgoVersion.objects.filter(kind="types").exists()


def test_trains_and_checks_honestly():
    make()
    run = training.train_types()
    m = run.metrics
    assert m["cv"] == "leave-trip-out" and set(m["counts"]) == {"manhole", "bump", "pothole"}
    assert m["model"]["f1"] > 0.85
    assert 0 < len(m["importances"]) <= 12
    av = AlgoVersion.objects.get(kind="types")
    assert av.active == m["activated"]
    if av.active:
        _, model = inference.active_type_model()
        probs = inference.predict_type(model, {**FEAT["manhole"], "peak": 8, "score": 8, "speed_kmh": 35}, wave("manhole", np.random.default_rng(5)), None)
        assert max(probs, key=probs.get) == "manhole"


def test_does_not_deactivate_other_model_kinds():
    make()
    AlgoVersion.objects.create(version="gbm-x", kind="gbm", params={}, active=True)
    AlgoVersion.objects.create(version="rules-x", kind="rules", params={}, active=True)
    training.train_types()
    assert AlgoVersion.objects.filter(kind="gbm", active=True).exists() and AlgoVersion.objects.filter(kind="rules", active=True).exists()
