"""Сторона и полоса элемента на дороге.

Что известно и чем это измеряется:
1. Тип элемента. Лежачий, рельсы, стык плит перекрывают всю проезжую часть (span=full): предупреждать о перестроении бессмысленно,
   нужно только сбросить скорость. Яма, просевший/выступающий люк занимают конкретное место (span=lane).
2. Поперечное смещение (xtrack_m) каждого проезда от оси дороги: при привязке к сети считаем, на сколько метров точка удара правее («+»)
   или левее («−») оси сегмента по ходу движения. GPS телефона плавает на ±3 м, но у ямы, на которую наезжают много раз, медиана по
   проездам сходится: с 3–4 проездами погрешность падает до ≈1–1,5 м — этого хватает, чтобы отличить «правая» полоса от «левой».
3. Лучше всего отделяет полосы разброс смещений: если проезды лежат в двух группах (разные полосы), а удары есть только в одной — яма на этой полосе.
   Если удар получают все проезды независимо от смещения — элемент перекрывает всю ширину.
4. Для разговора с водителем: «яма справа», «яма на левой полосе» — по знаку и величине смещения. Вблизи оси (|x| < 1,2 м) — «по центру»
   (на дорогах без разметки это «посередине полосы»).
"""
from __future__ import annotations
import statistics

from . import taxonomy

LANE_W = 3.2         # типичная ширина полосы в городе, м
CENTER_M = 1.2       # |смещение| меньше — «по центру»


def side_of(median_m: float | None, n: int) -> str:
    """left | right | center | unknown (по ходу движения)."""
    if median_m is None or n < 2:
        return "unknown"
    if abs(median_m) < CENTER_M:
        return "center"
    return "right" if median_m > 0 else "left"


def lane_index(median_m: float | None, one_way_lanes: int | None = None) -> int | None:
    """Номер полосы от правого края (1 — крайняя правая), если смещение известно. Дорога считается от оси сегмента: правее оси — полосы 1..k."""
    if median_m is None:
        return None
    if median_m <= 0:
        return None
    return int(median_m // LANE_W) + 1


def summarize(offsets: list[float]) -> dict:
    """Итог по списку смещений проездов (метры, «+» справа): медиана, разброс, сторона, уверенность."""
    xs = [x for x in offsets if x is not None]
    n = len(xs)
    if not n:
        return dict(n=0, median_m=None, spread_m=None, side="unknown", confidence=0.0)
    med = statistics.median(xs)
    spread = statistics.pstdev(xs) if n > 1 else None
    # уверенность: растёт с числом проездов и падает с разбросом (≈3 м — предел GPS одного проезда)
    conf = min(1.0, n / 5.0) * (1.0 if spread is None else max(0.2, 1.0 - spread / 6.0))
    return dict(n=n, median_m=round(med, 2), spread_m=None if spread is None else round(spread, 2), side=side_of(med, n), confidence=round(conf, 2))


def describe(type_: str, level: str, lane: dict | None) -> dict:
    """Что говорить водителю и можно ли обойти: {span, side, advice}."""
    span = taxonomy.span_for_type(type_)
    lane = lane or {}
    side = lane.get("side", "unknown")
    if span == "full":
        return dict(span="full", side="all", advice="slow")           # перестроиться нельзя — снизить скорость
    if span == "stretch":
        return dict(span="stretch", side="all", advice="slow")
    if side in ("left", "right") and lane.get("confidence", 0) >= 0.4:
        return dict(span="lane", side=side, advice="avoid")           # можно объехать, сместившись в другую сторону
    return dict(span="lane", side=side, advice="slow")
