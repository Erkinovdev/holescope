"""Экспорт эталонных результатов Python-алгоритма для проверки порта на Dart (app/test/parity_test.dart).
Запуск: python tools_export_fixtures.py"""
import json
import numpy as np
from holescope_algo.pipeline import process_csv
from holescope_algo.params import Params
from holescope_algo.io import load_csv, gps_frame
from holescope_algo.signal import vehicle_frame

A = "../analysis/"
OUT = "../app/test/fixtures/"
NAMES = ["pothole_2026-10-16_18-14-37.csv", "pothole_2026-10-17_12-09-50.csv"]


def clean(v):
    if isinstance(v, float) and v != v:
        return None
    if isinstance(v, (np.floating,)):
        return None if np.isnan(v) else float(v)
    if isinstance(v, (np.integer,)):
        return int(v)
    if isinstance(v, (np.bool_,)):
        return bool(v)
    return v


for n in NAMES:
    p = Params(wheelbase_m=2.485)
    r = process_csv(A + n, p)
    df, _ = load_csv(A + n)
    gps = gps_frame(df)
    sig = vehicle_frame(df, gps, p)
    ev = [{k: clean(v) for k, v in e.items() if k != "wave"} for e in r["events"]]
    seg = r["segments"]
    out = dict(
        file=n, wheelbase_m=2.485, algo_version=r["algo_version"], fwd_axis_ok=r["fwd_axis_ok"],
        hand_segments=[list(map(float, h)) for h in r["hand_segments"]],
        events=ev,
        segments=[{k: clean(v) for k, v in row.items()} for row in seg.to_dict("records")],
        auto_trips=[[float(a), float(b)] for a, b in r["auto_trips"]],
        damping={k: clean(v) for k, v in r["damping"].items()},
        suspension={k: clean(v) for k, v in r["suspension"].items()},
        n_samples=int(len(sig)),
        sig_probe=[dict(i=int(i), t=float(sig.t[i]), vz=float(sig.vz[i]), vx=float(sig.vx[i]), vy=float(sig.vy[i]),
                        gyro_h=float(sig.gyro_h[i]), tilt=float(sig.tilt[i])) for i in range(0, len(sig), 997)],
    )
    name = "ref_" + n.split("_")[1] + ".json"
    json.dump(out, open(OUT + name, "w", encoding="utf-8"), ensure_ascii=False)
    print(name, len(ev), "events", len(out["segments"]), "segments", len(out["sig_probe"]), "probes")
