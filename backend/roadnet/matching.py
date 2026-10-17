"""Привязка точек и сегментов ровности к дорожному графу (Segment) — собственный map matching.

Для каждой точки ищем ближайший отрезок сети с учётом направления движения (heading): встречные полосы — разные Segment.
Индекс держится в памяти (сетка ≈55 м); пересобирается при импорте сети.
Valhalla/Meili — возможное расширение для плотных кварталов (см. backend/README.md); сейчас точности GPS ±3 м и сетки OSM достаточно
для привязки отдельных событий и сегментов по 50 м.
"""
from __future__ import annotations
import math
import threading
from dataclasses import dataclass
import numpy as np
from .geo import K, ang_diff

CELL = 0.0005


@dataclass
class Match:
    segment_id: int
    distance_m: float
    frac: float            # положение вдоль сегмента 0..1
    heading_diff: float | None


class SegmentIndex:
    def __init__(self, rows):
        """rows: iterable (id, lat_a, lon_a, lat_b, lon_b, heading)."""
        rows = list(rows)
        self.n = len(rows)
        self.id = np.array([r[0] for r in rows], dtype=np.int64)
        self.lat_a = np.array([r[1] for r in rows], float); self.lon_a = np.array([r[2] for r in rows], float)
        self.lat_b = np.array([r[3] for r in rows], float); self.lon_b = np.array([r[4] for r in rows], float)
        self.heading = np.array([np.nan if r[5] is None else r[5] for r in rows], float)
        self.grid: dict[tuple[int, int], list[int]] = {}
        for i in range(self.n):
            i0, i1 = sorted((int(self.lat_a[i] / CELL), int(self.lat_b[i] / CELL)))
            j0, j1 = sorted((int(self.lon_a[i] / CELL), int(self.lon_b[i] / CELL)))
            for ci in range(i0, i1 + 1):
                for cj in range(j0, j1 + 1):
                    self.grid.setdefault((ci, cj), []).append(i)

    def snap(self, lat: float, lon: float, heading: float | None = None, max_m: float = 30.0, heading_tol: float = 50.0) -> Match | None:
        if self.n == 0:
            return None
        ci, cj = int(lat / CELL), int(lon / CELL)
        cand: set[int] = set()
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                cand.update(self.grid.get((ci + di, cj + dj), ()))
        if not cand:
            return None
        ix = np.fromiter(cand, int)
        c = math.cos(math.radians(lat))
        ax = (self.lon_a[ix] - lon) * c * K; ay = (self.lat_a[ix] - lat) * K
        bx = (self.lon_b[ix] - lon) * c * K; by = (self.lat_b[ix] - lat) * K
        dx, dy = bx - ax, by - ay
        L2 = np.maximum(dx * dx + dy * dy, 1e-9)
        t = np.clip(-(ax * dx + ay * dy) / L2, 0.0, 1.0)
        px, py = ax + t * dx, ay + t * dy
        d = np.hypot(px, py)
        ok = d <= max_m
        hd = None
        if heading is not None and not (isinstance(heading, float) and math.isnan(heading)):
            sh = self.heading[ix]
            diff = np.abs((sh - heading + 180.0) % 360.0 - 180.0)
            ok &= np.where(np.isnan(diff), True, diff <= heading_tol)
            hd = diff
        if not ok.any():
            return None
        score = np.where(ok, d + (0 if hd is None else np.nan_to_num(hd) * 0.05), np.inf)
        k = int(np.argmin(score))
        return Match(int(self.id[ix[k]]), float(d[k]), float(t[k]), None if hd is None or np.isnan(hd[k]) else float(hd[k]))


_lock = threading.Lock()
_index: SegmentIndex | None = None


def get_index() -> SegmentIndex:
    global _index
    with _lock:
        if _index is None:
            from .models import Segment
            _index = SegmentIndex(Segment.objects.values_list("id", "lat_a", "lon_a", "lat_b", "lon_b", "heading").iterator(chunk_size=20000))
        return _index


def reset_index():
    global _index
    with _lock:
        _index = None
