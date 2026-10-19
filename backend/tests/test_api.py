"""Этап 0: регистрация, загрузка поездки, кластеризация, drive/ahead, ответ на вопрос."""
import json
import pytest
from django.test import Client
from telemetry.models import EventCluster, RoadEvent
from brain.models import Question, Label

LAT, LON = 41.3270, 69.2284
JSON = "application/json"


def ev(t=10.0, lat=LAT, lon=LON, heading=90.0, score=4.0, **kw):
    d = dict(t=t, lat=lat, lon=lon, heading=heading, speed_kmh=40.0, peak=score, score=score, type="pothole",
             level="mid", confidence=0.5, wave=[0.1, 0.5, -0.4], safe_speed_kmh=30, low_conf=False, algo_version="2.0.0")
    d.update(kw)
    return d


def trip(events, **kw):
    d = dict(started_at="2026-10-17T07:00:00Z", duration_s=600, distance_km=5.0, algo_version="2.0.0",
             events=events, segments=[], suspension={}, damping={})
    d.update(kw)
    return d


def register(c: Client) -> str:
    r = c.post("/api/v1/devices/register", json.dumps({"platform": "android"}), content_type=JSON)
    assert r.status_code == 201
    return r.json()["token"]


def post_trip(c, token, payload):
    return c.post("/api/v1/trips", json.dumps(payload, allow_nan=True), content_type=JSON, headers={"X-Device-Token": token})


def answer(c, token, qid, a):
    return c.post(f"/api/v1/questions/{qid}/answer", json.dumps({"answer": a}), content_type=JSON, headers={"X-Device-Token": token})


@pytest.fixture
def c():
    return Client()


@pytest.mark.django_db
def test_register_returns_token_and_nick(c):
    r = c.post("/api/v1/devices/register", json.dumps({"platform": "ios", "lang": "uz"}), content_type=JSON)
    assert r.status_code == 201
    j = r.json()
    assert len(j["token"]) >= 32 and "#" in j["nickname"]


@pytest.mark.django_db
def test_auth_required(c):
    assert c.get("/api/v1/me/vehicle").status_code == 401
    assert post_trip(c, "bad", trip([])).status_code == 401


@pytest.mark.django_db
def test_upload_trip_creates_events_cluster_questions(c):
    tok = register(c)
    r = post_trip(c, tok, trip([ev(10), ev(60, lat=LAT + 0.01), ev(90, type="noise")]))
    assert r.status_code == 201
    j = r.json()
    assert j["events"] == 2                       # noise не сохраняется
    assert j["questions"] == 2
    assert EventCluster.objects.count() == 2


@pytest.mark.django_db
def test_upload_trip_requires_started_at(c):
    assert post_trip(c, register(c), {"events": []}).status_code == 400


@pytest.mark.django_db
def test_nan_in_features_is_stored(c):
    tok = register(c)
    r = post_trip(c, tok, trip([ev(10, zeta=float("nan"))]))
    assert r.status_code == 201
    assert RoadEvent.objects.get().features["zeta"] is None


@pytest.mark.django_db
def test_two_passes_two_devices_confirm_cluster(c):
    t1, t2 = register(c), register(c)
    post_trip(c, t1, trip([ev(10)]))
    cl = EventCluster.objects.get()
    assert (cl.passes, cl.devices, cl.status) == (1, 1, "candidate")
    post_trip(c, t2, trip([ev(30, lat=LAT + 0.00003, lon=LON + 0.00003, score=5.0)]))   # около 4 м от первой
    cl = EventCluster.objects.get()
    assert EventCluster.objects.count() == 1
    assert cl.passes == 2 and cl.devices == 2
    assert cl.status == "confirmed"


@pytest.mark.django_db
def test_same_device_twice_does_not_confirm(c):
    t1 = register(c)
    post_trip(c, t1, trip([ev(10)]))
    post_trip(c, t1, trip([ev(10)]))
    cl = EventCluster.objects.get()
    assert cl.passes == 2 and cl.devices == 1 and cl.status == "candidate"


@pytest.mark.django_db
def test_opposite_direction_is_separate_cluster(c):
    tok = register(c)
    post_trip(c, tok, trip([ev(10, heading=90)]))
    post_trip(c, tok, trip([ev(10, heading=270)]))
    assert EventCluster.objects.count() == 2


@pytest.mark.django_db
def test_far_event_is_separate_cluster(c):
    tok = register(c)
    post_trip(c, tok, trip([ev(10)]))
    post_trip(c, tok, trip([ev(10, lat=LAT + 0.0003)]))          # около 33 м
    assert EventCluster.objects.count() == 2


@pytest.mark.django_db
def test_drive_ahead(c):
    t1, t2 = register(c), register(c)
    import math
    lon_ahead = LON + 150 / (111_320 * math.cos(math.radians(LAT)))      # 150 м на восток
    post_trip(c, t1, trip([ev(10, lat=LAT, lon=lon_ahead)]))
    post_trip(c, t2, trip([ev(10, lat=LAT, lon=lon_ahead)]))
    r = c.get("/api/v1/drive/ahead", {"lat": LAT, "lon": LON, "heading": 90, "dist": 300})
    a = r.json()["ahead"]
    assert len(a) == 1 and 140 <= a[0]["distance_m"] <= 160 and a[0]["side"] == "center"
    # едем в обратную сторону — ямы впереди нет
    assert c.get("/api/v1/drive/ahead", {"lat": LAT, "lon": LON, "heading": 270}).json()["ahead"] == []
    # слишком далеко
    assert c.get("/api/v1/drive/ahead", {"lat": LAT, "lon": LON, "heading": 90, "dist": 100}).json()["ahead"] == []
    assert c.get("/api/v1/drive/ahead", {"lat": LAT}).status_code == 400


@pytest.mark.django_db
def test_map_clusters_bbox(c):
    post_trip(c, register(c), trip([ev(10)]))
    r = c.get("/api/v1/map/clusters", {"bbox": f"{LAT-0.01},{LON-0.01},{LAT+0.01},{LON+0.01}"})
    assert len(r.json()["clusters"]) == 1
    assert c.get("/api/v1/map/clusters", {"bbox": "0,0,1,1"}).json()["clusters"] == []
    assert c.get("/api/v1/map/clusters").status_code == 400


@pytest.mark.django_db
def test_question_flow_and_answer(c):
    tok = register(c)
    h = {"X-Device-Token": tok}
    post_trip(c, tok, trip([ev(10)]))
    qs = c.get("/api/v1/questions/next", headers=h).json()["questions"]
    assert len(qs) == 1 and "manhole" in qs[0]["all_options"] and qs[0]["options"][-1] == "not_sure" and "handled" in qs[0]["options"]
    assert 4 <= len(qs[0]["options"]) <= 10 and abs(sum(qs[0]["probs"].values()) - 1) < 0.02
    assert answer(c, tok, qs[0]["id"], "manhole").status_code == 200
    assert Label.objects.get().label == "manhole"
    assert RoadEvent.objects.get().user_label == "manhole"
    assert Question.objects.get().status == "answered"
    assert c.get("/api/v1/questions/next", headers=h).json()["questions"] == []
    assert answer(c, tok, qs[0]["id"], "nothing").status_code == 404      # повторный ответ


@pytest.mark.django_db
def test_answer_nothing_marks_single_pass_cluster_false(c):
    tok = register(c)
    post_trip(c, tok, trip([ev(10)]))
    qid = c.get("/api/v1/questions/next", headers={"X-Device-Token": tok}).json()["questions"][0]["id"]
    answer(c, tok, qid, "nothing")
    assert EventCluster.objects.get().status == "false"
    assert Label.objects.get().label == "noise"


@pytest.mark.django_db
def test_other_device_cannot_answer(c):
    t1, t2 = register(c), register(c)
    post_trip(c, t1, trip([ev(10)]))
    assert answer(c, t2, Question.objects.get().pk, "bump").status_code == 404


@pytest.mark.django_db
def test_vehicle_profile_patch(c):
    tok = register(c)
    r = c.patch("/api/v1/me/vehicle", json.dumps({"wheelbase_mm": 2485, "mount": "seat", "tire_pressure_bar": 2.1}),
                content_type=JSON, headers={"X-Device-Token": tok})
    j = r.json()
    assert j["vehicle"]["wheelbase_m"] == 2.485 and j["mount"] == "seat"


@pytest.mark.django_db
def test_admin_endpoints_need_staff(c, django_user_model):
    assert c.get("/api/v1/admin/brain/summary").status_code == 401
    django_user_model.objects.create_user("a", password="x", is_staff=True)
    c.login(username="a", password="x")
    assert "current" in c.get("/api/v1/admin/brain/summary").json()
