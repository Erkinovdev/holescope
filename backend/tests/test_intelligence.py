"""Разбор «что это»: признаки формы, правила с причинами, подбор границ уровней и ровности."""
import numpy as np
from brain import intelligence as it


def impulse(sign=-1.0, n=120, at=60, amp=8.0):
    t = np.arange(n)
    return list(sign * amp * np.exp(-((t - at) / 2.5) ** 2) * np.cos((t - at) * 0.9))


def washboard(n=120):
    t = np.arange(n)
    return list(5.0 * np.sin(t * 1.4) * (np.abs(t - 60) < 45))


def test_wave_features_distinguish_single_hit_from_washboard():
    a, b = it.wave_features(impulse()), it.wave_features(washboard())
    assert a["w_peaks"] <= 3 < b["w_peaks"]
    assert a["w_kurt"] > b["w_kurt"]
    assert a["w_decay"] < b["w_decay"] + 1
    assert set(it.WAVE_KEYS) == set(a)


def test_wave_features_handle_garbage():
    assert it.wave_features(None)["w_peaks"] == 0.0
    assert it.wave_features([1, 2, None, 3])["w_p2p"] == 0.0
    assert it.wave_features([float("nan")] * 50)["w_kurt"] == 0.0


def test_first_down_is_pothole_like():
    down = it.wave_features(impulse(sign=-1.0))
    up = it.wave_features(impulse(sign=+1.0))
    assert down["w_first_down"] == 1.0 and up["w_first_down"] == 0.0


def test_guess_rules_persistent_pair_near_tram_is_rails():
    g = it.guess_type({"pair": 0.8, "dur_ms": 220, "speed_kmh": 30}, {"c_hit_rate": 1.0, "c_passes": 8, "c_score_cv": 0.1, "c_tram": 1.0})
    assert g.top == "rail_tram" and g.reasons
    assert abs(sum(g.probs.values()) - 1) < 0.02


def test_guess_rules_partial_hits_is_pothole():
    g = it.guess_type({"pair": 0.1, "dur_ms": 150, "speed_kmh": 45}, {"c_hit_rate": 0.4, "c_passes": 6, "c_score_cv": 0.9}, wave=impulse(-1.0))
    assert g.top == "pothole"
    assert any("полосы" in r or "яму" in r for r in g.reasons)


def test_guess_rules_long_persistent_pair_slow_is_bump():
    g = it.guess_type({"pair": 0.9, "dur_ms": 380, "speed_kmh": 20}, {"c_hit_rate": 1.0, "c_passes": 10, "c_score_cv": 0.1}, wave=impulse(+1.0))
    assert g.top == "bump"


def test_guess_rules_many_peaks_is_washboard():
    g = it.guess_type({"pair": 0.3, "dur_ms": 200, "speed_kmh": 40}, {}, wave=washboard())
    assert g.top in ("rough_patch", "broken")


def test_suggest_level_bounds_improves_on_shifted_data():
    rng = np.random.default_rng(0)
    pairs = []
    for lv, (lo, hi) in {"light": (1, 3.5), "mid": (3.5, 6), "deep": (6, 10), "danger": (10, 20)}.items():
        pairs += [(float(rng.uniform(lo, hi)), lv) for _ in range(15)]
    out = it.suggest_level_bounds(pairs)
    assert out["suggested"] and out["acc_suggested"] >= out["acc_current"]
    assert out["acc_suggested"] > 0.85


def test_suggest_level_bounds_needs_data():
    assert it.suggest_level_bounds([(5.0, "mid")] * 3)["suggested"] is None


def test_suggest_ri_bounds_from_ratings():
    data = {"A": [0.02] * 9, "B": [0.04] * 9, "C": [0.07] * 9, "D": [0.11] * 9, "E": [0.2] * 9}
    out = it.suggest_ri_bounds(data)
    assert out["enough"] and out["suggested"] == [0.03, 0.055, 0.09, 0.155]


def test_suggest_ri_bounds_not_enough_or_scrambled():
    assert it.suggest_ri_bounds({"A": [0.02] * 3})["suggested"] is None
    bad = {"A": [0.2] * 9, "B": [0.04] * 9, "C": [0.07] * 9, "D": [0.11] * 9, "E": [0.02] * 9}
    out = it.suggest_ri_bounds(bad)
    assert out["suggested"] is None and "warning" in out
