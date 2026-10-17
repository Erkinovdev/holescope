"""Этап 3: дорожный граф — нарезка, классы, районы, привязка (на синтетической сети, без OSM-файла)."""
import math
import pytest
from roadnet import classify
from roadnet.builder import build_network
from roadnet.geo import PolygonSet, split_polyline, dist_m, bearing, ang_diff, K
from roadnet.matching import SegmentIndex, reset_index
from roadnet.models import District, Road, Segment

LAT0, LON0 = 41.30, 69.25


def dlon(m, lat=LAT0):
    return m / (K * math.cos(math.radians(lat)))


def square(lat_a, lon_a, lat_b, lon_b):
    return {"type": "MultiPolygon", "coordinates": [[[[lon_a, lat_a], [lon_b, lat_a], [lon_b, lat_b], [lon_a, lat_b], [lon_a, lat_a]]]]}


def way(wid, pts, **tags):
    return {"id": wid, "pts": pts, "tags": tags}


def test_split_polyline_lengths():
    pts = [(LAT0, LON0), (LAT0, LON0 + dlon(260))]
    segs = split_polyline(pts)
    assert len(segs) == 5                      # 260 м → 5 × 50 + хвост 10 м присоединён
    assert sum(s[5] for s in segs) == pytest.approx(260, abs=1)
    assert segs[0][4] == 0 and segs[1][4] == pytest.approx(50, abs=0.1)
    assert dist_m(segs[0][0], segs[0][1], segs[0][2], segs[0][3]) == pytest.approx(50, abs=0.5)
    # хвост ≥ 15 м даёт отдельный сегмент
    assert len(split_polyline([(LAT0, LON0), (LAT0, LON0 + dlon(120))])) == 3
    assert split_polyline([(LAT0, LON0), (LAT0, LON0)]) == []


def test_split_polyline_follows_bends():
    pts = [(LAT0, LON0), (LAT0, LON0 + dlon(60)), (LAT0 + 60 / K, LON0 + dlon(60))]
    segs = split_polyline(pts)
    assert sum(s[5] for s in segs) == pytest.approx(120, abs=1)
    assert segs[1][3] > segs[0][3] or segs[1][2] > LAT0     # второй сегмент уже поворачивает на север


def test_polygon_contains_with_hole():
    g = {"type": "MultiPolygon", "coordinates": [[[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]], [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]]]]}
    ps = PolygonSet(g)
    assert list(ps.contains([5, 2, 20], [5, 2, 5])) == [False, True, False]     # (lat, lon): дырка, внутри, снаружи


def test_bearing_and_angdiff():
    assert bearing(LAT0, LON0, LAT0 + 0.001, LON0) == pytest.approx(0, abs=0.5)
    assert bearing(LAT0, LON0, LAT0, LON0 + 0.001) == pytest.approx(90, abs=0.5)
    assert ang_diff(350, 10) == 20


def test_road_class_rules():
    assert classify.road_class({"highway": "motorway"}) == "R"
    assert classify.road_class({"highway": "trunk", "name": "Кичик халка йули"}) == "R"
    assert classify.road_class({"highway": "trunk_link", "name": "Улица"}) == "A"
    assert classify.road_class({"highway": "primary"}) == "A"
    assert classify.road_class({"highway": "tertiary"}) == "B"
    assert classify.road_class({"highway": "residential"}) == "C"
    assert classify.road_class({"highway": "service"}) == "D"
    assert classify.road_class({"highway": "track"}) == "S"
    assert classify.surface({"surface": "concrete:plates"}) == "concrete"
    assert classify.surface({"surface": "weird"}) == "unknown"
    assert classify.directions({"oneway": "yes"}) == [1]
    assert classify.directions({"oneway": "-1"}) == [-1]
    assert classify.directions({"junction": "roundabout"}) == [1]
    assert classify.directions({}) == [1, -1]


def _data():
    city = square(41.29, 69.24, 41.31, 69.27)
    dist_a = square(41.29, 69.24, 41.31, 69.255)
    ways = [
        way(1, [(LAT0, 69.245), (LAT0, 69.245 + dlon(300))], highway="primary", name="Улица Тест", **{"name:ru": "Улица Тест"}),
        way(2, [(LAT0 + 0.002, 69.245), (LAT0 + 0.002, 69.245 + dlon(100))], highway="residential", name="Малая", oneway="yes", surface="asphalt"),
        way(3, [(LAT0 + 0.004, 69.245), (LAT0 + 0.004, 69.245 + dlon(100))], highway="service"),          # без названия
        way(4, [(LAT0, 69.30), (LAT0, 69.301)], highway="primary", name="Вне города"),                      # вне контура
    ]
    return dict(areas=[
        {"id": 1, "name": "Toshkent", "name_ru": "Ташкент", "name_uz": "Toshkent", "admin_level": "4", "geometry": city},
        {"id": 2, "name": "Yunusobod Tumani", "name_ru": "Юнусабадский район", "name_uz": None, "admin_level": "6", "geometry": dist_a},
    ], ways=ways, tram=[[(LAT0 + 0.00005, 69.2452), (LAT0 + 0.00005, 69.2456)]], crossings=[(LAT0 + 0.002, 69.245 + dlon(90))])


@pytest.mark.django_db
def test_build_network_synthetic():
    stats = build_network(_data(), log=lambda *_: None)
    assert stats["roads"] == 3 and stats["districts"] == 1
    assert Road.objects.filter(name_ru="Вне города").count() == 0
    a = Road.objects.get(name_ru="Улица Тест")
    assert a.road_class == "A" and a.code == "A001"
    segs = Segment.objects.filter(road=a)
    assert segs.filter(direction=1).count() == 6 and segs.filter(direction=-1).count() == 6     # двустороннее
    # уникальные индексы внутри направления и коды
    s1 = segs.get(direction=1, index=1)
    assert s1.code == "A001-0001" and segs.get(direction=-1, index=1).code == "A001-0001r"
    assert s1.district.code == "UZ-TSH-YUN" and s1.heading == pytest.approx(90, abs=1)
    assert segs.get(direction=-1, index=1).heading == pytest.approx(270, abs=1)
    assert s1.tram is True                                           # рядом трамвайные пути
    b = Road.objects.get(name_ru="Малая")
    assert b.road_class == "C" and b.surface == "asphalt"
    assert Segment.objects.filter(road=b).count() == 2               # односторонняя, 100 м = 2 сегмента
    assert b.has_level_crossing is True
    d = Road.objects.get(road_class="D")
    assert d.named is False and "Без названия" in d.name_ru
    # идемпотентность
    stats2 = build_network(_data(), log=lambda *_: None)
    assert stats2["segments"] == stats["segments"] and Segment.objects.count() == stats["segments"]
    assert District.objects.filter(level="district").count() == 1


@pytest.mark.django_db
def test_segment_index_snap_with_direction():
    build_network(_data(), log=lambda *_: None)
    reset_index()
    from roadnet.matching import get_index
    idx = get_index()
    lon = 69.245 + dlon(120)
    east = idx.snap(LAT0 + 3 / K, lon, heading=90)
    west = idx.snap(LAT0 + 3 / K, lon, heading=270)
    assert east and west and east.segment_id != west.segment_id
    assert Segment.objects.get(pk=east.segment_id).direction == 1
    assert Segment.objects.get(pk=west.segment_id).direction == -1
    assert east.distance_m == pytest.approx(3, abs=0.5)
    # слишком далеко / поперёк
    assert idx.snap(LAT0 + 100 / K, lon, heading=90) is None
    assert idx.snap(LAT0, lon, heading=0, max_m=30) is None or idx.snap(LAT0, lon, heading=0) .heading_diff <= 50


def test_snap_pure_index_nearest_without_heading():
    idx = SegmentIndex([(1, LAT0, LON0, LAT0, LON0 + dlon(50), 90.0), (2, LAT0 + 20 / K, LON0, LAT0 + 20 / K, LON0 + dlon(50), 90.0)])
    m = idx.snap(LAT0 + 4 / K, LON0 + dlon(25))
    assert m.segment_id == 1 and m.frac == pytest.approx(0.5, abs=0.02)
    assert idx.snap(LAT0 + 4 / K, LON0 + dlon(25), heading=0) is None
    assert idx.snap(LAT0 + 15 / K, LON0 + dlon(25)).segment_id == 2
