"""Объяснения решений простыми словами и панель «что знает мозг / что делать дальше»."""
from __future__ import annotations
from django.db.models import Count
from .models import AlgoVersion, Label, Question, TrainingRun
from .training import MIN_LABELS, MIN_PER_TRIP, MIN_TRIPS, ROAD

LEVEL_RU = {"light": "лёгкая", "mid": "средняя", "deep": "глубокая", "danger": "опасная"}


def _num(f: dict, k: str):
    v = (f or {}).get(k)
    return float(v) if isinstance(v, (int, float)) else None


def explain_event(e) -> dict:
    """Почему система сочла это событие именно таким: список причин (за / против) и итог одной фразой."""
    f = e.features if isinstance(e.features, dict) else {}
    reasons: list[dict] = []

    def add(ok, text):
        reasons.append(dict(ok=ok, text=text))

    score = e.score
    if score >= 8:
        add(True, f"Сильный удар (сила {score:.1f}): заметно выше обычной тряски")
    elif score >= 5:
        add(True, f"Умеренный удар (сила {score:.1f})")
    elif score >= 2.4:
        add(True, f"Слабый удар (сила {score:.1f}), на грани шума")
    else:
        add(False, f"Очень слабый удар (сила {score:.1f}) — похоже на шум дороги")
    if e.speed_kmh < 15:
        add(False, f"Скорость всего {e.speed_kmh:.0f} км/ч — на малой скорости сигнал ненадёжен")
    else:
        add(True, f"Проезд на {e.speed_kmh:.0f} км/ч — скорости достаточно для уверенной оценки")
    pair, dur, gyro = _num(f, "pair"), _num(f, "dur_ms"), _num(f, "gyro_peak")
    if pair is not None:
        add(pair >= 0.2, "Удар пришёл парой (переднее колесо, затем заднее) — так бывает от ямы" if pair >= 0.2 else "Нет «пары» ударов передним и задним колесом — возможно, тронули телефон")
    if dur is not None and dur >= 250:
        add(True, f"Удар длился {dur:.0f} мс — дорожное событие, а не касание")
    if gyro is not None and gyro > 60 and pair is not None and pair < 0.2:
        add(False, "Сильный поворот телефона без пары ударов — похоже на касание телефона рукой")
    if e.user_label:
        add(e.user_label in ROAD, f"Водитель ответил: «{e.user_label}»")
    p = e.confidence
    word = "почти наверняка" if p >= 0.85 else "скорее всего" if p >= 0.6 else "возможно" if p >= 0.35 else "вряд ли"
    if e.type == "noise":
        verdict = "Считаем шумом — в карту не попадёт"
    elif e.type == "touch":
        verdict = "Считаем касанием телефона — не яма"
    else:
        verdict = f"{word.capitalize()} это неровность дороги ({LEVEL_RU.get(e.level, 'уровень не определён')}), уверенность {p:.0%}"
    return dict(verdict=verdict, reasons=reasons)


def explain_cluster(c, events) -> str:
    """Итог по яме: почему статус такой."""
    n_dev, n = c.devices, c.passes
    if c.status == "confirmed":
        return f"Подтверждена: удар зафиксирован на {n} проездах {n_dev} разными устройствами."
    if c.status == "fixed":
        return f"Считается заделанной: {c.quiet_passes} тихих проездов без удара."
    if c.status == "false":
        return "Отмечена ложной (модератором или моделью): не показывается водителям."
    if c.status == "candidate":
        need = max(0, 2 - n_dev)
        return f"Кандидат: пока {n} проезд(ов), {n_dev} устройств. " + (f"Нужно ещё {need} устройство с другого телефона, чтобы подтвердить." if need else "Ждём подтверждения.")
    return "Статус задан вручную."


def readiness() -> dict:
    """Что мозг знает и что делать дальше — простыми шагами."""
    n_labels = Label.objects.count()
    pos = Label.objects.filter(label__in=ROAD).count()
    neg = n_labels - pos
    per_trip = dict(Label.objects.exclude(trip_key="").values_list("trip_key").annotate(n=Count("id")))
    big = [k for k, n in per_trip.items() if n >= MIN_PER_TRIP]
    active = AlgoVersion.objects.filter(active=True, kind="gbm").first()
    last = TrainingRun.objects.order_by("-created").first()
    open_q = Question.objects.filter(status="open").count()
    steps = []
    if n_labels < MIN_LABELS:
        steps.append(f"Разметить ещё {MIN_LABELS - n_labels} событий (сейчас {n_labels} из {MIN_LABELS}) — в разделе «Очередь разметки».")
    if pos < 10:
        steps.append(f"Нужно хотя бы 10 примеров «это дорога» (сейчас {pos}).")
    if neg < 10:
        steps.append(f"Нужно хотя бы 10 примеров «это не дорога» — люки, рельсы, касания (сейчас {neg}).")
    if len(big) < MIN_TRIPS:
        steps.append(f"Разметка должна быть минимум из {MIN_TRIPS} разных поездок по {MIN_PER_TRIP}+ меток — иначе нельзя честно проверить модель (сейчас таких поездок: {len(big)}).")
    if not steps and not active:
        steps.append("Данных достаточно — нажмите «Обучить сейчас» на вкладке «Версии и метрики».")
    if active:
        steps.append("Модель включена. Продолжайте размечать спорные события — они улучшают её сильнее всего.")
    if open_q:
        steps.append(f"Ответов водителей ждут {open_q} вопросов — их можно разметить вручную.")
    pct = min(100, round(100 * min(n_labels / MIN_LABELS, 1) * 0.5 + 100 * min(len(big) / MIN_TRIPS, 1) * 0.5))
    if active:
        state, title = "learned", f"Умная модель {active.version} включена и принимает решения"
    elif pct >= 100:
        state, title = "ready", "Данных хватает — можно обучать модель"
    else:
        state, title = "rules", "Пока решают простые правила — модель ещё учится"
    last_txt = None
    if last:
        m = last.metrics or {}
        if m.get("model"):
            last_txt = f"Последнее обучение: модель {m['model']['f1']:.0%} против правил {m['rules']['f1']:.0%} (F1)"
        else:
            last_txt = last.log
    return dict(state=state, title=title, progress=pct, steps=steps, last_training=last_txt,
                facts=dict(labels=n_labels, road=pos, not_road=neg, trips_ready=len(big), trips_needed=MIN_TRIPS, labels_needed=MIN_LABELS, open_questions=open_q))
