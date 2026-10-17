"""Автоопределение марки/модели (каркас, HOLESCOPE_V2 §8.3). Включается только когда накоплены сотни машин с известной моделью;
до тех пор вернёт None, а пользователь выбирает модель в профиле."""
from __future__ import annotations
from collections import Counter
import numpy as np
from .models import Vehicle

KEYS = ("f_body", "zeta", "softness", "ri_coef")


def update_fingerprint(vehicle: Vehicle, ri_coef: float | None = None) -> dict:
    """Отпечаток машины из накопленных признаков. ri_coef — log(RI машины / медиана флота), если посчитан."""
    fp = dict(f_body=vehicle.f_body_median, zeta=vehicle.zeta_median, softness=vehicle.softness_score, ri_coef=ri_coef,
              km=round(vehicle.km_total, 1))
    vehicle.fingerprint = fp
    vehicle.save(update_fields=["fingerprint"])
    return fp


def _vec(fp: dict):
    v = [fp.get(k) for k in KEYS]
    return None if any(x is None for x in v) else np.array(v, float)


def suggest_model(vehicle: Vehicle, k: int = 5, min_known: int = 30, min_conf: float = 0.5):
    """k ближайших среди машин с известной моделью. Возвращает (CarModel, уверенность) или None."""
    me = _vec(vehicle.fingerprint or {})
    if me is None:
        return None
    known = [(v, _vec(v.fingerprint or {})) for v in Vehicle.objects.exclude(pk=vehicle.pk).exclude(car_model=None).exclude(fingerprint={})]
    known = [(v, x) for v, x in known if x is not None]
    if len(known) < min_known:
        return None
    M = np.array([x for _, x in known])
    mu, sd = M.mean(axis=0), M.std(axis=0)
    sd[sd == 0] = 1.0
    d = np.linalg.norm((M - mu) / sd - (me - mu) / sd, axis=1)
    near = np.argsort(d)[:k]
    votes = Counter(known[i][0].car_model_id for i in near)
    model_id, n = votes.most_common(1)[0]
    conf = n / len(near)
    if conf < min_conf:
        return None
    from .models import CarModel
    return CarModel.objects.get(pk=model_id), conf


def apply_suggestion(vehicle: Vehicle) -> bool:
    s = suggest_model(vehicle)
    if not s:
        return False
    vehicle.model_guess, vehicle.model_guess_conf = s[0], s[1]
    vehicle.save(update_fields=["model_guess", "model_guess_conf"])
    return True
