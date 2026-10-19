"""Челленджи: цели для водителей с прогрессом по реальным данным (километры, поездки, подтверждённые ямы, ответы)."""
from __future__ import annotations
from datetime import date, datetime, timedelta, time
from django.db.models import Sum
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from roadnet.models import District
from telemetry.models import Challenge, DriverMark, EventCluster, Trip
from .admin_api import audit
from .auth import body, role_required


def _bounds(c: Challenge):
    tz = timezone.get_current_timezone()
    a = timezone.make_aware(datetime.combine(c.starts, time.min), tz)
    b = timezone.make_aware(datetime.combine(c.ends + timedelta(days=1), time.min), tz) if c.ends else timezone.now() + timedelta(days=1)
    return a, b


def progress(c: Challenge) -> dict:
    a, b = _bounds(c)
    trips = Trip.objects.filter(started_at__gte=a, started_at__lt=b)
    if c.kind == "km":
        done = float(trips.aggregate(s=Sum("distance_km"))["s"] or 0)
    elif c.kind == "trips":
        done = trips.count()
    elif c.kind == "marks":
        done = DriverMark.objects.filter(created__gte=a, created__lt=b).count()
    else:
        qs = EventCluster.objects.filter(status__in=["confirmed", "complaint", "fixed"], first_seen__gte=a, first_seen__lt=b)
        if c.district_id:
            qs = qs.filter(segment__district_id=c.district_id)
        done = qs.count()
    people = trips.values("device").distinct().count()
    today = timezone.localdate()
    return dict(id=c.pk, title=c.title, kind=c.kind, kind_name=dict(Challenge.KINDS)[c.kind], target=c.target, done=round(done, 1), percent=min(100, round(100 * done / c.target)) if c.target else 0,
                district=c.district.name_ru if c.district_id else None, district_code=c.district.code if c.district_id else None, starts=c.starts.isoformat(), ends=c.ends.isoformat() if c.ends else None,
                days_left=(c.ends - today).days if c.ends else None, reward=c.reward, archived=c.archived, participants=people)


@role_required("analyst")
def challenges_list(request):
    items = [progress(c) for c in Challenge.objects.select_related("district")]
    active = [x for x in items if not x["archived"]]
    return JsonResponse(dict(items=items, summary=dict(active=len(active), participants=sum(x["participants"] for x in active),
                                                         completed=sum(1 for x in items if x["percent"] >= 100),
                                                         avg_percent=round(sum(x["percent"] for x in active) / len(active)) if active else 0),
                             districts=[dict(code=d.code, name=d.name_ru) for d in District.objects.filter(level="district").order_by("name_ru")]))


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def challenge_create(request):
    d = body(request)
    title, kind = str(d.get("title", "")).strip(), d.get("kind")
    try:
        target = int(d.get("target"))
        starts = date.fromisoformat(d.get("starts") or timezone.localdate().isoformat())
        ends = date.fromisoformat(d["ends"]) if d.get("ends") else None
    except (TypeError, ValueError):
        return JsonResponse({"error": "target — целое число, даты — ГГГГ-ММ-ДД"}, status=400)
    if not title or kind not in dict(Challenge.KINDS) or target <= 0:
        return JsonResponse({"error": "нужны название, тип (km|trips|confirmed|marks) и цель > 0"}, status=400)
    if ends and ends < starts:
        return JsonResponse({"error": "конец раньше начала"}, status=400)
    dist = None
    if d.get("district"):
        dist = District.objects.filter(code=d["district"], level="district").first()
        if not dist:
            return JsonResponse({"error": "район не найден"}, status=400)
    c = Challenge.objects.create(title=title[:120], kind=kind, target=target, district=dist, starts=starts, ends=ends, reward=str(d.get("reward", ""))[:120])
    audit(request, "challenge.create", str(c.pk), dict(title=c.title))
    return JsonResponse(progress(c), status=201)


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST", "PATCH"])
def challenge_patch(request, cid):
    c = Challenge.objects.filter(pk=cid).first()
    if not c:
        return JsonResponse({"error": "не найден"}, status=404)
    d = body(request)
    if "archived" in d:
        c.archived = bool(d["archived"])
    c.save()
    audit(request, "challenge.patch", str(c.pk), d)
    return JsonResponse(progress(c))
