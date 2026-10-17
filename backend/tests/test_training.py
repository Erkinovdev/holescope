"""Этап 3: обучение, безопасное включение версий, переобработка, импорт разметки, отпечаток машины, награды, ночные задачи."""
import numpy as np
import pytest
from django.core.management import call_command
from django.utils import timezone
from brain import awards, inference, training
from brain.models import AlgoVersion, Label, ModelAward
from fleet.models import CarModel, Device, Vehicle
from fleet.fingerprint import suggest_model, update_fingerprint
from telemetry.models import EventCluster, RoadEvent, Trip


def feats(road: bool, rng, rule_type=None):
    base = dict(peak=rng.normal(4.5 if road else 2.2, 0.8), score=rng.normal(4.5 if road else 2.0, 0.8), ratio=rng.normal(8 if road else 3, 1.2), first=int(rng.choice([-1, 1])),
                dur_ms=rng.normal(300 if road else 120, 40), energy=rng.normal(0.6 if road else 0.2, 0.1), pair=rng.normal(0.5, 0.1), hf_share=rng.normal(0.4, 0.1),
                lat_share=rng.normal(0.3, 0.1), long_share=rng.normal(0.4, 0.1), gyro_peak=rng.normal(40, 8), speed_kmh=rng.normal(35, 6), noise=rng.normal(0.6, 0.1))
    base["type"] = rule_type or ("pothole" if road else "noise")
    return base


def make_labels(rng, trips=("trip-a", "trip-b"), per_trip=40, rule_noise=0.0):
    for t in trips:
        for i in range(per_trip):
            road = i % 2 == 0
            # «правила» ошибаются в rule_noise случаев (имитация слабых правил)
            rt = ("pothole" if road else "noise") if rng.random() > rule_noise else ("noise" if road else "pothole")
            Label.objects.create(source="import", label="pothole_light" if road else "noise", features=feats(road, rng, rt), trip_key=t)


@pytest.mark.django_db
def test_train_refuses_with_too_little_data():
    rng = np.random.default_rng(0)
    make_labels(rng, per_trip=10)
    run = training.train()
    assert run.algo is None and "мало данных" in run.log
    assert AlgoVersion.objects.count() == 0


@pytest.mark.django_db
def test_train_activates_only_when_better_than_rules_on_heldout_trips():
    rng = np.random.default_rng(1)
    make_labels(rng, rule_noise=0.3)                                   # правила путаются в 30 % → модель обязана выиграть
    run = training.train()
    av = run.algo
    assert av and av.active and av.metrics["cv"] == "leave-trip-out"
    assert av.metrics["model"]["f1"] > av.metrics["rules"]["f1"] + training.MIN_F1_GAIN
    # вторая версия не включается, если не лучше (метки теперь согласованы с правилами → прироста нет)
    Label.objects.all().delete()
    make_labels(np.random.default_rng(2), rule_noise=0.0)
    run2 = training.train()
    assert run2.algo.active is False and AlgoVersion.objects.filter(active=True).count() == 1
    assert AlgoVersion.objects.get(active=True).pk == av.pk
    assert "не включена" in run2.algo.notes


@pytest.mark.django_db
def test_train_on_single_trip_never_activates():
    make_labels(np.random.default_rng(3), trips=("only",), per_trip=120, rule_noise=0.3)
    run = training.train()
    assert run.algo is not None and run.algo.active is False and run.algo.metrics["cv"] == "blocks-of-one-trip"


@pytest.mark.django_db
def test_reprocess_with_active_model_demotes_noise(db):
    rng = np.random.default_rng(4)
    make_labels(rng, rule_noise=0.3)
    av = training.train().algo
    assert av.active
    dev = Device.objects.create(nickname="d")
    trip = Trip.objects.create(device=dev, started_at=timezone.now())
    cl = EventCluster.objects.create(lat=41.3, lon=69.25, status="candidate")
    f = feats(False, rng)
    f.update(peak=1.9, score=1.9, ratio=2.5)
    e = RoadEvent.objects.create(trip=trip, device=dev, cluster=cl, t_offset=1, at=timezone.now(), lat=41.3, lon=69.25, speed_kmh=30, peak=1.9, score=1.9, features=f, algo_version="2.0.0")
    res = inference.reprocess_events()
    assert res["version"] == av.version and res["updated"] == 1 and res["demoted"] == 1
    e.refresh_from_db(); cl.refresh_from_db()
    assert e.type == "noise" and e.algo_version == av.version and cl.status == "false"
    # без активной модели ничего не меняется
    AlgoVersion.objects.update(active=False)
    assert inference.reprocess_events()["updated"] == 0


@pytest.mark.django_db
def test_import_real_labels_and_taps():
    """Импорт реальной разметки проекта (analysis/*), если файлы на месте."""
    from pathlib import Path
    d = Path(__file__).resolve().parents[2] / "analysis"
    if not (d / "labels_pothole_2026-10-16_18-14-37.json").exists():
        pytest.skip("нет analysis/")
    try:
        r = training.import_labels_json(d / "labels_pothole_2026-10-16_18-14-37.json", d)
    except MemoryError:
        pytest.skip("недостаточно памяти для разбора 20 МБ CSV (занята Docker-ВМ)")
    assert r["labels"] == 91 and r["imported"] + r["skipped"] == 91 and r["imported"] >= 60
    t = training.import_taps_csv(d / "pothole_2026-10-17_12-09-50.csv")
    assert t["taps"] == 8 and 1 <= t["imported"] <= 8
    assert Label.objects.filter(source="import").count() == r["imported"] + t["imported"]
    assert Label.objects.filter(label="pothole_deep").exists()


@pytest.mark.django_db
def test_fingerprint_suggest_needs_many_known_vehicles():
    a, b = CarModel.objects.create(brand="A", model="a"), CarModel.objects.create(brand="B", model="b")
    rng = np.random.default_rng(5)
    for i in range(40):
        cm = a if i % 2 == 0 else b
        v = Vehicle.objects.create(name=f"v{i}", car_model=cm, f_body_median=(1.2 if cm == a else 2.4) + rng.normal(0, 0.05), zeta_median=0.2 + rng.normal(0, 0.01),
                                   softness_score=(70 if cm == a else 30) + rng.normal(0, 2))
        update_fingerprint(v, ri_coef=(-0.3 if cm == a else 0.3) + rng.normal(0, 0.02))
    new = Vehicle.objects.create(name="new", f_body_median=1.21, zeta_median=0.2, softness_score=71)
    update_fingerprint(new, ri_coef=-0.29)
    cm, conf = suggest_model(new, min_known=30)
    assert cm == a and conf == 1.0
    assert suggest_model(new, min_known=100) is None                       # данных мало → не гадаем
    nofp = Vehicle.objects.create(name="empty")
    assert suggest_model(nofp) is None


@pytest.mark.django_db
def test_awards_thresholds():
    big, small = CarModel.objects.create(brand="Big", model="x"), CarModel.objects.create(brand="Small", model="y")
    for i in range(12):
        Vehicle.objects.create(name=f"b{i}", car_model=big, softness_score=60 + i, km_total=50)
    for i in range(5):
        Vehicle.objects.create(name=f"s{i}", car_model=small, softness_score=90, km_total=1000)
    res = awards.compute_awards("week")
    assert [a.car_model for a in res] == [big] and res[0].rank == 1 and res[0].n_vehicles == 12 and res[0].softness_median == pytest.approx(65.5)
    assert ModelAward.objects.count() == 1
    Vehicle.objects.filter(car_model=big).update(km_total=1)               # < 500 км суммарно
    assert awards.compute_awards("week") == []


@pytest.mark.django_db
def test_nightly_and_snapshot_run_clean(capsys):
    call_command("nightly")
    out = capsys.readouterr().out
    assert "заделаны" in out and "snapshot ok" in out and "награды week" in out
