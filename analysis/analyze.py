#!/usr/bin/env python3
"""Holescope: разбор записи: статистика, график, подсказка по порогу.

Установка (один раз):
    pip install pandas numpy matplotlib

Запуск:
    python analyze.py pothole_2026-10-16_12-00-00.csv
    python analyze.py запись.csv --show            # открыть окно с графиком
    python analyze.py запись.csv --from 120 --to 180   # приблизить участок (секунды от начала)

Что делает:
  * восстанавливает «вертикальный толчок» так же, как приложение (ускорение минус гравитация,
    спроецированное на направление гравитации);
  * по каждой ручной отметке находит пик толчка в окне перед отметкой
    (отметка всегда запаздывает: человек нажимает уже после удара);
  * сравнивает пики ям с фоновым шумом и подсказывает порог;
  * рисует график рядом с файлом (.png).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

LABELS_RU = {"pothole": "Яма", "manhole": "Люк", "bump": "Лежачий", "rail": "Рельсы / стык"}
COLORS = {"pothole": "#ff5d5d", "manhole": "#4da3ff", "bump": "#3ecf8e", "rail": "#c28bff"}
GRAV_ALPHA = 0.015  # как GRAV_K = 0.985 в app.js


def load(path: Path):
    meta: dict[str, str] = {}
    skip = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("#"):
                break
            skip += 1
            body = line[1:].strip()
            if "=" in body:
                k, v = body.split("=", 1)
                meta[k.strip()] = v.strip()
    df = pd.read_csv(path, skiprows=skip)
    if df.empty:
        raise SystemExit("В файле нет данных.")
    t0 = df["t_ms"].min()
    df["t"] = (df["t_ms"] - t0) / 1000.0
    return df, meta


def haversine(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dphi = p2 - p1
    dl = np.radians(lon2) - np.radians(lon1)
    a = np.sin(dphi / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * r * np.arcsin(np.sqrt(a))


def motion_vz(df: pd.DataFrame) -> pd.DataFrame:
    m = df[df["type"] == "m"].dropna(subset=["ax", "ay", "az"]).sort_values("t_ms").reset_index(drop=True)
    if m.empty:
        raise SystemExit("В файле нет отсчётов датчика движения.")
    a = m[["ax", "ay", "az"]].to_numpy(float)
    g = pd.DataFrame(a).ewm(alpha=GRAV_ALPHA, adjust=False).mean().to_numpy()
    gn = np.linalg.norm(g, axis=1)
    gn[gn == 0] = 1.0
    m["vz"] = ((a - g) * g).sum(axis=1) / gn
    return m


def gps_speed(df: pd.DataFrame) -> pd.DataFrame:
    g = df[df["type"] == "g"].sort_values("t_ms").reset_index(drop=True).copy()
    if g.empty:
        return g.assign(speed_kmh=np.nan)
    sp = g["speed_ms"].to_numpy(float)
    if np.isnan(sp).all() or np.isnan(sp).mean() > 0.5:
        # Скорость от GPS не пришла — считаем по смещению между фиксами.
        d = haversine(g["lat"].shift().to_numpy(float), g["lon"].shift().to_numpy(float),
                      g["lat"].to_numpy(float), g["lon"].to_numpy(float))
        dt = g["t"].diff().to_numpy(float)
        acc = g["gps_acc_m"].to_numpy(float)
        noise = np.fmax(acc, np.roll(acc, 1))   # погрешность худшего из двух фиксов
        with np.errstate(divide="ignore", invalid="ignore"):
            # смещение меньше погрешности GPS — это «дрожание» точки, а не движение
            derived = np.where(d > noise, d / dt, 0.0)
        sp = np.where(np.isnan(sp), derived, sp)
    g["speed_kmh"] = sp * 3.6
    return g


def speed_at(g: pd.DataFrame, t: float) -> float:
    ok = g.dropna(subset=["speed_kmh"])
    if ok.empty:
        return float("nan")
    return float(np.interp(t, ok["t"], ok["speed_kmh"]))


def real_marks(df: pd.DataFrame) -> pd.DataFrame:
    k = df[df["type"] == "k"].copy()
    u = df[df["type"] == "u"]
    if not u.empty and "note" in u:
        undone = set(pd.to_numeric(u["note"], errors="coerce").dropna().astype("int64"))
        k = k[~k["t_ms"].isin(undone)]
    return k.sort_values("t_ms")


def summary(df, m, g, k, a, meta, args):
    print("=" * 60)
    for key in ("car", "mount", "started", "ended", "auto_threshold_ms2"):
        if key in meta:
            print(f"{key:20s} {meta[key]}")
    print("-" * 60)
    dur = df["t"].max()
    dt = np.diff(m["t"].to_numpy())
    rate = 1.0 / np.median(dt) if len(dt) else float("nan")
    gaps = int((dt > 0.5).sum())
    print(f"Длительность          {dur / 60:.1f} мин")
    print(f"Отсчётов датчика      {len(m)}  (≈{rate:.0f} Гц), разрывов >0.5 с: {gaps}")
    v = df[df["type"] == "v"]
    if not v.empty:
        print(f"Экран скрывался/показывался: {len(v)} раз(а) — на этих участках данных нет")
    print(f"GPS-фиксов            {len(g)}"
          + (f", средняя точность ±{g['gps_acc_m'].mean():.0f} м" if len(g) else ""))
    if len(g):
        print(f"Скорость              средняя {g['speed_kmh'].mean():.0f}, максимум {g['speed_kmh'].max():.0f} км/ч")
    print(f"Отметок               {len(k)}: " +
          ", ".join(f"{LABELS_RU.get(l, l)} {n}" for l, n in k["label"].value_counts().items()))
    print(f"Авто-кандидатов       {len(a)}")
    print("=" * 60)


def mark_peaks(m, g, k, before, after):
    rows = []
    for _, r in k.iterrows():
        w = m[(m["t"] >= r["t"] - before) & (m["t"] <= r["t"] + after)]
        if w.empty:
            continue
        i = w["vz"].abs().idxmax()
        rows.append({
            "label": r["label"],
            "t": r["t"],
            "peak": float(abs(w.loc[i, "vz"])),
            "lag": float(r["t"] - w.loc[i, "t"]),   # на сколько секунд отметка позже удара
            "speed": speed_at(g, r["t"]),
        })
    return pd.DataFrame(rows)


def advise(m, k, peaks, before, threshold_in_file):
    print("\nПики толчка по ручным отметкам (окно: "
          f"{before:.1f} с до отметки):")
    if peaks.empty:
        print("  нет отметок с данными датчика")
        return
    for lab, grp in peaks.groupby("label"):
        print(f"  {LABELS_RU.get(lab, lab):14s} n={len(grp):3d}  "
              f"пик: медиана {grp['peak'].median():.1f}, мин {grp['peak'].min():.1f}, макс {grp['peak'].max():.1f} м/с²  "
              f"запаздывание отметки: медиана {grp['lag'].median():.1f} с")

    # Фон: всё, что не лежит рядом с отметками.
    mask = np.ones(len(m), bool)
    for t in k["t"]:
        mask &= ~((m["t"] >= t - before - 1.0) & (m["t"] <= t + 1.5))
    noise = m.loc[mask, "vz"].abs()
    if len(noise) < 100:
        print("\nМало данных вне отметок, чтобы оценить фон.")
        return
    p99, p999 = noise.quantile(0.99), noise.quantile(0.999)
    print(f"\nФон (вне отметок): 99% значений ниже {p99:.1f}, 99.9% ниже {p999:.1f} м/с²")

    holes = peaks[peaks["label"] == "pothole"]
    if holes.empty:
        print("Отметок «Яма» нет — порог подсказать не с чем.")
        return
    med = holes["peak"].median()
    low = holes["peak"].quantile(0.25)
    print(f"Ямы: медиана пика {med:.1f}, нижняя четверть {low:.1f} м/с²")
    if low > p999:
        thr = (p999 + low) / 2
        print(f"→ Порог можно ставить около {thr:.1f} м/с²: он выше шума и ниже большинства ям.")
    elif med > p99:
        print(f"→ Шум и слабые ямы пересекаются. Порог около {p999:.1f} поймает часть ям, "
              "остальные придётся различать по форме сигнала, не только по амплитуде.")
    else:
        print("→ Пики ям не отличаются от фона. Проверьте крепление телефона и время отметок "
              "(возможно, окно --before слишком мало).")
    if threshold_in_file:
        print(f"(порог в приложении во время записи: {threshold_in_file} м/с²)")

    others = peaks[peaks["label"].isin(["manhole", "bump", "rail"])]
    if not others.empty and not holes.empty:
        print("\nСравнение с неровностями другого типа (медиана пика):")
        for lab, grp in others.groupby("label"):
            print(f"  {LABELS_RU.get(lab, lab):14s} {grp['peak'].median():.1f} м/с²  (ямы {med:.1f})")


def plot(df, m, g, k, a, path, args):
    import matplotlib
    if not args.show:
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 7), sharex=True, gridspec_kw={"height_ratios": [1, 3]})
    if len(g):
        ax1.plot(g["t"], g["speed_kmh"], color="#555", lw=1.2)
    ax1.set_ylabel("км/ч")
    ax1.grid(alpha=0.25)

    ax2.plot(m["t"], m["vz"], color="#ffb020", lw=0.6)
    ax2.axhline(0, color="#999", lw=0.5)
    ax2.set_ylabel("вертикальный толчок, м/с²")
    ax2.set_xlabel("секунды от начала записи")
    ax2.grid(alpha=0.25)

    seen = set()
    for _, r in k.iterrows():
        lab = r["label"]
        ax2.axvline(r["t"], color=COLORS.get(lab, "#888"), lw=1.2, alpha=0.8,
                    label=None if lab in seen else LABELS_RU.get(lab, lab))
        seen.add(lab)
    if len(a):
        ax2.scatter(a["t"], [m["vz"].abs().max() * 1.02] * len(a), marker="v", color="#999", s=18, label="авто")

    if args.t_from is not None or args.t_to is not None:
        ax2.set_xlim(args.t_from, args.t_to)
    ax2.legend(loc="upper right")
    fig.tight_layout()

    out = path.with_suffix(".png")
    fig.savefig(out, dpi=130)
    print(f"\nГрафик сохранён: {out}")
    if args.show:
        plt.show()


def main():
    # Windows-консоль в режиме cp1252 падает на русском тексте — принудительно UTF-8.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    ap = argparse.ArgumentParser(description="Holescope: разбор записи")
    ap.add_argument("csv", type=Path)
    ap.add_argument("--before", type=float, default=3.0, help="окно перед отметкой, с (по умолчанию 3)")
    ap.add_argument("--after", type=float, default=0.5, help="окно после отметки, с (по умолчанию 0.5)")
    ap.add_argument("--from", dest="t_from", type=float, default=None, help="начало участка на графике, с")
    ap.add_argument("--to", dest="t_to", type=float, default=None, help="конец участка на графике, с")
    ap.add_argument("--show", action="store_true", help="открыть окно с графиком")
    args = ap.parse_args()

    df, meta = load(args.csv)
    m = motion_vz(df)
    m["t"] = (m["t_ms"] - df["t_ms"].min()) / 1000.0
    g = gps_speed(df)
    k = real_marks(df)
    a = df[df["type"] == "a"]

    summary(df, m, g, k, a, meta, args)
    peaks = mark_peaks(m, g, k, args.before, args.after)
    advise(m, k, peaks, args.before, meta.get("auto_threshold_ms2"))
    plot(df, m, g, k, a, args.csv, args)


if __name__ == "__main__":
    main()
