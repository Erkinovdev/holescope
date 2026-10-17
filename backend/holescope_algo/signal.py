"""Слой 1–2: система координат автомобиля и чистка сигнала."""
from __future__ import annotations
import numpy as np
import pandas as pd
from .params import Params


def movavg(x: np.ndarray, n: int) -> np.ndarray:
    if n <= 1:
        return x
    k = np.ones(n) / n
    return np.convolve(x, k, mode="same")


def vehicle_frame(df: pd.DataFrame, gps: pd.DataFrame, p: Params) -> pd.DataFrame:
    """Возвращает отсчёты датчика с осями: vz (вертикаль), vx (вдоль движения), vy (поперёк), gyro_h (крен/тангаж),
    gravity-drift (для детектора «телефон взяли в руку»). Продольная ось оценивается регрессией горизонтального
    ускорения на ускорение по GPS (изменение скорости) — так торможение и разгон не попадают в «вертикаль»."""
    m = df[df["type"] == "m"].dropna(subset=["ax", "ay", "az"]).sort_values("t_ms").reset_index(drop=True)
    if len(m) < 100:
        raise ValueError("мало отсчётов датчика")
    t = m["t"].to_numpy(float)
    a = m[["ax", "ay", "az"]].to_numpy(float)
    g = pd.DataFrame(a).ewm(alpha=p.grav_alpha, adjust=False).mean().to_numpy()
    gn = np.linalg.norm(g, axis=1); gn[gn == 0] = 1.0
    gu = g / gn[:, None]
    dyn = a - g
    vz = (dyn * gu).sum(axis=1)
    h = dyn - vz[:, None] * gu                       # горизонтальная часть
    # базис горизонтальной плоскости по средней гравитации
    gm = gu.mean(axis=0); gm /= np.linalg.norm(gm)
    e1 = np.cross(gm, [1, 0, 0]);
    if np.linalg.norm(e1) < 0.2: e1 = np.cross(gm, [0, 1, 0])
    e1 /= np.linalg.norm(e1); e2 = np.cross(gm, e1)
    h1, h2 = h @ e1, h @ e2
    # продольная ось: регрессия на ускорение GPS (сглаженное)
    fwd = np.array([1.0, 0.0]); ok = False
    if len(gps) > 20:
        gt = gps["t"].to_numpy(float); sp = gps["speed"].to_numpy(float)
        acc = np.gradient(sp, gt)
        acc = movavg(acc, 3)
        a_i = np.interp(t, gt, acc)
        h1s, h2s = movavg(h1, 31), movavg(h2, 31)
        sel = np.abs(a_i) > 0.4
        if sel.sum() > 200:
            X = np.stack([h1s[sel], h2s[sel]], axis=1)
            coef, *_ = np.linalg.lstsq(X, a_i[sel], rcond=None)
            n = np.linalg.norm(coef)
            if n > 1e-6:
                fwd = coef / n; ok = True
    vx = h1 * fwd[0] + h2 * fwd[1]
    vy = -h1 * fwd[1] + h2 * fwd[0]
    # гироскоп: горизонтальная часть (крен/тангаж) — без вращения вокруг вертикали (повороты)
    gyro_h = np.zeros(len(m))
    if {"rx", "ry", "rz"}.issubset(m.columns):
        r = m[["rx", "ry", "rz"]].fillna(0).to_numpy(float)
        rv = (r * gu).sum(axis=1)
        gyro_h = np.linalg.norm(r - rv[:, None] * gu, axis=1)
    # локальное изменение направления гравитации за ~3 с (признак: телефон взяли в руку / сдвинули)
    rate = len(t) / max(t[-1] - t[0], 1.0)
    k = max(int(3.0 * rate), 1)
    gs = np.stack([movavg(gu[:, i], 15) for i in range(3)], axis=1)
    gs /= np.maximum(np.linalg.norm(gs, axis=1, keepdims=True), 1e-9)
    tilt = np.zeros(len(t))
    tilt[k:] = np.degrees(np.arccos(np.clip((gs[k:] * gs[:-k]).sum(axis=1), -1, 1)))
    out = pd.DataFrame(dict(t=t, vz=movavg(vz, p.smooth_samples), vx=vx, vy=vy, gyro_h=gyro_h, tilt=tilt))
    out.attrs["fwd_ok"] = ok
    return out


def hand_segments(sig: pd.DataFrame, gyro_thr=100.0, tilt_thr=30.0, pad_s=1.5):
    """Интервалы, где телефон, вероятно, брали в руку: большой гироскоп + смена наклона. Возвращает [(t0, t1), ...]."""
    t = sig["t"].to_numpy(float)
    bad = sig["tilt"].to_numpy(float) > tilt_thr      # гироскоп один не годится: сильная яма даёт короткий всплеск
    if not bad.any():
        return []
    idx = np.where(bad)[0]
    groups = np.split(idx, np.where(np.diff(t[idx]) > 2.0)[0] + 1)
    return [(float(t[g[0]] - pad_s), float(t[g[-1]] + pad_s)) for g in groups if len(g) and t[g[-1]] - t[g[0]] >= 0.8]
