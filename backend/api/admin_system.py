"""Админка: бейджи меню и состояние системы (здоровье сервисов, объёмы данных, свежесть данных)."""
from __future__ import annotations
import os
import time
from datetime import timedelta
from django.db import connection
from django.http import JsonResponse
from django.utils import timezone
from brain.models import AlgoVersion, AuditLog, Question, TrainingRun
from fleet.models import Device
from holescope_algo import ALGO_VERSION
from roadnet.models import Segment
from telemetry.models import Complaint, DriverMark, EventCluster, RawUpload, RoadEvent, Trip
from .admin_api import iso
from .auth import role_required


@role_required("analyst")
def badges(request):
    """Числа для значков в меню: что ждёт внимания."""
    return JsonResponse(dict(
        events=EventCluster.objects.filter(status="candidate", passes__lte=1).count(),
        complaints=Complaint.objects.filter(status="filed", external_number="").count(),
        questions=Question.objects.filter(status="open").count(),
        algo=ALGO_VERSION,
    ))


def _stt_state() -> dict:
    url = os.environ.get("STT_URL", "").rstrip("/")
    if not url:
        return dict(name="Распознавание голоса", state="off", detail="не подключено")
    try:
        import urllib.request
        t0 = time.time()
        with urllib.request.urlopen(url + "/health", timeout=2) as r:
            ok = r.status == 200
        return dict(name="Распознавание голоса", state="ok" if ok else "down", detail=f"ответ {int((time.time() - t0) * 1000)} мс")
    except Exception as e:  # сервис недоступен — это и есть ответ
        return dict(name="Распознавание голоса", state="down", detail=type(e).__name__)


@role_required("analyst")
def system(request):
    now = timezone.now()
    t0 = time.time()
    with connection.cursor() as c:
        c.execute("SELECT 1")
    db_ms = int((time.time() - t0) * 1000)
    last_trip = Trip.objects.order_by("-started_at").values_list("started_at", flat=True).first()
    last_run = TrainingRun.objects.order_by("-created").first()
    active = AlgoVersion.objects.filter(active=True).first()
    services = [
        dict(name="API (Django)", state="ok", detail=f"версия алгоритма {ALGO_VERSION}"),
        dict(name="База данных", state="ok" if db_ms < 500 else "slow", detail=f"ответ {db_ms} мс"),
        _stt_state(),
        dict(name="Свежесть данных", state=("ok" if last_trip and now - last_trip < timedelta(days=2) else "slow"),
             detail=("последняя поездка " + iso(last_trip)) if last_trip else "поездок ещё нет"),
        dict(name="Обучение модели", state=("ok" if last_run and now - last_run.created < timedelta(days=3) else "slow"),
             detail=("последнее " + iso(last_run.created)) if last_run else "ещё не запускалось"),
    ]
    counts = dict(trips=Trip.objects.count(), events=RoadEvent.objects.count(), clusters=EventCluster.objects.count(), segments=Segment.objects.count(),
                  devices=Device.objects.count(), marks=DriverMark.objects.count(), complaints=Complaint.objects.count(), uploads=RawUpload.objects.count())
    log = [dict(id=a.pk, at=iso(a.at), user=a.user.username if a.user_id else None, action=a.action, target=a.target) for a in AuditLog.objects.select_related("user").order_by("-id")[:30]]
    return JsonResponse(dict(
        now=iso(now), algo=ALGO_VERSION, active_version=active.version if active else None, services=services, counts=counts, log=log,
        uptime_note="Время работы считает Docker (docker compose ps); здесь — проверка ответа сервисов в момент открытия страницы.",
    ))
