"""Чтение CSV логгера Holescope (формат версии 0.1)."""
from __future__ import annotations
from pathlib import Path
import numpy as np
import pandas as pd


def load_csv(path) -> tuple[pd.DataFrame, dict]:
    meta, skip = {}, 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("#"):
                break
            skip += 1
            body = line[1:].strip()
            if "=" in body:
                k, v = body.split("=", 1)
                meta[k.strip()] = v.strip()
    df = pd.read_csv(path, skiprows=skip, dtype={"type": "category", "label": "string", "note": "string"})
    if df.empty:
        raise ValueError("пустой файл")
    t0 = df["t_ms"].min()
    df["t"] = (df["t_ms"] - t0) / 1000.0
    return df, meta


def haversine(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = np.radians(lat1), np.radians(lat2)
    a = np.sin((p2 - p1) / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin((np.radians(lon2) - np.radians(lon1)) / 2) ** 2
    return 2 * r * np.arcsin(np.sqrt(a))


def gps_frame(df: pd.DataFrame) -> pd.DataFrame:
    g = df[df["type"] == "g"].dropna(subset=["lat", "lon"]).sort_values("t_ms").reset_index(drop=True).copy()
    sp = g["speed_ms"].to_numpy(float)
    bad = np.isnan(sp)
    if bad.mean() > 0.5:  # скорость не пришла — считаем по координатам
        d = haversine(g["lat"].shift().to_numpy(float), g["lon"].shift().to_numpy(float),
                      g["lat"].to_numpy(float), g["lon"].to_numpy(float))
        dt = np.diff(g["t"].to_numpy(float), prepend=np.nan)
        sp = np.nan_to_num(d / np.where(dt > 0, dt, np.nan))
    else:
        sp = np.where(bad, 0.0, sp)
    g["speed"] = sp
    return g
