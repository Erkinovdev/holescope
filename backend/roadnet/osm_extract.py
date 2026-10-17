"""Извлечение дорожных данных Ташкента из OSM-экстракта (Geofabrik .osm.pbf) в компактный JSON-кэш.

Берём: дороги (highway=*), трамвайные пути (railway=tram), ж/д переезды (railway=level_crossing), контур города
(relation 2216724) и районы (admin_level=6 внутри Ташкента). Границы махаллей в OSM по Ташкенту отсутствуют (см. README).
Разбор PBF занимает ~3 минуты, поэтому результат кэшируется (`data/tashkent_osm.json.gz`).
"""
from __future__ import annotations
import gzip
import json
import time
from pathlib import Path

CITY_REL = 2216724
BBOX = (41.18, 69.08, 41.44, 69.44)       # min_lat, min_lon, max_lat, max_lon — с запасом вокруг города
DISTRICT_KEYS = ("yunus", "chilon", "mirobod", "sergeli", "olmazor", "bektemir", "shayhon", "uchtepa", "yakkasaroy", "yashnobod", "mirzo", "hayot")
DRIVABLE = {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary",
            "tertiary_link", "unclassified", "residential", "living_street", "service", "track", "road"}
KEEP_TAGS = ("name", "name:ru", "name:uz", "ref", "highway", "oneway", "surface", "maxspeed", "bridge", "tunnel", "junction", "service", "access", "lanes")


def _in_bbox(lat, lon):
    return BBOX[0] <= lat <= BBOX[2] and BBOX[1] <= lon <= BBOX[3]


def extract(pbf: str | Path, out: str | Path, log=print) -> dict:
    import osmium
    t0 = time.time()
    fac = osmium.geom.GeoJSONFactory()
    fp = (osmium.FileProcessor(str(pbf)).with_locations().with_areas(osmium.filter.TagFilter(("boundary", "administrative"))))
    ways, tram, crossings, areas = [], [], [], {}
    for o in fp:
        if o.is_way():
            t = o.tags
            hw = t.get("highway")
            rw = t.get("railway")
            if hw not in DRIVABLE and rw != "tram":
                continue
            try:
                pts = [(n.lat, n.lon) for n in o.nodes if n.location.valid()]
            except Exception:
                continue
            if len(pts) < 2 or not _in_bbox(*pts[0]):
                continue
            if rw == "tram":
                tram.append(pts)
            else:
                ways.append({"id": o.id, "pts": [(round(a, 6), round(b, 6)) for a, b in pts], "tags": {k: t.get(k) for k in KEEP_TAGS if t.get(k)}})
        elif o.is_node():
            if o.tags.get("railway") == "level_crossing" and o.location.valid() and _in_bbox(o.location.lat, o.location.lon):
                crossings.append((o.location.lat, o.location.lon))
        elif o.is_area() and not o.from_way():
            t = o.tags
            lvl = t.get("admin_level")
            nm = (t.get("name") or "").lower().replace(" ", "")
            if o.orig_id() == CITY_REL or (lvl == "6" and any(k in nm for k in DISTRICT_KEYS)):
                g = json.loads(fac.create_multipolygon(o))
                areas[o.orig_id()] = {"id": o.orig_id(), "name": t.get("name"), "name_ru": t.get("name:ru"), "name_uz": t.get("name:uz"), "admin_level": lvl, "geometry": g}
    data = {"source": str(pbf), "extracted": time.strftime("%Y-%m-%d"), "ways": ways, "tram": tram, "crossings": crossings, "areas": list(areas.values())}
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(out, "wt", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    log(f"OSM: дорог {len(ways)}, трамвай {len(tram)}, переездов {len(crossings)}, областей {len(areas)}, {time.time() - t0:.0f} с")
    return data


def load_cache(path) -> dict:
    with gzip.open(path, "rt", encoding="utf-8") as f:
        return json.load(f)
