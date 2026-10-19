"""Эволюция модели: насколько она умнеет, где ошибается и от чего это зависит. Всё считается по разметке; оценка — на отложенных поездках."""
from __future__ import annotations
from collections import Counter, defaultdict
from datetime import timedelta
from django.http import JsonResponse
from django.utils import timezone
from brain import guesser, taxonomy
from brain.models import AlgoVersion, BrainSnapshot, TrainingRun
from telemetry.marks import label_of as brain_label
from telemetry.models import DriverMark, RoadEvent
from .admin_api import iso
from .auth import role_required


def _intelligence(res: dict, n_labels: int, class_counts: dict[str, int]) -> dict:
    """Индекс «ума» 0–100 из четырёх понятных частей (формула показывается в админке)."""
    data = min(1.0, n_labels / 200.0)
    if res.get("guess"):
        maj = res["majority"]["acc"]
        lift = max(0.0, min(1.0, (res["guess"]["top1"] - maj) / max(1e-9, 1.0 - maj)))
        cal = res["calibration"]
        calib = max(0.0, 1.0 - 2.0 * abs(cal["mean_confidence"] - cal["accuracy"]))
    else:
        lift = calib = 0.0
    classes = sum(1 for n in class_counts.values() if n >= 6)
    cover = min(1.0, classes / 8.0)
    score = 100.0 * (0.30 * data + 0.35 * lift + 0.15 * calib + 0.20 * cover)
    return dict(score=round(score), parts=dict(data=round(data, 2), lift=round(lift, 2), calibration=round(calib, 2), coverage=round(cover, 2)),
                weights=dict(data=0.30, lift=0.35, calibration=0.15, coverage=0.20),
                formula="30 % объём разметки (200 меток = максимум) + 35 % выигрыш у «всегда самое частое» + 15 % честность уверенности + 20 % число типов с ≥6 метками (8 = максимум)")


@role_required("analyst")
def evolution(request):
    rows = guesser.labeled_rows()
    res = guesser.evaluate(rows)
    n = len(rows)
    truth_counts = Counter(r["truth"] for r in rows)
    names = {i.key: i.ru for i in taxonomy.ITEMS}

    # динамика: догадки, сохранённые на момент приёма, против меток по дням разметки
    by_day: dict[str, list] = defaultdict(list)
    for r in rows:
        if r["stored"]:
            by_day[r["labeled_at"].date().isoformat()].append(1.0 if r["stored"] == r["truth"] else 0.0)
    series, cum_ok, cum_n = [], 0.0, 0
    for day in sorted(by_day):
        v = by_day[day]
        cum_ok += sum(v)
        cum_n += len(v)
        series.append(dict(day=day, labeled=len(v), accuracy=round(sum(v) / len(v), 3), cumulative=round(cum_ok / cum_n, 3)))

    # разбивки по сохранённой догадке: класс дороги, машина, источник метки
    def split(keyf):
        b: dict[str, list] = defaultdict(list)
        for r in rows:
            if r["stored"]:
                b[str(keyf(r) or "—")].append(1.0 if r["stored"] == r["truth"] else 0.0)
        return {k: dict(n=len(v), accuracy=round(sum(v) / len(v), 3)) for k, v in sorted(b.items(), key=lambda kv: -len(kv[1]))}

    # матрица ошибок: истина → что сказала модель
    conf: dict[str, Counter] = defaultdict(Counter)
    for r in rows:
        if r["stored"]:
            conf[r["truth"]][r["stored"]] += 1
    confusion = [dict(truth=t, truth_name=names.get(t, t), predicted={p: c for p, c in cnt.most_common(4)}) for t, cnt in sorted(conf.items(), key=lambda kv: -sum(kv[1].values()))]

    snaps = [dict(day=s.day.isoformat(), events=s.events_total, labels=s.labels_total, km=round(s.km_total, 1), devices=s.devices_active) for s in BrainSnapshot.objects.order_by("day")[:120]]
    versions = []
    for a in AlgoVersion.objects.order_by("-created")[:40]:
        m = a.metrics or {}
        versions.append(dict(id=a.pk, version=a.version, kind=a.kind, active=a.active, created=iso(a.created), notes=a.notes,
                             f1=(m.get("model") or {}).get("f1"), rules_f1=(m.get("rules") or {}).get("f1"), logloss=((m.get("eval") or {}).get("guess") or {}).get("logloss")))
    runs = [dict(id=r.pk, at=iso(r.created), kind=(r.metrics or {}).get("kind", "gbm"), n=r.n_labels, log=r.log) for r in TrainingRun.objects.order_by("-created")[:15]]
    marks_day = defaultdict(int)
    for at in DriverMark.objects.filter(created__gte=timezone.now() - timedelta(days=30)).values_list("created", flat=True):
        marks_day[at.date().isoformat()] += 1
    dev = [(m.guess, brain_label(m.kind)) for m in DriverMark.objects.exclude(guess={}).only("guess", "kind")]
    device_guess = None
    if dev:
        ok = sum(1 for g, t in dev if g.get("top") == t)
        top3 = sum(1 for g, t in dev if t in (g.get("top3") or {}))
        via = Counter(g.get("via", "?") for g, _ in dev)
        device_guess = dict(n=len(dev), top1=round(ok / len(dev), 3), top3=round(top3 / len(dev), 3), voice_share=round(via.get("voice", 0) / len(dev), 3),
                            mean_confidence=round(sum(float(g.get("p") or 0) for g, _ in dev) / len(dev), 3))
    ev_total = RoadEvent.objects.count()
    return JsonResponse(dict(
        labeled=n, events=ev_total, coverage=round(n / ev_total, 3) if ev_total else 0, eval=res,
        classes=[dict(key=k, name=names.get(k, k), n=c) for k, c in truth_counts.most_common()], device_guess=device_guess,
        intelligence=_intelligence(res, n, dict(truth_counts)), params=guesser.active_params(),
        series=series, by_road_class=split(lambda r: r["road_class"]), by_vehicle=split(lambda r: r["vehicle"]), by_source=split(lambda r: r["source"]),
        confusion=confusion, snapshots=snaps, versions=versions, runs=runs, marks_per_day=[dict(day=d, n=c) for d, c in sorted(marks_day.items())],
    ))
