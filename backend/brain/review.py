"""Просмотр записи (перенос analysis/review.py в админку): сигнал вертикали с пиками, события, путь, участки «в руке»."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import numpy as np
from holescope_algo.classify import classify
from holescope_algo.detector import detect
from holescope_algo.io import gps_frame, load_csv
from holescope_algo.params import Params
from holescope_algo.signal import hand_segments, vehicle_frame


def params_from(d: dict | None) -> Params:
    p = Params()
    for k, v in (d or {}).items():
        if hasattr(p, k) and k != "features":
            setattr(p, k, tuple(v) if k == "ri_bounds" else v)
    return p


def downsample_minmax(t: np.ndarray, y: np.ndarray, buckets: int = 1500):
    """Прореживание с сохранением экстремумов (пики не теряются): на каждый бакет — min и max."""
    n = len(t)
    if n <= buckets * 2:
        return t.tolist(), y.tolist()
    idx = np.linspace(0, n, buckets + 1, dtype=int)
    tt, yy = [], []
    for a, b in zip(idx[:-1], idx[1:]):
        seg = y[a:b]
        if not len(seg):
            continue
        i0, i1 = int(np.argmin(seg)) + a, int(np.argmax(seg)) + a
        for i in sorted({i0, i1}):
            tt.append(float(t[i]))
            yy.append(float(y[i]))
    return tt, yy


def review(path: str | Path, params: dict | None = None, use_cache: bool = True) -> dict:
    path = Path(path)
    key = hashlib.sha1(json.dumps(params or {}, sort_keys=True).encode()).hexdigest()[:10]
    cache = path.with_suffix(path.suffix + f".review-{key}.json")
    if use_cache and cache.exists():
        return json.loads(cache.read_text(encoding="utf-8"))
    p = params_from(params)
    df, meta = load_csv(path)
    gps = gps_frame(df)
    sig = vehicle_frame(df, gps, p)
    hands = hand_segments(sig)
    events = detect(sig, gps, p, exclude=hands)
    out_ev = []
    for e in events:
        d = e.asdict()
        d.update(classify(e))
        d.pop("wave", None)
        out_ev.append({k: (None if isinstance(v, float) and v != v else v) for k, v in d.items()})
    t, vz = downsample_minmax(sig["t"].to_numpy(float), sig["vz"].to_numpy(float))
    step = max(1, len(gps) // 400)
    path_pts = [[round(float(r.lat), 6), round(float(r.lon), 6), round(float(r.t), 1), round(float(r.speed) * 3.6, 1)] for r in gps.iloc[::step].itertuples()]
    res = dict(meta={k: v for k, v in meta.items() if k != "user_agent"}, params=p.to_dict(), duration_s=float(sig["t"].iloc[-1]), samples=int(len(sig)),
               signal=dict(t=t, vz=vz), events=out_ev, hands=[[float(a), float(b)] for a, b in hands], path=path_pts, fwd_ok=bool(sig.attrs.get("fwd_ok")))
    cache.write_text(json.dumps(res, ensure_ascii=False), encoding="utf-8")
    return res
