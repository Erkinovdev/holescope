"""Голосовые отметки водителя: привязка к событию, разметка, кандидаты, идемпотентность, защита."""
import json
from datetime import timedelta
import pytest
from django.test import Client
from django.utils import timezone
from brain.models import Label
from telemetry.marks import apply_pending
from telemetry.models import DriverMark, EventCluster, RoadEvent
from tests.test_api import JSON, LAT, LON, ev, register, trip

pytestmark = pytest.mark.django_db


@pytest.fixture
def c():
    return Client()


def mark(cid="m1", kind="pothole", lat=LAT, lon=LON, at=None, **kw):
    return dict(client_id=cid, kind=kind, lat=lat, lon=lon, heading=90.0, at=(at or timezone.now()).isoformat(), **kw)


def post_marks(c, tok, items):
    return c.post("/api/v1/marks", json.dumps({"marks": items}), content_type=JSON, HTTP_X_DEVICE_TOKEN=tok)


def upload(c, tok, events, started="2026-10-17T07:00:00Z"):
    r = c.post("/api/v1/trips", json.dumps(trip(events, started_at=started)), content_type=JSON, HTTP_X_DEVICE_TOKEN=tok)
    assert r.status_code == 201, r.content


def test_requires_auth(c):
    assert c.post("/api/v1/marks", json.dumps({"marks": [mark()]}), content_type=JSON).status_code == 401


def test_mark_labels_matching_event(c):
    tok = register(c)
    upload(c, tok, [ev(t=30.0)])
    e = RoadEvent.objects.get()
    r = post_marks(c, tok, [mark(kind="manhole", at=e.at)])
    assert r.status_code == 201 and r.json()["created"] == 1
    e.refresh_from_db()
    assert e.user_label == "manhole"
    assert Label.objects.filter(event=e, source="driver", label="manhole").exists()
    assert DriverMark.objects.get().applied


def test_not_pothole_marks_noise_and_false_cluster(c):
    tok = register(c)
    upload(c, tok, [ev(t=30.0)])
    e = RoadEvent.objects.get()
    post_marks(c, tok, [mark(kind="not_pothole", at=e.at)])
    e.refresh_from_db()
    assert e.user_label == "nothing"
    assert Label.objects.get(event=e).label == "noise"
    assert EventCluster.objects.get().status == "false"


def test_mark_before_upload_is_applied_after_trip_upload(c):
    tok = register(c)
    at = timezone.now()
    post_marks(c, tok, [mark(at=at)])
    m = DriverMark.objects.get()
    assert not m.applied                      # поездка ещё не загружена — отметка ждёт
    started = (at - timedelta(seconds=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
    upload(c, tok, [ev(t=30.0)], started=started)
    m.refresh_from_db()
    assert m.applied and m.event_id is not None
    assert RoadEvent.objects.get().user_label == "pothole_mid"


def test_unmatched_old_mark_creates_candidate_and_two_drivers_confirm(c):
    t1, t2 = register(c), register(c)
    old = timezone.now() - timedelta(hours=5)
    for tok, cid in ((t1, "a"), (t2, "b")):
        post_marks(c, tok, [mark(cid=cid, kind="deep")])
    DriverMark.objects.update(created=old)
    assert apply_pending() == 2
    cl = EventCluster.objects.get()
    assert cl.status == "confirmed" and cl.level == "deep" and cl.marks.count() == 2


def test_idempotent_and_validation(c):
    tok = register(c)
    assert post_marks(c, tok, [mark("x")]).json()["created"] == 1
    assert post_marks(c, tok, [mark("x")]).json()["created"] == 0
    assert post_marks(c, tok, [mark("y", kind="bogus")]).status_code == 400
    assert post_marks(c, tok, [mark("z", lat=10.0)]).status_code == 400
    assert post_marks(c, tok, []).status_code == 400


# ───────────── расширенный справочник «что это» и оценки дороги ─────────────
from brain import taxonomy  # noqa: E402
from brain.models import Question  # noqa: E402
from tests.test_api import answer, post_trip  # noqa: E402


def test_taxonomy_endpoint_and_options(c):
    d = c.get("/api/v1/taxonomy").json()
    keys = [i["key"] for i in d["items"]]
    for k in ("pothole_danger", "manhole_sunk", "washboard", "broken", "patch", "rail_train", "handled"):
        assert k in keys
    assert d["driver_options"][-1] == "not_sure" and len(d["driver_options"]) >= 15
    assert set(d["road_ratings"]) == {"road_a", "road_b", "road_c", "road_d", "road_e"}


def test_every_label_maps_to_a_known_cluster_type():
    valid = {k for k, _ in EventCluster.TYPES}
    for it in taxonomy.ITEMS:
        if it.road:
            assert it.type in valid, it.key


def test_driver_answers_new_label_and_legacy_alias(c):
    tok = register(c)
    post_trip(c, tok, trip([ev(t=30.0), ev(t=60.0, lat=LAT + 0.01)]))
    qs = list(Question.objects.filter(status="open"))
    assert answer(c, tok, qs[0].pk, "manhole_sunk").status_code == 200
    assert answer(c, tok, qs[1].pk, "nothing").status_code == 200       # старый ключ приложения
    assert sorted(Label.objects.values_list("label", flat=True)) == ["manhole_sunk", "noise"]
    assert answer(c, tok, qs[0].pk, "bogus").status_code in (400, 404)


def test_votes_change_type_and_level():
    from brain import road_stats
    cl = EventCluster.objects.create(lat=LAT, lon=LON, type="pothole", level="light", status="confirmed")
    for _ in range(3):
        road_stats.refine_cluster_type(cl, "pothole_danger")
    cl.refresh_from_db()
    assert cl.type == "pothole" and cl.level == "danger"
    for _ in range(8):
        road_stats.refine_cluster_type(cl, "washboard")
    cl.refresh_from_db()
    assert cl.type == "rough_patch"


def test_mark_with_new_kind_labels_event(c):
    tok = register(c)
    upload(c, tok, [ev(t=30.0)])
    e = RoadEvent.objects.get()
    assert post_marks(c, tok, [mark(kind="pothole_danger", at=e.at)]).status_code == 201
    e.refresh_from_db()
    assert e.user_label == "pothole_danger"
    assert Label.objects.get(event=e).label == "pothole_danger"


def test_road_rating_uses_segment_scores_of_last_stretch(c):
    from statistics import median
    from fleet.models import Device
    from telemetry.models import SegmentScore, Trip
    tok = register(c)
    dev = Device.objects.get()
    now = timezone.now()
    trip_obj = Trip.objects.create(device=dev, started_at=now - timedelta(minutes=5), distance_km=3, algo_version="2.0.0")
    for i, ri in enumerate([0.10, 0.12, 0.16]):
        SegmentScore.objects.create(trip=trip_obj, device=dev, lat_a=LAT, lon_a=LON, lat_b=LAT, lon_b=LON + 0.0005, speed_kmh=40, ri=ri, cls="D", at=now - timedelta(seconds=60 - i * 10))
    assert post_marks(c, tok, [mark(kind="road_d", at=now)]).status_code == 201
    m = DriverMark.objects.get()
    assert m.applied and m.ri == median([0.10, 0.12, 0.16])


# ───────────── калибровка и подробный разбор объекта ─────────────
from django.contrib.auth import get_user_model  # noqa: E402


def _admin(c):
    get_user_model().objects.create_superuser("boss", "b@x.uz", "pw-12345-pw")
    tok = c.post("/api/v1/admin/login", json.dumps({"username": "boss", "password": "pw-12345-pw"}), content_type=JSON).json()["token"]
    return {"HTTP_AUTHORIZATION": f"Bearer {tok}"}


def test_calibration_apply_levels_relevels_and_is_audited(c):
    h = _admin(c)
    tok = register(c)
    upload(c, tok, [ev(t=30.0, score=9.0, level="light")])
    r = c.post("/api/v1/admin/brain/calibration/apply", json.dumps({"kind": "levels", "bounds": [3.0, 6.0, 12.0]}), content_type=JSON, **h)
    assert r.status_code == 201 and r.json()["bounds"] == [3.0, 6.0, 12.0]
    assert RoadEvent.objects.get().level == "deep"
    g = c.get("/api/v1/admin/brain/calibration", **h).json()
    assert g["levels"]["active"] and g["levels"]["current"] == [3.0, 6.0, 12.0]
    assert c.post("/api/v1/admin/brain/calibration/apply", json.dumps({"kind": "levels", "bounds": [9, 3, 1]}), content_type=JSON, **h).status_code == 400
    assert c.post("/api/v1/admin/brain/calibration/apply", json.dumps({"kind": "levels", "bounds": [1, 2, 3]}), content_type=JSON).status_code == 401


def test_new_events_use_calibrated_levels(c):
    h = _admin(c)
    c.post("/api/v1/admin/brain/calibration/apply", json.dumps({"kind": "levels", "bounds": [2.0, 3.0, 4.0]}), content_type=JSON, **h)
    tok = register(c)
    upload(c, tok, [ev(t=30.0, score=6.0, level="light")])
    assert RoadEvent.objects.get().level == "danger"


def test_calibration_ri_applies_and_keeps_other_versions_active(c):
    h = _admin(c)
    from brain.models import AlgoVersion
    c.post("/api/v1/admin/brain/calibration/apply", json.dumps({"kind": "levels", "bounds": [3.0, 6.0, 12.0]}), content_type=JSON, **h)
    r = c.post("/api/v1/admin/brain/calibration/apply", json.dumps({"kind": "ri", "bounds": [0.04, 0.06, 0.09, 0.14]}), content_type=JSON, **h)
    assert r.status_code == 201
    assert AlgoVersion.objects.get(kind="levels", active=True) and AlgoVersion.objects.get(kind="rules", active=True).params["ri_bounds"] == [0.04, 0.06, 0.09, 0.14]


def test_cluster_detail_has_analysis(c):
    h = _admin(c)
    tok = register(c)
    upload(c, tok, [ev(t=30.0)])
    cid = EventCluster.objects.get().pk
    d = c.get(f"/api/v1/admin/clusters/{cid}", **h).json()
    a = d["analysis"]
    assert a["guess"]["ranked"] and abs(sum(x["p"] for x in a["guess"]["ranked"])) <= 1.0
    assert "Сила удара" in a["level"]["text"] and a["context"]["c_passes"] >= 1
