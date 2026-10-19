"""Калибровка «мозга» по разметке: границы уровней ям и классов ровности дорог — с предложением системы и применением одной кнопкой."""
from __future__ import annotations
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from brain import intelligence, road_stats, taxonomy
from brain.models import AlgoVersion, Label
from telemetry.models import DriverMark, Segment
from .admin_api import audit
from .admin_brain import active_params, validate_params
from .auth import body, role_required

LEVEL_LABELS = {"pothole_light": "light", "pothole_mid": "mid", "pothole_deep": "deep", "pothole_danger": "danger"}


def _level_pairs() -> list[tuple[float, str]]:
    out = []
    for lab, score in Label.objects.filter(label__in=LEVEL_LABELS, event__isnull=False).values_list("label", "event__score"):
        out.append((float(score), LEVEL_LABELS[lab]))
    return out


def _ratings() -> dict[str, list[float]]:
    by: dict[str, list[float]] = {c: [] for c in "ABCDE"}
    for kind, ri in DriverMark.objects.filter(kind__in=list(taxonomy.ROAD_RATINGS), ri__isnull=False).values_list("kind", "ri"):
        by[taxonomy.ROAD_RATINGS[kind][0]].append(float(ri))
    return by


@role_required("analyst")
def calibration(request):
    cur_levels = road_stats.level_bounds()
    levels = intelligence.suggest_level_bounds(_level_pairs(), current=cur_levels)
    levels.update(active=road_stats.active_level_bounds() is not None, default=list(road_stats.DEFAULT_LEVEL_BOUNDS))
    ri_now = tuple(active_params().get("ri_bounds") or (0.03, 0.05, 0.08, 0.13))
    ri = intelligence.suggest_ri_bounds(_ratings(), current=ri_now)
    ri["names"] = {c: v[1] for c, v in ((v[0], v) for v in taxonomy.ROAD_RATINGS.values())}
    return JsonResponse(dict(levels=levels, ri=ri))


def _bounds(d, n):
    b = d.get("bounds")
    if not (isinstance(b, list) and len(b) == n and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in b) and b == sorted(b) and b[0] > 0):
        return None
    return [float(x) for x in b]


@csrf_exempt
@role_required("admin")
@require_http_methods(["POST"])
def calibration_apply(request):
    """{"kind": "levels"|"ri", "bounds": [..]} — новая версия границ, включается сразу; уровни ям пересчитываются."""
    d = body(request)
    kind = d.get("kind")
    if kind == "levels":
        b = _bounds(d, 3)
        if not b:
            return JsonResponse({"error": "bounds: 3 возрастающих положительных числа"}, status=400)
        n = AlgoVersion.objects.filter(kind="levels").count() + 1
        AlgoVersion.objects.filter(kind="levels", active=True).update(active=False)
        av = AlgoVersion.objects.create(version=f"levels-{n}", kind="levels", params={"bounds": b}, metrics=intelligence.suggest_level_bounds(_level_pairs(), current=b), notes=str(d.get("notes", ""))[:300], active=True)
        res = road_stats.relevel_all(tuple(b))
        audit(request, "calibration.levels", f"version:{av.pk}", res)
        return JsonResponse(dict(version=av.version, **res), status=201)
    if kind == "ri":
        b = _bounds(d, 4)
        if not b:
            return JsonResponse({"error": "bounds: 4 возрастающих положительных числа"}, status=400)
        p, err = validate_params({**active_params(), "ri_bounds": b})
        if err:
            return JsonResponse({"error": err}, status=400)
        n = AlgoVersion.objects.filter(kind="rules").count() + 1
        AlgoVersion.objects.filter(kind="rules", active=True).update(active=False)
        av = AlgoVersion.objects.create(version=f"rules-{n}", kind="rules", params=p, notes="границы классов по оценкам водителей", active=True)
        ids = list(Segment.objects.filter(ri_n__gt=0).values_list("id", flat=True))
        done = road_stats.refresh_segments(ids)
        audit(request, "calibration.ri", f"version:{av.pk}", dict(bounds=b, segments=done))
        return JsonResponse(dict(version=av.version, segments=done, bounds=b), status=201)
    return JsonResponse({"error": "kind: levels | ri"}, status=400)
