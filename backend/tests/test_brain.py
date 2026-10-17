"""Этап 3: приём поездки с привязкой к дороге, антиспам, «заделана», калибровка, относительная подвеска."""
import math
import uuid
from datetime import timedelta
import pytest
from django.utils import timezone
from brain import road_stats, services, validation
from brain.models import Label
from fleet.models import CarModel, Device, Vehicle
from roadnet.builder import build_network
from roadnet.geo import K
from roadnet.matching import reset_index
from roadnet.models import Segment
from telemetry.models import EventCluster, QuietPass, RoadEvent, SegmentScore, Trip

LAT0, LON0 = 41.30, 69.250


def dlon(m, lat=LAT0):
    return m / (K * math.cos(math.radians(lat)))


def square(a, b, c, d):
    return {"type": "MultiPolygon", "coordinates": [[[[b, a], [d, a], [d, c], [b, c], [b, a]]]]}


@pytest.fixture
def network(db):
    """Улица 500 м с востока на запад (двусторонняя), внутри города и района."""
    data = dict(
        areas=[{"id": 1, "name": "Toshkent", "name_ru": "Ташкент", "name_uz": "Toshkent", "admin_level": "4", "geometry": square(41.29, 69.24, 41.31, 69.27)},
               {"id": 2, "name": "Yunusobod Tumani", "name_ru": "Юнусабадский район", "name_uz": None, "admin_level": "6", "geometry": square(41.29, 69.24, 41.31, 69.26)}],
        ways=[{"id": 11, "pts": [(LAT0, LON0), (LAT0, LON0 + dlon(500))], "tags": {"highway": "primary", "name": "Улица Тест", "name:ru": "Улица Тест"}}],
        tram=[], crossings=[])
    build_network(data, log=lambda *_: None)
    reset_index()
    return data


def mk_device(**kw):
    return Device.objects.create(nickname=kw.pop("nickname", "d"), **kw)


def seg_rows(start_m, n, speed=40.0, ri=0.03, lat=LAT0 + 2 / K, t0=0.0):
    """n сегментов по 50 м вдоль улицы на восток, начиная с start_m."""
    return [dict(lat_a=lat, lon_a=LON0 + dlon(start_m + 50 * i), lat_b=lat, lon_b=LON0 + dlon(start_m + 50 * (i + 1)), speed_kmh=speed, ri=ri, cls="B", t0=t0 + i * 4)
            for i in range(n)]


def ev(at_m, t=10.0, lat=LAT0 + 2 / K, score=4.0, speed=40.0, **kw):
    d = dict(t=t, lat=lat, lon=LON0 + dlon(at_m), heading=90.0, speed_kmh=speed, peak=score, score=score, type="pothole", level="mid", confidence=0.5,
             wave=[0.1, 0.4], safe_speed_kmh=30, low_conf=False, algo_version="2.0.0")
    d.update(kw)
    return d


def payload(events=(), segments=(), started=None, **kw):
    d = dict(started_at=(started or timezone.now() - timedelta(hours=1)).isoformat(), duration_s=600, distance_km=5.0, algo_version="2.0.0",
             events=list(events), segments=list(segments), suspension={}, damping={})
    d.update(kw)
    return d


# ───────────────────────── привязка к дороге ─────────────────────────
@pytest.mark.django_db
def test_ingest_snaps_events_and_segments_and_aggregates(network):
    dev = mk_device()
    trip = services.ingest_trip(dev, payload([ev(120)], seg_rows(0, 8, ri=0.04)))
    cl = EventCluster.objects.get()
    assert cl.segment is not None and cl.segment.road.name_ru == "Улица Тест" and cl.segment.direction == 1
    assert SegmentScore.objects.filter(segment__isnull=False).count() == 8
    seg = Segment.objects.filter(direction=1).order_by("index").first()
    assert seg.ri_median == pytest.approx(0.04) and seg.ri_n == 1 and seg.ri_devices == 1 and seg.cls == "B"
    # встречное направление не затронуто
    assert Segment.objects.filter(direction=-1, ri_n__gt=0).count() == 0
    assert trip.events.count() == 1


@pytest.mark.django_db
def test_segment_class_uses_fixed_bounds(network):
    dev = mk_device()
    services.ingest_trip(dev, payload(segments=seg_rows(0, 1, ri=0.15)))
    assert Segment.objects.filter(direction=1).order_by("index").first().cls == "E"


@pytest.mark.django_db
def test_not_car_trip_stored_but_not_mapped(network):
    dev = mk_device()
    t = services.ingest_trip(dev, payload([ev(100)], seg_rows(0, 4), mode="bus_or_tram"))
    assert Trip.objects.count() == 1 and t.mode == "bus_or_tram"
    assert RoadEvent.objects.count() == 0 and EventCluster.objects.count() == 0 and SegmentScore.objects.count() == 0


# ───────────────────────── идемпотентность и антиспам ─────────────────────────
@pytest.mark.django_db
def test_client_id_makes_upload_idempotent(network):
    dev = mk_device()
    p = payload([ev(100)], client_id="abc-1")
    a = services.ingest_trip(dev, p)
    b = services.ingest_trip(dev, p)
    assert a.pk == b.pk and b.duplicate is True and Trip.objects.count() == 1 and RoadEvent.objects.count() == 1
    assert services.ingest_trip(mk_device(nickname="other"), p).pk != a.pk       # у другого устройства — своя поездка


@pytest.mark.django_db
@pytest.mark.parametrize("mut,reason", [
    (dict(started_at=(timezone.now() + timedelta(days=2)).isoformat()), "future"),
    (dict(started_at=(timezone.now() - timedelta(days=90)).isoformat()), "too old"),
    (dict(duration_s=3600, distance_km=900), "too long"),
    (dict(duration_s=600, distance_km=100), "average speed"),
    (dict(events=[ev(i) for i in range(2500)]), "too many events"),
    (dict(duration_s=-5), "bad duration"),
])
def test_validation_rejects(db, mut, reason):
    dev = mk_device()
    p = payload()
    p.update(mut)
    with pytest.raises(validation.Rejected):
        services.ingest_trip(dev, p)
    assert Trip.objects.count() == 0, reason


@pytest.mark.django_db
def test_validation_drops_bad_events_keeps_good(network):
    dev = mk_device()
    bad = [ev(100, lat=0.0), ev(110, speed=400.0), dict(t="x"), ev(120, score=float("nan"))]
    services.ingest_trip(dev, payload([ev(130)] + bad))
    assert RoadEvent.objects.count() == 1


@pytest.mark.django_db
def test_too_dense_events_rejected_and_blocked_device(network):
    dev = mk_device()
    with pytest.raises(validation.Rejected):
        services.ingest_trip(dev, payload([ev(i * 2.0, t=i) for i in range(300)], distance_km=2.0))
    dev.blocked = True
    dev.save()
    with pytest.raises(validation.Rejected) as e:
        services.ingest_trip(dev, payload())
    assert e.value.status == 403


@pytest.mark.django_db
def test_daily_trip_limit(network, settings):
    settings.HOLESCOPE = {**settings.HOLESCOPE, "LIMITS": {"max_trips_per_day": 3}}
    dev = mk_device()
    for i in range(3):
        services.ingest_trip(dev, payload(client_id=f"c{i}"))
    with pytest.raises(validation.Rejected) as e:
        services.ingest_trip(dev, payload(client_id="c4"))
    assert e.value.status == 429


@pytest.mark.django_db
def test_low_trust_device_does_not_confirm(network):
    a, b = mk_device(nickname="a"), mk_device(nickname="b", trust=0.1)
    services.ingest_trip(a, payload([ev(100)]))
    services.ingest_trip(b, payload([ev(100)]))
    cl = EventCluster.objects.get()
    assert cl.passes == 2 and cl.devices == 1 and cl.status == "candidate"        # недоверенное устройство не подтверждает


@pytest.mark.django_db
def test_trust_changes():
    d = mk_device(trust=0.5)
    validation.adjust_trust(d, True)
    assert d.trust > 0.5
    validation.adjust_trust(d, False)
    assert d.trust < 0.51


# ───────────────────────── «заделана» ─────────────────────────
def _confirm_pothole(network):
    """Яма в 200 м: два устройства подтвердили 3 дня назад."""
    t0 = timezone.now() - timedelta(days=3)
    a, b = mk_device(nickname="a"), mk_device(nickname="b")
    services.ingest_trip(a, payload([ev(200)], started=t0))
    services.ingest_trip(b, payload([ev(200)], started=t0 + timedelta(hours=1)))
    cl = EventCluster.objects.get()
    assert cl.status == "confirmed" and cl.passes == 2
    return cl


@pytest.mark.django_db
def test_quiet_passes_mark_pothole_fixed(network):
    cl = _confirm_pothole(network)
    t1 = timezone.now() - timedelta(days=1)
    devs = [mk_device(nickname=f"q{i}") for i in range(3)]
    # проезжают то же место на 40 км/ч БЕЗ ударов
    for i, d in enumerate(devs):
        services.ingest_trip(d, payload(segments=seg_rows(150, 4), started=t1 + timedelta(hours=i)))
    cl.refresh_from_db()
    assert QuietPass.objects.filter(cluster=cl).count() == 3
    assert cl.status == "fixed" and cl.fixed_at is not None and cl.quiet_passes == 3


@pytest.mark.django_db
def test_not_fixed_by_one_device_or_slow_pass_or_too_early(network):
    cl = _confirm_pothole(network)
    t1 = timezone.now() - timedelta(days=1)
    one = mk_device(nickname="one")
    for i in range(4):                                                                 # много проездов, но одно устройство
        services.ingest_trip(one, payload(segments=seg_rows(150, 4), started=t1 + timedelta(hours=i), client_id=f"x{i}"))
    cl.refresh_from_db()
    assert cl.status == "confirmed"
    slow = mk_device(nickname="slow")
    services.ingest_trip(slow, payload(segments=seg_rows(150, 4, speed=8.0), started=t1))     # 8 км/ч: яму не видно → не считается
    assert QuietPass.objects.filter(cluster=cl, device=slow).count() == 0


@pytest.mark.django_db
def test_other_direction_and_far_pass_do_not_count(network):
    cl = _confirm_pothole(network)
    d = mk_device(nickname="far")
    services.ingest_trip(d, payload(segments=seg_rows(150, 4, lat=LAT0 + 40 / K), started=timezone.now() - timedelta(hours=2)))   # в 40 м от ямы
    assert QuietPass.objects.filter(cluster=cl).count() == 0


@pytest.mark.django_db
def test_new_hit_reopens_fixed(network):
    cl = _confirm_pothole(network)
    EventCluster.objects.filter(pk=cl.pk).update(status="fixed", fixed_at=timezone.now())
    services.ingest_trip(mk_device(nickname="again"), payload([ev(200)]))
    cl.refresh_from_db()
    assert cl.status in ("candidate", "confirmed") and cl.fixed_at is None


@pytest.mark.django_db
def test_encounter_with_event_is_not_quiet(network):
    cl = _confirm_pothole(network)
    d = mk_device(nickname="hit")
    services.ingest_trip(d, payload([ev(200)], seg_rows(150, 4), started=timezone.now() - timedelta(hours=5)))
    assert QuietPass.objects.filter(cluster=cl, device=d).count() == 0


# ───────────────────────── типы и калибровка ─────────────────────────
@pytest.mark.django_db
def test_cluster_type_from_driver_votes(network):
    services.ingest_trip(mk_device(), payload([ev(100)]))
    cl = EventCluster.objects.get()
    for _ in range(2):
        road_stats.refine_cluster_type(cl, "manhole")
    cl.refresh_from_db()
    assert cl.type == "pothole"                      # 2 голоса мало
    road_stats.refine_cluster_type(cl, "manhole")
    cl.refresh_from_db()
    assert cl.type == "manhole" and cl.type_votes == {"manhole": 3}


@pytest.mark.django_db
def test_device_calibration_from_landmarks(network):
    ref, hot = mk_device(nickname="ref"), mk_device(nickname="hot")
    t0 = timezone.now() - timedelta(days=2)
    for k in range(10):                                                        # 10 люков: «hot» чувствительнее вдвое
        m = 20 + k * 40
        services.ingest_trip(ref, payload([ev(m, score=4.0)], started=t0, client_id=f"r{k}"))
        services.ingest_trip(hot, payload([ev(m, score=8.0)], started=t0, client_id=f"h{k}"))
    EventCluster.objects.update(type="manhole")
    assert road_stats.update_calibration(ref, min_events=8) == pytest.approx(0.7 * 1 + 0.3 * 2.0, abs=0.01)
    g = road_stats.update_calibration(hot, min_events=8)
    assert g == pytest.approx(0.7 * 1 + 0.3 * 0.5, abs=0.01)                  # сильнее эталона → коэффициент < 1
    hot.refresh_from_db()
    assert hot.calib_n >= 8
    # применяется к новым событиям, исходная сила сохраняется в признаках
    services.ingest_trip(hot, payload([ev(450, score=8.0)], client_id="new"))
    e = RoadEvent.objects.filter(device=hot).order_by("-id").first()
    assert e.score == pytest.approx(8.0 * hot.calib_gain, abs=0.01) and e.features["score_raw"] == 8.0


@pytest.mark.django_db
def test_calibration_needs_enough_landmarks(network):
    d = mk_device()
    assert road_stats.update_calibration(d) is None


# ───────────────────────── относительная подвеска ─────────────────────────
@pytest.mark.django_db
def test_relative_suspension_softer_than_fleet(network):
    cm = CarModel.objects.create(brand="Test", model="Soft")
    vehicles = [Vehicle.objects.create(name=f"v{i}", car_model=cm) for i in range(4)]
    devs = [mk_device(nickname=f"d{i}", vehicle=v) for i, v in enumerate(vehicles)]
    t0 = timezone.now() - timedelta(days=1)
    # 45 сегментов по 50 м: на улице всего 10 → используем разные ряды по 8 сегментов с разной долготой нельзя; расширим сеть
    from roadnet.models import Road
    road = Road.objects.get()
    extra = [Segment(road=road, index=1000 + i, direction=1, lat_a=LAT0 + 0.0004 * (1 + i // 10), lon_a=LON0 + dlon(50 * (i % 10)), lat_b=LAT0 + 0.0004 * (1 + i // 10), lon_b=LON0 + dlon(50 * (i % 10) + 50), heading=90.0)
             for i in range(50)]
    Segment.objects.bulk_create(extra)
    reset_index()
    ids = list(Segment.objects.filter(index__gte=1000).order_by("index").values_list("id", flat=True))
    for vi, d in enumerate(devs):
        trip = Trip.objects.create(device=d, vehicle=d.vehicle, started_at=t0, distance_km=5)
        ri = 0.02 if vi == 0 else 0.04                                         # машина 0 в 2 раза мягче остальных
        SegmentScore.objects.bulk_create([SegmentScore(trip=trip, device=d, segment_id=sid, lat_a=0, lon_a=0, lat_b=0, lon_b=0, speed_kmh=40, ri=ri, cls="B", at=t0) for sid in ids])
    res = road_stats.recompute_vehicle_suspension(vehicles[0], min_segments=40)
    assert res["segments"] == 50 and res["relative"] == pytest.approx(math.log(2), abs=0.02)
    vehicles[0].refresh_from_db()
    assert vehicles[0].softness_score is not None and vehicles[0].softness_score > 60
    res_hard = road_stats.recompute_vehicle_suspension(vehicles[1], min_segments=40)
    assert res_hard["relative"] < 0.1
    # мало общих сегментов или машин → индекс не считается
    assert road_stats.recompute_vehicle_suspension(Vehicle.objects.create(name="lonely"), min_segments=40) is None
    assert road_stats.refresh_car_model_stats() >= 1
    cm.refresh_from_db()
    assert cm.softness_n_vehicles >= 1


@pytest.mark.django_db
def test_label_import_roundtrip(network):
    services.ingest_trip(mk_device(), payload([ev(100)]))
    e = RoadEvent.objects.get()
    Label.objects.create(event=e, source="driver", label="manhole", features=e.features, trip_key=str(e.trip_id))
    assert Label.objects.count() == 1
