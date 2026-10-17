"""Геометрия на малых расстояниях (Ташкент): локальная проекция в метры, полигоны, привязка точки к отрезку."""
from __future__ import annotations
import math
import numpy as np

K = 111_320.0     # метров в градусе широты


def to_xy(lat, lon, lat0):
    return (np.asarray(lon, float) * K * math.cos(math.radians(lat0)), np.asarray(lat, float) * K)


def dist_m(lat1, lon1, lat2, lon2):
    c = math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot((lon2 - lon1) * K * c, (lat2 - lat1) * K)


def bearing(lat1, lon1, lat2, lon2) -> float:
    """Азимут 0..360 (0 = север, 90 = восток)."""
    c = math.cos(math.radians((lat1 + lat2) / 2))
    dx, dy = (lon2 - lon1) * c, (lat2 - lat1)
    return (math.degrees(math.atan2(dx, dy)) + 360.0) % 360.0


def ang_diff(a: float, b: float) -> float:
    return abs((a - b + 180.0) % 360.0 - 180.0)


def split_polyline(pts, step=50.0, min_tail=15.0):
    """Режет ломаную [(lat, lon), ...] на отрезки ≈step метров. Возвращает [(lat_a, lon_a, lat_b, lon_b, offset_m, length_m)].
    Короткий хвост (< min_tail) присоединяется к предыдущему отрезку."""
    lat0 = pts[0][0]
    xy = [(lon * K * math.cos(math.radians(lat0)), lat * K) for lat, lon in pts]
    cum = [0.0]
    for i in range(1, len(xy)):
        cum.append(cum[-1] + math.hypot(xy[i][0] - xy[i - 1][0], xy[i][1] - xy[i - 1][1]))
    total = cum[-1]
    if total < 1.0:
        return []

    def at(d):
        d = min(max(d, 0.0), total)
        j = max(1, next((k for k in range(1, len(cum)) if cum[k] >= d), len(cum) - 1))
        f = (d - cum[j - 1]) / max(cum[j] - cum[j - 1], 1e-9)
        return (pts[j - 1][0] + (pts[j][0] - pts[j - 1][0]) * f, pts[j - 1][1] + (pts[j][1] - pts[j - 1][1]) * f)

    n = max(1, int(total // step))
    if total - n * step >= min_tail:
        n += 1
    bounds = [i * step for i in range(n)] + [total]
    out = []
    for i in range(n):
        a, b = at(bounds[i]), at(bounds[i + 1])
        out.append((a[0], a[1], b[0], b[1], bounds[i], bounds[i + 1] - bounds[i]))
    return out


class PolygonSet:
    """Набор полигонов (GeoJSON MultiPolygon) с быстрым попаданием точек (метод лучей, векторизовано)."""

    def __init__(self, geometry: dict):
        polys = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        self.rings = []        # [(outer ndarray[lon,lat], [holes])]
        for p in polys:
            outer = np.asarray(p[0], float)
            holes = [np.asarray(h, float) for h in p[1:]]
            self.rings.append((outer, holes))
        allpts = np.concatenate([r[0] for r in self.rings])
        self.bbox = (allpts[:, 1].min(), allpts[:, 0].min(), allpts[:, 1].max(), allpts[:, 0].max())

    @staticmethod
    def _ring_contains(ring: np.ndarray, lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
        x, y = lon, lat
        inside = np.zeros(len(x), bool)
        x1, y1 = ring[:-1, 0], ring[:-1, 1]
        x2, y2 = ring[1:, 0], ring[1:, 1]
        for i in range(len(x1)):
            cond = (y1[i] > y) != (y2[i] > y)
            with np.errstate(divide="ignore", invalid="ignore"):
                xi = (x2[i] - x1[i]) * (y - y1[i]) / (y2[i] - y1[i]) + x1[i]
            inside ^= cond & (x < xi)
        return inside

    def contains(self, lat, lon) -> np.ndarray:
        lat = np.atleast_1d(np.asarray(lat, float)); lon = np.atleast_1d(np.asarray(lon, float))
        res = np.zeros(len(lat), bool)
        pre = (lat >= self.bbox[0]) & (lat <= self.bbox[2]) & (lon >= self.bbox[1]) & (lon <= self.bbox[3])
        idx = np.where(pre)[0]
        if not len(idx):
            return res
        for outer, holes in self.rings:
            m = self._ring_contains(outer, lat[idx], lon[idx])
            for h in holes:
                m &= ~self._ring_contains(h, lat[idx], lon[idx])
            res[idx] |= m
        return res
