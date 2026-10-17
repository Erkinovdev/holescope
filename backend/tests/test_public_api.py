"""Этап 3: рейтинги, отчёт недели, жалобы, справочники, статистика профиля."""
import json
import math
from datetime import timedelta
import pytest
from django.test import Client
from django.utils import timezone
from brain import services
from fleet.models import Device
from roadnet.models import Segment
from telemetry.models import Complaint, EventCluster
from .test_brain import LAT0, LON0, K, dlon, ev, mk_device, network, payload, seg_rows  # noqa: F401  (network — фикстура)

J = "application/json"


def hdr(dev):
    return {"X-Device-Token": dev.token}


@pytest.fixture
def city(network):
    """Две машины проезжают улицу; на ней три ямы, подтверждённые двумя устройствами."""
    a, b = mk_device(nickname="a"), mk_device(nickname="b")
    t0 = timezone.now() - timedelta(days=2)
    for d in (a, b):
        services.ingest_trip(d, payload([ev(100), ev(220), ev(380)], seg_rows(0, 10, ri=0.05), started=t0, client_id=d.nickname))
    return a, b


@pytest.mark.django_db
def test_street_ranking_potholes_per_km(city):
    c = Client()
    j = c.get("/api/v1/rankings/streets", {"days": 30}).json()
    assert j["streets"] and j["streets"][0]["name"] == "Улица Тест"
    s = j["streets"][0]
    assert s["potholes"] == 3 and s["covered_km"] == pytest.approx(0.5, abs=0.01) and s["per_km"] == pytest.approx(6.0, abs=0.1) and s["rank"] == 1
    assert c.get("/api/v1/rankings/streets", {"scope": "district"}).status_code == 400
    d = c.get("/api/v1/rankings/streets", {"scope": "district", "district": "UZ-TSH-YUN"}).json()
    assert d["streets"][0]["road"] == s["road"]
    assert c.get("/api/v1/rankings/streets", {"scope": "district", "district": "UZ-TSH-CHI"}).json()["streets"] == []
    # короткое покрытие (< 0.2 км) не попадает в рейтинг
    Segment.objects.filter(direction=1).update(length_m=10)
    assert c.get("/api/v1/rankings/streets").json()["streets"] == []


@pytest.mark.django_db
def test_district_ranking_needs_enough_segments(city):
    c = Client()
    j = c.get("/api/v1/rankings/districts").json()
    assert j["districts"] == [] and j["city_score"] is None                      # покрыто всего 10 сегментов < 20
    from api import public
    public.MIN_SEGMENTS_FOR_DISTRICT = 5
    try:
        j = Client().get("/api/v1/rankings/districts").json()
        assert j["districts"][0]["code"] == "UZ-TSH-YUN" and j["districts"][0]["score"] == 60.0      # RI 0.05 = граница B|C → класс C → 60
    finally:
        public.MIN_SEGMENTS_FOR_DISTRICT = 20


@pytest.mark.django_db
def test_weekly_report(city):
    EventCluster.objects.filter(pk=EventCluster.objects.first().pk).update(status="fixed", fixed_at=timezone.now())
    j = Client().get("/api/v1/reports/weekly").json()
    assert j["found"] == 3 and j["fixed"] == 1 and j["complaints"] == 0 and j["drivers"] == 2 and j["km"] == 10.0


@pytest.mark.django_db
def test_dictionaries_and_car_models(db):
    from fleet.models import CarModel
    CarModel.objects.create(brand="Geely", model="Geometry E", wheelbase_mm=2485, specs_verified=True, source_url="https://example.org/x")
    CarModel.objects.create(brand="Chevrolet", model="Cobalt", wheelbase_mm=2620, specs_verified=False)
    c = Client()
    d = c.get("/api/v1/dictionaries").json()
    assert d["event_statuses"]["fixed"] == "заделана" and d["roughness_classes"]["E"] == "разбитая" and "holder" in d["mounts"]
    models = {m["model"]: m for m in c.get("/api/v1/car-models").json()["models"]}
    assert models["Geometry E"]["wheelbase_mm"] == 2485
    assert "wheelbase_mm" not in models["Cobalt"], "непроверенные характеристики наружу не отдаём"


@pytest.mark.django_db
def test_complaint_flow(city):
    a, _ = city
    c = Client()
    cl = EventCluster.objects.filter(status="confirmed").first()
    r = c.post("/api/v1/complaints", json.dumps({"cluster_id": cl.pk}), content_type=J, headers=hdr(a))
    assert r.status_code == 201
    j = r.json()
    assert "Улица Тест" in j["text"] and "Юнусабадский район" in j["text"] and "2 водителями" in j["text"] and j["status"] == "draft"
    assert [s["done"] for s in j["steps"]] == [True, False, False, False]
    again = c.post("/api/v1/complaints", json.dumps({"cluster_id": cl.pk}), content_type=J, headers=hdr(a))
    assert again.status_code == 200 and again.json()["id"] == j["id"]
    sent = c.post(f"/api/v1/complaints/{j['id']}/send", headers=hdr(a)).json()
    assert sent["status"] == "filed" and sent["steps"][1]["done"] is True
    cl.refresh_from_db()
    assert cl.status == "complaint"
    # чужой не видит
    other = mk_device(nickname="x")
    assert c.get(f"/api/v1/complaints/{j['id']}", headers=hdr(other)).status_code == 404
    assert c.get(f"/api/v1/complaints/{j['id']}", headers=hdr(a)).status_code == 200
    # админ проставил номер и ответ — цепочка обновляется
    Complaint.objects.filter(pk=j["id"]).update(status="review", external_number="48217")
    s = c.get(f"/api/v1/complaints/{j['id']}", headers=hdr(a)).json()
    assert s["number"] == "48217" and s["steps"][2]["done"] is True
    # заделанная яма — жалобу уже не создать
    EventCluster.objects.filter(pk=cl.pk).update(status="fixed")
    assert c.post("/api/v1/complaints", json.dumps({"cluster_id": cl.pk}), content_type=J, headers=hdr(a)).status_code == 409
    assert c.post("/api/v1/complaints", json.dumps({"cluster_id": 999999}), content_type=J, headers=hdr(a)).status_code == 404
    assert c.post("/api/v1/complaints", json.dumps({"cluster_id": cl.pk}), content_type=J).status_code == 401


@pytest.mark.django_db
def test_my_stats(city):
    a, _ = city
    j = Client().get("/api/v1/me/stats", headers=hdr(a)).json()
    assert j["found"] == 3 and j["confirmed"] == 3 and j["km"] == 5.0 and j["trips"] == 1
    assert Client().get("/api/v1/me/stats").status_code == 401


@pytest.mark.django_db
def test_upload_endpoint_errors_and_idempotency(network):
    c = Client()
    dev = mk_device()
    r = c.post("/api/v1/trips", json.dumps(payload([ev(100)], client_id="z1")), content_type=J, headers=hdr(dev))
    assert r.status_code == 201 and r.json()["duplicate"] is False
    r2 = c.post("/api/v1/trips", json.dumps(payload([ev(100)], client_id="z1")), content_type=J, headers=hdr(dev))
    assert r2.status_code == 200 and r2.json()["duplicate"] is True and r2.json()["trip_id"] == r.json()["trip_id"]
    bad = c.post("/api/v1/trips", json.dumps(payload(duration_s=3600, distance_km=900)), content_type=J, headers=hdr(dev))
    assert bad.status_code == 413
    dev.refresh_from_db()
    assert dev.trust < 0.51
    broken = c.post("/api/v1/trips", json.dumps({"started_at": "не дата"}), content_type=J, headers=hdr(dev))
    assert broken.status_code == 400
    dev.blocked = True
    dev.save()
    assert c.post("/api/v1/trips", json.dumps(payload()), content_type=J, headers=hdr(dev)).status_code == 403
