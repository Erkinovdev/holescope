"""Все настраиваемые параметры алгоритма в одном месте (подбираются по данным, хранятся в БД как AlgoVersion.params)."""
from dataclasses import dataclass, asdict


@dataclass
class Params:
    # --- сигнал
    grav_alpha: float = 0.015          # EWMA гравитации (как в приложении, GRAV_K = 0.985)
    smooth_samples: int = 2            # скользящее среднее для вертикали (убирает дребезг > ~25 Гц)
    # --- детектор
    floor: float = 2.0                 # минимальный порог, м/с²
    k_noise: float = 4.0               # порог = max(floor, k × фоновый шум за 21 с)
    min_speed_ms: float = 1.0          # ниже — события не ищем
    low_conf_speed_ms: float = 2.8     # ниже ~10 км/ч — помечаем «слабая достоверность»
    v0_ms: float = 11.1                # опорная скорость 40 км/ч
    speed_alpha: float = 0.8           # удар ~ (v/v0)^alpha  (подбирается по повторным проездам)
    merge_gap_s: float = 1.0
    # --- форма
    wheelbase_m: float = 2.6           # колёсная база; по умолчанию средняя, берётся из профиля машины
    touch_pair_max: float = 0.2
    touch_dur_max_ms: float = 250.0
    touch_peak_min: float = 6.0
    # --- ровность
    seg_len_m: float = 50.0
    ri_beta: float = 1.0
    ri_bounds: tuple = (0.03, 0.05, 0.08, 0.13)   # границы A|B|C|D|E (стартовые, калибруются по городу)
    min_speed_ri_ms: float = 3.0

    def to_dict(self):
        return asdict(self)
