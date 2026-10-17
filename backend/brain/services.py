"""Ядро «мозга»: приём результатов поездки, привязка к кластерам, пересчёт состояния."""
from __future__ import annotations
import math
from datetime import timedelta
from django.conf import settings
from django.db import transaction
from django.utils import timezone
from fleet.models import Device
from telemetry.models import Trip, RoadEvent, EventCluster, SegmentScore
from holescope_algo.cluster import angdiff, confidence as cl_confidence
from .active_learning import create_questions_for_trip


def _dist_m(lat1, lon1, lat2, lon2):
    k = 111_320.0
    return math.hypot((lon2 - lon1) * k * math.cos(math.radians((lat1 + lat2) / 2)), (lat2 - lat1) * k)


def _clean(v):
    """NaN/inf -> None, numpy-скаляры -> python (иначе JSONField падает на CHECK JSON_VALID)."""
    if isinstance(v, dict):
        return {k: _clean(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [_clean(x) for x in v]
    if hasattr(v, "item") and not isinstance(v, (str, bytes)):
        v = v.item()
    if isinstance(v, float) and not math.isfinite(v):
        return None
    return v


def attach_to_cluster(ev: RoadEvent) -> EventCluster:
    r = settings.HOLESCOPE["CLUSTER_RADIUS_M"]
    d = r / 111_320.0 * 1.6
    cands = EventCluster.objects.filter(lat__gte=ev.lat - d, lat__lte=ev.lat + d, lon__gte=ev.lon - d * 1.5, lon__lte=ev.lon + d * 1.5)
    best, bd = None, 1e9
    for c in cands:
        dm = _dist_m(c.lat, c.lon, ev.lat, ev.lon)
        if dm > r:
            continue
        if ev.heading is not None and c.heading is not None and angdiff(ev.heading, c.heading) > 70:
            continue
        if dm < bd:
            best, bd = c, dm
    if best is None:
        return EventCluster.objects.create(lat=ev.lat, lon=ev.lon, heading=ev.heading, type=ev.type, level=ev.level,
                                           score_median=ev.score, safe_speed_kmh=ev.features.get("safe_speed_kmh"))
    n = best.passes
    best.lat = (best.lat * n + ev.lat) / (n + 1); best.lon = (best.lon * n + ev.lon) / (n + 1)
    best.passes = n + 1
    best.devices = RoadEvent.objects.filter(cluster=best).values("device").distinct().count() + (0 if best.events.filter(device=ev.device).exists() else 1)
    scores = sorted(list(best.events.values_list("score", flat=True)) + [ev.score]); best.score_median = scores[len(scores) // 2]
    best.confidence = cl_confidence(best.passes, best.devices)
    if best.confidence >= 0.7 and best.status == "candidate":
        best.status = "confirmed"
    best.save()
    return best


@transaction.atomic
def ingest_trip(device: Device, payload: dict) -> Trip:
    """payload: результат holescope_algo.pipeline.process_csv ИЛИ пакет событий с телефона (тот же формат полей)."""
    started = payload["started_at"]; started = started if hasattr(started, "tzinfo") else timezone.datetime.fromisoformat(started.replace("Z", "+00:00"))
    trip = Trip.objects.create(device=device, vehicle=device.vehicle, started_at=started,
                               ended_at=started + timedelta(seconds=payload.get("duration_s", 0)),
                               start_reason=payload.get("start_reason", "auto"), end_reason=payload.get("end_reason", ""),
                               mode=payload.get("mode", "car"), mode_conf=payload.get("mode_conf", 0.0),
                               distance_km=payload.get("distance_km", 0.0), mount=device.mount,
                               algo_version=payload.get("algo_version", ""), app_version=device.app_version,
                               summary=_clean(payload.get("summary", {})))
    for e in payload.get("events", []):
        if e.get("type") in ("touch", "noise"):
            continue                                   # не дорога — не храним как событие
        ev = RoadEvent.objects.create(
            trip=trip, device=device, t_offset=e["t"], at=started + timedelta(seconds=e["t"]), lat=e["lat"], lon=e["lon"],
            heading=None if e.get("heading") is None or e["heading"] != e["heading"] else e["heading"],
            speed_kmh=e["speed_kmh"], type=e.get("type", "pothole"), level=e.get("level") or "", confidence=e.get("confidence", 0.0),
            peak=e["peak"], score=e["score"], features=_clean({k: v for k, v in e.items() if k != "wave"}),
            wave=_clean(e.get("wave", [])), algo_version=e.get("algo_version", ""), low_conf=e.get("low_conf", False))
        ev.cluster = attach_to_cluster(ev); ev.save(update_fields=["cluster"])
    for s in payload.get("segments", []):
        SegmentScore.objects.create(trip=trip, device=device, lat_a=s["lat_a"], lon_a=s["lon_a"], lat_b=s["lat_b"], lon_b=s["lon_b"],
                                    speed_kmh=s["speed_kmh"], ri=s["ri"], cls=s["cls"], at=started + timedelta(seconds=s.get("t0", 0)))
    # профиль машины: накопление км и подвеска каждые 25 км
    v = device.vehicle
    if v:
        v.km_total += trip.distance_km; v.km_since_susp_eval += trip.distance_km
        susp = payload.get("suspension") or {}
        if susp.get("score") is not None and v.km_since_susp_eval >= 25:
            v.softness_score = susp["score"]; v.suspension_cls = susp.get("cls") or ""; v.softness_conf = susp.get("confidence", 0.0)
            v.km_since_susp_eval = 0.0
        d = payload.get("damping") or {}
        if d.get("zeta_median"): v.zeta_median, v.f_body_median = d["zeta_median"], d.get("f_body_median")
        v.save()
    device.last_seen = timezone.now(); device.save(update_fields=["last_seen"])
    create_questions_for_trip(trip)
    return trip


def mark_quiet_pass(lat, lon, heading, device):
    """Проезд мимо известной ямы без удара: растёт quiet_passes; после N тихих проездов подряд — «вероятно заделана»."""
    r = settings.HOLESCOPE["CLUSTER_RADIUS_M"]; d = r / 111_320.0 * 1.6
    for c in EventCluster.objects.filter(lat__gte=lat - d, lat__lte=lat + d, lon__gte=lon - d * 1.5, lon__lte=lon + d * 1.5,
                                          status__in=["confirmed", "complaint", "candidate"]):
        if _dist_m(c.lat, c.lon, lat, lon) <= r:
            c.quiet_passes += 1
            if c.quiet_passes >= 3 and c.quiet_passes > c.passes:
                c.status = "fixed"
            c.save()
