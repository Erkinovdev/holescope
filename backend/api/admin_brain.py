"""Раздел «Мозг» админки: граф для 3D, шкала обучения, очередь вопросов, разметка, параметры алгоритма, версии, загрузка CSV."""
from __future__ import annotations
from datetime import timedelta
import numpy as np
from django.db.models import Count
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from brain import inference, review as review_mod, training
from brain.active_learning import uncertainty
from brain.models import AlgoVersion, AuditLog, BrainSnapshot, Label, Question, TrainingRun
from fleet.models import Device, Vehicle
from holescope_algo import ALGO_VERSION
from holescope_algo.params import Params
from roadnet.models import Segment
from telemetry.models import EventCluster, RawUpload, RoadEvent, SegmentScore, Trip
from .admin_api import audit, iso, page_of
from .auth import body, role_required

LABELS = ["pothole_light", "pothole_mid", "pothole_deep", "bump", "manhole", "rail", "joint", "noise", "handled"]

# допустимые диапазоны параметров алгоритма (защита от случайной порчи)
RANGES = dict(grav_alpha=(0.001, 0.2), smooth_samples=(1, 8), floor=(0.5, 10.0), k_noise=(1.0, 10.0), min_speed_ms=(0.2, 5.0), low_conf_speed_ms=(0.5, 8.0),
              v0_ms=(3.0, 20.0), speed_alpha=(0.0, 2.0), merge_gap_s=(0.2, 5.0), wheelbase_m=(1.5, 4.5), seg_len_m=(10.0, 200.0), ri_beta=(0.0, 2.0), min_speed_ri_ms=(0.5, 10.0))


def validate_params(d: dict) -> tuple[dict, str | None]:
    base = Params().to_dict()
    out = dict(base)
    for k, v in d.items():
        if k == "features" or k not in base:
            continue
        if k == "ri_bounds":
            if not (isinstance(v, (list, tuple)) and len(v) == 4 and all(isinstance(x, (int, float)) for x in v) and list(v) == sorted(v) and v[0] > 0):
                return {}, "ri_bounds: 4 возрастающих положительных числа (границы A|B|C|D|E)"
            out[k] = [float(x) for x in v]
            continue
        if not isinstance(v, (int, float)) or isinstance(v, bool):
            return {}, f"{k}: нужно число"
        lo, hi = RANGES.get(k, (-1e9, 1e9))
        if not lo <= v <= hi:
            return {}, f"{k}: допустимо {lo}…{hi}"
        out[k] = int(v) if isinstance(base[k], int) else float(v)
    return out, None


def version_json(a: AlgoVersion) -> dict:
    return dict(id=a.pk, version=a.version, kind=a.kind, active=a.active, metrics=a.metrics, notes=a.notes, created=iso(a.created), params=a.params if a.kind == "rules" else {"features": a.params.get("features")})


def active_params() -> dict:
    av = AlgoVersion.objects.filter(active=True, kind="rules").first()
    return validate_params(av.params)[0] if av and av.params else Params().to_dict()


# ───────────────────────── сводка и шкала ─────────────────────────
@role_required("analyst")
def summary(request):
    cur = dict(events=RoadEvent.objects.count(), clusters=EventCluster.objects.count(), confirmed=EventCluster.objects.filter(status="confirmed").count(),
               labels=Label.objects.count(), questions_open=Question.objects.filter(status="open").count(), devices=Device.objects.count(), vehicles=Vehicle.objects.count(),
               active_algo=str(AlgoVersion.objects.filter(active=True).first() or f"rules {ALGO_VERSION}"), segments=Segment.objects.count(),
               segments_scored=Segment.objects.exclude(cls="").count(), trips=Trip.objects.count(), uploads=RawUpload.objects.count())
    return JsonResponse({"current": cur, "history": list(BrainSnapshot.objects.order_by("-day")[:60].values())})


@role_required("analyst")
def timeline(request):
    runs = [dict(id=r.pk, at=iso(r.created), n_labels=r.n_labels, metrics=r.metrics, log=r.log, version=r.algo.version if r.algo else None) for r in TrainingRun.objects.order_by("-created")[:50]]
    snaps = [dict(day=s.day.isoformat(), events=s.events_total, clusters=s.clusters_total, labels=s.labels_total, km=round(s.km_total, 1), devices=s.devices_active, precision=s.precision, recall=s.recall)
             for s in BrainSnapshot.objects.order_by("day")[:365]]
    versions = [version_json(a) for a in AlgoVersion.objects.order_by("-created")]
    rules_f1 = next((v["metrics"].get("rules", {}).get("f1") for v in versions if v["kind"] == "gbm" and v["metrics"].get("rules")), None)
    return JsonResponse(dict(runs=runs, snapshots=snaps, versions=versions, base=dict(version=f"rules {ALGO_VERSION}", f1=rules_f1)))


# ───────────────────────── граф для 3D ─────────────────────────
@role_required("analyst")
def graph(request):
    """Узлы: ямы (размер = проезды, цвет = уверенность), дороги, версии, признаки модели, устройства-подтвердители. Связи — принадлежность и подтверждения."""
    limit = max(20, min(int(request.GET.get("limit", 220) or 220), 500))
    clusters = list(EventCluster.objects.exclude(status="false").select_related("segment__road").order_by("-passes", "-last_hit")[:limit])
    nodes, edges, idx = [], [], {}

    def node(key, **kw):
        if key not in idx:
            idx[key] = len(nodes)
            nodes.append(dict(id=key, **kw))
        return idx[key]
    for c in clusters:
        node(f"c{c.pk}", kind="cluster", label=(c.segment.road.name_ru if c.segment and c.segment.road.named else f"{c.lat:.4f},{c.lon:.4f}"), size=1 + c.passes, confidence=round(c.confidence, 2),
             status=c.status, level=c.level, ref=c.pk)
        if c.segment:
            r = c.segment.road
            node(f"r{r.pk}", kind="road", label=r.name_ru, size=3, confidence=1.0, ref=r.pk, road_class=r.road_class)
            edges.append(dict(a=f"c{c.pk}", b=f"r{r.pk}", kind="on_road", w=1))
    ids = [c.pk for c in clusters]
    for d_id, cid, n in RoadEvent.objects.filter(cluster_id__in=ids, device__trust__gte=0.3).values_list("device_id", "cluster_id").annotate(n=Count("id")):
        node(f"d{d_id}", kind="device", label=f"устройство {d_id}", size=2, confidence=0.7, ref=d_id)
        edges.append(dict(a=f"d{d_id}", b=f"c{cid}", kind="confirms", w=int(n)))
    for a in AlgoVersion.objects.order_by("created")[:10]:
        node(f"v{a.pk}", kind="version", label=a.version, size=6, confidence=1.0 if a.active else 0.4, ref=a.pk, active=a.active)
        for f in (a.params or {}).get("features", []) if a.kind == "gbm" else []:
            node(f"f{f}", kind="feature", label=f, size=2, confidence=0.8)
            edges.append(dict(a=f"v{a.pk}", b=f"f{f}", kind="uses", w=1))
    ev_versions = dict(RoadEvent.objects.filter(cluster_id__in=ids).values_list("algo_version").annotate(n=Count("id")))
    for ver, n in ev_versions.items():
        k = next((f"v{a.pk}" for a in AlgoVersion.objects.filter(version=ver)), None)
        if k is None:
            k = f"vr{ver}"
            node(k, kind="version", label=f"rules {ver}" if ver else "rules", size=6, confidence=1.0, active=not AlgoVersion.objects.filter(active=True, kind="gbm").exists())
        # связь «версия → её события» показываем весом узла версии
        nodes[idx[k]]["events"] = nodes[idx[k]].get("events", 0) + int(n)
    return JsonResponse(dict(nodes=nodes, edges=edges, counts=dict(clusters=len(clusters), nodes=len(nodes), edges=len(edges))))


# ───────────────────────── очередь вопросов и разметка ─────────────────────────
@role_required("analyst")
def questions(request):
    now = timezone.now()
    stats = dict(open=Question.objects.filter(status="open").count(), answered=Question.objects.filter(status="answered").count(), skipped=Question.objects.filter(status="skipped").count(),
                 answered_7d=Question.objects.filter(status="answered", answered_at__gte=now - timedelta(days=7)).count(), labels=Label.objects.count(),
                 by_source=dict(Label.objects.values_list("source").annotate(n=Count("id"))))
    labeled = set(Label.objects.exclude(event=None).values_list("event_id", flat=True))
    cand = []
    for e in RoadEvent.objects.exclude(pk__in=labeled).filter(user_label="").select_related("cluster").order_by("-at")[:400]:
        pr = 0.6 * uncertainty(e.confidence) + 0.3 * (1.0 if (e.cluster is None or e.cluster.passes <= 1) else 1 / np.sqrt(e.cluster.passes)) + 0.1 * min(e.score / 10.0, 1.0)
        cand.append((pr, e))
    cand.sort(key=lambda x: -x[0])
    queue = [dict(id=e.pk, priority=round(float(pr), 3), at=iso(e.at), lat=e.lat, lon=e.lon, speed_kmh=e.speed_kmh, peak=e.peak, score=e.score, type=e.type, level=e.level,
                  confidence=e.confidence, wave=e.wave, cluster=e.cluster_id) for pr, e in cand[:int(request.GET.get("limit", 30) or 30)]]
    return JsonResponse(dict(stats=stats, queue=queue, labels=LABELS))


@csrf_exempt
@role_required("labeler")
@require_http_methods(["POST"])
def label_event(request):
    d = body(request)
    e = RoadEvent.objects.filter(pk=d.get("event_id")).first()
    if not e:
        return JsonResponse({"error": "event not found"}, status=404)
    if d.get("label") not in LABELS:
        return JsonResponse({"error": f"label: {LABELS}"}, status=400)
    lab = Label.objects.create(event=e, source="admin", label=d["label"], features=e.features, trip_key=str(e.trip_id))
    RoadEvent.objects.filter(pk=e.pk).update(user_label=d["label"])
    audit(request, "label", f"event:{e.pk}", dict(label=d["label"]))
    return JsonResponse(dict(id=lab.pk, labels_total=Label.objects.count()), status=201)


# ───────────────────────── параметры и версии ─────────────────────────
@role_required("analyst")
def params_get(request):
    av = AlgoVersion.objects.filter(active=True, kind="rules").first()
    return JsonResponse(dict(version=av.version if av else f"rules {ALGO_VERSION} (по умолчанию)", params=active_params(), ranges=RANGES, defaults=Params().to_dict()))


@csrf_exempt
@role_required("admin")
@require_http_methods(["PUT"])
def params_put(request):
    """Новая версия правил с изменёнными параметрами. {"params": {...}, "activate": true, "notes": "..."}"""
    d = body(request)
    p, err = validate_params(d.get("params") or {})
    if err:
        return JsonResponse({"error": err}, status=400)
    n = AlgoVersion.objects.filter(kind="rules").count() + 1
    av = AlgoVersion.objects.create(version=f"rules-{n}", kind="rules", params=p, notes=str(d.get("notes", ""))[:500], active=False)
    if d.get("activate"):
        AlgoVersion.objects.filter(kind="rules", active=True).update(active=False)
        av.active = True
        av.save(update_fields=["active"])
    audit(request, "algo.params", f"version:{av.pk}", dict(params=p, activate=bool(d.get("activate"))))
    return JsonResponse(version_json(av), status=201)


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def activate(request):
    """Переключить активную версию. Для gbm применяется ограничение: нельзя включить версию, не прошедшую проверку, без подтверждения force=true."""
    d = body(request)
    av = AlgoVersion.objects.filter(pk=d.get("version_id")).first()
    if not av:
        return JsonResponse({"error": "version not found"}, status=404)
    if av.kind == "gbm" and not (av.metrics or {}).get("activated") and not d.get("force"):
        return JsonResponse({"error": "версия не прошла проверку (не лучше правил на отложенных поездках); force=true — включить вручную", "metrics": av.metrics}, status=409)
    AlgoVersion.objects.filter(kind=av.kind, active=True).update(active=False)
    av.active = True
    av.save(update_fields=["active"])
    audit(request, "algo.activate", f"version:{av.pk}", dict(force=bool(d.get("force"))))
    return JsonResponse(version_json(av))


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def deactivate(request):
    d = body(request)
    av = AlgoVersion.objects.filter(pk=d.get("version_id")).first()
    if not av:
        return JsonResponse({"error": "version not found"}, status=404)
    av.active = False
    av.save(update_fields=["active"])
    audit(request, "algo.deactivate", f"version:{av.pk}")
    return JsonResponse(version_json(av))


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def train_now(request):
    run = training.train()
    out = dict(log=run.log, metrics=run.metrics, n_labels=run.n_labels, version=run.algo.version if run.algo else None, active=bool(run.algo and run.algo.active))
    if run.algo and run.algo.active and request.GET.get("reprocess") == "1":
        out["reprocess"] = inference.reprocess_events()
    audit(request, "brain.train", f"run:{run.pk}", out)
    return JsonResponse(out)


def algo_params_public(request):
    """Публично: параметры активной версии правил — приложение подтягивает их и применяет на устройстве."""
    av = AlgoVersion.objects.filter(active=True, kind="rules").first()
    return JsonResponse(dict(version=av.version if av else ALGO_VERSION, params=active_params()))


# ───────────────────────── загрузки CSV, просмотр, предпросмотр ─────────────────────────
def upload_json(u: RawUpload):
    return dict(id=u.pk, filename=u.filename, created=iso(u.created), processed=u.processed, algo_version=u.algo_version, report=u.report, device=u.device_id)


@csrf_exempt
@role_required("labeler")
@require_http_methods(["POST"])
def upload_csv(request):
    """Ручная загрузка CSV поездки (drag-and-drop): прогон алгоритма активной версии и отчёт."""
    from holescope_algo.pipeline import process_csv
    f = request.FILES.get("file")
    if not f:
        return JsonResponse({"error": "file required"}, status=400)
    try:
        wb = float(request.POST.get("wheelbase_m", 2.6))
    except ValueError:
        return JsonResponse({"error": "wheelbase_m"}, status=400)
    if not 1.5 <= wb <= 4.5:
        return JsonResponse({"error": "wheelbase_m 1.5–4.5"}, status=400)
    ru = RawUpload.objects.create(file=f, filename=f.name[:200])
    p = review_mod.params_from({**active_params(), "wheelbase_m": wb})
    try:
        r = process_csv(ru.file.path, p)
    except Exception as e:                         # битый файл — понятная ошибка, а не 500
        ru.file.delete(save=False)           # битый файл не копим
        ru.delete()
        return JsonResponse({"error": f"не удалось разобрать файл: {str(e)[:200]}"}, status=422)
    ru.processed, ru.algo_version = True, r["algo_version"]
    from collections import Counter
    ru.report = dict(events=len(r["events"]), by_type=dict(Counter(e["type"] for e in r["events"])), segments=len(r["segments"]), hand=len(r["hand_segments"]), auto_trips=len(r["auto_trips"]),
                     duration_s=round(r["duration_s"]), distance_km=round(r["distance_km"], 1), damping=r["damping"], suspension=r["suspension"], wheelbase_m=wb)
    ru.save()
    audit(request, "upload.csv", f"upload:{ru.pk}", dict(name=f.name))
    return JsonResponse(dict(raw_id=ru.pk, report=ru.report), status=201)


@role_required("analyst")
def uploads_list(request):
    return JsonResponse(page_of(RawUpload.objects.order_by("-created"), request, upload_json, default=30))


@role_required("analyst")
def upload_review(request, rid):
    """Сигнал, события и путь загруженной записи (перенос review.html)."""
    u = RawUpload.objects.filter(pk=rid).first()
    if not u:
        return JsonResponse({"error": "not found"}, status=404)
    try:
        return JsonResponse(review_mod.review(u.file.path, {**active_params(), "wheelbase_m": (u.report or {}).get("wheelbase_m", 2.6)}))
    except Exception as e:
        return JsonResponse({"error": f"не удалось разобрать: {str(e)[:200]}"}, status=422)


@csrf_exempt
@role_required("analyst")
@require_http_methods(["POST"])
def preview(request):
    """Предпросмотр параметров на выбранной записи БЕЗ сохранения: сравнение событий с текущей версией."""
    d = body(request)
    u = RawUpload.objects.filter(pk=d.get("raw_id")).first()
    if not u:
        return JsonResponse({"error": "raw_id: запись не найдена"}, status=404)
    p, err = validate_params(d.get("params") or {})
    if err:
        return JsonResponse({"error": err}, status=400)
    base = {**active_params(), "wheelbase_m": (u.report or {}).get("wheelbase_m", 2.6)}
    try:
        new = review_mod.review(u.file.path, {**p, "wheelbase_m": base["wheelbase_m"]}, use_cache=False)
        cur = review_mod.review(u.file.path, base)
    except Exception as e:
        return JsonResponse({"error": f"не удалось разобрать: {str(e)[:200]}"}, status=422)
    from collections import Counter
    count = lambda r: dict(total=len(r["events"]), by_type=dict(Counter(e["type"] for e in r["events"])), by_level=dict(Counter(e["level"] for e in r["events"] if e.get("level"))))
    ct = {round(e["t"], 1) for e in cur["events"]}
    nt = {round(e["t"], 1) for e in new["events"]}
    return JsonResponse(dict(current=count(cur), preview=count(new), added=len(nt - ct), removed=len(ct - nt), events=new["events"], signal=new["signal"], path=new["path"]))
