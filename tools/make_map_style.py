"""Генерирует site/map/style-dark.json и style-light.json (стиль карты Holescope под схему OpenMapTiles)."""
import json, pathlib

BASE = "https://holescop.duckdns.org/map"
OUT = pathlib.Path(__file__).resolve().parent.parent / "site" / "map"

PAL = {
    "dark": dict(bg="#0b0d12", land="#10131a", block="#151922", water="#0f2236", park="#0f2a1e", wood="#0e2519",
                 bldg="#1c2230", bldg_edge="#2a3245", road_minor="#2d3548", road_main="#3b465d", road_major="#48546e",
                 casing="#0b0d12", label="#8f99ab", label_hi="#c9d0dd", halo="#0b0d12", rail="#2a3040"),
    "light": dict(bg="#eef1f6", land="#f4f6fa", block="#e8ecf3", water="#cfe3f5", park="#d5ecd9", wood="#c8e5cf",
                  bldg="#e1e6ef", bldg_edge="#d3d9e4", road_minor="#ffffff", road_main="#ffffff", road_major="#fff4d6",
                  casing="#d3d9e4", label="#5b6577", label_hi="#12151c", halo="#ffffff", rail="#c4cad6"),
}


def build(theme):
    p = PAL[theme]
    W = lambda a, b: {"stops": [[a[0], a[1]], [b[0], b[1]]]}
    ls = []
    add = ls.append
    add({"id": "bg", "type": "background", "paint": {"background-color": p["land"]}})
    add({"id": "landuse", "type": "fill", "source": "omt", "source-layer": "landuse",
         "filter": ["in", "class", "residential", "commercial", "industrial", "retail", "neighbourhood"],
         "paint": {"fill-color": p["block"], "fill-opacity": 0.7}})
    add({"id": "wood", "type": "fill", "source": "omt", "source-layer": "landcover",
         "filter": ["in", "class", "wood", "grass"], "paint": {"fill-color": p["wood"], "fill-opacity": 0.8}})
    add({"id": "park", "type": "fill", "source": "omt", "source-layer": "park", "paint": {"fill-color": p["park"]}})
    add({"id": "water", "type": "fill", "source": "omt", "source-layer": "water", "paint": {"fill-color": p["water"]}})
    add({"id": "waterway", "type": "line", "source": "omt", "source-layer": "waterway",
         "paint": {"line-color": p["water"], "line-width": {"stops": [[10, 0.6], [16, 3]]}}})
    add({"id": "building", "type": "fill", "source": "omt", "source-layer": "building", "minzoom": 14.5,
         "paint": {"fill-color": p["bldg"], "fill-outline-color": p["bldg_edge"],
                   "fill-opacity": {"stops": [[14.5, 0], [16, 1]]}}})
    minor = ["in", "class", "minor", "service", "track", "path", "pedestrian"]
    add({"id": "road-minor", "type": "line", "source": "omt", "source-layer": "transportation", "minzoom": 12,
         "filter": minor, "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": p["road_minor"], "line-width": {"base": 1.4, "stops": [[12, 0.4], [16, 3], [19, 12]]}}})
    add({"id": "road-main", "type": "line", "source": "omt", "source-layer": "transportation", "minzoom": 10,
         "filter": ["in", "class", "tertiary", "secondary"], "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": p["road_main"], "line-width": {"base": 1.4, "stops": [[10, 0.6], [14, 2.5], [16, 6], [19, 20]]}}})
    add({"id": "road-major", "type": "line", "source": "omt", "source-layer": "transportation", "minzoom": 6,
         "filter": ["in", "class", "primary", "trunk", "motorway"], "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": p["road_major"], "line-width": {"base": 1.4, "stops": [[6, 0.6], [12, 2.5], [16, 8], [19, 26]]}}})
    add({"id": "rail", "type": "line", "source": "omt", "source-layer": "transportation", "minzoom": 12,
         "filter": ["==", "class", "rail"], "paint": {"line-color": p["rail"], "line-width": 1, "line-dasharray": [3, 3]}})
    add({"id": "road-name", "type": "symbol", "source": "omt", "source-layer": "transportation_name", "minzoom": 14,
         "layout": {"symbol-placement": "line", "text-field": ["coalesce", ["get", "name:ru"], ["get", "name"]],
                    "text-font": ["Noto Sans Regular"], "text-size": {"stops": [[14, 10], [18, 13]]},
                    "text-letter-spacing": 0.02},
         "paint": {"text-color": p["label"], "text-halo-color": p["halo"], "text-halo-width": 1.5}})
    add({"id": "water-name", "type": "symbol", "source": "omt", "source-layer": "water_name",
         "layout": {"text-field": ["coalesce", ["get", "name:ru"], ["get", "name"]], "text-font": ["Noto Sans Regular"], "text-size": 12, "text-letter-spacing": 0.1},
         "paint": {"text-color": "#3f6a96" if theme == "dark" else "#5d8db8", "text-halo-color": p["halo"], "text-halo-width": 1}})
    add({"id": "place-district", "type": "symbol", "source": "omt", "source-layer": "place", "minzoom": 11,
         "filter": ["in", "class", "suburb", "neighbourhood", "quarter"],
         "layout": {"text-field": ["coalesce", ["get", "name:ru"], ["get", "name"]], "text-font": ["Noto Sans Regular"],
                    "text-size": {"stops": [[11, 10], [16, 13]]}, "text-transform": "uppercase", "text-letter-spacing": 0.12, "text-max-width": 7},
         "paint": {"text-color": p["label"], "text-halo-color": p["halo"], "text-halo-width": 1.5}})
    add({"id": "place-city", "type": "symbol", "source": "omt", "source-layer": "place",
         "filter": ["in", "class", "city", "town"],
         "layout": {"text-field": ["coalesce", ["get", "name:ru"], ["get", "name"]], "text-font": ["Noto Sans Medium"],
                    "text-size": {"stops": [[6, 12], [12, 18]]}},
         "paint": {"text-color": p["label_hi"], "text-halo-color": p["halo"], "text-halo-width": 1.8}})
    return {
        "version": 8, "name": "Holescope " + theme,
        "glyphs": BASE + "/fonts/{fontstack}/{range}.pbf",
        "sources": {"omt": {"type": "vector", "tiles": [BASE + "/t/{z}/{x}/{y}.pbf"], "minzoom": 0, "maxzoom": 14,
                            "bounds": [69.05, 41.15, 69.50, 41.45]}},
        "layers": ls,
    }


for t in PAL:
    (OUT / f"style-{t}.json").write_text(json.dumps(build(t), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("ok", t)
