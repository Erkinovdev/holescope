"""Публичные эндпоинты этапа 3: рейтинги улиц и районов, отчёт недели, жалобы, справочники, статистика устройства."""
from __future__ import annotations
from collections import defaultdict
from datetime import timedelta
import numpy as np
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from fleet.models import CarModel, Device, Vehicle
from roadnet.models import District, Road, Segment
from telemetry.models import Complaint, EventCluster, RoadEvent, SegmentScore, Trip
from .auth import body, device_required

ACTIVE = ("candidate", "confirmed", "complaint")
RI_POINTS = {"A": 100, "B": 80, "C": 60, "D": 35, "E": 10}      # ПРОВИЗОРНАЯ шкала 0–100 из классов ровности
MIN_COVERED_KM = 0.2                                              # меньше — рейтинг улицы ненадёжен
MIN_SEGMENTS_FOR_DISTRICT = 20


def _days(request, default=30):
    try:
        return max(1, min(int(request.GET.get("days", default)), 365))
    except ValueError:
        return default


def _exposure(days: int, district_code: str | None = None):
    """Покрытые сегменты за период: {segment_id: length_m}."""
    since = timezone.now() - timedelta(days=days)
    qs = SegmentScore.objects.filter(at__gte=since, segment__isnull=False)
    if district_code:
        qs = qs.filter(segment__district__code=district_code)
    ids = list(qs.values_list("segment_id", flat=True).distinct())
    return dict(Segment.objects.filter(pk__in=ids).values_list("pk", "length_m"))


def rankings_streets(request):
    """Худшие улицы: ям на покрытый километр за N дней. ?scope=city|district&district=UZ-TSH-YUN&days=30&limit=20"""
    days = _days(request)
    scope = request.GET.get("scope", "city")
    code = request.GET.get("district") if scope == "district" else None
    if scope == "district" and not code:
        return JsonResponse({"error": "district=<код района> обязателен при scope=district"}, status=400)
    limit = min(int(request.GET.get("limit", 20) or 20), 100)
    cov = _exposure(days, code)
    seg_road = dict(Segment.objects.filter(pk__in=list(cov)).values_list("pk", "road_id"))
    km_by_road: dict[int, float] = defaultdict(float)
    for sid, length in cov.items():
        km_by_road[seg_road[sid]] += length / 1000.0
    since = timezone.now() - timedelta(days=days)
    cl = EventCluster.objects.filter(status__in=ACTIVE, last_hit__gte=since, segment_id__in=list(cov)).values_list("segment__road_id", flat=True)
    n_by_road: dict[int, int] = defaultdict(int)
    for rid in cl:
        n_by_road[rid] += 1
    roads = {r.pk: r for r in Road.objects.filter(pk__in=list(km_by_road), named=True)}
    rows = []
    for rid, km in km_by_road.items():
        if rid in roads and km >= MIN_COVERED_KM:
            r = roads[rid]
            rows.append(dict(road=r.code, name=r.name_ru, name_uz=r.name_uz, road_class=r.road_class, covered_km=round(km, 2), potholes=n_by_road.get(rid, 0),
                             per_km=round(n_by_road.get(rid, 0) / km, 2)))
    rows.sort(key=lambda x: (-x["per_km"], -x["potholes"]))
    return JsonResponse({"days": days, "scope": scope, "district": code, "min_covered_km": MIN_COVERED_KM, "streets": [dict(rank=i + 1, **r) for i, r in enumerate(rows[:limit])]})


def _score(classes: list[str]) -> float | None:
    if not classes:
        return None
    return round(float(np.mean([RI_POINTS[c] for c in classes])), 1)


def rankings_districts(request):
    """Качество дорог по районам, 0–100 (среднее по классам ровности покрытых сегментов; шкала provisional). ?days=30"""
    days = _days(request)
    cov = _exposure(days)
    by: dict[int | None, list[str]] = defaultdict(list)
    for sid, dist_id, cls in Segment.objects.filter(pk__in=list(cov)).exclude(cls="").values_list("pk", "district_id", "cls"):
        by[dist_id].append(cls)
    names = {d.pk: d for d in District.objects.filter(level="district")}
    out = []
    for dist_id, cls in by.items():
        if dist_id in names and len(cls) >= MIN_SEGMENTS_FOR_DISTRICT:
            d = names[dist_id]
            out.append(dict(code=d.code, name=d.name_ru, name_uz=d.name_uz, score=_score(cls), segments=len(cls)))
    out.sort(key=lambda x: -x["score"])
    all_cls = [c for v in by.values() for c in v]
    return JsonResponse({"days": days, "city_score": _score(all_cls) if len(all_cls) >= MIN_SEGMENTS_FOR_DISTRICT else None, "districts": out,
                         "note": "шкала 0–100 провизорная: A=100, B=80, C=60, D=35, E=10, среднее по покрытым сегментам"})


def weekly_report(request):
    """Отчёт недели: найдено / заделано / жалоб. ?days=7"""
    days = _days(request, 7)
    since = timezone.now() - timedelta(days=days)
    found = EventCluster.objects.filter(first_seen__gte=since).exclude(status="false").count()
    fixed = EventCluster.objects.filter(fixed_at__gte=since).count()
    complaints = Complaint.objects.filter(filed_at__gte=since).count()
    return JsonResponse({"days": days, "found": found, "fixed": fixed, "complaints": complaints,
                         "drivers": Trip.objects.filter(started_at__gte=since).values("device").distinct().count(),
                         "km": round(sum(Trip.objects.filter(started_at__gte=since).values_list("distance_km", flat=True)), 1)})


DICTIONARIES = {
    "event_types": {k: v for k, v in EventCluster.TYPES},
    "event_levels": {"light": "лёгкая", "mid": "средняя", "deep": "глубокая", "danger": "опасная"},
    "event_statuses": {k: v for k, v in EventCluster.STATUS},
    "road_classes": {k: v for k, v in Road.CLASSES},
    "surfaces": {k: v for k, v in Road.SURFACES},
    "roughness_classes": {"A": "ровная", "B": "хорошая", "C": "удовлетворительная", "D": "плохая", "E": "разбитая"},
    "suspension_classes": {k: v for k, v in Vehicle.SUSP},
    "mounts": {"seat": "на сиденье", "cupholder": "в подстаканнике", "holder": "в держателе"},
    "roles": {k: v for k, v in Device.ROLES},
    "trip_modes": {k: v for k, v in Trip.MODES},
    "complaint_statuses": {k: v for k, v in Complaint.STATUS},
    "complaint_channels": {k: v for k, v in Complaint.CHANNELS},
}


def dictionaries(request):
    return JsonResponse(DICTIONARIES)


def car_models(request):
    """Справочник моделей. Характеристики показываются только подтверждённые (specs_verified)."""
    out = []
    for c in CarModel.objects.all():
        d = dict(id=c.pk, brand=c.brand, model=c.model, generation=c.generation, is_ev=c.is_ev, specs_verified=c.specs_verified, rank=c.popularity_rank)
        if c.specs_verified:
            d.update(wheelbase_mm=c.wheelbase_mm, tire_size=c.tire_size, rim_inch=c.rim_inch, source_url=c.source_url)
        out.append(d)
    return JsonResponse({"models": out})


# ───────────────────────── жалобы ─────────────────────────
def _draft_text(cluster: EventCluster, lang: str = "ru") -> str:
    seg = cluster.segment
    street = f"{seg.road.name_ru}" if seg and seg.road.named else f"{cluster.lat:.5f}, {cluster.lon:.5f}"
    district = f", {seg.district.name_ru}" if seg and seg.district else ""
    level = {"light": "лёгкая", "mid": "средняя", "deep": "глубокая", "danger": "опасная"}.get(cluster.level, "")
    days = max(1, (timezone.now() - cluster.first_seen).days)
    return (f"На {street}{district} обнаружена {level} яма. Подтверждена {cluster.devices} водителями, {cluster.passes} проездами за {days} дн. "
            f"Координаты: {cluster.lat:.6f}, {cluster.lon:.6f}. Данные датчиков приложены.").replace("  ", " ")


def _complaint_json(c: Complaint) -> dict:
    cl = c.cluster
    steps = [dict(step="found", done=True, at=cl.first_seen.isoformat(), drivers=cl.devices),
             dict(step="filed", done=c.status != "draft", at=c.filed_at.isoformat() if c.filed_at else None, number=c.external_number, channel=c.channel),
             dict(step="review", done=c.status in ("review", "answered", "fixed"), due=c.due_at.isoformat() if c.due_at else None),
             dict(step="fixed", done=cl.status == "fixed" or c.status == "fixed", at=cl.fixed_at.isoformat() if cl.fixed_at else None)]
    return dict(id=c.pk, cluster_id=cl.pk, channel=c.channel, status=c.status, text=c.text, anonymous=c.anonymous, number=c.external_number, steps=steps,
                created=c.created.isoformat())


@csrf_exempt
@device_required
@require_http_methods(["POST"])
def complaint_create(request):
    """Готовит черновик жалобы по яме (текст и координаты автоматически). Повторный вызов возвращает тот же черновик."""
    d = body(request)
    cl = EventCluster.objects.filter(pk=d.get("cluster_id")).select_related("segment__road", "segment__district").first()
    if not cl:
        return JsonResponse({"error": "cluster not found"}, status=404)
    if cl.status not in ACTIVE:
        return JsonResponse({"error": "pothole is not active"}, status=409)
    existing = Complaint.objects.filter(device=request.device, cluster=cl, status="draft").first()
    c = existing or Complaint.objects.create(cluster=cl, device=request.device, channel=d.get("channel", "xalq_nazorati"), anonymous=bool(d.get("anonymous", True)),
                                             text=_draft_text(cl, request.device.lang))
    return JsonResponse(_complaint_json(c), status=200 if existing else 201)


@csrf_exempt
@device_required
@require_http_methods(["POST"])
def complaint_send(request, cid):
    """«Отправить жалобу»: статус filed. Передача во внешнюю систему (Xalq Nazorati и др.) — TODO интеграции; сейчас обрабатывает администратор."""
    c = Complaint.objects.filter(pk=cid, device=request.device).select_related("cluster").first()
    if not c:
        return JsonResponse({"error": "not found"}, status=404)
    if c.status == "draft":
        c.status, c.filed_at = "filed", timezone.now()
        c.save(update_fields=["status", "filed_at"])
        if c.cluster.status in ("candidate", "confirmed"):
            c.cluster.status = "complaint"
            c.cluster.save(update_fields=["status"])
    return JsonResponse(_complaint_json(c))


@device_required
def complaint_detail(request, cid):
    c = Complaint.objects.filter(pk=cid, device=request.device).select_related("cluster").first()
    if not c:
        return JsonResponse({"error": "not found"}, status=404)
    return JsonResponse(_complaint_json(c))


@device_required
def my_stats(request):
    """Профиль: найдено / подтверждено другими / км."""
    dev = request.device
    found = RoadEvent.objects.filter(device=dev).exclude(cluster__status="false").count()
    clusters = EventCluster.objects.filter(events__device=dev).distinct()
    confirmed = clusters.filter(devices__gte=2).count()
    km = round(sum(Trip.objects.filter(device=dev).values_list("distance_km", flat=True)), 1)
    return JsonResponse({"nickname": dev.nickname, "found": found, "confirmed": confirmed, "km": km, "trips": Trip.objects.filter(device=dev).count(), "trust": round(dev.trust, 2)})
