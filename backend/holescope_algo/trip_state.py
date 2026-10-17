"""Автоматический старт/стоп поездки (фон): конечный автомат без кнопки.

Состояния: IDLE → ARMED (похоже на езду) → DRIVING → ENDING → IDLE.
Старт: скорость ≥ 15 км/ч держится 20 с (или ОС сообщает activity=automotive).
Стоп: скорость < 3 км/ч дольше 3 мин  ИЛИ  стоим дольше 45 с и ОС видит ходьбу (водитель вышел, забыл выключить)
      ИЛИ нет датчиков/GPS дольше 5 мин. Последние `trim_s` секунд простоя из записи обрезаются.
Тип транспорта (авто / автобус-трамвай / поезд / пешком) — по профилю остановок и вибрации (см. classify_mode).
"""
from __future__ import annotations
from dataclasses import dataclass, field


@dataclass
class TripConfig:
    start_speed_kmh: float = 15.0
    start_hold_s: float = 20.0
    stop_speed_kmh: float = 3.0
    stop_hold_s: float = 180.0
    walk_stop_hold_s: float = 45.0
    lost_signal_s: float = 300.0
    trim_s: float = 60.0


class TripDetector:
    def __init__(self, cfg: TripConfig | None = None):
        self.cfg = cfg or TripConfig()
        self.state = "IDLE"
        self._t_fast = None      # с какого момента скорость выше порога старта
        self._t_slow = None      # с какого момента скорость ниже порога остановки
        self._t_walk = None
        self._last_t = None
        self.trip_start = None
        self.trips: list[tuple[float, float]] = []

    def update(self, t: float, speed_kmh: float | None, activity: str | None = None):
        """activity: 'automotive' | 'walking' | 'stationary' | None (из CoreMotion / Activity Recognition)."""
        c = self.cfg
        if speed_kmh is None:
            if self.state == "DRIVING" and self._last_t is not None and t - self._last_t > c.lost_signal_s:
                self._end(self._last_t)
            return self.state
        self._last_t = t
        if self.state in ("IDLE", "ARMED"):
            if speed_kmh >= c.start_speed_kmh or activity == "automotive" and speed_kmh >= 8:
                self._t_fast = self._t_fast if self._t_fast is not None else t
                self.state = "ARMED"
                if t - self._t_fast >= c.start_hold_s:
                    self.state = "DRIVING"; self.trip_start = self._t_fast
                    self._t_slow = self._t_walk = None
            else:
                self._t_fast = None; self.state = "IDLE"
        elif self.state == "DRIVING":
            slow = speed_kmh < c.stop_speed_kmh
            self._t_slow = (self._t_slow if self._t_slow is not None else t) if slow else None
            walking = slow and activity == "walking"
            self._t_walk = (self._t_walk if self._t_walk is not None else t) if walking else None
            if self._t_walk is not None and t - self._t_walk >= c.walk_stop_hold_s:
                self._end(self._t_slow if self._t_slow is not None else t)
            elif self._t_slow is not None and t - self._t_slow >= c.stop_hold_s:
                self._end(self._t_slow)
        return self.state

    def _end(self, t_end: float):
        self.trips.append((self.trip_start, t_end))
        self.state = "IDLE"; self._t_fast = self._t_slow = self._t_walk = None; self.trip_start = None

    def finish(self, t: float):
        if self.state == "DRIVING":
            self._end(self._t_slow if self._t_slow is not None else t)


def classify_mode(speeds_kmh, stops_per_km: float, hf_vibration_rms: float) -> tuple[str, float]:
    """Грубое правило определения «не легковая» поездка. Возвращает (mode, confidence).
    car: остановки у светофоров ≤ 3/км; bus/tram: ≥ 3 остановок/км ровным шагом; walk: < 8 км/ч постоянно."""
    import numpy as np
    s = np.asarray(speeds_kmh, float)
    if len(s) == 0:
        return "unknown", 0.0
    if np.percentile(s, 90) < 9:
        return "walk_or_bike", 0.7
    if stops_per_km >= 3.0 and np.percentile(s, 90) < 55:
        return "bus_or_tram", 0.5
    if np.percentile(s, 90) > 110:
        return "train_or_highway", 0.4
    return "car", 0.6
