import re
from api.openapi import build_spec
from api.urls import urlpatterns


def _norm(route: str) -> str:
    return "/" + re.sub(r"<int:(\w+)>", r"{\1}", route)


def test_every_route_is_documented():
    spec = build_spec()["paths"]
    for p in urlpatterns:
        route = _norm(str(p.pattern))
        if route in ("/openapi.json", "/docs"):
            continue
        assert route in spec, f"маршрут {route} не описан в api/openapi.py"
    for route in spec:
        assert any(_norm(str(p.pattern)) == route for p in urlpatterns), f"описан несуществующий маршрут {route}"


def test_openapi_served(client, db):
    j = client.get("/api/v1/openapi.json").json()
    assert j["openapi"].startswith("3.0") and "/trips" in j["paths"] and "post" in j["paths"]["/trips"]
    assert client.get("/api/v1/docs").status_code == 200
