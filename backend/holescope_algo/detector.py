"""Слои 3–4: детектор толчков и признаки формы удара."""
from __future__ import annotations
from dataclasses import dataclass, field
import numpy as np
import pandas as pd
from .params import Params
from .signal import movavg


@dataclass
class Event:
    t: float
    lat: float = float("nan")
    lon: float = float("nan")
    speed_kmh: float = 0.0
    heading: float = float("nan")
    peak: float = 0.0           # |vz|, м/с²
    score: float = 0.0          # пик с поправкой на скорость
    noise: float = 0.0
    ratio: float = 0.0          # пик / фон
    first: int = 0              # знак первого заметного удара (-1 провал, +1 толчок)
    dur_ms: float = 0.0
    energy: float = 0.0
    pair: float = 0.0           # амплитуда второго удара / первого в окне колёсной базы
    pair_dt: float = 0.0        # интервал между ударами, с
    hf_share: float = 0.0       # доля энергии 8–25 Гц
    lat_share: float = 0.0      # боковая компонента / вертикаль
    long_share: float = 0.0     # продольная компонента / вертикаль
    gyro_peak: float = 0.0
    zeta: float = float("nan")  # коэффициент затухания после удара (признак подвески)
    f_body: float = float("nan")
    low_conf: bool = False
    wave: list = field(default_factory=list)

    def asdict(self):
        d = self.__dict__.copy()
        return d


def background_noise(t, vz, p: Params):
    sec = np.floor(t).astype(int)
    rms = pd.Series(vz ** 2).groupby(sec).mean() ** 0.5
    rms = rms.reindex(range(sec.min(), sec.max() + 1)).interpolate()
    ns = rms.rolling(21, center=True, min_periods=5).median().bfill().ffill()
    return np.interp(t, ns.index.to_numpy(float) + 0.5, ns.to_numpy(float)), ns


def _decay(t, vz, j, te, p: Params):
    """Оценка частоты и затухания кузова по затуханию колебаний после удара (низкочастотная часть)."""
    w = (t > te + 0.1) & (t <= te + 1.6)
    if w.sum() < 30:
        return float("nan"), float("nan")
    seg = movavg(vz[w], 9)                              # ~0.15 с — оставляем частоты кузова < ~4 Гц
    ts = t[w]
    d = np.diff(np.sign(np.diff(seg)))
    ext = np.where(d != 0)[0] + 1
    if len(ext) < 3:
        return float("nan"), float("nan")
    amp = np.abs(seg[ext]); tt = ts[ext]
    a0, a1 = amp[0], amp[1]
    if a1 < 1e-3 or a0 <= a1 or a0 < 0.4:
        return float("nan"), float("nan")
    delta = np.log(a0 / a1)
    zeta = delta / np.sqrt(4 * np.pi ** 2 + delta ** 2)
    half = np.mean(np.diff(tt[:3])) if len(tt) >= 3 else np.nan
    f = 1.0 / (2 * half) if half and half > 0 else float("nan")
    return float(zeta), float(f)


def detect(sig: pd.DataFrame, gps: pd.DataFrame, p: Params, exclude=()) -> list[Event]:
    t = sig["t"].to_numpy(float)
    vz = sig["vz"].to_numpy(float)
    vx = sig["vx"].to_numpy(float); vy = sig["vy"].to_numpy(float); gy = sig["gyro_h"].to_numpy(float)
    gt = gps["t"].to_numpy(float)
    sp = np.interp(t, gt, gps["speed"].to_numpy(float))
    lat = np.interp(t, gt, gps["lat"].to_numpy(float)); lon = np.interp(t, gt, gps["lon"].to_numpy(float))
    hd = gps["heading_deg"].to_numpy(float) if "heading_deg" in gps else np.full(len(gt), np.nan)
    hd = np.interp(t, gt, np.nan_to_num(hd))
    noise, _ = background_noise(t, vz, p)
    # поправка на скорость: удар ~ (v/v0)^alpha  →  нормализуем к опорной скорости
    vfac = np.clip(sp / p.v0_ms, 0.35, 3.0) ** p.speed_alpha
    thr = np.maximum(p.floor, p.k_noise * noise)
    ok_t = np.ones(len(t), bool)
    for a, b in exclude:
        ok_t &= ~((t >= a) & (t <= b))
    idx = np.where((np.abs(vz) > thr) & (sp >= p.min_speed_ms) & ok_t)[0]
    if not len(idx):
        return []
    groups = np.split(idx, np.where(np.diff(t[idx]) > p.merge_gap_s)[0] + 1)
    dts = np.median(np.diff(t))
    events: list[Event] = []
    for gi in groups:
        j = gi[np.argmax(np.abs(vz[gi]))]
        te = t[j]; v = max(sp[j], 0.5)
        w = (t >= te - 0.5) & (t <= te + 0.5)
        wv, wt = vz[w], t[w]
        peak = float(abs(vz[j]))
        half = np.abs(wv) >= 0.5 * peak
        dur = float(wt[half].max() - wt[half].min()) if half.any() else 0.0
        energy = float((wv ** 2).sum() * dts)
        first = int(np.sign(wv[np.argmax(np.abs(wv) >= 0.5 * peak)])) if half.any() else 0
        # второй удар: окно вокруг wheelbase / v
        dt2 = p.wheelbase_m / v
        lo, hi = te + 0.6 * dt2, te + 1.6 * dt2
        a2 = (t > lo) & (t <= min(hi, te + 0.6))
        pair = float(np.abs(vz[a2]).max() / peak) if a2.any() else 0.0
        # спектр 0.5 с вокруг удара
        if len(wv) > 16:
            sp_ = np.abs(np.fft.rfft(wv - wv.mean())) ** 2
            fr = np.fft.rfftfreq(len(wv), dts)
            tot = sp_.sum() + 1e-9
            hf = float(sp_[(fr >= 8) & (fr <= 25)].sum() / tot)
        else:
            hf = 0.0
        lat_s = float(np.abs(vy[w]).max() / peak); lon_s = float(np.abs(vx[w]).max() / peak)
        zeta, fb = _decay(t, vz, j, te, p)
        sn = (t >= te - 2) & (t <= te + 2)
        events.append(Event(
            t=round(float(te), 3), lat=float(lat[j]), lon=float(lon[j]), speed_kmh=round(float(v * 3.6), 1),
            heading=float(hd[j]), peak=round(peak, 3), score=round(float(peak / vfac[j]), 3),
            noise=round(float(noise[j]), 3), ratio=round(peak / max(float(noise[j]), 0.05), 2),
            first=first, dur_ms=round(dur * 1000), energy=round(energy, 3), pair=round(pair, 3),
            pair_dt=round(dt2, 3), hf_share=round(hf, 3), lat_share=round(lat_s, 3), long_share=round(lon_s, 3),
            gyro_peak=round(float(gy[w].max()), 1), zeta=zeta, f_body=fb,
            low_conf=bool(v < p.low_conf_speed_ms), wave=[round(float(x), 1) for x in vz[sn][::2]]))
    return events
