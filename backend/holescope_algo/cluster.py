"""Серверная кластеризация событий: одно место (≈12 м) и одно направление → одна яма; подтверждают разные устройства."""
from __future__ import annotations
import math
import numpy as np


def _m(lat1, lon1, lat2, lon2):
    k = 111_320.0
    dx = (lon2 - lon1) * k * math.cos(math.radians((lat1 + lat2) / 2)); dy = (lat2 - lat1) * k
    return math.hypot(dx, dy)


def angdiff(a, b):
    d = abs((a - b + 180) % 360 - 180)
    return d


def cluster_events(events: list[dict], radius_m=12.0, heading_tol=70.0):
    """events: [{id, lat, lon, heading, device, score, ...}] → список кластеров. Простая жадная кластеризация по сетке."""
    cells: dict[tuple[int, int], list[int]] = {}
    def key(e): return (int(e["lat"] * 111_320 // radius_m), int(e["lon"] * 111_320 * math.cos(math.radians(e["lat"])) // radius_m))
    lab = [-1] * len(events); clusters = []
    for i, e in enumerate(events):
        if lab[i] != -1:
            continue
        stack = [i]; members = []; lab[i] = len(clusters)
        while stack:
            k = stack.pop(); members.append(k); ek = events[k]
            kx, ky = key(ek)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for j in cells.get((kx + dx, ky + dy), []):
                        pass
            for j, ej in enumerate(events):
                if lab[j] != -1: continue
                if abs(ej["lat"] - ek["lat"]) > radius_m / 111_320 * 1.5: continue
                if _m(ek["lat"], ek["lon"], ej["lat"], ej["lon"]) > radius_m: continue
                hj, hk = ej.get("heading"), ek.get("heading")
                if hj is not None and hk is not None and not (math.isnan(hj) or math.isnan(hk)) and angdiff(hj, hk) > heading_tol:
                    continue
                lab[j] = lab[i]; stack.append(j)
        scores = [events[k]["score"] for k in members]
        clusters.append(dict(
            members=members, n=len(members), devices=len({events[k].get("device") for k in members}),
            lat=float(np.mean([events[k]["lat"] for k in members])), lon=float(np.mean([events[k]["lon"] for k in members])),
            score_median=float(np.median(scores)), score_max=float(np.max(scores))))
    return clusters


def confidence(n_passes: int, n_devices: int) -> float:
    """Уверенность в яме: растёт с числом проездов и разных устройств (логистика, 0..1)."""
    x = 0.9 * (n_passes - 1) + 0.9 * (n_devices - 1) - 0.3
    return round(1 / (1 + math.exp(-x)), 3)
