"""Классы дорог (R/A/B/C/D/S) и покрытие из тегов OSM. Правила эвристические — проверяются и правятся в админке (раздел «Дороги»)."""
from __future__ import annotations
import re

RING_NAME = re.compile(r"(halqa|ҳалқа|халка|кольцев|ring|bkad|бкад)", re.I)


def road_class(tags: dict) -> str:
    hw = (tags.get("highway") or "").replace("_link", "")
    name = " ".join(filter(None, [tags.get("name"), tags.get("name:ru"), tags.get("name:uz"), tags.get("ref")]))
    if hw == "motorway":
        return "R"
    if hw in ("trunk", "primary") and RING_NAME.search(name):
        return "R"
    if hw in ("trunk", "primary"):
        return "A"
    if hw in ("secondary", "tertiary"):
        return "B"
    if hw in ("residential", "unclassified", "road"):
        return "C"
    if hw in ("living_street", "service"):
        return "D"
    if hw == "track":
        return "S"
    return "C"


SURFACE = {
    "asphalt": "asphalt", "paved": "asphalt", "concrete": "concrete", "concrete:plates": "concrete", "concrete:lanes": "concrete",
    "paving_stones": "paving", "sett": "paving", "cobblestone": "paving", "unhewn_cobblestone": "paving",
    "gravel": "gravel", "fine_gravel": "gravel", "compacted": "gravel", "pebblestone": "gravel",
    "ground": "dirt", "dirt": "dirt", "unpaved": "dirt", "mud": "dirt", "sand": "dirt", "earth": "dirt",
}


def surface(tags: dict) -> str:
    return SURFACE.get((tags.get("surface") or "").lower(), "unknown")


def directions(tags: dict) -> list[int]:
    """[+1] только вдоль, [-1] только против, [+1, -1] двустороннее."""
    ow = (tags.get("oneway") or "").lower()
    if ow in ("yes", "true", "1") or tags.get("junction") in ("roundabout", "circular") or (tags.get("highway") == "motorway" and ow != "no"):
        return [1]
    if ow == "-1":
        return [-1]
    return [1, -1]


def maxspeed(tags: dict):
    v = (tags.get("maxspeed") or "").split()[0] if tags.get("maxspeed") else ""
    return int(v) if v.isdigit() else None
