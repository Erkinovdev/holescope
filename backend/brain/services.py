"""Ядро «мозга»: приём поездки (проверка, привязка к дороге, кластеры, «заделана», калибровка), пересчёт состояния."""
from __future__ import annotations
import math
from datetime import timedelta
from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone
from fleet.models import Device
from holescope_algo.cluster import angdiff, confidence as cl_confidence
from roadnet.geo import bearing
from roadnet.matching import get_index
from roadnet.models import Segment
from telemetry.models import EventCluster, RoadEvent, SegmentScore, Trip
from . import guesser, inference, lane, road_stats, validation
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


def _trusted_devices(cluster: EventCluster) -> int:
    min_trust = validation.limits()["min_trust_for_votes"]
    return (RoadEvent.objects.filter(cluster=cluster, device__trust__gte=min_trust).values("device").distinct().count())


def attach_to_cluster(ev: RoadEvent) -> EventCluster:
    r = settings.HOLESCOPE["CLUSTER_RADIUS_M"]
    d = r / 111_320.0 * 1.6
    cands = EventCluster.objects.filter(lat__gte=ev.lat - d, lat__lte=ev.lat + d, lon__gte=ev.lon - d * 1.5, lon__lte=ev.lon + d * 1.5).exclude(status="false")
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
        return EventCluster.objects.create(lat=ev.lat, lon=ev.lon, heading=ev.heading, type=ev.type, level=ev.level, score_median=ev.score,
                                           safe_speed_kmh=ev.features.get("safe_speed_kmh"), last_hit=ev.at)
    n = best.passes
    best.lat = (best.lat * n + ev.lat) / (n + 1)
    best.lon = (best.lon * n + ev.lon) / (n + 1)
    best.passes = n + 1
    best.last_hit = max(best.last_hit, ev.at) if best.last_hit else ev.at
    own_new = not best.events.filter(device=ev.device).exists()
    best.devices = _trusted_devices(best) + (1 if own_new and ev.device.trust >= validation.limits()["min_trust_for_votes"] else 0)
    scores = sorted(list(best.events.values_list("score", flat=True)) + [ev.score])
    best.score_median = scores[len(scores) // 2]
    best.confidence = cl_confidence(best.passes, max(best.devices, 1))
    if best.status == "fixed":                                   # снова бьёт → яму не заделали
        best.status, best.fixed_at = "candidate", None
    if best.confidence >= 0.7 and best.status == "candidate":
        best.status = "confirmed"
    best.save()
    return best


def refresh_lane(cluster: EventCluster) -> None:
    """Пересчитывает сторону/полосу кластера по поперечным смещениям всех его проездов."""
    xs = [f.get("xtrack_m") for f in cluster.events.values_list("features", flat=True) if isinstance(f, dict)]
    cluster.lane = lane.summarize([x for x in xs if isinstance(x, (int, float))])
    EventCluster.objects.filter(pk=cluster.pk).update(lane=cluster.lane)


def _parse_started(payload: dict):
    s = payload["started_at"]
    return s if hasattr(s, "tzinfo") else timezone.datetime.fromisoformat(s.replace("Z", "+00:00"))


@transaction.atomic
def ingest_trip(device: Device, payload: dict, validate: bool = True) -> Trip:
    """payload: результат holescope_algo.pipeline.process_csv ИЛИ пакет с телефона (тот же формат полей).
    Повторная отправка с тем же client_id возвращает уже созданную поездку (trip.duplicate = True)."""
    started = _parse_started(payload)
    client_id = str(payload.get("client_id") or "")[:64]
    if client_id:
        old = Trip.objects.filter(device=device, client_id=client_id).first()
        if old:
            old.duplicate = True
            return old
    if validate:
        checked = validation.check_trip(device, payload, started)
        events, segments = checked.events, checked.segments
        bad_ratio = (checked.dropped_events + checked.dropped_segments) / max(1, len(payload.get("events", [])) + len(payload.get("segments", [])))
    else:
        events, segments, bad_ratio = payload.get("events", []), payload.get("segments", []), 0.0
    mode = payload.get("mode", "car")
    use_map = mode == "car"            # не-авто поездки (автобус, пешком) в карту ям не идут
    trip = Trip.objects.create(
        device=device, vehicle=device.vehicle, started_at=started, ended_at=started + timedelta(seconds=payload.get("duration_s", 0)),
        start_reason=payload.get("start_reason", "auto"), end_reason=payload.get("end_reason", ""), mode=mode, mode_conf=payload.get("mode_conf", 0.0),
        distance_km=payload.get("distance_km", 0.0), mount=device.mount, algo_version=payload.get("algo_version", ""), app_version=device.app_version,
        summary=_clean(payload.get("summary", {})) | ({} if use_map else {"skipped": f"mode={mode}"}), client_id=client_id)
    trip.duplicate = False
    touched_clusters: set[int] = set()
    touched_segments: set[int] = set()
    idx = get_index() if use_map else None
    gain = device.calib_gain or 1.0
    av, model = inference.active_model() if use_map else (None, None)
    guess_params = guesser.active_params()
    lvl_bounds = road_stats.active_level_bounds()  # None — уровень остаётся таким, как посчитал телефон
    if use_map:
        for e in events:
            if e.get("type") in ("touch", "noise"):
                continue                                           # не дорога — не храним как событие
            feats = {k: v for k, v in e.items() if k != "wave"}
            feats["score_raw"] = e["score"]
            conf, ver = e.get("confidence", 0.0), e.get("algo_version", "")
            if model is not None:                                  # серверная модель уточняет решение телефона
                p = inference.road_probability(model, feats)
                if p < 0.2:
                    continue
                conf, ver = round(p, 3), av.version
            hd = None if e.get("heading") is None or e["heading"] != e["heading"] else e["heading"]
            ev = RoadEvent.objects.create(
                trip=trip, device=device, t_offset=e["t"], at=started + timedelta(seconds=e["t"]), lat=e["lat"], lon=e["lon"], heading=hd,
                speed_kmh=e["speed_kmh"], type=e.get("type", "pothole"), level=(road_stats.level_for(round(e["score"] * gain, 3), lvl_bounds) if lvl_bounds and e.get("type", "pothole") == "pothole" else e.get("level") or ""), confidence=conf,
                peak=e["peak"], score=round(e["score"] * gain, 3), features=_clean(feats), wave=_clean(e.get("wave", [])),
                algo_version=ver, low_conf=e.get("low_conf", False))
            ev.cluster = attach_to_cluster(ev)
            ev.guess = guesser.guess_for_event(ev, guess_params)
            ev.save(update_fields=["cluster", "guess"])
            touched_clusters.add(ev.cluster_id)
            if idx is not None:
                m = idx.snap(ev.lat, ev.lon, hd)
                if m:
                    if ev.cluster.segment_id is None:
                        EventCluster.objects.filter(pk=ev.cluster_id).update(segment_id=m.segment_id)
                    ev.features = {**ev.features, "xtrack_m": round(m.xtrack_m, 2)}
                    ev.save(update_fields=["features"])
                    refresh_lane(ev.cluster)
    seg_rows = []
    for s in segments if use_map else []:
        at = started + timedelta(seconds=s.get("t0", 0))
        hd = bearing(s["lat_a"], s["lon_a"], s["lat_b"], s["lon_b"])
        sid = None
        if idx is not None:
            m = idx.snap((s["lat_a"] + s["lat_b"]) / 2, (s["lon_a"] + s["lon_b"]) / 2, hd)
            sid = m.segment_id if m else None
        SegmentScore.objects.create(trip=trip, device=device, segment_id=sid, lat_a=s["lat_a"], lon_a=s["lon_a"], lat_b=s["lat_b"], lon_b=s["lon_b"],
                                    speed_kmh=s["speed_kmh"], ri=s["ri"], cls=s["cls"], at=at)
        if sid:
            touched_segments.add(sid)
        seg_rows.append(dict(lat_a=s["lat_a"], lon_a=s["lon_a"], lat_b=s["lat_b"], lon_b=s["lon_b"], speed_kmh=s["speed_kmh"], at=at))
    if touched_segments:
        road_stats.refresh_segments(touched_segments)
    if use_map and seg_rows and device.trust >= validation.limits()["min_trust_for_votes"]:
        road_stats.record_quiet_passes(trip, device, seg_rows, touched_clusters)
    # профиль машины: км, подвеска каждые 25 км
    v = device.vehicle
    if v:
        v.km_total += trip.distance_km
        v.km_since_susp_eval += trip.distance_km
        d = payload.get("damping") or {}
        if d.get("zeta_median"):
            v.zeta_median, v.f_body_median = d["zeta_median"], d.get("f_body_median")
        v.save()
        if v.km_since_susp_eval >= 25:
            road_stats.recompute_vehicle_suspension(v)
            if v.softness_score is None:                           # данных для относительного индекса ещё нет — резерв с первой поездки
                susp = payload.get("suspension") or {}
                if susp.get("score") is not None:
                    v.softness_score, v.suspension_cls, v.softness_conf = susp["score"], susp.get("cls") or "", susp.get("confidence", 0.0)
                    v.km_since_susp_eval = 0.0
                    v.save()
    validation.adjust_trust(device, True, bad_ratio)
    device.last_seen = timezone.now()
    device.save(update_fields=["last_seen"])
    create_questions_for_trip(trip)
    return trip
