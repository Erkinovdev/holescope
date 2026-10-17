#!/usr/bin/env python3
"""Holescope: режим разбора поездки.

Запуск:
    python analysis\review.py analysis\pothole_2026-10-16_18-14-37.csv
Результат: рядом с файлом появится review_<имя>.html — откройте его двойным щелчком в браузере.
Опции: --floor 2.0 (минимальный порог, м/с²)  --k 4 (во сколько раз выше фонового шума)
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
import numpy as np
import pandas as pd
from analyze import load, motion_vz, gps_speed, real_marks, haversine

MIN_SPEED_MS = 3.0
SEG_M = 50.0
WIN_BEFORE, WIN_AFTER = 3.0, 0.5   # окно поиска толчка относительно отметки (как в analyze.py)


def build(path: Path, floor: float, k: float, minspeed: float = 1.0):
    df, meta = load(path)
    m = motion_vz(df)
    g = gps_speed(df).dropna(subset=["lat", "lon"]).reset_index(drop=True)
    marks = real_marks(df)
    app = df[df["type"] == "a"]
    t = m["t"].to_numpy(float)
    vz = m["vz"].to_numpy(float)
    gt = g["t"].to_numpy(float)
    sp_ms = np.interp(t, gt, g["speed_kmh"].to_numpy(float) / 3.6)
    lat = np.interp(t, gt, g["lat"].to_numpy(float))
    lon = np.interp(t, gt, g["lon"].to_numpy(float))
    moving = sp_ms >= MIN_SPEED_MS

    # --- фоновый шум: rms по секундам, скользящая медиана 21 с
    sec = np.floor(t).astype(int)
    rms = pd.Series(vz ** 2).groupby(sec).mean() ** 0.5
    rms = rms.reindex(range(sec.min(), sec.max() + 1)).interpolate()
    noise_s = rms.rolling(21, center=True, min_periods=5).median().bfill().ffill()
    noise = np.interp(t, noise_s.index.to_numpy(float) + 0.5, noise_s.to_numpy(float))
    thr = np.maximum(floor, k * noise)

    # --- события: превышение порога при движении, слияние в пределах 1 с
    idx = np.where((np.abs(vz) > thr) & (sp_ms >= minspeed))[0]
    events = []
    if len(idx):
        groups = np.split(idx, np.where(np.diff(t[idx]) > 1.0)[0] + 1)
        for gi in groups:
            j = gi[np.argmax(np.abs(vz[gi]))]
            events.append(j)

    # --- признаки
    ev = []
    for n, j in enumerate(events):
        te = t[j]
        w = (t >= te - 0.5) & (t <= te + 0.5)
        wv = vz[w]; wt = t[w]
        peak = float(np.abs(vz[j]))
        half = np.abs(wv) >= 0.5 * peak
        dur = float(wt[half].max() - wt[half].min()) if half.any() else 0.0
        energy = float((wv ** 2).sum() * np.median(np.diff(wt))) if len(wt) > 1 else 0.0
        after = (t > te + 0.06) & (t <= te + 0.35)
        pair = float(np.abs(vz[after]).max() / peak) if after.any() else 0.0
        first = int(np.sign(wv[np.argmax(np.abs(wv) >= 0.5 * peak)])) if half.any() else 0
        sn = (t >= te - 2) & (t <= te + 2)
        ev.append(dict(
            id=n, t=round(float(te), 2), lat=round(float(lat[j]), 6), lon=round(float(lon[j]), 6),
            speed=round(float(sp_ms[j] * 3.6), 1), peak=round(peak, 2), noise=round(float(noise[j]), 2),
            thr=round(float(thr[j]), 2), ratio=round(peak / max(float(noise[j]), 0.05), 1),
            pos=round(float(wv.max()), 2), neg=round(float(wv.min()), 2), first=first,
            dur=round(dur * 1000), energy=round(energy, 2), pair=round(pair, 2),
            wave=[round(float(x), 1) for x in vz[sn]], wt0=round(float(t[sn][0] - te), 2),
            src=[], mark=None))

    # --- сопоставление с ручными отметками и авто-кандидатами приложения
    et = np.array([e["t"] for e in ev]) if ev else np.array([])
    miss = []
    for _, r in marks.iterrows():
        sel = np.where((et >= r["t"] - WIN_BEFORE) & (et <= r["t"] + WIN_AFTER))[0]
        if len(sel):
            best = sel[np.argmax([ev[i]["peak"] for i in sel])]
            ev[best]["src"].append("mark"); ev[best]["mark"] = r["label"]
        else:
            lo = (t >= r["t"] - WIN_BEFORE) & (t <= r["t"] + WIN_AFTER)
            miss.append((r["label"], float(r["t"]), float(np.abs(vz[lo]).max()) if lo.any() else float("nan"),
                         float(noise[np.argmin(np.abs(t - r["t"]))])))
    app_hit = 0
    for _, r in app.iterrows():
        sel = np.where(np.abs(et - r["t"]) <= 1.0)[0] if len(et) else []
        if len(sel):
            app_hit += 1
            for i in sel: ev[i]["src"].append("app")
    for e in ev:
        e["src"] = sorted(set(e["src"]))

    # --- ровность: сегменты по 50 м
    sp_g = g["speed_kmh"].to_numpy(float) / 3.6
    d = haversine(g["lat"].shift().to_numpy(float), g["lon"].shift().to_numpy(float),
                  g["lat"].to_numpy(float), g["lon"].to_numpy(float))
    d = np.where(np.nan_to_num(sp_g) >= MIN_SPEED_MS, np.nan_to_num(d), 0.0)
    cum = np.cumsum(d)
    dist = np.interp(t, gt, cum)
    sid = (dist // SEG_M).astype(int)
    seg = []
    for s in np.unique(sid[moving]):
        sel = (sid == s) & moving
        if sel.sum() < 30:
            continue
        v = float(np.mean(sp_ms[sel]))
        r_ = float(np.sqrt(np.mean(vz[sel] ** 2)) / max(v, MIN_SPEED_MS))
        i0, i1 = np.where(sel)[0][[0, -1]]
        seg.append(dict(a=[round(float(lat[i0]), 6), round(float(lon[i0]), 6)],
                        b=[round(float(lat[i1]), 6), round(float(lon[i1]), 6)], r=r_))
    if seg:
        rr = np.array([s["r"] for s in seg])
        qs = np.quantile(rr, [0.40, 0.75, 0.93])
        for s in seg:
            s["lvl"] = int(np.searchsorted(qs, s["r"]))
            s["r"] = round(s["r"], 4)
    lvl_names = ["ровная", "нормальная", "неровная", "разбитая"]

    step = max(1, len(g) // 600)
    route = [[round(float(a), 6), round(float(b), 6)] for a, b in zip(g["lat"][::step], g["lon"][::step])]
    stats = dict(events=len(ev), marks=len(marks), marks_hit=len(marks) - len(miss), miss=miss,
                 app=len(app), app_hit=app_hit, new=sum(1 for e in ev if not e["src"]),
                 seg=len(seg), seg_lvl=[sum(1 for s in seg if s["lvl"] == i) for i in range(4)],
                 floor=floor, k=k, noise_med=float(np.median(noise_s)))
    return dict(file=path.name, meta=meta, events=ev, segs=seg, route=route, lvl=lvl_names), stats


def main():
    for s in (sys.stdout, sys.stderr):
        try: s.reconfigure(encoding="utf-8", errors="replace")
        except Exception: pass
    ap = argparse.ArgumentParser(description="Holescope: режим разбора поездки")
    ap.add_argument("csv"); ap.add_argument("--floor", type=float, default=2.0); ap.add_argument("--k", type=float, default=4.0)
    ap.add_argument("--minspeed", type=float, default=1.0); ap.add_argument("--no-html", action="store_true")
    a = ap.parse_args()
    path = Path(a.csv)
    data, st = build(path, a.floor, a.k, a.minspeed)
    print(f"Порог: max({st['floor']}, {st['k']}×шум), фоновый шум (медиана) {st['noise_med']:.2f} м/с²")
    print(f"Найдено толчков (событий): {st['events']}")
    print(f"Ваши отметки: {st['marks']}, из них попало в найденные толчки: {st['marks_hit']}")
    for lab, tm, pk, nz in st["miss"]:
        print(f"   пропущена: {lab} на {tm:.0f} с  (пик {pk:.1f}, шум {nz:.2f})")
    print(f"Авто-кандидаты приложения: {st['app']}, совпали с событиями: {st['app_hit']}")
    print(f"Новых событий без отметки и без кандидата: {st['new']}")
    print(f"Сегментов дороги по {int(SEG_M)} м: {st['seg']}; ровная/нормальная/неровная/разбитая: {st['seg_lvl']}")
    if a.no_html: return
    tpl = (Path(__file__).parent / "review_template.html").read_text(encoding="utf-8")
    out = path.with_name("review_" + path.stem + ".html")
    out.write_text(tpl.replace("__DATA__", json.dumps(data, ensure_ascii=False)), encoding="utf-8")
    print("Страница разбора:", out)

if __name__ == "__main__":
    main()
