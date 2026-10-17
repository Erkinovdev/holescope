"""Агрегаты по дороге: индекс ровности сегментов, «заделана» (тихие проезды), калибровка устройств, относительная подвеска."""
from __future__ import annotations
import math
from collections import defaultdict
from datetime import timedelta
import numpy as np
from django.conf import settings
from django.db.models import Count
from django.utils import timezone
from holescope_algo.params import Params
from holescope_algo.roughness import ri_class
from holescope_algo.suspension import relative_softness, softness_score
from roadnet.geo import K, ang_diff, bearing
from roadnet.models import Segment
from telemetry.models import EventCluster, QuietPass, RoadEvent, SegmentScore

LANDMARK_TYPES = ("manhole", "rail_tram", "rail_train", "joint")
ACTIVE = ("candidate", "confirmed", "complaint")


def fixed_rules() -> dict:
    d = dict(min_quiet=3, min_devices=2, min_age_hours=24, min_speed_kmh=20.0, across_m=8.0)
    d.update(getattr(settings, "HOLESCOPE", {}).get("FIXED", {}))
    return d


def current_params() -> Params:
    """Параметры алгоритма активной версии (границы классов ровности и т.д.)."""
    from .models import AlgoVersion
    av = AlgoVersion.objects.filter(active=True).first()
    p = Params()
    if av and av.params:
        for k, v in av.params.items():
            if hasattr(p, k) and k != "features":
                setattr(p, k, tuple(v) if k == "ri_bounds" else v)
    return p


# ───────────────────────── ровность сегментов ─────────────────────────
def refresh_segments(segment_ids, window_days: int = 180) -> int:
    """Пересчёт медианы RI, числа проездов и устройств, класса A–E для сегментов."""
    ids = list(set(segment_ids))
    if not ids:
        return 0
    since = timezone.now() - timedelta(days=window_days)
    rows = SegmentScore.objects.filter(segment_id__in=ids, at__gte=since, speed_kmh__gte=15, speed_kmh__lte=90).values_list("segment_id", "device_id", "ri")
    by: dict[int, list] = defaultdict(list)
    for sid, dev, ri in rows:
        by[sid].append((dev, ri))
    p = current_params()
    upd = []
    for seg in Segment.objects.filter(pk__in=ids):
        v = by.get(seg.pk, [])
        if v:
            seg.ri_median = float(np.median([x[1] for x in v])); seg.ri_n = len(v); seg.ri_devices = len({x[0] for x in v})
            seg.cls = ri_class(seg.ri_median, p)
        else:
            seg.ri_median, seg.ri_n, seg.ri_devices, seg.cls = None, 0, 0, ""
        upd.append(seg)
    Segment.objects.bulk_update(upd, ["ri_median", "ri_n", "ri_devices", "cls"], batch_size=1000)
    return len(upd)


# ───────────────────────── «заделана» ─────────────────────────
def _rel(lat, lon, seg):
    """Положение точки относительно отрезка a→b: (вдоль, поперёк, длина), метры."""
    c = math.cos(math.radians(seg["lat_a"]))
    bx, by = (seg["lon_b"] - seg["lon_a"]) * c * K, (seg["lat_b"] - seg["lat_a"]) * K
    px, py = (lon - seg["lon_a"]) * c * K, (lat - seg["lat_a"]) * K
    L = math.hypot(bx, by) or 1e-9
    return (px * bx + py * by) / L, (px * by - py * bx) / L, L


def record_quiet_passes(trip, device, seg_rows: list[dict], touched_cluster_ids: set[int], now=None) -> int:
    """Проезд мимо известных ям без удара. seg_rows: [{lat_a, lon_a, lat_b, lon_b, speed_kmh, at}]."""
    R = fixed_rules()
    rows = [s for s in seg_rows if s["speed_kmh"] >= R["min_speed_kmh"]]
    if not rows:
        return 0
    pad = 0.0003
    lat_lo = min(min(s["lat_a"], s["lat_b"]) for s in rows) - pad; lat_hi = max(max(s["lat_a"], s["lat_b"]) for s in rows) + pad
    lon_lo = min(min(s["lon_a"], s["lon_b"]) for s in rows) - pad; lon_hi = max(max(s["lon_a"], s["lon_b"]) for s in rows) + pad
    clusters = list(EventCluster.objects.filter(status__in=ACTIVE, lat__gte=lat_lo, lat__lte=lat_hi, lon__gte=lon_lo, lon__lte=lon_hi))
    if not clusters:
        return 0
    cell = 0.0005
    grid = defaultdict(list)
    for c in clusters:
        grid[(int(c.lat / cell), int(c.lon / cell))].append(c)
    made = 0
    seen: set[int] = set()
    for s in rows:
        hd = bearing(s["lat_a"], s["lon_a"], s["lat_b"], s["lon_b"])
        mi, mj = int((s["lat_a"] + s["lat_b"]) / 2 / cell), int((s["lon_a"] + s["lon_b"]) / 2 / cell)
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for c in grid.get((mi + di, mj + dj), ()):
                    if c.pk in touched_cluster_ids or c.pk in seen:
                        continue
                    along, across, L = _rel(c.lat, c.lon, s)
                    if not (0 <= along <= L) or abs(across) > R["across_m"]:
                        continue
                    if c.heading is not None and ang_diff(c.heading, hd) > 70:
                        continue
                    seen.add(c.pk)
                    _, created = QuietPass.objects.get_or_create(cluster=c, trip=trip, defaults=dict(device=device, at=s["at"], speed_kmh=s["speed_kmh"]))
                    if created:
                        EventCluster.objects.filter(pk=c.pk).update(quiet_passes=c.quiet_passes + 1)
                        made += 1
    for pk in seen:
        evaluate_fixed(EventCluster.objects.get(pk=pk), now=now)
    return made


def evaluate_fixed(cluster: EventCluster, now=None) -> bool:
    """Яма считается заделанной, если после последнего удара прошло ≥N тихих проездов от ≥M разных устройств и прошло ≥24 ч."""
    now = now or timezone.now()
    if cluster.status not in ACTIVE:
        return False
    R = fixed_rules()
    since = cluster.last_hit or cluster.first_seen
    if now - since < timedelta(hours=R["min_age_hours"]):
        return False
    q = cluster.quiet.filter(at__gt=since)
    n = q.count()
    devs = q.values("device").distinct().count()
    # отметки водителей «заделана» (вручную, после поездки) считаются как тихие проезды, но не больше одной от устройства
    rep = cluster.reports.filter(state="fixed", at__gt=since)
    rep_devs = rep.values("device").distinct().count()
    n += rep_devs
    devs = len(set(q.values_list("device", flat=True)) | set(rep.values_list("device", flat=True)))
    if n >= R["min_quiet"] and devs >= R["min_devices"] and n >= cluster.passes:
        cluster.status, cluster.fixed_at = "fixed", now
        cluster.save(update_fields=["status", "fixed_at"])
        return True
    return False


def evaluate_all_fixed(now=None) -> int:
    return sum(evaluate_fixed(c, now) for c in EventCluster.objects.filter(status__in=ACTIVE, quiet_passes__gt=0))


# ───────────────────────── голоса по типу ─────────────────────────
TYPE_BY_LABEL = {"manhole": "manhole", "bump": "bump", "joint": "joint", "rail": "rail_tram"}


def refine_cluster_type(cluster: EventCluster, label: str) -> None:
    """Ответы водителей уточняют тип объекта: ≥3 голосов и >60 % → меняем type (люк, лежачий, рельсы, стык)."""
    votes = dict(cluster.type_votes or {})
    votes[label] = votes.get(label, 0) + 1
    cluster.type_votes = votes
    total = sum(votes.values())
    for lab, n in votes.items():
        if lab in TYPE_BY_LABEL and n >= 3 and n / total > 0.6:
            t = TYPE_BY_LABEL[lab]
            if lab == "rail":
                seg = cluster.segment
                t = "rail_train" if seg is not None and seg.level_crossing and not seg.tram else "rail_tram"
            cluster.type = t
            break
    cluster.save(update_fields=["type_votes", "type"])


# ───────────────────────── калибровка устройства ─────────────────────────
def update_calibration(device, min_events: int = 8) -> float | None:
    """По «известным ориентирам» (люки, рельсы, стыки, подтверждённые разными устройствами) сравниваем силу удара этого устройства
    с медианой остальных: calib_gain = медиана (чужая_сила / своя_сила), ограничен 0.5..2, сглажен."""
    evs = list(RoadEvent.objects.filter(device=device, cluster__type__in=LANDMARK_TYPES, cluster__devices__gte=2).select_related("cluster")[:500])
    ratios = []
    for e in evs:
        own = (e.features or {}).get("score_raw", e.score)
        others = [(x.features or {}).get("score_raw", x.score) for x in RoadEvent.objects.filter(cluster_id=e.cluster_id).exclude(device=device)]
        if own and own > 0.5 and others:
            ratios.append(float(np.median(others)) / own)
    if len(ratios) < min_events:
        return None
    new = float(np.clip(np.median(ratios), 0.5, 2.0))
    device.calib_gain = round(0.7 * device.calib_gain + 0.3 * new, 4)
    device.calib_n = len(ratios)
    device.save(update_fields=["calib_gain", "calib_n"])
    return device.calib_gain


# ───────────────────────── относительная подвеска ─────────────────────────
def recompute_vehicle_suspension(vehicle, min_vehicles: int = 3, min_segments: int = 40, window_days: int = 180) -> dict | None:
    """Относительный индекс: ln(RI машины / медиана RI всех машин на тех же сегментах). Нужны сегменты с ≥3 разными машинами."""
    since = timezone.now() - timedelta(days=window_days)
    rows = SegmentScore.objects.filter(trip__vehicle=vehicle, segment__isnull=False, at__gte=since, speed_kmh__gte=20, speed_kmh__lte=60).values_list("segment_id", "ri")
    mine: dict[int, list[float]] = defaultdict(list)
    for sid, ri in rows:
        mine[sid].append(ri)
    if not mine:
        return None
    others = SegmentScore.objects.filter(segment_id__in=list(mine), at__gte=since, speed_kmh__gte=20, speed_kmh__lte=60, trip__vehicle__isnull=False).values_list("segment_id", "trip__vehicle_id", "ri")
    per_seg: dict[int, dict[int, list[float]]] = defaultdict(lambda: defaultdict(list))
    for sid, vid, ri in others:
        per_seg[sid][vid].append(ri)
    car_ri, seg_med = {}, {}
    for sid, vals in mine.items():
        veh = per_seg.get(sid, {})
        if len(veh) < min_vehicles or vehicle.pk not in veh:
            continue
        car_ri[sid] = float(np.mean(vals))
        seg_med[sid] = float(np.median([np.mean(v) for v in veh.values()]))
    rel, n = relative_softness(car_ri, seg_med, min_segments=min_segments)
    sc = softness_score(rel, vehicle.zeta_median, vehicle.f_body_median)
    if rel is not None:
        vehicle.softness_score, vehicle.suspension_cls, vehicle.softness_conf = sc["score"], sc["cls"] or "", sc["confidence"]
        vehicle.km_since_susp_eval = 0.0
        vehicle.save(update_fields=["softness_score", "suspension_cls", "softness_conf", "km_since_susp_eval"])
    return dict(relative=rel, segments=n, **sc)


def refresh_car_model_stats(min_vehicles: int = 1) -> int:
    """Медиана softness_score по моделям (для профиля и «самой мягкой машины»)."""
    from fleet.models import CarModel, Vehicle
    n = 0
    for cm in CarModel.objects.all():
        vals = list(Vehicle.objects.filter(car_model=cm, softness_score__isnull=False).values_list("softness_score", flat=True))
        if len(vals) >= min_vehicles:
            cm.softness_median, cm.softness_n_vehicles = float(np.median(vals)), len(vals)
            cm.save(update_fields=["softness_median", "softness_n_vehicles"])
            n += 1
    return n
