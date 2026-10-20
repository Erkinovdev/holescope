"""Качество дороги: протяжённые участки плохой ровности.

Элемент — точка (яма, лежачий). Участок — отрезок дороги в сотни метров и километры, где полотно расшатано целиком: старый асфальт, колея от
грузовиков, россыпь мелких ям. Внутри участка могут быть и элементы. Для участка водителю нужно не «объезжайте», а «снизьте скорость на N км/ч
на ближайшие X м».

Участок = подряд идущие 50-метровые сегменты одной дороги и направления с классом ровности D или E (допускаем один пропуск между ними).
"""
from __future__ import annotations
from collections import defaultdict
from roadnet.models import Segment

BAD = ("D", "E")
MIN_LEN_M = 100.0
SPEED_BY_CLASS = {"D": 40, "E": 30}


def advised_speed(worst: str) -> int:
    return SPEED_BY_CLASS.get(worst, 40)


def _runs(rows):
    """rows: [(index, seg)], уже отсортированные по index одной (road, direction). Возвращает группы подряд идущих плохих сегментов."""
    out, cur, last = [], [], None
    for idx, seg in rows:
        if last is not None and idx - last > 2:     # разрыв больше одного пропущенного сегмента
            if cur:
                out.append(cur)
            cur = []
        cur.append(seg)
        last = idx
    if cur:
        out.append(cur)
    return out


def find(bbox: tuple[float, float, float, float] | None = None, min_len: float = MIN_LEN_M, limit: int = 300) -> list[dict]:
    """Список участков: id, дорога, класс (худший), длина, ср. индекс ровности, рекомендуемая скорость, геометрия [[lat, lon], …]."""
    qs = Segment.objects.filter(cls__in=BAD).select_related("road")
    if bbox:
        a, b, c, d = bbox
        qs = qs.filter(lat_a__gte=a, lat_a__lte=c, lon_a__gte=b, lon_a__lte=d)
    groups: dict[tuple[int, int], list] = defaultdict(list)
    for s in qs.order_by("road_id", "direction", "index")[:20000]:
        groups[(s.road_id, s.direction)].append((s.index, s))
    res = []
    for (road_id, direction), rows in groups.items():
        for run in _runs(rows):
            length = sum(s.length_m for s in run)
            if length < min_len:
                continue
            worst = "E" if any(s.cls == "E" for s in run) else "D"
            ris = [s.ri_median for s in run if s.ri_median is not None]
            pts = [[run[0].lat_a, run[0].lon_a]] + [[s.lat_b, s.lon_b] for s in run]
            road = run[0].road
            res.append(dict(id=f"{road.code}:{direction}:{run[0].index}", road=road.name_ru, road_code=road.code, road_class=road.road_class, direction=direction,
                            cls=worst, length_m=round(length), segments=len(run), ri_median=round(sum(ris) / len(ris), 3) if ris else None,
                            speed_kmh=advised_speed(worst), surface=road.surface, geometry=pts))
    res.sort(key=lambda r: (-r["length_m"], r["cls"]))
    return res[:limit]


def ahead(lat: float, lon: float, heading: float, dist: float = 600.0) -> list[dict]:
    """Участки плохого качества впереди по ходу движения: где начинается, сколько тянется, с какой скоростью ехать."""
    import math
    d = dist / 111_320.0 * 1.2
    segs = Segment.objects.filter(cls__in=BAD, lat_a__gte=lat - d, lat_a__lte=lat + d, lon_a__gte=lon - d * 1.5, lon_a__lte=lon + d * 1.5).select_related("road")
    hits = []
    for s in segs:
        dx = (s.lon_a - lon) * 111_320 * math.cos(math.radians(lat)); dy = (s.lat_a - lat) * 111_320
        along = dx * math.sin(math.radians(heading)) + dy * math.cos(math.radians(heading))
        across = dx * math.cos(math.radians(heading)) - dy * math.sin(math.radians(heading))
        if not (-25 < along <= dist and abs(across) <= 14):
            continue
        if s.heading is not None and abs((s.heading - heading + 180) % 360 - 180) > 60:
            continue
        hits.append((along, s))
    hits.sort(key=lambda x: x[0])
    out, cur = [], []
    for along, s in hits:
        if cur and along - cur[-1][0] > 130:
            out.append(cur)
            cur = []
        cur.append((along, s))
    if cur:
        out.append(cur)
    res = []
    for run in out:
        length = sum(s.length_m for _, s in run)
        if length < MIN_LEN_M:
            continue
        worst = "E" if any(s.cls == "E" for _, s in run) else "D"
        res.append(dict(start_m=max(0, round(run[0][0])), length_m=round(length), cls=worst, speed_kmh=advised_speed(worst), road=run[0][1].road.name_ru))
    return res[:3]
