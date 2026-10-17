"""Активное обучение: какие события спросить у водителя. Спрашиваем после поездки, не за рулём."""
from __future__ import annotations
import math
from django.conf import settings
from telemetry.models import RoadEvent
from .models import Question


def uncertainty(conf: float) -> float:
    return 1.0 - abs(conf - 0.5) * 2.0          # 1 при conf≈0.5, 0 при 0 или 1


def novelty(event: RoadEvent) -> float:
    """Новое место (кластер из 1 проезда) важнее известного."""
    c = event.cluster
    return 1.0 if (c is None or c.passes <= 1) else 1.0 / math.sqrt(c.passes)


def create_questions_for_trip(trip, limit=None) -> list[Question]:
    limit = limit or settings.HOLESCOPE["QUESTIONS_PER_TRIP"]
    evs = list(trip.events.filter(user_label="", low_conf=False).select_related("cluster"))
    scored = []
    for e in evs:
        pr = 0.6 * uncertainty(e.confidence) + 0.3 * novelty(e) + 0.1 * min(e.score / 10.0, 1.0)
        scored.append((pr, e))
    scored.sort(key=lambda x: -x[0])
    out = []
    for pr, e in scored[:limit]:
        out.append(Question.objects.create(device=trip.device, event=e, priority=round(pr, 3)))
    return out
