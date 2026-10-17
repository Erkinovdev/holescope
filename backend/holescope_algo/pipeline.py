"""Полный проход: CSV → события, типы, сегменты ровности, поездки, индекс подвески."""
from __future__ import annotations
from pathlib import Path
import numpy as np
from . import ALGO_VERSION
from .params import Params
from .io import load_csv, gps_frame
from .signal import vehicle_frame, hand_segments
from .detector import detect
from .classify import classify
from .roughness import segments
from .suspension import damping_summary, softness_score
from .trip_state import TripDetector


def process_csv(path, params: Params | None = None) -> dict:
    p = params or Params()
    df, meta = load_csv(path)
    gps = gps_frame(df)
    sig = vehicle_frame(df, gps, p)
    hands = hand_segments(sig)
    events = detect(sig, gps, p, exclude=hands)
    out_events = []
    for e in events:
        c = classify(e)
        d = e.asdict(); d.update(c); d["algo_version"] = ALGO_VERSION
        out_events.append(d)
    seg = segments(sig, gps, p)
    td = TripDetector()
    for _, r in gps.iterrows():
        td.update(float(r["t"]), float(r["speed"]) * 3.6)
    td.finish(float(gps["t"].iloc[-1]))
    damp = damping_summary(events)
    susp = softness_score(None, damp["zeta_median"], damp["f_body_median"])
    return dict(meta=meta, algo_version=ALGO_VERSION, params=p.to_dict(), fwd_axis_ok=bool(sig.attrs.get("fwd_ok")),
                hand_segments=hands, events=out_events, segments=seg, auto_trips=td.trips,
                damping=damp, suspension=susp,
                duration_s=float(sig["t"].iloc[-1]), distance_km=float(gps["speed"].mean() * gps["t"].iloc[-1] / 1000))
