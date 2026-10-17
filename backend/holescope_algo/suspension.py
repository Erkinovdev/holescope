"""Индекс подвески автомобиля: «мягкость» 0–100 + затухание.

Как измеряем (без эталонной дороги):
 1) Относительный (основной): на одних и тех же сегментах 50 м сравниваем RI этой машины с медианой RI всех
    машин на этом сегменте при той же скорости. softness = −median(log(RI_car / RI_segment_median)).
    > 0 — мягче типичной машины, < 0 — жёстче. Нужны сегменты с ≥3 разными машинами.
 2) Абсолютный (резерв, работает с первой поездки): затухание кузова после одиночных ударов (ζ) и частота
    кузова f_body. Мягкая подвеска: низкий f_body (~1–1.3 Гц), ζ 0.25–0.4; жёсткая: f_body > 1.8 Гц, быстрое затухание.
 3) Оценка пересчитывается скользящим окном каждые N км (по умолчанию 25 км) и показывается с доверием.
"""
from __future__ import annotations
import numpy as np


def damping_summary(events) -> dict:
    z = np.array([e.zeta for e in events if e.zeta == e.zeta and 0.02 < e.zeta < 0.9], float)
    f = np.array([e.f_body for e in events if e.f_body == e.f_body and 0.4 < e.f_body < 4.0], float)
    return dict(n=int(len(z)), zeta_median=float(np.median(z)) if len(z) else None,
                f_body_median=float(np.median(f)) if len(f) else None)


def relative_softness(car_ri: dict[int, float], seg_median_ri: dict[int, float], min_segments: int = 40):
    """car_ri / seg_median_ri: {segment_id: RI}. Возвращает (softness в логарифмах, число сегментов)."""
    ratios = [np.log(car_ri[s] / seg_median_ri[s]) for s in car_ri
              if s in seg_median_ri and seg_median_ri[s] > 1e-6 and car_ri[s] > 1e-6]
    if len(ratios) < min_segments:
        return None, len(ratios)
    return float(-np.median(ratios)), len(ratios)


def softness_score(rel: float | None, zeta: float | None, f_body: float | None) -> dict:
    """Сводный индекс 0–100 (100 = очень мягкая) и класс: S1 жёсткая … S5 очень мягкая. Веса — стартовые."""
    parts, w = [], []
    if rel is not None:
        parts.append(50 + 50 * np.tanh(rel / 0.5)); w.append(0.6)
    if f_body is not None:
        parts.append(float(np.clip((2.2 - f_body) / (2.2 - 0.9) * 100, 0, 100))); w.append(0.25)
    if zeta is not None:
        parts.append(float(np.clip((0.45 - zeta) / 0.35 * 100, 0, 100)) * 0.5 + 25); w.append(0.15)
    if not parts:
        return dict(score=None, cls=None, confidence=0.0)
    sc = float(np.average(parts, weights=w))
    cls = "S1" if sc < 20 else "S2" if sc < 40 else "S3" if sc < 60 else "S4" if sc < 80 else "S5"
    conf = min(1.0, sum(w))
    return dict(score=round(sc, 1), cls=cls, confidence=round(conf, 2))
