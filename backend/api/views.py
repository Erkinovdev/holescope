import math, tempfile
from django.conf import settings
from django.db.models import Count, Avg
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from fleet.models import Device, Vehicle, CarModel
from telemetry.models import Trip, RoadEvent, EventCluster, RawUpload
from brain.models import Question, Label, BrainSnapshot, AlgoVersion
from brain import services, road_stats, validation
from .auth import device_required, body

NICK_A = ["Тихий", "Быстрый", "Ночной", "Ясный", "Смелый", "Зоркий"]
NICK_B = ["Сокол", "Беркут", "Барс", "Ястреб", "Кречет", "Лис"]


@csrf_exempt
@require_http_methods(["POST"])
def register(request):
    """Анонимная регистрация устройства → токен. Без почты и телефона."""
    d = body(request)
    import random
    nick = f"{random.choice(NICK_A)} {random.choice(NICK_B)} #{random.randint(1000, 9999)}"
    dev = Device.objects.create(nickname=nick, platform=d.get("platform", ""), phone_model=d.get("phone_model", ""),
                                app_version=d.get("app_version", ""), lang=d.get("lang", "ru"),
                                role=d.get("role", "driver"))
    return JsonResponse({"token": dev.token, "nickname": nick}, status=201)


@csrf_exempt
@device_required
@require_http_methods(["GET", "PATCH"])
def me_vehicle(request):
    dev = request.device
    if request.method == "PATCH":
        d = body(request)
        v = dev.vehicle or Vehicle.objects.create(); dev.vehicle = v
        for f in ("name", "year", "rim_inch", "tire_pressure_bar", "wheelbase_mm", "suspension_note"):
            if f in d: setattr(v, f, d[f])
        if d.get("car_model_id"): v.car_model = CarModel.objects.filter(pk=d["car_model_id"]).first()
        if "mount" in d: dev.mount = d["mount"]
        v.save(); dev.save()
    v = dev.vehicle
    return JsonResponse({"vehicle": None if not v else dict(
        id=v.pk, name=str(v), car_model=str(v.car_model) if v.car_model else None, wheelbase_m=v.wb_m, rim_inch=v.rim_inch,
        tire_pressure_bar=v.tire_pressure_bar, suspension_note=v.suspension_note, suspension_cls=v.suspension_cls,
        softness_score=v.softness_score, softness_conf=v.softness_conf, km_total=round(v.km_total, 1),
        model_guess=str(v.model_guess) if v.model_guess else None, model_guess_conf=v.model_guess_conf),
        "mount": dev.mount})


@csrf_exempt
@device_required
@require_http_methods(["POST"])
def upload_trip(request):
    """Телефон присылает результат поездки: события, сегменты ровности, сводку (≈ десятки КБ, не сырой поток)."""
    payload = body(request)
    if "started_at" not in payload:
        return JsonResponse({"error": "started_at required"}, status=400)
    try:
        trip = services.ingest_trip(request.device, payload)
    except validation.Rejected as e:
        validation.adjust_trust(request.device, False)
        return JsonResponse({"error": e.reason}, status=e.status)
    except (KeyError, ValueError, TypeError) as e:
        validation.adjust_trust(request.device, False)
        return JsonResponse({"error": f"bad payload: {e}"}, status=400)
    qs = Question.objects.filter(device=request.device, status="open", event__trip=trip).count()
    return JsonResponse({"trip_id": trip.pk, "events": trip.events.count(), "questions": qs, "duplicate": bool(getattr(trip, "duplicate", False))},
                        status=200 if getattr(trip, "duplicate", False) else 201)


@csrf_exempt
@device_required
@require_http_methods(["POST"])
def upload_raw(request):
    """Сырой CSV (только исследовательские устройства): multipart file=... Обрабатывается алгоритмом на сервере."""
    f = request.FILES.get("file")
    if not f:
        return JsonResponse({"error": "file required"}, status=400)
    ru = RawUpload.objects.create(device=request.device, file=f, filename=f.name)
    return JsonResponse({"raw_id": ru.pk}, status=201)


@device_required
def questions_next(request):
    qs = Question.objects.filter(device=request.device, status="open").select_related("event").order_by("-priority")[:5]
    return JsonResponse({"questions": [dict(
        id=q.pk, lat=q.event.lat, lon=q.event.lon, speed_kmh=q.event.speed_kmh, at=q.event.at.isoformat(),
        wave=q.event.wave, guess=q.event.type, guess_level=q.event.level,
        options=["pothole_light", "pothole_mid", "pothole_deep", "bump", "manhole", "rail", "joint", "nothing", "not_sure"]) for q in qs]})


@csrf_exempt
@device_required
@require_http_methods(["POST"])
def question_answer(request, qid):
    q = Question.objects.filter(pk=qid, device=request.device, status="open").select_related("event").first()
    if not q:
        return JsonResponse({"error": "not found"}, status=404)
    a = body(request).get("answer", "not_sure")
    q.answer = a; q.status = "skipped" if a == "not_sure" else "answered"; q.answered_at = timezone.now(); q.save()
    if a != "not_sure":
        e = q.event; e.user_label = a; e.save(update_fields=["user_label"])
        Label.objects.create(event=e, source="driver", label="noise" if a == "nothing" else a, features=e.features, trip_key=str(e.trip_id))
        if a == "nothing" and e.cluster and e.cluster.passes <= 1:
            e.cluster.status = "false"; e.cluster.save()
        elif e.cluster and a != "nothing":
            road_stats.refine_cluster_type(e.cluster, a)
        request.device.trust = min(1.0, request.device.trust + 0.01); request.device.save(update_fields=["trust"])
    return JsonResponse({"ok": True})


def map_clusters(request):
    """Публичная карта: ?bbox=min_lat,min_lon,max_lat,max_lon&status=confirmed,candidate"""
    try:
        a, b, c, d = [float(x) for x in request.GET["bbox"].split(",")]
    except (KeyError, ValueError):
        return JsonResponse({"error": "bbox=min_lat,min_lon,max_lat,max_lon"}, status=400)
    st = request.GET.get("status", "confirmed,candidate,complaint").split(",")
    qs = EventCluster.objects.filter(lat__gte=a, lat__lte=c, lon__gte=b, lon__lte=d, status__in=st)[:2000]
    return JsonResponse({"clusters": [dict(id=x.pk, lat=x.lat, lon=x.lon, type=x.type, level=x.level, status=x.status,
                                           passes=x.passes, devices=x.devices, confidence=x.confidence, safe_speed=x.safe_speed_kmh) for x in qs]})


def ahead(request):
    """Режим Drive: что впереди по ходу движения. ?lat&lon&heading&dist=300 — ямы в «коридоре» шириной ±25 м."""
    try:
        lat, lon, hd = float(request.GET["lat"]), float(request.GET["lon"]), float(request.GET["heading"])
    except (KeyError, ValueError):
        return JsonResponse({"error": "lat, lon, heading"}, status=400)
    dist = min(float(request.GET.get("dist", settings.HOLESCOPE["AHEAD_DEFAULT_M"])), 600)
    d = dist / 111_320.0 * 1.2
    out = []
    for c in EventCluster.objects.filter(lat__gte=lat - d, lat__lte=lat + d, lon__gte=lon - d * 1.5, lon__lte=lon + d * 1.5,
                                         status__in=["confirmed", "candidate", "complaint"]):
        dx = (c.lon - lon) * 111_320 * math.cos(math.radians(lat)); dy = (c.lat - lat) * 111_320
        along = dx * math.sin(math.radians(hd)) + dy * math.cos(math.radians(hd))
        across = dx * math.cos(math.radians(hd)) - dy * math.sin(math.radians(hd))
        if 5 < along <= dist and abs(across) <= 25 and (c.heading is None or abs((c.heading - hd + 180) % 360 - 180) < 70):
            out.append(dict(id=c.pk, distance_m=round(along), side="right" if across > 6 else "left" if across < -6 else "center",
                            level=c.level, type=c.type, confidence=c.confidence, safe_speed=c.safe_speed_kmh))
    out.sort(key=lambda x: x["distance_m"])
    return JsonResponse({"ahead": out[:5]})
