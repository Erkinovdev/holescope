"""Раздел «Мозг»: модели ИИ с именами, их состояние и эксперименты на размеченных данных.

Модели (всё это одна система, разные «области мозга»):
  Сезги   (Sezgi, «ощущение»)    — детектор ударов в сигнале телефона: пороги, шум, скорость
  Назар   (Nazar, «взгляд»)      — угадывает, что это было (яма / люк / лежачий …) и насколько опасно
  Мезон   (Mezon, «мерило»)      — оценивает качество дороги по участкам A–E и находит протяжённые плохие участки
  Хотира  (Xotira, «память»)     — запоминает места: объединяет проезды в элементы, подтверждает и закрывает
  Устоз   (Ustoz, «наставник»)   — выбирает вопросы водителям там, где модель не уверена, и учит остальных
  Холи    (Holi, голос)          — слушает голосовые отметки водителя
"""
from __future__ import annotations
from collections import Counter
from datetime import timedelta
from django.db.models import Count
from django.http import JsonResponse
from django.utils import timezone
from brain import guesser, lane, stretches, taxonomy
from brain.models import AlgoVersion, Label, Question, TrainingRun
from roadnet.models import Segment
from telemetry.models import DriverMark, EventCluster, RoadEvent, Trip
from .admin_brain import active_params
from .admin_api import iso
from .auth import role_required


def _pct(v):
    return None if v is None else round(v * 100)


@role_required("analyst")
def models_overview(request):
    now = timezone.now()
    day = now - timedelta(days=1)
    params = active_params()
    rules = AlgoVersion.objects.filter(active=True, kind="rules").first()
    guess_v = AlgoVersion.objects.filter(active=True, kind="guess").first()
    types_v = AlgoVersion.objects.filter(active=True, kind="types").first()
    rows = guesser.labeled_rows()
    res = guesser.evaluate(rows) if len(rows) >= 8 else {}
    ev_total = RoadEvent.objects.count()
    ev_24 = RoadEvent.objects.filter(created__gte=day).count()
    clusters = list(EventCluster.objects.exclude(status="false").values_list("type", "level", "status"))
    elements = sum(1 for t, l, _ in clusters if taxonomy.is_element(t, l))
    confirmed = sum(1 for _, _, s in clusters if s == "confirmed")
    seg_total = Segment.objects.count()
    seg_scored = Segment.objects.exclude(cls="").count()
    bad = Segment.objects.filter(cls__in=("D", "E")).count()
    q_open = Question.objects.filter(status="open").count()
    q_done = Question.objects.filter(status="answered").count()
    q_all = Question.objects.exclude(status="open").count()
    marks = DriverMark.objects.count()
    marks_with = list(DriverMark.objects.exclude(guess={}).values_list("guess", flat=True)[:500])
    voice_top1 = None
    if marks_with:
        from telemetry.marks import label_of as brain_label
        pairs = [(g, brain_label(k)) for g, k in zip(marks_with, DriverMark.objects.exclude(guess={}).values_list("kind", flat=True)[:500])]
        voice_top1 = sum(1 for g, t in pairs if g.get("top") == t) / len(pairs)
    last_run = TrainingRun.objects.order_by("-created").first()
    models = [
        dict(key="sezgi", name="Сезги", sub="Детектор ударов", color="amber", tab="algo", version=rules.version if rules else "правила по умолчанию",
             about="Ищет удары в сигнале акселерометра: считает фоновый шум дороги и ловит всплески выше порога. Чем выше порог, тем меньше ложных срабатываний на неровностях.",
             stats=[("Порог (пол)", f"{params['floor']:.1f} м/с²"), ("Порог шума", f"×{params['k_noise']:.1f}"), ("Событий всего", ev_total), ("За 24 часа", ev_24)]),
        dict(key="nazar", name="Назар", sub="Что это было?", color="info", tab="learning", version=(guess_v.version if guess_v else "—") + (f" · типы {types_v.version}" if types_v else ""),
             about="Смотрит на форму удара и контекст (рельсы, мост, повторные проезды) и называет вероятности: яма, люк, лежачий, рельсы… Учится на ответах водителей.",
             stats=[("Точность (top-1)", f"{_pct((res.get('guess') or {}).get('top1'))}%" if res.get("guess") else "—"), ("Точность (top-3)", f"{_pct((res.get('guess') or {}).get('top3'))}%" if res.get("guess") else "—"),
                    ("Размечено", len(rows)), ("Дорога/не дорога", f"{_pct(res.get('road_vs_not'))}%" if res.get("road_vs_not") is not None else "—")]),
        dict(key="mezon", name="Мезон", sub="Качество дороги", color="smooth", tab="algo", version=f"RI · {len(params['ri_bounds'])+1} класса" if False else "индекс ровности A–E",
             about="Оценивает ровность каждого 50-метрового сегмента и склеивает плохие сегменты в протяжённые участки: старый асфальт, колея, расшатанное полотно.",
             stats=[("Оценено сегментов", f"{seg_scored} из {seg_total}"), ("Плохих (D/E)", bad), ("Участков ≥100 м", len(stretches.find(min_len=100, limit=500))), ("Границы A|B|C|D|E", " · ".join(f"{x:g}" for x in params["ri_bounds"]))]),
        dict(key="xotira", name="Хотира", sub="Память мест", color="crater", tab="memory", version="кластеры по проездам",
             about="Объединяет повторные удары в одно место, считает проезды и устройства, подтверждает элемент, отмечает «заделано», определяет сторону и полосу.",
             stats=[("Элементов", elements), ("Подтверждено", confirmed), ("Мелкие/средние ямы → качество", len(clusters) - elements), ("С известной стороной", sum(1 for c in EventCluster.objects.exclude(lane={}).values_list("lane", flat=True) if c.get("side") in ("left", "right")))]),
        dict(key="ustoz", name="Устоз", sub="Наставник", color="amber", tab="questions", version="активное обучение",
             about="Выбирает самые полезные вопросы водителю: где Назар сомневается и где место новое. Каждый ответ становится разметкой и учит остальные модели.",
             stats=[("Ждут ответа", q_open), ("Отвечено", q_done), ("Доля ответов", f"{round(100 * q_done / q_all)}%" if q_all else "—"), ("Последнее обучение", iso(last_run.created)[:10] if last_run else "—")]),
        dict(key="holi", name="Холи", sub="Голосовой помощник", color="info", tab="learning", version="распознавание команд",
             about="Слушает короткие команды водителя — «яма», «люк», «да», «нет» — и превращает их в разметку, пока руки заняты рулём.",
             stats=[("Голосовых отметок", marks), ("Точность угадывания", f"{_pct(voice_top1)}%" if voice_top1 is not None else "—")]),
    ]
    for m in models:
        m["stats"] = [dict(label=a, value=b) for a, b in m["stats"]]
    iq = None
    try:
        from .admin_evolution import _intelligence
        counts = Counter(r["truth"] for r in rows)
        iq = _intelligence(res, len(rows), dict(counts))
    except Exception:
        pass
    activity = dict(events_24h=ev_24, trips_24h=Trip.objects.filter(created__gte=day).count(), labels_7d=Label.objects.filter(created__gte=now - timedelta(days=7)).count(),
                    questions_open=q_open, events_total=ev_total, labels_total=Label.objects.count(), trips_total=Trip.objects.count(), clusters_total=len(clusters),
                    elements=elements, quality=len(clusters) - elements)
    return JsonResponse(dict(models=models, iq=iq, activity=activity, at=iso(now)))


# ───────────────────────── эксперименты ─────────────────────────
LEVEL_FLOORS = [2.0, 2.3, 2.6, 3.0, 3.5, 4.0]
NOT_ROAD = ("noise", "handled", "curb", "braking")


def _kind(truth: str) -> str:
    it = taxonomy.BY_KEY.get(taxonomy.norm(truth))
    return it.kind if it else "none"


@role_required("analyst")
def experiments(request):
    """Три опыта на размеченных событиях: 1) насколько снижение чувствительности убирает ложные срабатывания и что теряет;
    2) как делятся метки на элементы и качество; 3) как растёт точность Назара по мере разметки (кривая обучения)."""
    rows = guesser.labeled_rows()
    n = len(rows)
    base = Counter(_kind(r["truth"]) for r in rows)
    sweep = []
    for fl in LEVEL_FLOORS:
        kept = Counter(); total = Counter()
        for r in rows:
            k = _kind(r["truth"])
            total[k] += 1
            if float(r["f"].get("score") or 0) >= fl:
                kept[k] += 1
        share = lambda k: None if not total[k] else round(kept[k] / total[k], 3)
        sweep.append(dict(floor=fl, events_kept=round(sum(kept.values()) / n, 3) if n else None, noise_removed=None if not total["none"] else round(1 - kept["none"] / total["none"], 3),
                          elements_kept=share("element"), quality_kept=share("quality")))
    # кривая обучения: точность на отложенной части при росте объёма разметки (последовательно, по времени разметки)
    curve = []
    ordered = sorted(rows, key=lambda r: r["labeled_at"])
    for frac in (0.25, 0.4, 0.55, 0.7, 0.85, 1.0):
        m = max(8, int(n * frac))
        if m > n or m < 8:
            continue
        r = guesser.evaluate(ordered[:m])
        if r.get("guess"):
            curve.append(dict(labels=m, top1=r["guess"]["top1"], logloss=r["guess"]["logloss"], top3=r["guess"]["top3"]))
    # сторона и полоса: сколько элементов уже имеют уверенное определение
    lane_cnt = Counter()
    for t, lv, ln in EventCluster.objects.exclude(status="false").values_list("type", "level", "lane"):
        if not taxonomy.is_element(t, lv):
            continue
        d = lane.describe(t, lv, ln)
        lane_cnt[d["span"] + ":" + d["advice"]] += 1
    return JsonResponse(dict(labeled=n, kinds=dict(base), floor_sweep=sweep, learning_curve=curve, lane=dict(lane_cnt),
                             note="Опыт 1 показывает цену чувствительности: строка с высоким «убрано шума» и почти полным «сохранено элементов» — хороший порог."))
