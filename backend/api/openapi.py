"""OpenAPI 3.0 для публичного API v1. Описание ведётся вручную (views — простые JSON-вью, без DRF) и проверяется тестом
tests/test_api_docs.py: каждый маршрут из api/urls.py обязан быть описан."""
from __future__ import annotations
from django.http import HttpResponse, JsonResponse

Q = lambda name, desc, required=False, typ="string", **kw: dict(name=name, **{"in": "query"}, required=required, description=desc, schema=dict(type=typ, **kw))
P = lambda name, desc: dict(name=name, **{"in": "path"}, required=True, description=desc, schema=dict(type="integer"))
OBJ = {"type": "object", "additionalProperties": True}

# (path, method, tag, summary, auth, parameters, request_body_desc)
OPS = [
    ("/devices/register", "post", "devices", "Анонимная регистрация устройства: токен и ник", None, [], "platform, phone_model, app_version, lang, role"),
    ("/me/vehicle", "get", "devices", "Профиль машины и положение телефона", "device", [], None),
    ("/me/vehicle", "patch", "devices", "Изменить профиль машины (колёсная база, шины, давление, положение телефона)", "device", [], "name, year, rim_inch, tire_pressure_bar, wheelbase_mm, suspension_note, car_model_id, mount"),
    ("/me/stats", "get", "devices", "Статистика профиля: найдено / подтверждено / км", "device", [], None),
    ("/trips", "post", "trips", "Результат поездки: события, сегменты ровности, подвеска (идемпотентно по client_id)", "device", [], "started_at, duration_s, distance_km, events[], segments[], client_id, mode"),
    ("/trips/raw", "post", "trips", "Сырой CSV (исследовательские устройства), multipart file", "device", [], "file"),
    ("/questions/next", "get", "brain", "До 5 вопросов «что это было?» после поездки", "device", [], None),
    ("/questions/{qid}/answer", "post", "brain", "Ответ водителя → разметка", "device", [P("qid", "id вопроса")], "answer"),
    ("/map/clusters", "get", "map", "Ямы в прямоугольнике", None, [Q("bbox", "min_lat,min_lon,max_lat,max_lon", True), Q("status", "через запятую", False)], None),
    ("/map/segments", "get", "map", "Векторная карта: сегменты дорог с классом ровности A–E", None, [Q("bbox", "min_lat,min_lon,max_lat,max_lon (≤0.1°)", True), Q("scored", "1 — только оценённые", False), Q("limit", "до 8000", False, "integer")], None),
    ("/search", "get", "map", "Поиск улицы или района по названию", None, [Q("q", "название, ≥2 символа", True)], None),
    ("/clusters/{cid}", "get", "map", "Карточка ямы: улица, район, статус, подтверждения", None, [P("cid", "id ямы")], None),
    ("/clusters/{cid}/report", "post", "map", "Отметка «яма на месте» / «заделана»", "device", [P("cid", "id ямы")], "state: present | fixed"),
    ("/drive/ahead", "get", "map", "Ямы впереди по ходу движения (режим Drive)", None, [Q("lat", "широта", True, "number"), Q("lon", "долгота", True, "number"), Q("heading", "курс 0..360", True, "number"), Q("dist", "дальность, м (≤600)", False, "integer")], None),
    ("/rankings/streets", "get", "rankings", "Худшие улицы: ям на покрытый км", None, [Q("scope", "city | district"), Q("district", "код района (UZ-TSH-YUN)"), Q("days", "период, дней", False, "integer"), Q("limit", "до 100", False, "integer")], None),
    ("/rankings/districts", "get", "rankings", "Качество дорог по районам 0–100", None, [Q("days", "период, дней", False, "integer")], None),
    ("/reports/weekly", "get", "rankings", "Отчёт недели: найдено / заделано / жалоб", None, [Q("days", "период, дней", False, "integer")], None),
    ("/dictionaries", "get", "dictionaries", "Справочники: типы, уровни, классы, покрытия, статусы", None, [], None),
    ("/car-models", "get", "dictionaries", "Справочник моделей авто (только подтверждённые характеристики)", None, [], None),
    ("/complaints", "post", "complaints", "Подготовить черновик жалобы по яме", "device", [], "cluster_id, channel, anonymous"),
    ("/complaints/{cid}", "get", "complaints", "Цепочка «нашли → подали → рассмотрение → исправили»", "device", [P("cid", "id жалобы")], None),
    ("/complaints/{cid}/send", "post", "complaints", "Отправить жалобу (статус filed)", "device", [P("cid", "id жалобы")], None),
    ("/admin/brain/summary", "get", "admin", "Сводка «Мозга»", "staff", [], None),
    ("/admin/brain/upload-csv", "post", "admin", "Загрузка CSV поездки на разбор", "staff", [], "file, wheelbase_m"),
]


def build_spec() -> dict:
    paths: dict = {}
    for path, method, tag, summary, auth, params, body in OPS:
        op = dict(tags=[tag], summary=summary, parameters=params, responses={"200": {"description": "OK", "content": {"application/json": {"schema": OBJ}}}})
        if auth == "device":
            op["security"] = [{"DeviceToken": []}]
            op["responses"]["401"] = {"description": "нет или неверный X-Device-Token"}
        elif auth == "staff":
            op["security"] = [{"SessionAuth": []}]
            op["responses"]["403"] = {"description": "нужен вход сотрудника"}
        if body:
            op["requestBody"] = {"description": body, "content": {"application/json": {"schema": OBJ}}}
        paths.setdefault(path, {})[method] = op
    return {
        "openapi": "3.0.3",
        "info": {"title": "Holescope API", "version": "1.0.0", "description": "API v1: приём поездок, карта ям, режим Drive, рейтинги. Данные обезличены: токен устройства без почты и номера."},
        "servers": [{"url": "/api/v1"}],
        "components": {"securitySchemes": {"DeviceToken": {"type": "apiKey", "in": "header", "name": "X-Device-Token"}, "SessionAuth": {"type": "apiKey", "in": "cookie", "name": "sessionid"}}},
        "paths": paths,
    }


def openapi_json(request):
    return JsonResponse(build_spec(), json_dumps_params={"ensure_ascii": False})


def docs(request):
    # Swagger UI с фиксированной версией (cdn.jsdelivr.net)
    html = """<!doctype html><html><head><meta charset="utf-8"><title>Holescope API</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui.css"></head>
<body><div id="ui"></div><script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
<script>SwaggerUIBundle({url:'/api/v1/openapi.json',dom_id:'#ui'})</script></body></html>"""
    return HttpResponse(html)
