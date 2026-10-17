"""Сборка дорожного графа в БД: OSM-кэш → Road (R01, A014, B203…) и Segment (≈50 м, R01-0412)."""
from __future__ import annotations
import math
from collections import Counter, defaultdict
import numpy as np
from django.db import transaction
from . import classify
from .geo import PolygonSet, split_polyline, bearing, K
from .models import District, Road, Segment

CLASS_ORDER = "RABCDS"
# Коды районов Ташкента. Названия берутся из OSM (ru/uz), ничего не придумываем.
DISTRICT_CODES = {
    "yunus": "UZ-TSH-YUN", "chilon": "UZ-TSH-CHI", "mirobod": "UZ-TSH-MIR", "sergeli": "UZ-TSH-SER", "olmazor": "UZ-TSH-ALM",
    "bektemir": "UZ-TSH-BEK", "shayhon": "UZ-TSH-SHA", "uchtepa": "UZ-TSH-UCH", "yakkasaroy": "UZ-TSH-YAK", "yashnobod": "UZ-TSH-YAS",
    "mirzo": "UZ-TSH-MUL", "hayot": "UZ-TSH-YAN",
}


def _district_code(name: str) -> str | None:
    n = (name or "").lower().replace(" ", "")
    for k, v in DISTRICT_CODES.items():
        if k in n:
            return v
    return None


def _norm_name(tags: dict) -> str:
    return (tags.get("name:ru") or tags.get("name") or tags.get("name:uz") or "").strip()


@transaction.atomic
def import_districts(data: dict) -> tuple[District, dict[str, District]]:
    """Страна/область/город/районы из OSM. Возвращает (город, {код: район})."""
    uz, _ = District.objects.get_or_create(code="UZ", defaults=dict(name_ru="Узбекистан", name_uz="Oʻzbekiston", level="country"))
    region, _ = District.objects.get_or_create(code="UZ-TSH", defaults=dict(name_ru="Ташкент", name_uz="Toshkent", level="region", parent=uz))
    city, _ = District.objects.get_or_create(code="UZ-TSH-CITY", defaults=dict(name_ru="город Ташкент", name_uz="Toshkent shahri", level="city", parent=region))
    city_area = next((a for a in data["areas"] if a["admin_level"] == "4"), None)
    if city_area:
        ps = PolygonSet(city_area["geometry"])
        city.boundary, city.bbox, city.osm_relation_id = city_area["geometry"], list(ps.bbox), city_area["id"]
        city.save()
    out = {}
    for a in data["areas"]:
        if a["admin_level"] != "6":
            continue
        code = _district_code(a["name"])
        if not code:
            continue
        ps = PolygonSet(a["geometry"])
        d, _ = District.objects.update_or_create(code=code, defaults=dict(
            name_ru=(a["name_ru"] or a["name"]).strip(), name_uz=(a["name_uz"] or a["name"]).strip(), level="district", parent=city,
            bbox=list(ps.bbox), boundary=a["geometry"], osm_relation_id=a["id"]))
        out[code] = d
    return city, out


def _grid(points, cell=0.0006):
    g = defaultdict(list)
    for lat, lon in points:
        g[(int(lat / cell), int(lon / cell))].append((lat, lon))
    return g, cell


def _near(grid, lat, lon, radius_m):
    g, cell = grid
    ci, cj = int(lat / cell), int(lon / cell)
    c = math.cos(math.radians(lat))
    for di in (-1, 0, 1):
        for dj in (-1, 0, 1):
            for la, lo in g.get((ci + di, cj + dj), ()):
                if math.hypot((lo - lon) * c * K, (la - lat) * K) <= radius_m:
                    return True
    return False


def build_network(data: dict, log=print, replace: bool = True, only_city: bool = True) -> dict:
    """Строит Road и Segment из OSM-кэша. Идемпотентно: при replace=True старая сеть удаляется."""
    city, districts = import_districts(data)
    city_poly = PolygonSet(city.boundary) if (only_city and city.boundary) else None
    tram_grid = _grid([p for line in data["tram"] for p in line])
    lc_grid = _grid(data["crossings"])

    ways = []
    for w in data["ways"]:
        pts = w["pts"]
        mid = pts[len(pts) // 2]
        if city_poly is not None and not city_poly.contains([mid[0]], [mid[1]])[0]:
            continue
        ways.append(w)
    log(f"путей в городе: {len(ways)} из {len(data['ways'])}")

    raw = []        # (way, cls, direction, seg)
    for w in ways:
        tags = w["tags"]
        cls = classify.road_class(tags)
        for d in classify.directions(tags):
            pts = w["pts"] if d == 1 else w["pts"][::-1]
            for seg in split_polyline(pts):
                raw.append((w, cls, d, seg))
    log(f"сегментов: {len(raw)}")

    mids_lat = np.array([(s[0] + s[2]) / 2 for _, _, _, s in raw])
    mids_lon = np.array([(s[1] + s[3]) / 2 for _, _, _, s in raw])
    seg_district = np.full(len(raw), -1, int)
    dlist = list(districts.items())
    for i, (code, d) in enumerate(dlist):
        m = PolygonSet(d.boundary).contains(mids_lat, mids_lon)
        seg_district[m & (seg_district < 0)] = i

    groups: dict[tuple, list[int]] = defaultdict(list)
    for i, (w, cls, d, s) in enumerate(raw):
        nm = _norm_name(w["tags"])
        key = (cls, nm) if nm else (cls, "", int(seg_district[i]))
        groups[key].append(i)

    if replace:
        Segment.objects.all().delete()
        Road.objects.all().delete()

    lengths = {k: sum(raw[i][3][5] for i in v) for k, v in groups.items()}
    counters = Counter()
    ordered = sorted(groups, key=lambda k: (CLASS_ORDER.index(k[0]), -lengths[k]))
    to_create = []
    for key in ordered:
        cls = key[0]
        counters[cls] += 1
        n = counters[cls]
        code = f"{cls}{n:02d}" if cls == "R" else f"{cls}{n:03d}"
        idxs = groups[key]
        w0 = raw[idxs[0]][0]
        named = bool(key[1])
        di = key[2] if len(key) > 2 else Counter(int(seg_district[i]) for i in idxs).most_common(1)[0][0]
        dist = dlist[di][1] if 0 <= di < len(dlist) else None
        surfs = Counter(s for s in (classify.surface(raw[i][0]["tags"]) for i in idxs) if s != "unknown").most_common(1)
        way_ids = sorted({raw[i][0]["id"] for i in idxs})[:200]
        name_ru = key[1] if named else f"Без названия ({dist.name_ru if dist else 'вне районов'})"
        name_uz = (w0["tags"].get("name:uz") or w0["tags"].get("name") or "") if named else ""
        to_create.append((key, Road(code=code, name_ru=name_ru[:120], name_uz=name_uz[:120], road_class=cls, surface=surfs[0][0] if surfs else "unknown",
                                    osm_way_ids=way_ids, district=dist, length_m=round(lengths[key], 1), named=named, speed_limit_kmh=classify.maxspeed(w0["tags"]))))
    Road.objects.bulk_create([r for _, r in to_create], batch_size=2000)
    saved = {r.code: r for r in Road.objects.all()}
    roads = {key: saved[r.code] for key, r in to_create}

    rows = []
    idx_counter: dict[tuple[int, int], int] = defaultdict(int)
    for key in ordered:
        road = roads[key]
        for i in groups[key]:
            w, cls, d, s = raw[i]
            idx_counter[(road.pk, d)] += 1
            di = seg_district[i]
            tags = w["tags"]
            rows.append(Segment(
                road=road, index=idx_counter[(road.pk, d)], direction=d, lat_a=s[0], lon_a=s[1], lat_b=s[2], lon_b=s[3],
                heading=round(bearing(s[0], s[1], s[2], s[3]), 1), district=dlist[di][1] if di >= 0 else None,
                osm_way_id=w["id"], offset_m=round(s[4], 1), length_m=round(s[5], 1), surface=classify.surface(tags),
                bridge=tags.get("bridge") not in (None, "no"), tunnel=tags.get("tunnel") not in (None, "no"),
                tram=_near(tram_grid, mids_lat[i], mids_lon[i], 12), level_crossing=_near(lc_grid, mids_lat[i], mids_lon[i], 20)))
    Segment.objects.bulk_create(rows, batch_size=3000)
    for road_id in Segment.objects.filter(tram=True).values_list("road_id", flat=True).distinct():
        Road.objects.filter(pk=road_id).update(has_tram=True)
    for road_id in Segment.objects.filter(level_crossing=True).values_list("road_id", flat=True).distinct():
        Road.objects.filter(pk=road_id).update(has_level_crossing=True)
    from .matching import reset_index
    reset_index()
    stats = dict(roads=len(roads), segments=len(rows), classes={c: counters[c] for c in CLASS_ORDER}, districts=len(districts),
                 km=round(sum(lengths.values()) / 1000, 1), outside_districts=int((seg_district < 0).sum()))
    log(f"готово: {stats}")
    return stats
