"""Догадка «что это»: здравый смысл (слабый удар — не глубокая яма, сильный — не мелкая), контекст, честная оценка."""
import pytest
from brain import guesser as g, taxonomy


def ev(score, speed=50, dur=550, pair=0.5, gyro=12, hf=0.2, **kw):
    return dict(score=score, speed_kmh=speed, dur_ms=dur, pair=pair, gyro_peak=gyro, hf_share=hf, **kw)


def p(guess, *keys):
    return sum(guess.probs[k] for k in keys)


def test_probabilities_sum_to_one_and_cover_taxonomy():
    gs = g.guess_event(ev(3.2))
    assert abs(sum(gs.probs.values()) - 1) < 0.01
    assert set(gs.probs) <= set(taxonomy.BY_KEY)


def test_weak_shake_cannot_be_deep_pothole():
    assert p(g.guess_event(ev(1.9)), "pothole_deep", "pothole_danger") < 0.03


def test_strong_shake_cannot_be_light_pothole():
    gs = g.guess_event(ev(9.0))
    assert p(gs, "pothole_light") < 0.05 and p(gs, "pothole_deep", "pothole_danger") > 0.5


def test_deep_probability_grows_with_score():
    vals = [p(g.guess_event(ev(s)), "pothole_deep", "pothole_danger") for s in (2, 3, 4, 6, 9)]
    assert vals == sorted(vals)


def test_phone_knock_is_false_signal():
    gs = g.guess_event(ev(2.5, dur=200, pair=0.1, gyro=150))
    assert gs.top in ("handled", "noise") or p(gs, "handled", "noise") > 0.3


def test_slow_long_hit_is_likely_bump():
    gs = g.guess_event(ev(5.5, speed=14, dur=800, pair=0.3))
    assert "bump" in gs.reasons[0] or any("лежач" in r for r in gs.reasons)
    assert p(gs, "bump", "bump_low", "bump_high") > 0.25


def test_known_manhole_nearby_wins():
    gs = g.guess_event(ev(3.0, dur=200, pair=0.2), dict(near_type="manhole", near_passes=7))
    assert p(gs, "manhole", "manhole_sunk", "manhole_raised") > 0.5


def test_tram_context_raises_rails():
    base = p(g.guess_event(ev(4.0)), "rail_tram")
    assert p(g.guess_event(ev(4.0), dict(tram=True)), "rail_tram") > base * 3


def test_options_are_plausible_short_and_always_include_false_signal():
    gs = g.guess_event(ev(1.9))
    opts = g.options_for(gs, taxonomy.driver_option_keys())
    assert "pothole_deep" not in opts and "pothole_danger" not in opts
    assert 3 <= len(opts) <= 8 and "handled" in opts
    strong = g.options_for(g.guess_event(ev(9.0)), taxonomy.driver_option_keys())
    assert "pothole_light" not in strong and "pothole_deep" in strong


def test_fit_needs_data_and_shrinks_to_defaults():
    assert not g.fit_level_params([(3.0, 1)] * 5)["fitted"]
    data = [(2.0 + i * 0.25, min(3, i // 5)) for i in range(20)]
    fit = g.fit_level_params(data)
    assert fit["fitted"] and fit["weight"] < 0.5  # 20 меток — данным доверяем меньше половины
    assert fit["level_theta"] == sorted(fit["level_theta"])


def test_evaluate_reports_honest_metrics():
    rows = []
    for i in range(30):
        s = 2.0 + (i % 3) * 2.5
        rows.append(dict(truth=["pothole_light", "pothole_mid", "pothole_deep"][i % 3], f=ev(s), ctx=None, group=i // 10))
    r = g.evaluate(rows)
    for k in ("n", "majority", "guess", "guess_default_params", "level", "by_label", "by_speed", "by_score", "calibration", "road_vs_not"):
        assert k in r
    assert 0 <= r["guess"]["top1"] <= 1 and r["level"]["n"] == 30
    assert g.evaluate(rows[:4]) == {"n": 4}


@pytest.mark.django_db
def test_stored_guess_after_ingest_and_questions_use_it():
    import json
    from django.test import Client
    from telemetry.models import RoadEvent
    from tests.test_api import JSON, register, trip, ev as api_ev
    c = Client()
    tok = register(c)
    c.post("/api/v1/trips", json.dumps(trip([api_ev(t=30.0, score=2.0)])), content_type=JSON, headers={"X-Device-Token": tok})
    e = RoadEvent.objects.get()
    assert e.guess["top"] and abs(sum(e.guess["probs"].values()) - 1) < 0.02
    q = c.get("/api/v1/questions/next", headers={"X-Device-Token": tok}).json()["questions"][0]
    assert "pothole_deep" not in q["options"] and q["guess_p"] > 0


@pytest.mark.django_db
def test_evolution_endpoint_params_and_backfill():
    import json
    from django.contrib.auth import get_user_model
    from django.core.management import call_command
    from django.test import Client
    from brain.models import Label
    from telemetry.models import RoadEvent
    from tests.test_api import JSON, register, trip, ev as api_ev
    c = Client()
    tok = register(c)
    c.post("/api/v1/trips", json.dumps(trip([api_ev(t=30.0 + i * 20, lat=41.327 + i * 0.01, score=2.0 + i * 0.6) for i in range(8)])), content_type=JSON, headers={"X-Device-Token": tok})
    for e in RoadEvent.objects.all():
        Label.objects.create(event=e, source="driver", label="pothole_light" if e.score < 4 else "pothole_mid", features=e.features, trip_key=str(e.trip_id))
    RoadEvent.objects.update(guess={})
    call_command("backfill_guess")
    assert all(e.guess["probs"] for e in RoadEvent.objects.all())
    get_user_model().objects.create_superuser("boss", "b@x.uz", "pw-12345-pw")
    h = {"HTTP_AUTHORIZATION": "Bearer " + c.post("/api/v1/admin/login", json.dumps({"username": "boss", "password": "pw-12345-pw"}), content_type=JSON).json()["token"]}
    d = c.get("/api/v1/admin/brain/evolution", **h).json()
    assert d["labeled"] == 8 and d["eval"]["n"] == 8 and 0 <= d["intelligence"]["score"] <= 100
    assert d["series"] and d["confusion"] and set(d["intelligence"]["parts"]) == {"data", "lift", "calibration", "coverage"}
    p = c.get("/api/v1/algo/params").json()
    assert p["guess"]["level_theta"] and "params" in p
    from brain import guesser as gg
    assert gg.train_guess().log.startswith("догадка")


@pytest.mark.django_db
def test_marks_store_device_guess_and_evolution_reports_it():
    import json
    from django.contrib.auth import get_user_model
    from django.test import Client
    from django.utils import timezone
    from telemetry.models import DriverMark
    from tests.test_api import JSON, register
    c = Client()
    tok = register(c)
    now = timezone.now().isoformat()
    marks = [dict(client_id=f"g{i}", kind=k, lat=41.3, lon=69.2, at=now, guess=dict(top=t, p=0.6, v="guess-0", top3={t: 0.6}, via="voice")) for i, (k, t) in enumerate([("pothole_mid", "pothole_mid"), ("manhole", "pothole_light")])]
    r = c.post("/api/v1/marks", json.dumps({"marks": marks}), content_type=JSON, headers={"X-Device-Token": tok})
    assert r.status_code == 201 and DriverMark.objects.filter(guess__via="voice").count() == 2
    get_user_model().objects.create_superuser("boss", "b@x.uz", "pw-12345-pw")
    h = {"HTTP_AUTHORIZATION": "Bearer " + c.post("/api/v1/admin/login", json.dumps({"username": "boss", "password": "pw-12345-pw"}), content_type=JSON).json()["token"]}
    d = c.get("/api/v1/admin/brain/evolution", **h).json()["device_guess"]
    assert d["n"] == 2 and d["top1"] == 0.5 and d["voice_share"] == 1.0
