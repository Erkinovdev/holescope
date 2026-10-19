"""Этап 4: API админки — вход, роли, модерация, дороги, устройства, машины, пользователи, раздел «Мозг»."""
import json
from datetime import timedelta
from pathlib import Path
import pytest
from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client
from django.utils import timezone
from brain import services
from brain.models import AlgoVersion, AuditLog, Label
from fleet.models import CarModel, Device, Vehicle
from roadnet.models import Road
from telemetry.models import Complaint, EventCluster, RoadEvent, Trip
from .test_brain import ev, mk_device, network, payload, seg_rows  # noqa: F401

J = "application/json"
A = "/api/v1/admin"


def mk_user(name, role, pw="Str0ng-pass-123"):
    from api.admin_api import _set_role
    u = User.objects.create_user(name, password=pw)
    _set_role(u, role)
    return u


def token(client, name, pw="Str0ng-pass-123"):
    r = client.post(f"{A}/login", json.dumps({"username": name, "password": pw}), content_type=J)
    assert r.status_code == 200, r.content
    return {"Authorization": "Bearer " + r.json()["token"]}


@pytest.fixture
def staff(db):
    mk_user("boss", "admin"), mk_user("lab", "labeler"), mk_user("ana", "analyst")
    c = Client()
    return c, {r: token(c, n) for r, n in (("admin", "boss"), ("labeler", "lab"), ("analyst", "ana"))}


@pytest.fixture
def data(network, staff):
    """Две подтверждённые ямы на улице + поездки двух устройств."""
    t0 = timezone.now() - timedelta(days=2)
    a, b = mk_device(nickname="a"), mk_device(nickname="b")
    for d in (a, b):
        services.ingest_trip(d, payload([ev(100), ev(300, score=9.0)], seg_rows(0, 10, ri=0.04), started=t0, client_id=d.nickname))
    return a, b


def test_login_and_roles(staff):
    c, tok = staff
    assert c.post(f"{A}/login", json.dumps({"username": "boss", "password": "bad"}), content_type=J).status_code == 401
    assert c.get(f"{A}/me").status_code == 401
    assert c.get(f"{A}/me", headers={"Authorization": "Bearer junk"}).status_code == 401
    me = c.get(f"{A}/me", headers=tok["labeler"]).json()
    assert me["role"] == "labeler" and me["role_name"] == "разметчик"
    # неактивный сотрудник не входит
    User.objects.filter(username="ana").update(is_active=False)
    assert c.post(f"{A}/login", json.dumps({"username": "ana", "password": "Str0ng-pass-123"}), content_type=J).status_code == 401


def test_role_matrix(staff, data):
    c, tok = staff
    cl = EventCluster.objects.first()
    patch = lambda role: c.patch(f"{A}/clusters/{cl.pk}/patch", json.dumps({"level": "deep"}), content_type=J, headers=tok[role])
    assert patch("analyst").status_code == 403          # аналитик только читает
    assert patch("labeler").status_code == 200          # разметчик модерирует
    assert c.patch(f"{A}/roads/{Road.objects.first().pk}/patch", json.dumps({"surface": "asphalt"}), content_type=J, headers=tok["labeler"]).status_code == 403
    assert c.patch(f"{A}/roads/{Road.objects.first().pk}/patch", json.dumps({"surface": "asphalt"}), content_type=J, headers=tok["admin"]).status_code == 200
    assert c.get(f"{A}/users", headers=tok["labeler"]).status_code == 403
    assert c.get(f"{A}/users", headers=tok["admin"]).status_code == 200
    assert c.get(f"{A}/clusters", headers=tok["analyst"]).status_code == 200


def test_overview(staff, data):
    c, tok = staff
    j = c.get(f"{A}/overview", {"days": 7}, headers=tok["analyst"]).json()
    assert j["kpi"]["trips"] == 2 and j["kpi"]["km"] == 10.0 and j["kpi"]["clusters_total"] == 2 and j["kpi"]["confirmed"] == 2 and j["kpi"]["devices_total"] == 2
    assert len(j["series"]) == 7 and sum(x["trips"] for x in j["series"]) == 2
    assert j["recent"] and j["recent"][0]["street"] == "Улица Тест"


def test_clusters_list_filters_detail_and_moderation(staff, data):
    c, tok = staff
    h = tok["labeler"]
    j = c.get(f"{A}/clusters", {"status": "confirmed", "q": "тест", "size": 1}, headers=h).json()
    assert j["total"] == 2 and len(j["items"]) == 1 and j["size"] == 1
    assert c.get(f"{A}/clusters", {"status": "fixed"}, headers=h).json()["total"] == 0
    assert c.get(f"{A}/clusters", {"district": "UZ-TSH-YUN"}, headers=h).json()["total"] == 2
    assert c.get(f"{A}/clusters", {"bbox": "bad"}, headers=h).status_code == 400
    cid = j["items"][0]["id"]
    d = c.get(f"{A}/clusters/{cid}", headers=h).json()
    assert d["street"] == "Улица Тест" and len(d["events"]) == 2 and d["events"][0]["wave"]
    # модерация: тип «люк» + уровень → метки обучения
    r = c.patch(f"{A}/clusters/{cid}/patch", json.dumps({"type": "manhole", "status": "confirmed", "safe_speed": 25}), content_type=J, headers=h)
    assert r.status_code == 200 and r.json()["type"] == "manhole" and r.json()["safe_speed"] == 25
    assert Label.objects.filter(source="admin", label="manhole").count() == 2
    assert c.patch(f"{A}/clusters/{cid}/patch", json.dumps({"status": "bogus"}), content_type=J, headers=h).status_code == 400
    assert c.patch(f"{A}/clusters/{cid}/patch", json.dumps({}), content_type=J, headers=h).status_code == 400
    assert c.patch(f"{A}/clusters/999999/patch", json.dumps({"level": "mid"}), content_type=J, headers=h).status_code == 404
    # закрыть как «заделана» ставит время
    c.patch(f"{A}/clusters/{cid}/patch", json.dumps({"status": "fixed"}), content_type=J, headers=h)
    assert EventCluster.objects.get(pk=cid).fixed_at is not None
    assert AuditLog.objects.filter(action="cluster.patch").count() == 2


def test_merge_and_manual_create(staff, data):
    c, tok = staff
    h = tok["labeler"]
    a = EventCluster.objects.order_by("id").first()
    # дубль рядом: ещё одна яма в том же месте, в которую «разъехались» события
    dup = EventCluster.objects.create(lat=a.lat + 0.00001, lon=a.lon, heading=a.heading, passes=1, devices=1)
    RoadEvent.objects.filter(pk=a.events.first().pk).update(cluster=dup)
    r = c.post(f"{A}/clusters/merge", json.dumps({"ids": [a.pk, dup.pk], "into": a.pk}), content_type=J, headers=h)
    assert r.status_code == 200 and r.json()["id"] == a.pk and r.json()["passes"] == 2
    assert not EventCluster.objects.filter(pk=dup.pk).exists()
    assert c.post(f"{A}/clusters/merge", json.dumps({"ids": [a.pk]}), content_type=J, headers=h).status_code == 400
    # ручное добавление
    new = c.post(f"{A}/clusters/create", json.dumps({"lat": 41.3, "lon": 69.2503, "type": "pothole", "level": "deep", "heading": 90}), content_type=J, headers=h)
    assert new.status_code == 201 and new.json()["status"] == "confirmed" and new.json()["street"] == "Улица Тест"
    assert c.post(f"{A}/clusters/create", json.dumps({"lat": 0, "lon": 0}), content_type=J, headers=h).status_code == 400
    assert c.post(f"{A}/clusters/create", json.dumps({"lat": "x"}), content_type=J, headers=h).status_code == 400


def test_roads_registry_and_edit(staff, data):
    c, tok = staff
    j = c.get(f"{A}/roads", {"class": "A", "q": "тест"}, headers=tok["analyst"]).json()
    assert j["total"] == 1 and j["items"][0]["code"] == "A001" and j["items"][0]["segments"] == 20 and j["items"][0]["scored"] >= 10
    rid = j["items"][0]["id"]
    d = c.get(f"{A}/roads/{rid}", headers=tok["analyst"]).json()
    assert d["segments_total"] == 20 and d["classes"] and d["clusters"] == 2
    r = c.patch(f"{A}/roads/{rid}/patch", json.dumps({"road_class": "B", "name_ru": "Улица Тестовая"}), content_type=J, headers=tok["admin"])
    assert r.status_code == 200 and r.json()["road_class"] == "B" and r.json()["class_reviewed"] is True
    assert c.get(f"{A}/roads", {"q": "тестовая"}, headers=tok["analyst"]).json()["total"] == 1       # name_key обновился
    assert c.patch(f"{A}/roads/{rid}/patch", json.dumps({"road_class": "Z"}), content_type=J, headers=tok["admin"]).status_code == 400
    assert c.get(f"{A}/roads", {"reviewed": "1"}, headers=tok["analyst"]).json()["total"] == 1


def test_devices_and_vehicle_editing(staff, data):
    c, tok = staff
    ad = tok["admin"]
    lst = c.get(f"{A}/devices", {"q": "a"}, headers=ad).json()
    assert lst["total"] >= 1 and lst["items"][0]["trips"] == 1
    dev = Device.objects.get(nickname="a")
    d = c.get(f"{A}/devices/{dev.pk}", headers=ad).json()
    assert d["events_total"] == 2 and len(d["trips"]) == 1
    r = c.patch(f"{A}/devices/{dev.pk}/patch", json.dumps({"role": "research", "trust": 0.9, "mount": "seat", "blocked": True}), content_type=J, headers=ad).json()
    assert r["role"] == "research" and r["trust"] == 0.9 and r["blocked"] is True
    assert c.patch(f"{A}/devices/{dev.pk}/patch", json.dumps({"role": "king"}), content_type=J, headers=ad).status_code == 400
    assert c.patch(f"{A}/devices/{dev.pk}/patch", json.dumps({"reset_calibration": True}), content_type=J, headers=ad).json()["calib_gain"] == 1.0
    # машина: создаём профиль, привязываем модель, правим характеристики
    cm = CarModel.objects.create(brand="Geely", model="Geometry E", wheelbase_mm=2485, specs_verified=True, source_url="https://example.org")
    v = Vehicle.objects.create(name="моя")
    Device.objects.filter(pk=dev.pk).update(vehicle=v)
    body_ok = dict(car_model_id=cm.pk, year=2024, wheelbase_mm=2485, rim_inch=16, tire_pressure_bar=2.1, suspension_note="чуть выше средней", suspension_cls="S2")
    r = c.patch(f"{A}/vehicles/{v.pk}/patch", json.dumps(body_ok), content_type=J, headers=ad)
    assert r.status_code == 200 and r.json()["car_model"] == "Geely Geometry E" and r.json()["wheelbase_effective_m"] == 2.485 and r.json()["suspension_cls"] == "S2"
    for bad in ({"wheelbase_mm": 900}, {"year": 1800}, {"tire_pressure_bar": 12}, {"rim_inch": 3}, {"suspension_cls": "S9"}, {"car_model_id": 99999}, {"year": "abc"}):
        assert c.patch(f"{A}/vehicles/{v.pk}/patch", json.dumps(bad), content_type=J, headers=ad).status_code == 400, bad
    assert c.patch(f"{A}/vehicles/{v.pk}/patch", json.dumps({"wheelbase_mm": 2600}), content_type=J, headers=tok["labeler"]).status_code == 403
    assert c.get(f"{A}/devices/{dev.pk}", headers=ad).json()["vehicle"]["wheelbase_mm"] == 2485


def test_trips_review(staff, data):
    c, tok = staff
    j = c.get(f"{A}/trips", headers=tok["analyst"]).json()
    assert j["total"] == 2 and j["items"][0]["events"] == 2
    d = c.get(f"{A}/trips/{j['items'][0]['id']}", headers=tok["analyst"]).json()
    assert len(d["events"]) == 2 and d["events"][0]["wave"] and len(d["segments"]) == 10
    assert c.get(f"{A}/trips", {"device": Device.objects.get(nickname="a").pk}, headers=tok["analyst"]).json()["total"] == 1
    assert c.get(f"{A}/trips/999999", headers=tok["analyst"]).status_code == 404


def test_car_models_directory(staff, db):
    c, tok = staff
    ad = tok["admin"]
    r = c.post(f"{A}/car-models/create", json.dumps({"brand": "Chevrolet", "model": "Cobalt"}), content_type=J, headers=ad)
    assert r.status_code == 201 and r.json()["specs_verified"] is False
    cid = r.json()["id"]
    # подтверждать характеристики без источника нельзя
    assert c.patch(f"{A}/car-models/{cid}/patch", json.dumps({"wheelbase_mm": 2620, "specs_verified": True}), content_type=J, headers=ad).status_code == 400
    ok = c.patch(f"{A}/car-models/{cid}/patch", json.dumps({"wheelbase_mm": 2620, "specs_verified": True, "source_url": "https://example.org/cobalt"}), content_type=J, headers=ad)
    assert ok.status_code == 200 and ok.json()["specs_verified"] is True
    assert c.patch(f"{A}/car-models/{cid}/patch", json.dumps({"wheelbase_mm": 100}), content_type=J, headers=ad).status_code == 400
    assert c.post(f"{A}/car-models/create", json.dumps({"brand": "X"}), content_type=J, headers=ad).status_code == 400
    assert any(m["model"] == "Cobalt" for m in c.get(f"{A}/car-models", headers=tok["analyst"]).json()["items"])


def test_complaints_admin(staff, data):
    c, tok = staff
    cl = EventCluster.objects.first()
    comp = Complaint.objects.create(cluster=cl, text="текст", status="filed", filed_at=timezone.now())
    assert c.get(f"{A}/complaints", {"status": "filed"}, headers=tok["analyst"]).json()["total"] == 1
    r = c.patch(f"{A}/complaints/{comp.pk}/patch", json.dumps({"status": "review", "external_number": "48217", "due_at": "2026-11-01T10:00:00+05:00"}), content_type=J, headers=tok["labeler"])
    assert r.status_code == 200 and r.json()["external_number"] == "48217" and r.json()["due_at"].startswith("2026-11-01")
    r = c.patch(f"{A}/complaints/{comp.pk}/patch", json.dumps({"status": "answered"}), content_type=J, headers=tok["labeler"]).json()
    assert r["answered_at"] is not None
    assert c.patch(f"{A}/complaints/{comp.pk}/patch", json.dumps({"status": "zzz"}), content_type=J, headers=tok["labeler"]).status_code == 400
    assert c.patch(f"{A}/complaints/{comp.pk}/patch", json.dumps({"status": "fixed"}), content_type=J, headers=tok["analyst"]).status_code == 403


def test_users_management(staff):
    c, tok = staff
    ad = tok["admin"]
    r = c.post(f"{A}/users/create", json.dumps({"username": "new", "password": "123", "role": "labeler"}), content_type=J, headers=ad)
    assert r.status_code == 400                                                    # слабый пароль
    r = c.post(f"{A}/users/create", json.dumps({"username": "new", "password": "Another-Str0ng-1", "role": "labeler"}), content_type=J, headers=ad)
    assert r.status_code == 201 and r.json()["role"] == "labeler"
    uid = r.json()["id"]
    assert c.post(f"{A}/users/create", json.dumps({"username": "new", "password": "Another-Str0ng-1", "role": "admin"}), content_type=J, headers=ad).status_code == 409
    assert c.post(f"{A}/users/create", json.dumps({"username": "x", "password": "Another-Str0ng-1", "role": "king"}), content_type=J, headers=ad).status_code == 400
    # вход новым сотрудником, смена роли и пароля
    assert c.post(f"{A}/login", json.dumps({"username": "new", "password": "Another-Str0ng-1"}), content_type=J).status_code == 200
    assert c.patch(f"{A}/users/{uid}/patch", json.dumps({"role": "analyst"}), content_type=J, headers=ad).json()["role"] == "analyst"
    assert c.post(f"{A}/users/{uid}/password", json.dumps({"password": "short"}), content_type=J, headers=ad).status_code == 400
    assert c.post(f"{A}/users/{uid}/password", json.dumps({"password": "Brand-New-Pass-77"}), content_type=J, headers=ad).status_code == 200
    assert c.post(f"{A}/login", json.dumps({"username": "new", "password": "Brand-New-Pass-77"}), content_type=J).status_code == 200
    # нельзя отключить или понизить самого себя
    boss = User.objects.get(username="boss")
    assert c.patch(f"{A}/users/{boss.pk}/patch", json.dumps({"is_active": False}), content_type=J, headers=ad).status_code == 400
    assert c.patch(f"{A}/users/{boss.pk}/patch", json.dumps({"role": "analyst"}), content_type=J, headers=ad).status_code == 400
    assert c.patch(f"{A}/users/{uid}/patch", json.dumps({"is_active": False}), content_type=J, headers=ad).json()["is_active"] is False
    assert c.post(f"{A}/login", json.dumps({"username": "new", "password": "Brand-New-Pass-77"}), content_type=J).status_code == 401
    assert c.get(f"{A}/audit", headers=ad).json()["total"] >= 4


# ───────────────────────── «Мозг» ─────────────────────────
def test_brain_summary_timeline_graph(staff, data):
    c, tok = staff
    h = tok["analyst"]
    s = c.get(f"{A}/brain/summary", headers=h).json()
    assert s["current"]["clusters"] == 2 and s["current"]["segments"] > 0 and s["current"]["segments_scored"] >= 10
    t = c.get(f"{A}/brain/timeline", headers=h).json()
    assert t["base"]["version"].startswith("rules") and t["versions"] == []
    g = c.get(f"{A}/brain/graph", headers=h).json()
    kinds = {n["kind"] for n in g["nodes"]}
    assert {"cluster", "road", "device"} <= kinds and g["counts"]["edges"] >= 5
    ids = {n["id"] for n in g["nodes"]}
    assert all(e["a"] in ids and e["b"] in ids for e in g["edges"])


def test_brain_questions_and_labeling(staff, data):
    c, tok = staff
    q = c.get(f"{A}/brain/questions", headers=tok["analyst"]).json()
    assert q["queue"] and "wave" in q["queue"][0] and "manhole" in q["labels"]
    eid = q["queue"][0]["id"]
    assert c.post(f"{A}/brain/label", json.dumps({"event_id": eid, "label": "manhole"}), content_type=J, headers=tok["analyst"]).status_code == 403
    r = c.post(f"{A}/brain/label", json.dumps({"event_id": eid, "label": "manhole"}), content_type=J, headers=tok["labeler"])
    assert r.status_code == 201 and r.json()["labels_total"] == 1
    assert RoadEvent.objects.get(pk=eid).user_label == "manhole"
    assert c.post(f"{A}/brain/label", json.dumps({"event_id": eid, "label": "wat"}), content_type=J, headers=tok["labeler"]).status_code == 400
    assert c.post(f"{A}/brain/label", json.dumps({"event_id": 99999, "label": "noise"}), content_type=J, headers=tok["labeler"]).status_code == 404
    after = c.get(f"{A}/brain/questions", headers=tok["analyst"]).json()
    assert eid not in [x["id"] for x in after["queue"]] and after["stats"]["by_source"]["admin"] == 1


def test_params_versions_and_public_distribution(staff, db):
    c, tok = staff
    ad = tok["admin"]
    p = c.get(f"{A}/brain/params", headers=tok["analyst"]).json()
    assert p["params"]["floor"] == 2.0 and "floor" in p["ranges"]
    # публичный эндпоинт отдаёт то же самое
    assert c.get("/api/v1/algo/params").json()["params"]["k_noise"] == 4.0
    bad = c.put(f"{A}/brain/params/save", json.dumps({"params": {"floor": 99}}), content_type=J, headers=ad)
    assert bad.status_code == 400 and "floor" in bad.json()["error"]
    assert c.put(f"{A}/brain/params/save", json.dumps({"params": {"ri_bounds": [0.1, 0.05, 0.2, 0.3]}}), content_type=J, headers=ad).status_code == 400
    assert c.put(f"{A}/brain/params/save", json.dumps({"params": {"floor": 3.0}}), content_type=J, headers=tok["labeler"]).status_code == 403
    r = c.put(f"{A}/brain/params/save", json.dumps({"params": {"floor": 3.0, "k_noise": 5}, "activate": True, "notes": "тест"}), content_type=J, headers=ad)
    assert r.status_code == 201 and r.json()["active"] is True and r.json()["version"] == "rules-1"
    got = c.get("/api/v1/algo/params").json()
    got.pop("guess")  # параметры догадки проверяются в test_guesser
    assert got == {"version": "rules-1", "params": {**p["defaults"], "floor": 3.0, "k_noise": 5.0}}
    # вторая версия не включена по умолчанию; переключение и откат
    r2 = c.put(f"{A}/brain/params/save", json.dumps({"params": {"floor": 2.5}}), content_type=J, headers=ad).json()
    assert r2["active"] is False and AlgoVersion.objects.filter(active=True).count() == 1
    assert c.post(f"{A}/brain/activate", json.dumps({"version_id": r2["id"]}), content_type=J, headers=ad).json()["active"] is True
    assert AlgoVersion.objects.get(version="rules-1").active is False
    assert c.post(f"{A}/brain/deactivate", json.dumps({"version_id": r2["id"]}), content_type=J, headers=ad).json()["active"] is False
    assert c.get("/api/v1/algo/params").json()["params"]["floor"] == 2.0                      # без активной версии — значения по умолчанию
    # новые параметры влияют на классы ровности на сервере
    from brain.road_stats import current_params
    AlgoVersion.objects.filter(version="rules-1").update(active=True)
    assert current_params().k_noise == 5.0


def test_gbm_activation_requires_force(staff, db):
    c, tok = staff
    av = AlgoVersion.objects.create(version="gbm-1", kind="gbm", metrics={"activated": False, "f1_gain": -0.03}, params={"features": ["peak"]})
    r = c.post(f"{A}/brain/activate", json.dumps({"version_id": av.pk}), content_type=J, headers=tok["admin"])
    assert r.status_code == 409 and "force" in r.json()["error"]
    assert c.post(f"{A}/brain/activate", json.dumps({"version_id": av.pk, "force": True}), content_type=J, headers=tok["admin"]).json()["active"] is True
    assert c.post(f"{A}/brain/activate", json.dumps({"version_id": 999}), content_type=J, headers=tok["admin"]).status_code == 404


def test_train_endpoint_reports_not_enough_data(staff, db):
    c, tok = staff
    r = c.post(f"{A}/brain/train", headers=tok["admin"]).json()
    assert "мало данных" in r["log"] and r["version"] is None
    assert c.post(f"{A}/brain/train", headers=tok["labeler"]).status_code == 403


CSV = Path(__file__).resolve().parents[2] / "analysis" / "pothole_2026-10-17_12-09-50.csv"


@pytest.mark.skipif(not CSV.exists(), reason="нет analysis/*.csv")
def test_csv_upload_review_and_preview(staff, tmp_path, settings):
    settings.MEDIA_ROOT = tmp_path
    c, tok = staff
    lab = tok["labeler"]
    bad = c.post(f"{A}/brain/upload-csv", {"file": SimpleUploadedFile("x.csv", b"garbage,not\n1,2\n"), "wheelbase_m": "2.485"}, headers=lab)
    assert bad.status_code == 422 and "error" in bad.json()
    assert c.post(f"{A}/brain/upload-csv", {"file": SimpleUploadedFile("x.csv", b"")}, headers=lab).status_code in (400, 422)
    assert c.post(f"{A}/brain/upload-csv", {"file": SimpleUploadedFile("x.csv", b"a"), "wheelbase_m": "9"}, headers=lab).status_code == 400
    assert c.post(f"{A}/brain/upload-csv", {"file": SimpleUploadedFile("x.csv", b"a")}, headers=tok["analyst"]).status_code == 403
    try:
        up = c.post(f"{A}/brain/upload-csv", {"file": SimpleUploadedFile(CSV.name, CSV.read_bytes()), "wheelbase_m": "2.485"}, headers=lab)
    except MemoryError:
        pytest.skip("мало памяти")
    if up.status_code == 422 and "allocate" in up.json().get("error", ""):
        pytest.skip("мало памяти в системе (Docker-ВМ)")
    assert up.status_code == 201
    rep = up.json()["report"]
    assert rep["events"] == 37 and rep["by_type"]["pothole"] == 27 and rep["segments"] == 231        # то же, что eval_v2.py
    rid = up.json()["raw_id"]
    assert c.get(f"{A}/brain/uploads", headers=tok["analyst"]).json()["total"] == 1
    rv = c.get(f"{A}/brain/uploads/{rid}/review", headers=tok["analyst"]).json()
    assert len(rv["events"]) == 37 and len(rv["signal"]["t"]) == len(rv["signal"]["vz"]) > 500 and rv["path"] and rv["hands"]
    # предпросмотр: более высокий порог → событий не больше, добавленных нет
    pv = c.post(f"{A}/brain/preview", json.dumps({"raw_id": rid, "params": {"floor": 4.0}}), content_type=J, headers=tok["analyst"]).json()
    assert pv["current"]["total"] == 37 and pv["preview"]["total"] < 37 and pv["removed"] > 0 and pv["added"] == 0
    assert c.post(f"{A}/brain/preview", json.dumps({"raw_id": rid, "params": {"floor": 0}}), content_type=J, headers=tok["analyst"]).status_code == 400
    assert c.post(f"{A}/brain/preview", json.dumps({"raw_id": 999, "params": {}}), content_type=J, headers=tok["analyst"]).status_code == 404


def test_system_and_badges(staff):
    c, tok = staff
    assert c.get(f"{A}/badges").status_code == 401
    b = c.get(f"{A}/badges", headers=tok["analyst"]).json()
    assert set(b) >= {"events", "complaints", "questions", "algo"}
    s = c.get(f"{A}/system", headers=tok["analyst"]).json()
    assert s["services"][0]["state"] == "ok" and "counts" in s and isinstance(s["log"], list)
