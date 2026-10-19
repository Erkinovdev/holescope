"""Отметки водителей: привязка к событиям алгоритма, разметка для обучения, кандидаты от людей."""
from __future__ import annotations
import math
from datetime import timedelta
from django.utils import timezone
from brain import road_stats
from brain.models import Label
from roadnet.matching import get_index
from .models import DriverMark, EventCluster, RoadEvent

MATCH_M, MATCH_S, WAIT_S = 35.0, 90.0, 2 * 3600
LABEL = {"deep": "pothole_deep", "bump": "bump", "manhole": "manhole"}
TYPE = {"pothole": "pothole", "deep": "pothole", "bump": "bump", "manhole": "manhole"}


def _meters(la1, lo1, la2, lo2) -> float:
    dx = (lo2 - lo1) * 111320 * math.cos(math.radians(la1))
    return math.hypot(dx, (la2 - la1) * 111320)


def _label_for(mark: DriverMark, ev: RoadEvent | None) -> str:
    if mark.kind == "pothole":
        lv = ev.level if ev and ev.level in ("light", "mid", "deep") else "mid"
        return f"pothole_{lv}"
    return LABEL[mark.kind]


def _match_event(mark: DriverMark) -> RoadEvent | None:
    lo, hi = mark.at - timedelta(seconds=MATCH_S), mark.at + timedelta(seconds=MATCH_S)
    best, best_d = None, MATCH_M
    for e in RoadEvent.objects.filter(device=mark.device, at__gte=lo, at__lte=hi).select_related("cluster"):
        d = _meters(mark.lat, mark.lon, e.lat, e.lon)
        if d <= best_d:
            best, best_d = e, d
    return best


def _bump_trust(device, delta):
    device.trust = max(0.0, min(1.0, device.trust + delta))
    device.save(update_fields=["trust"])


def _confirm_by_people(c: EventCluster):
    """Яма, которую независимо отметили два разных водителя, подтверждается."""
    n = c.marks.filter(applied=True).values("device").distinct().count()
    if c.status == "candidate" and n >= 2:
        c.status, c.confidence = "confirmed", max(c.confidence, 0.7)
        c.save(update_fields=["status", "confidence"])


def apply_mark(mark: DriverMark, now=None) -> bool:
    """Применяет отметку, если есть к чему привязать (или вышло время ожидания поездки). True — обработана."""
    if mark.applied:
        return True
    now = now or timezone.now()
    ev = _match_event(mark)
    if ev:
        if mark.kind == "not_pothole":
            Label.objects.create(event=ev, source="driver", label="noise", features=ev.features, trip_key=str(ev.trip_id))
            ev.user_label = "nothing"
            ev.save(update_fields=["user_label"])
            if ev.cluster and ev.cluster.passes <= 1:
                ev.cluster.status = "false"
                ev.cluster.save(update_fields=["status"])
        else:
            lab = _label_for(mark, ev)
            Label.objects.create(event=ev, source="driver", label=lab, features=ev.features, trip_key=str(ev.trip_id))
            ev.user_label = lab
            ev.save(update_fields=["user_label"])
            if ev.cluster:
                if lab in ("bump", "manhole"):
                    road_stats.refine_cluster_type(ev.cluster, lab)
                mark.cluster = ev.cluster
        mark.event, mark.applied = ev, True
        mark.save(update_fields=["event", "cluster", "applied"])
        _bump_trust(mark.device, 0.005)
        return True
    if (now - mark.created).total_seconds() < WAIT_S:
        return False  # поездка ещё не загружена — подождём
    mark.applied = True  # алгоритм ничего не нашёл
    if mark.kind != "not_pothole":
        cands = EventCluster.objects.filter(lat__gte=mark.lat - 0.0003, lat__lte=mark.lat + 0.0003, lon__gte=mark.lon - 0.0004, lon__lte=mark.lon + 0.0004).exclude(status__in=("false", "fixed"))
        near = next((c for c in cands if _meters(mark.lat, mark.lon, c.lat, c.lon) <= 25), None)
        if near is None:
            near = EventCluster.objects.create(lat=mark.lat, lon=mark.lon, heading=mark.heading, type=TYPE[mark.kind], level="deep" if mark.kind == "deep" else "mid",
                                               status="candidate", passes=0, devices=0, confidence=0.4, last_hit=mark.at, type_votes={"driver": 1})
            m = get_index().snap(mark.lat, mark.lon, mark.heading)
            if m:
                EventCluster.objects.filter(pk=near.pk).update(segment_id=m.segment_id)
        mark.cluster = near
    mark.save(update_fields=["applied", "cluster"])
    if mark.cluster:
        _confirm_by_people(mark.cluster)
    return True


def apply_pending(device=None, now=None) -> int:
    qs = DriverMark.objects.filter(applied=False).select_related("device")
    if device is not None:
        qs = qs.filter(device=device)
    return sum(1 for m in qs[:2000] if apply_mark(m, now))
