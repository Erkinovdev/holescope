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
