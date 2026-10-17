"""Слой 7: индекс ровности сегментов 50 м (абсолютные классы A–E)."""
from __future__ import annotations
import numpy as np
import pandas as pd
from .params import Params
from .io import haversine

CLASSES = ["A", "B", "C", "D", "E"]
NAMES = {"A": "ровная", "B": "хорошая", "C": "удовлетворительная", "D": "плохая", "E": "разбитая"}


def segments(sig: pd.DataFrame, gps: pd.DataFrame, p: Params) -> pd.DataFrame:
    t = sig["t"].to_numpy(float); vz = sig["vz"].to_numpy(float)
    gt = gps["t"].to_numpy(float); gs = gps["speed"].to_numpy(float)
    sp = np.interp(t, gt, gs)
    d = haversine(gps["lat"].shift().to_numpy(float), gps["lon"].shift().to_numpy(float),
                  gps["lat"].to_numpy(float), gps["lon"].to_numpy(float))
    d = np.where(np.nan_to_num(gs) >= p.min_speed_ri_ms, np.nan_to_num(d), 0.0)
    dist = np.interp(t, gt, np.cumsum(d))
    moving = sp >= p.min_speed_ri_ms
    lat = np.interp(t, gt, gps["lat"].to_numpy(float)); lon = np.interp(t, gt, gps["lon"].to_numpy(float))
    sid = (dist // p.seg_len_m).astype(int)
    rows = []
    for s in np.unique(sid[moving]):
        sel = (sid == s) & moving
        if sel.sum() < 30:
            continue
        v = float(np.mean(sp[sel]))
        rms = float(np.sqrt(np.mean(vz[sel] ** 2)))
        ri = rms / max(v, p.min_speed_ri_ms) ** p.ri_beta
        i0, i1 = np.where(sel)[0][[0, -1]]
        rows.append(dict(seg=int(s), lat_a=lat[i0], lon_a=lon[i0], lat_b=lat[i1], lon_b=lon[i1],
                         speed_kmh=v * 3.6, rms=rms, ri=ri, t0=t[i0], t1=t[i1]))
    df = pd.DataFrame(rows)
    if not df.empty:
        df["cls"] = [ri_class(x, p) for x in df["ri"]]
    return df


def ri_class(ri: float, p: Params) -> str:
    return CLASSES[int(np.searchsorted(p.ri_bounds, ri, side="right"))]
