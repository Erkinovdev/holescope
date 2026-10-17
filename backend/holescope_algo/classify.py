"""Слой 5–6: тип события и тяжесть (правила v2; затем заменяются моделью по разметке)."""
from __future__ import annotations
import math
from .detector import Event

LEVELS = ["light", "mid", "deep", "danger"]


def classify(e: Event) -> dict:
    """Возвращает {type, level, confidence, safe_speed_kmh}. type: touch|pothole|bump|manhole|joint|noise."""
    # 1) касание телефона / удар по креплению: короткий одиночный сильный пик с большим гироскопом
    if e.pair < 0.2 and e.dur_ms < 250 and e.peak > 6 and e.gyro_peak > 60:
        return dict(type="touch", level=None, confidence=0.7, safe_speed_kmh=None)
    # 2) слабое и «пустое» — шум дороги
    if e.score < 2.4 and e.ratio < 5:
        return dict(type="noise", level=None, confidence=0.6, safe_speed_kmh=None)
    # 3) тип: по данным 16.10 (91 размеченное событие) форма удара пока НЕ разделяет яму / лежачий / люк
    #    (длительность, pair, знак первого удара пересекаются), поэтому все дорожные события = "pothole" (яма/неровность).
    #    Раздел типов включится после разметки ≥30 событий каждого типа (модель, не правила).
    typ, conf = "pothole", 0.6
    # 4) тяжесть: ПРОВИЗОРНЫЕ границы по score (пик с поправкой на скорость): 3 глубоких на 91 события — мало для подбора
    s = e.score
    level = "light" if s < 5.0 else "mid" if s < 8.0 else "deep" if s < 14.0 else "danger"
    return dict(type=typ, level=level, confidence=conf, safe_speed_kmh=safe_speed(e, level))


def safe_speed(e: Event, level) -> int | None:
    """Скорость, при которой ожидаемый пик ≤ 3 м/с² (комфорт): peak ~ (v/v0)^alpha, v0 = опорная."""
    if level is None or e.score <= 0:
        return None
    comfort = 3.0
    if e.score <= comfort:
        return None
    alpha = 0.8
    v = 40.0 * (comfort / e.score) ** (1.0 / alpha)
    return int(max(10, min(60, round(v / 5.0) * 5)))
