"""Рейтинг «Самая мягкая машина недели/месяца/года по оценке Holescope» (заготовка, идея отложена до сотен машин).
Правило: модель участвует, если у неё ≥10 машин с посчитанным индексом и суммарный пробег ≥500 км."""
from __future__ import annotations
import numpy as np
from django.db.models import Sum
from django.utils import timezone
from fleet.models import CarModel, Vehicle
from .models import ModelAward

MIN_VEHICLES = 10
MIN_KM = 500.0


def compute_awards(period: str = "week", day=None, top: int = 10) -> list[ModelAward]:
    day = day or timezone.localdate()
    rows = []
    for cm in CarModel.objects.all():
        vs = Vehicle.objects.filter(car_model=cm, softness_score__isnull=False)
        n = vs.count()
        km = vs.aggregate(s=Sum("km_total"))["s"] or 0.0
        if n >= MIN_VEHICLES and km >= MIN_KM:
            rows.append((cm, float(np.median(list(vs.values_list("softness_score", flat=True)))), n, float(km)))
    rows.sort(key=lambda r: -r[1])
    ModelAward.objects.filter(period=period, day=day).delete()
    return [ModelAward.objects.create(period=period, day=day, car_model=cm, softness_median=sc, n_vehicles=n, km_total=km, rank=i + 1) for i, (cm, sc, n, km) in enumerate(rows[:top])]
