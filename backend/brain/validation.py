"""Антиспам и проверка правдоподобия присланных поездок (этап 3, п.6).

Принцип: мусор не принимаем и снижаем доверие устройства (`Device.trust`), мелкие нестыковки чистим точечно.
Все пороги — в одном месте, настраиваются через settings.HOLESCOPE["LIMITS"].
"""
from __future__ import annotations
import math
from dataclasses import dataclass
from datetime import timedelta
from django.conf import settings
from django.utils import timezone

DEFAULT_LIMITS = dict(
    max_events=2000, max_segments=6000, max_duration_s=12 * 3600, max_distance_km=800.0, max_avg_speed_kmh=160.0,
    max_event_speed_kmh=220.0, max_events_per_km=40.0, max_trips_per_day=60, max_age_days=45, future_slack_s=3600,
    region=(36.0, 55.0, 46.0, 80.0),          # Узбекистан и соседи (min_lat, min_lon, max_lat, max_lon)
    min_trust_for_votes=0.3,                  # устройства с доверием ниже не считаются подтверждающими
)


def limits() -> dict:
    d = dict(DEFAULT_LIMITS)
    d.update(getattr(settings, "HOLESCOPE", {}).get("LIMITS", {}))
    return d


class Rejected(Exception):
    def __init__(self, reason: str, status: int = 400):
        super().__init__(reason)
        self.reason, self.status = reason, status


@dataclass
class Checked:
    events: list
    segments: list
    dropped_events: int
    dropped_segments: int


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _in_region(lat, lon, region) -> bool:
    return _num(lat) and _num(lon) and region[0] <= lat <= region[2] and region[1] <= lon <= region[3]


def check_trip(device, payload: dict, started_at, now=None) -> Checked:
    """Проверяет поездку. Бросает Rejected при явном мусоре; иначе возвращает очищенные события и сегменты."""
    from telemetry.models import Trip
    L = limits()
    now = now or timezone.now()
    if device.blocked:
        raise Rejected("device blocked", 403)
    events, segments = payload.get("events", []), payload.get("segments", [])
    if not isinstance(events, list) or not isinstance(segments, list):
        raise Rejected("events/segments must be lists")
    if len(events) > L["max_events"] or len(segments) > L["max_segments"]:
        raise Rejected("too many events or segments", 413)
    dur, dist = payload.get("duration_s", 0) or 0, payload.get("distance_km", 0) or 0
    if not (_num(dur) and _num(dist)) or dur < 0 or dist < 0:
        raise Rejected("bad duration/distance")
    if dur > L["max_duration_s"] or dist > L["max_distance_km"]:
        raise Rejected("trip too long", 413)
    if dur > 60 and dist / (dur / 3600.0) > L["max_avg_speed_kmh"]:
        raise Rejected("unrealistic average speed")
    if started_at > now + timedelta(seconds=L["future_slack_s"]):
        raise Rejected("trip starts in the future")
    if started_at < now - timedelta(days=L["max_age_days"]):
        raise Rejected("trip too old")
    day_ago = now - timedelta(days=1)
    if Trip.objects.filter(device=device, created__gte=day_ago).count() >= L["max_trips_per_day"]:
        raise Rejected("daily trip limit", 429)
    good, bad = [], 0
    for e in events:
        if not isinstance(e, dict) or not all(_num(e.get(k)) for k in ("t", "lat", "lon", "speed_kmh", "peak", "score")):
            bad += 1
            continue
        if not _in_region(e["lat"], e["lon"], L["region"]) or not (0 <= e["speed_kmh"] <= L["max_event_speed_kmh"]) or e["peak"] < 0 or e["peak"] > 200:
            bad += 1
            continue
        good.append(e)
    # аномальная плотность событий = подозрение на спам/сломанный датчик
    if dist >= 1.0 and len(good) / dist > L["max_events_per_km"]:
        raise Rejected("too many events per km")
    gs, bad_s = [], 0
    for s in segments:
        ok = isinstance(s, dict) and all(_num(s.get(k)) for k in ("lat_a", "lon_a", "lat_b", "lon_b", "speed_kmh", "ri")) and isinstance(s.get("cls"), str)
        if ok and _in_region(s["lat_a"], s["lon_a"], L["region"]) and 0 <= s["speed_kmh"] <= L["max_event_speed_kmh"] and 0 <= s["ri"] < 5:
            gs.append(s)
        else:
            bad_s += 1
    return Checked(good, gs, bad, bad_s)


def adjust_trust(device, accepted: bool, bad_ratio: float = 0.0):
    """Доверие 0..1: медленно растёт за нормальные поездки, быстро падает за мусор."""
    if accepted:
        device.trust = min(1.0, device.trust + 0.01 * (1.0 - min(bad_ratio * 5, 1.0)) - 0.05 * min(bad_ratio * 5, 1.0))
    else:
        device.trust = max(0.0, device.trust - 0.1)
        if device.trust <= 0.0:
            device.blocked = False   # блокировка — только ручная (админка), автоматически не блокируем
    device.save(update_fields=["trust"])
