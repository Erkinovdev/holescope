"""API админки (этап 4): вход, обзор, модерация ям, реестр дорог, устройства и машины, поездки, справочники, жалобы, доступы.
Доступ по ролям: analyst (чтение) < labeler (модерация и разметка) < admin (всё). Токен: Authorization: Bearer <token> (12 ч)."""
from __future__ import annotations
from collections import Counter, defaultdict
from datetime import timedelta
import numpy as np
from django.contrib.auth import authenticate, get_user_model
from django.contrib.auth.models import Group
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.db.models import Avg, Count, Q, Sum
from django.db.models.functions import TruncDate
from django.http import JsonResponse
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from brain.models import AlgoVersion, AuditLog, Label, Question
from fleet.models import CarModel, Device, Vehicle
from roadnet.matching import get_index
from roadnet.models import District, Road, Segment
from telemetry.models import Complaint, EventCluster, QuietPass, RoadEvent, SegmentScore, Trip
from .auth import ROLE_NAMES, body, make_admin_token, role_required, user_role

LEVELS = ["light", "mid", "deep", "danger"]
STATUSES = [k for k, _ in EventCluster.STATUS]
TYPES = [k for k, _ in EventCluster.TYPES]


def audit(request, action: str, target: str, payload=None):
    AuditLog.objects.create(user=request.staff, action=action, target=target, payload=payload or {})


def page_of(qs, request, ser, default=50, maxsize=200):
    try:
        size = max(1, min(int(request.GET.get("size", default)), maxsize))
        page = max(1, int(request.GET.get("page", 1)))
    except ValueError:
        size, page = default, 1
    total = qs.count()
    items = [ser(x) for x in qs[(page - 1) * size: page * size]]
    return {"items": items, "total": total, "page": page, "size": size}


def iso(d):
    return d.isoformat() if d else None


# ───────────────────────── вход ─────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def login(request):
    d = body(request)
    u = authenticate(request, username=d.get("username", ""), password=d.get("password", ""))
    r = user_role(u) if u else None
    if not r:
        return JsonResponse({"error": "неверный логин или пароль"}, status=401)
    return JsonResponse({"token": make_admin_token(u), "user": {"username": u.username, "role": r, "role_name": ROLE_NAMES[r]}})


@role_required("analyst")
def me(request):
    return JsonResponse({"username": request.staff.username, "role": request.staff_role, "role_name": ROLE_NAMES[request.staff_role]})


# ───────────────────────── обзор ─────────────────────────
@role_required("analyst")
def overview(request):
    days = max(1, min(int(request.GET.get("days", 30) or 30), 365))
    now = timezone.now()
    since = now - timedelta(days=days)
    trips = Trip.objects.filter(started_at__gte=since)
    agg = trips.aggregate(n=Count("id"), km=Sum("distance_km"))
    status_counts = dict(EventCluster.objects.values_list("status").annotate(n=Count("id")))
    series = defaultdict(lambda: dict(trips=0, km=0.0, events=0, clusters=0))
    for r in trips.annotate(d=TruncDate("started_at")).values("d").annotate(n=Count("id"), km=Sum("distance_km")):
        series[r["d"].isoformat()].update(trips=r["n"], km=round(r["km"] or 0, 1))
    for r in RoadEvent.objects.filter(at__gte=since).annotate(d=TruncDate("at")).values("d").annotate(n=Count("id")):
        series[r["d"].isoformat()]["events"] = r["n"]
    for r in EventCluster.objects.filter(first_seen__gte=since).annotate(d=TruncDate("first_seen")).values("d").annotate(n=Count("id")):
        series[r["d"].isoformat()]["clusters"] = r["n"]
    days_list = [(since + timedelta(days=i + 1)).date().isoformat() for i in range(days)]
    recent = EventCluster.objects.select_related("segment__road").order_by("-last_hit", "-id")[:8]
    av = AlgoVersion.objects.filter(active=True).first()
    return JsonResponse({
        "days": days,
        "kpi": dict(trips=agg["n"], km=round(agg["km"] or 0, 1), events=RoadEvent.objects.filter(at__gte=since).count(),
                    clusters_total=EventCluster.objects.count(), confirmed=status_counts.get("confirmed", 0) + status_counts.get("complaint", 0),
                    fixed=status_counts.get("fixed", 0), candidates=status_counts.get("candidate", 0),
                    devices_active=Device.objects.filter(last_seen__gte=now - timedelta(days=7)).count(), devices_total=Device.objects.count(),
                    labels=Label.objects.count()),
        "queues": dict(candidates_single=EventCluster.objects.filter(status="candidate", passes__lte=1).count(),
                       questions_open=Question.objects.filter(status="open").count(),
                       complaints_to_file=Complaint.objects.filter(status="filed", external_number="").count()),
        "series": [dict(day=d, **series.get(d, dict(trips=0, km=0.0, events=0, clusters=0))) for d in days_list],
        "recent": [cluster_json(c) for c in recent],
        "classes": {**{k: 0 for k in "ABCDE"}, **dict(Segment.objects.exclude(cls="").values_list("cls").annotate(n=Count("id")))},
        "segments_total": Segment.objects.count(),
        "brain": dict(version=(av.version if av else None), f1=(((av.metrics or {}).get("model") or {}).get("f1") if av else None), labels=Label.objects.count()),
    })

from brain.explain import analyze_cluster, explain_event, explain_cluster  # noqa: E402


# ───────────────────────── ямы (модерация) ─────────────────────────
def cluster_json(c: EventCluster) -> dict:
    seg = c.segment
    return dict(id=c.pk, lat=c.lat, lon=c.lon, heading=c.heading, type=c.type, level=c.level, status=c.status, passes=c.passes, devices=c.devices,
                quiet_passes=c.quiet_passes, confidence=round(c.confidence, 3), score_median=round(c.score_median, 2), safe_speed=c.safe_speed_kmh,
                first_seen=iso(c.first_seen), last_hit=iso(c.last_hit), fixed_at=iso(c.fixed_at),
                street=seg.road.name_ru if seg and seg.road.named else None, road=seg.road.code if seg else None, segment=seg.code if seg else None,
                district=seg.district.name_ru if seg and seg.district else None)


@role_required("analyst")
def clusters_list(request):
    g = request.GET
    qs = EventCluster.objects.select_related("segment__road", "segment__district")
    if g.get("status"):
        qs = qs.filter(status__in=g["status"].split(","))
    if g.get("type"):
        qs = qs.filter(type__in=g["type"].split(","))
    if g.get("level"):
        qs = qs.filter(level__in=g["level"].split(","))
    if g.get("district"):
        qs = qs.filter(segment__district__code=g["district"])
    if g.get("q"):
        qs = qs.filter(segment__road__name_key__contains=g["q"].lower())
    if g.get("min_passes"):
        qs = qs.filter(passes__gte=int(g["min_passes"]))
    if g.get("bbox"):
        try:
            a, b, c, d = [float(x) for x in g["bbox"].split(",")]
            qs = qs.filter(lat__gte=a, lat__lte=c, lon__gte=b, lon__lte=d)
        except ValueError:
            return JsonResponse({"error": "bbox=min_lat,min_lon,max_lat,max_lon"}, status=400)
    sort = g.get("sort", "-last_hit")
    if sort.lstrip("-") in ("last_hit", "first_seen", "passes", "devices", "score_median", "confidence", "id"):
        qs = qs.order_by(sort, "-id")
    return JsonResponse(page_of(qs, request, cluster_json))


@role_required("analyst")
def cluster_detail(request, cid):
    c = EventCluster.objects.select_related("segment__road", "segment__district").filter(pk=cid).first()
    if not c:
        return JsonResponse({"error": "not found"}, status=404)
    evs = [dict(id=e.pk, at=iso(e.at), device=e.device.nickname, device_id=e.device_id, speed_kmh=e.speed_kmh, peak=e.peak, score=e.score, type=e.type, level=e.level,
                confidence=e.confidence, user_label=e.user_label, trip=e.trip_id, wave=e.wave, algo_version=e.algo_version, explain=explain_event(e), guess=(e.guess or None),
                features={k: e.features.get(k) for k in ("ratio", "dur_ms", "pair", "first", "hf_share", "gyro_peak", "noise") if isinstance(e.features, dict)})
           for e in c.events.select_related("device").order_by("-at")[:60]]
    return JsonResponse(dict(cluster_json(c), why=explain_cluster(c, evs), analysis=analyze_cluster(c), events=evs, type_votes=c.type_votes, complaints=c.complaints.count(),
                             quiet=list(c.quiet.order_by("-at").values("at", "speed_kmh", "device_id")[:20])))


@csrf_exempt
@role_required("labeler")
@require_http_methods(["PATCH"])
def cluster_patch(request, cid):
    c = EventCluster.objects.filter(pk=cid).first()
    if not c:
        return JsonResponse({"error": "not found"}, status=404)
    d, ch = body(request), {}
    if "status" in d:
        if d["status"] not in STATUSES:
            return JsonResponse({"error": f"status: {STATUSES}"}, status=400)
        ch["status"] = d["status"]
        if d["status"] == "fixed":
            c.fixed_at = timezone.now()
        elif c.status == "fixed":
            c.fixed_at = None
    if "type" in d:
        if d["type"] not in TYPES:
            return JsonResponse({"error": f"type: {TYPES}"}, status=400)
        ch["type"] = d["type"]
    if "level" in d:
        if d["level"] not in LEVELS + [""]:
            return JsonResponse({"error": f"level: {LEVELS}"}, status=400)
        ch["level"] = d["level"]
    if "safe_speed" in d:
        ch["safe_speed_kmh"] = None if d["safe_speed"] is None else max(5, min(int(d["safe_speed"]), 120))
    if not ch:
        return JsonResponse({"error": "нечего менять"}, status=400)
    old = {k: getattr(c, k) for k in ch}
    for k, v in ch.items():
        setattr(c, k, v)
    c.save()
    audit(request, "cluster.patch", f"cluster:{c.pk}", dict(old=old, new=ch))
    # ручная правка типа/уровня — тоже разметка для обучения (по событиям кластера)
    if "type" in ch or "level" in ch:
        lab = {"manhole": "manhole", "bump": "bump", "pothole": {"light": "pothole_light", "mid": "pothole_mid", "deep": "pothole_deep", "danger": "pothole_deep"}.get(c.level, "pothole_light"),
               "joint": "joint", "rail_tram": "rail", "rail_train": "rail"}.get(c.type)
        if lab:
            for e in c.events.all()[:20]:
                Label.objects.create(event=e, source="admin", label=lab, features=e.features, trip_key=str(e.trip_id))
    return JsonResponse(cluster_json(EventCluster.objects.select_related("segment__road", "segment__district").get(pk=c.pk)))


@csrf_exempt
@role_required("labeler")
@require_http_methods(["POST"])
def clusters_merge(request):
    """Объединить дубли: {"ids": [1,2,3], "into": 1 (необязательно)} — события переходят в целевую яму."""
    d = body(request)
    ids = [int(x) for x in d.get("ids", [])]
    cl = list(EventCluster.objects.filter(pk__in=ids))
    if len(cl) < 2:
        return JsonResponse({"error": "нужно ≥2 существующих ям"}, status=400)
    target = next((c for c in cl if c.pk == d.get("into")), None) or max(cl, key=lambda c: c.passes)
    others = [c for c in cl if c.pk != target.pk]
    for c in others:
        RoadEvent.objects.filter(cluster=c).update(cluster=target)
        QuietPass.objects.filter(cluster=c).update(cluster=target)
        c.complaints.update(cluster=target)
        target.type_votes = dict(Counter(target.type_votes or {}) + Counter(c.type_votes or {}))
    evs = list(target.events.select_related("device"))
    if evs:
        target.passes = len(evs)
        target.devices = len({e.device_id for e in evs if e.device.trust >= 0.3})
        target.lat, target.lon = float(np.mean([e.lat for e in evs])), float(np.mean([e.lon for e in evs]))
        target.score_median = float(np.median([e.score for e in evs]))
        target.last_hit = max(e.at for e in evs)
        from holescope_algo.cluster import confidence as conf
        target.confidence = conf(target.passes, max(target.devices, 1))
    target.save()
    audit(request, "cluster.merge", f"cluster:{target.pk}", dict(merged=[c.pk for c in others]))
    EventCluster.objects.filter(pk__in=[c.pk for c in others]).delete()
    return JsonResponse(cluster_json(EventCluster.objects.select_related("segment__road", "segment__district").get(pk=target.pk)))


@csrf_exempt
@role_required("labeler")
@require_http_methods(["POST"])
def cluster_create(request):
    """Добавить яму вручную (нашли на месте / по жалобе). Сразу «подтверждена» человеком."""
    d = body(request)
    try:
        lat, lon = float(d["lat"]), float(d["lon"])
    except (KeyError, TypeError, ValueError):
        return JsonResponse({"error": "lat, lon"}, status=400)
    if not (36 <= lat <= 46 and 55 <= lon <= 80):
        return JsonResponse({"error": "координаты вне региона"}, status=400)
    t, lv = d.get("type", "pothole"), d.get("level", "mid")
    if t not in TYPES or lv not in LEVELS:
        return JsonResponse({"error": "type/level"}, status=400)
    hd = d.get("heading")
    c = EventCluster.objects.create(lat=lat, lon=lon, heading=hd, type=t, level=lv, status="confirmed", passes=0, devices=0, confidence=1.0, last_hit=timezone.now(), type_votes={"admin": 1})
    m = get_index().snap(lat, lon, hd)
    if m:
        EventCluster.objects.filter(pk=c.pk).update(segment_id=m.segment_id)
    audit(request, "cluster.create", f"cluster:{c.pk}", dict(lat=lat, lon=lon, type=t, level=lv))
    return JsonResponse(cluster_json(EventCluster.objects.select_related("segment__road", "segment__district").get(pk=c.pk)), status=201)


# ───────────────────────── дороги ─────────────────────────
def road_json(r: Road, extra=None) -> dict:
    d = dict(id=r.pk, code=r.code, name_ru=r.name_ru, name_uz=r.name_uz, road_class=r.road_class, surface=r.surface, named=r.named, length_km=round(r.length_m / 1000, 2),
             district=r.district.name_ru if r.district else None, district_code=r.district.code if r.district else None, has_tram=r.has_tram,
             has_level_crossing=r.has_level_crossing, speed_limit_kmh=r.speed_limit_kmh, class_reviewed=r.class_reviewed)
    d.update(extra or {})
    return d


@role_required("analyst")
def roads_list(request):
    g = request.GET
    qs = Road.objects.select_related("district")
    if g.get("class"):
        qs = qs.filter(road_class__in=g["class"].split(","))
    if g.get("district"):
        qs = qs.filter(district__code=g["district"])
    if g.get("q"):
        qs = qs.filter(Q(name_key__contains=g["q"].lower()) | Q(code__iexact=g["q"]))
    if g.get("named") in ("0", "1"):
        qs = qs.filter(named=g["named"] == "1")
    if g.get("reviewed") in ("0", "1"):
        qs = qs.filter(class_reviewed=g["reviewed"] == "1")
    qs = qs.order_by("road_class", "-length_m")
    res = page_of(qs, request, lambda r: r)
    ids = [r.pk for r in res["items"]]
    stats = {x["road_id"]: x for x in Segment.objects.filter(road_id__in=ids).values("road_id").annotate(n=Count("id"), ri=Avg("ri_median"), scored=Count("id", filter=~Q(cls="")))}
    res["items"] = [road_json(r, dict(segments=stats.get(r.pk, {}).get("n", 0), scored=stats.get(r.pk, {}).get("scored", 0),
                                      ri_avg=round(stats[r.pk]["ri"], 4) if stats.get(r.pk, {}).get("ri") is not None else None)) for r in res["items"]]
    return JsonResponse(res)


@role_required("analyst")
def road_detail(request, rid):
    r = Road.objects.select_related("district").filter(pk=rid).first()
    if not r:
        return JsonResponse({"error": "not found"}, status=404)
    classes = dict(Segment.objects.filter(road=r).exclude(cls="").values_list("cls").annotate(n=Count("id")))
    first = list(r.segments.order_by("direction", "index").values("id", "index", "direction", "lat_a", "lon_a", "lat_b", "lon_b", "cls", "ri_median", "ri_n")[:400])
    return JsonResponse(road_json(r, dict(classes=classes, segments_total=r.segments.count(), segments=first, osm_way_ids=r.osm_way_ids[:20],
                                          clusters=EventCluster.objects.filter(segment__road=r, status__in=["candidate", "confirmed", "complaint"]).count())))


@csrf_exempt
@role_required("admin")
@require_http_methods(["PATCH"])
def road_patch(request, rid):
    r = Road.objects.filter(pk=rid).first()
    if not r:
        return JsonResponse({"error": "not found"}, status=404)
    d, ch = body(request), {}
    if "road_class" in d:
        if d["road_class"] not in [k for k, _ in Road.CLASSES]:
            return JsonResponse({"error": "road_class"}, status=400)
        ch["road_class"] = d["road_class"]
    if "surface" in d:
        if d["surface"] not in [k for k, _ in Road.SURFACES]:
            return JsonResponse({"error": "surface"}, status=400)
        ch["surface"] = d["surface"]
    for k in ("name_ru", "name_uz"):
        if k in d:
            ch[k] = str(d[k]).strip()[:120]
    if "speed_limit_kmh" in d:
        ch["speed_limit_kmh"] = None if d["speed_limit_kmh"] in (None, "") else max(5, min(int(d["speed_limit_kmh"]), 140))
    if not ch:
        return JsonResponse({"error": "нечего менять"}, status=400)
    old = {k: getattr(r, k) for k in ch}
    for k, v in ch.items():
        setattr(r, k, v)
    if "road_class" in ch or "surface" in ch:
        r.class_reviewed = True
    r.save()
    if "surface" in ch:
        Segment.objects.filter(road=r).update(surface=ch["surface"])
    audit(request, "road.patch", f"road:{r.pk}", dict(old=old, new=ch))
    return JsonResponse(road_json(Road.objects.select_related("district").get(pk=r.pk)))


# ───────────────────────── устройства и машины ─────────────────────────
def vehicle_json(v: Vehicle | None):
    if not v:
        return None
    return dict(id=v.pk, name=v.name, car_model_id=v.car_model_id, car_model=str(v.car_model) if v.car_model else None, year=v.year, rim_inch=v.rim_inch,
                tire_pressure_bar=v.tire_pressure_bar, wheelbase_mm=v.wheelbase_mm, wheelbase_effective_m=v.wb_m, suspension_note=v.suspension_note,
                suspension_cls=v.suspension_cls, softness_score=v.softness_score, softness_conf=v.softness_conf, km_total=round(v.km_total, 1),
                zeta_median=v.zeta_median, f_body_median=v.f_body_median, model_guess=str(v.model_guess) if v.model_guess else None, model_guess_conf=v.model_guess_conf)


def device_json(d: Device, trips=None) -> dict:
    return dict(id=d.pk, nickname=d.nickname, platform=d.platform, phone_model=d.phone_model, app_version=d.app_version, role=d.role, mount=d.mount, lang=d.lang,
                calib_gain=d.calib_gain, calib_n=d.calib_n, trust=round(d.trust, 3), blocked=d.blocked, last_seen=iso(d.last_seen), created=iso(d.created),
                vehicle=vehicle_json(d.vehicle), trips=trips)


@role_required("analyst")
def devices_list(request):
    g = request.GET
    qs = Device.objects.select_related("vehicle__car_model").annotate(n_trips=Count("trips"))
    if g.get("q"):
        qs = qs.filter(Q(nickname__icontains=g["q"]) | Q(phone_model__icontains=g["q"]))
    if g.get("role"):
        qs = qs.filter(role=g["role"])
    if g.get("blocked") in ("0", "1"):
        qs = qs.filter(blocked=g["blocked"] == "1")
    qs = qs.order_by("-last_seen", "-id")
    return JsonResponse(page_of(qs, request, lambda d: dict(device_json(d), trips=d.n_trips)))


@role_required("analyst")
def device_detail(request, did):
    d = Device.objects.select_related("vehicle__car_model", "vehicle__model_guess").filter(pk=did).first()
    if not d:
        return JsonResponse({"error": "not found"}, status=404)
    trips = [dict(id=t.pk, started_at=iso(t.started_at), distance_km=round(t.distance_km, 2), mode=t.mode, events=t.events.count(), algo_version=t.algo_version)
             for t in d.trips.order_by("-started_at")[:30]]
    out = device_json(d, trips)
    out["events_total"] = RoadEvent.objects.filter(device=d).count()
    out["labels"] = Label.objects.filter(event__device=d).count()
    return JsonResponse(out)


@csrf_exempt
@role_required("admin")
@require_http_methods(["PATCH"])
def device_patch(request, did):
    dev = Device.objects.filter(pk=did).first()
    if not dev:
        return JsonResponse({"error": "not found"}, status=404)
    d, ch = body(request), {}
    if "role" in d:
        if d["role"] not in [k for k, _ in Device.ROLES]:
            return JsonResponse({"error": "role"}, status=400)
        ch["role"] = d["role"]
    if "blocked" in d:
        ch["blocked"] = bool(d["blocked"])
    if "trust" in d:
        ch["trust"] = max(0.0, min(float(d["trust"]), 1.0))
    if "mount" in d:
        if d["mount"] not in ("", "seat", "cupholder", "holder"):
            return JsonResponse({"error": "mount"}, status=400)
        ch["mount"] = d["mount"]
    if d.get("reset_calibration"):
        ch.update(calib_gain=1.0, calib_n=0)
    if "calib_gain" in d:
        ch["calib_gain"] = max(0.5, min(float(d["calib_gain"]), 2.0))
    if "nickname" in d:
        ch["nickname"] = str(d["nickname"]).strip()[:60]
    if not ch:
        return JsonResponse({"error": "нечего менять"}, status=400)
    old = {k: getattr(dev, k) for k in ch}
    for k, v in ch.items():
        setattr(dev, k, v)
    dev.save()
    audit(request, "device.patch", f"device:{dev.pk}", dict(old=old, new=ch))
    return JsonResponse(device_json(Device.objects.select_related("vehicle__car_model").get(pk=dev.pk)))


@csrf_exempt
@role_required("admin")
@require_http_methods(["PATCH"])
def vehicle_patch(request, vid):
    """Профиль машины: модель, год, колёсная база, шины, давление, класс подвески (ручная правка)."""
    v = Vehicle.objects.filter(pk=vid).first()
    if not v:
        return JsonResponse({"error": "not found"}, status=404)
    d, ch = body(request), {}
    try:
        if "name" in d:
            ch["name"] = str(d["name"]).strip()[:80]
        if "car_model_id" in d:
            cm = None if d["car_model_id"] in (None, "") else CarModel.objects.filter(pk=d["car_model_id"]).first()
            if d["car_model_id"] not in (None, "") and not cm:
                return JsonResponse({"error": "car_model_id не найден"}, status=400)
            ch["car_model"] = cm
        if "year" in d:
            y = None if d["year"] in (None, "") else int(d["year"])
            if y is not None and not 1950 <= y <= 2035:
                return JsonResponse({"error": "year 1950–2035"}, status=400)
            ch["year"] = y
        if "wheelbase_mm" in d:
            w = None if d["wheelbase_mm"] in (None, "") else int(d["wheelbase_mm"])
            if w is not None and not 1500 <= w <= 4500:
                return JsonResponse({"error": "wheelbase_mm 1500–4500"}, status=400)
            ch["wheelbase_mm"] = w
        if "rim_inch" in d:
            r = None if d["rim_inch"] in (None, "") else int(d["rim_inch"])
            if r is not None and not 10 <= r <= 26:
                return JsonResponse({"error": "rim_inch 10–26"}, status=400)
            ch["rim_inch"] = r
        if "tire_pressure_bar" in d:
            p = None if d["tire_pressure_bar"] in (None, "") else float(d["tire_pressure_bar"])
            if p is not None and not 0.5 <= p <= 6.0:
                return JsonResponse({"error": "tire_pressure_bar 0.5–6"}, status=400)
            ch["tire_pressure_bar"] = p
        if "suspension_note" in d:
            ch["suspension_note"] = str(d["suspension_note"]).strip()[:120]
        if "suspension_cls" in d:
            if d["suspension_cls"] not in ("", "S1", "S2", "S3", "S4", "S5"):
                return JsonResponse({"error": "suspension_cls S1–S5"}, status=400)
            ch["suspension_cls"] = d["suspension_cls"]
    except (TypeError, ValueError):
        return JsonResponse({"error": "неверный формат числа"}, status=400)
    if not ch:
        return JsonResponse({"error": "нечего менять"}, status=400)
    for k, val in ch.items():
        setattr(v, k, val)
    v.save()
    audit(request, "vehicle.patch", f"vehicle:{v.pk}", {k: (str(x) if k == "car_model" else x) for k, x in ch.items()})
    return JsonResponse(vehicle_json(Vehicle.objects.select_related("car_model", "model_guess").get(pk=v.pk)))


# ───────────────────────── поездки ─────────────────────────
@role_required("analyst")
def trips_list(request):
    g = request.GET
    qs = Trip.objects.select_related("device").annotate(n_events=Count("events", distinct=True))
    if g.get("device"):
        qs = qs.filter(device_id=g["device"])
    if g.get("mode"):
        qs = qs.filter(mode=g["mode"])
    for key, fld in (("from", "started_at__gte"), ("to", "started_at__lte")):
        if g.get(key):
            dt = parse_datetime(g[key]) or parse_datetime(g[key] + "T00:00:00+05:00")
            if dt:
                qs = qs.filter(**{fld: dt})
    return JsonResponse(page_of(qs.order_by("-started_at"), request, lambda t: dict(
        id=t.pk, device=t.device.nickname, device_id=t.device_id, started_at=iso(t.started_at), ended_at=iso(t.ended_at), distance_km=round(t.distance_km, 2), mode=t.mode,
        events=t.n_events, algo_version=t.algo_version, end_reason=t.end_reason)))


@role_required("analyst")
def trip_detail(request, tid):
    t = Trip.objects.select_related("device").filter(pk=tid).first()
    if not t:
        return JsonResponse({"error": "not found"}, status=404)
    evs = [dict(id=e.pk, t=e.t_offset, lat=e.lat, lon=e.lon, speed_kmh=e.speed_kmh, peak=e.peak, score=e.score, type=e.type, level=e.level, confidence=e.confidence,
                cluster=e.cluster_id, user_label=e.user_label, wave=e.wave) for e in t.events.order_by("t_offset")]
    segs = list(t.seg_scores.order_by("at").values("lat_a", "lon_a", "lat_b", "lon_b", "ri", "cls", "speed_kmh"))
    return JsonResponse(dict(id=t.pk, device=t.device.nickname, device_id=t.device_id, started_at=iso(t.started_at), ended_at=iso(t.ended_at), distance_km=round(t.distance_km, 2),
                             mode=t.mode, mode_conf=t.mode_conf, algo_version=t.algo_version, end_reason=t.end_reason, summary=t.summary, events=evs, segments=segs,
                             quiet_passes=t.quiet_passes.count()))


# ───────────────────────── справочник моделей авто ─────────────────────────
def car_json(c: CarModel):
    return dict(id=c.pk, brand=c.brand, model=c.model, generation=c.generation, body=c.body, is_ev=c.is_ev, wheelbase_mm=c.wheelbase_mm, length_mm=c.length_mm,
                tire_size=c.tire_size, rim_inch=c.rim_inch, popularity_rank=c.popularity_rank, specs_verified=c.specs_verified, source_url=c.source_url,
                softness_median=c.softness_median, softness_n_vehicles=c.softness_n_vehicles)


@role_required("analyst")
def car_models_admin(request):
    return JsonResponse({"items": [car_json(c) for c in CarModel.objects.all()]})


def _apply_car(c: CarModel, d: dict):
    for k in ("brand", "model", "generation", "body", "tire_size", "source_url"):
        if k in d:
            setattr(c, k, str(d[k]).strip())
    for k in ("wheelbase_mm", "length_mm", "rim_inch", "popularity_rank"):
        if k in d:
            setattr(c, k, None if d[k] in (None, "") else int(d[k]))
    if "is_ev" in d:
        c.is_ev = bool(d["is_ev"])
    if "specs_verified" in d:
        c.specs_verified = bool(d["specs_verified"])
    if c.specs_verified and not c.source_url:
        raise ValueError("для подтверждённых характеристик нужна ссылка на источник (source_url)")
    if c.wheelbase_mm is not None and not 1500 <= c.wheelbase_mm <= 4500:
        raise ValueError("wheelbase_mm 1500–4500")


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def car_model_create(request):
    d = body(request)
    if not d.get("brand") or not d.get("model"):
        return JsonResponse({"error": "brand и model обязательны"}, status=400)
    c = CarModel()
    try:
        _apply_car(c, d)
        c.save()
    except (ValueError, TypeError) as e:
        return JsonResponse({"error": str(e)}, status=400)
    audit(request, "carmodel.create", f"carmodel:{c.pk}", d)
    return JsonResponse(car_json(c), status=201)


@csrf_exempt
@role_required("admin")
@require_http_methods(["PATCH"])
def car_model_patch(request, cid):
    c = CarModel.objects.filter(pk=cid).first()
    if not c:
        return JsonResponse({"error": "not found"}, status=404)
    d = body(request)
    try:
        _apply_car(c, d)
        c.save()
    except (ValueError, TypeError) as e:
        return JsonResponse({"error": str(e)}, status=400)
    audit(request, "carmodel.patch", f"carmodel:{c.pk}", d)
    return JsonResponse(car_json(c))


# ───────────────────────── жалобы ─────────────────────────
def complaint_json(c: Complaint):
    cl = c.cluster
    seg = cl.segment
    return dict(id=c.pk, cluster_id=cl.pk, street=seg.road.name_ru if seg and seg.road.named else None, channel=c.channel, status=c.status, external_number=c.external_number,
                text=c.text, anonymous=c.anonymous, created=iso(c.created), filed_at=iso(c.filed_at), due_at=iso(c.due_at), answered_at=iso(c.answered_at), cluster_status=cl.status)


@role_required("analyst")
def complaints_admin(request):
    qs = Complaint.objects.select_related("cluster__segment__road")
    if request.GET.get("status"):
        qs = qs.filter(status__in=request.GET["status"].split(","))
    return JsonResponse(page_of(qs.order_by("-created"), request, complaint_json))


@csrf_exempt
@role_required("labeler")
@require_http_methods(["PATCH"])
def complaint_patch(request, cid):
    c = Complaint.objects.select_related("cluster__segment__road").filter(pk=cid).first()
    if not c:
        return JsonResponse({"error": "not found"}, status=404)
    d = body(request)
    if "status" in d:
        if d["status"] not in [k for k, _ in Complaint.STATUS]:
            return JsonResponse({"error": "status"}, status=400)
        if d["status"] != c.status:
            now = timezone.now()
            if d["status"] == "filed" and not c.filed_at:
                c.filed_at = now
            if d["status"] in ("answered", "fixed"):
                c.answered_at = now
            c.status = d["status"]
    if "external_number" in d:
        c.external_number = str(d["external_number"]).strip()[:40]
    if "text" in d:
        c.text = str(d["text"])[:4000]
    if "due_at" in d:
        c.due_at = parse_datetime(d["due_at"]) if d["due_at"] else None
    c.save()
    audit(request, "complaint.patch", f"complaint:{c.pk}", d)
    return JsonResponse(complaint_json(c))


# ───────────────────────── доступы ─────────────────────────
def user_json(u):
    return dict(id=u.pk, username=u.username, role=user_role(u), role_name=ROLE_NAMES.get(user_role(u) or "", "—"), is_active=u.is_active, last_login=iso(u.last_login))


def _set_role(u, role: str):
    for r in ("admin", "labeler", "analyst"):
        g, _ = Group.objects.get_or_create(name=r)
        (u.groups.add if r == role else u.groups.remove)(g)
    u.is_staff = True
    u.save(update_fields=["is_staff"])


@role_required("admin")
def users_list(request):
    U = get_user_model()
    return JsonResponse({"items": [user_json(u) for u in U.objects.filter(Q(is_staff=True) | Q(is_superuser=True)).order_by("username")]})


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def user_create(request):
    d = body(request)
    U = get_user_model()
    name, pw, role = str(d.get("username", "")).strip(), d.get("password", ""), d.get("role")
    if not name or role not in ("admin", "labeler", "analyst"):
        return JsonResponse({"error": "username и role (admin|labeler|analyst) обязательны"}, status=400)
    if U.objects.filter(username=name).exists():
        return JsonResponse({"error": "такой логин уже есть"}, status=409)
    try:
        validate_password(pw)
    except ValidationError as e:
        return JsonResponse({"error": " ".join(e.messages)}, status=400)
    u = U.objects.create_user(username=name, password=pw)
    _set_role(u, role)
    audit(request, "user.create", f"user:{u.pk}", dict(username=name, role=role))
    return JsonResponse(user_json(u), status=201)


@csrf_exempt
@role_required("admin")
@require_http_methods(["PATCH"])
def user_patch(request, uid):
    U = get_user_model()
    u = U.objects.filter(pk=uid).first()
    if not u:
        return JsonResponse({"error": "not found"}, status=404)
    d = body(request)
    if u.pk == request.staff.pk and (d.get("is_active") is False or (d.get("role") and d["role"] != "admin")):
        return JsonResponse({"error": "нельзя понизить или отключить самого себя"}, status=400)
    if "role" in d:
        if d["role"] not in ("admin", "labeler", "analyst"):
            return JsonResponse({"error": "role"}, status=400)
        if u.is_superuser and d["role"] != "admin":
            return JsonResponse({"error": "суперпользователь всегда admin"}, status=400)
        _set_role(u, d["role"])
    if "is_active" in d:
        u.is_active = bool(d["is_active"])
        u.save(update_fields=["is_active"])
    audit(request, "user.patch", f"user:{u.pk}", d)
    return JsonResponse(user_json(u))


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def user_password(request, uid):
    U = get_user_model()
    u = U.objects.filter(pk=uid).first()
    if not u:
        return JsonResponse({"error": "not found"}, status=404)
    pw = body(request).get("password", "")
    try:
        validate_password(pw, u)
    except ValidationError as e:
        return JsonResponse({"error": " ".join(e.messages)}, status=400)
    u.set_password(pw)
    u.save()
    audit(request, "user.password", f"user:{u.pk}")
    return JsonResponse({"ok": True})


@role_required("admin")
def audit_list(request):
    qs = AuditLog.objects.select_related("user").order_by("-at")
    return JsonResponse(page_of(qs, request, lambda a: dict(id=a.pk, user=a.user.username if a.user else None, action=a.action, target=a.target, payload=a.payload, at=iso(a.at))))
