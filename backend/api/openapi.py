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
    ("/voice/transcribe", "post", "brain", "Распознавание голосовой команды на сервере: WAV → текст (не сохраняется)", "device", [], "file (wav 16 кГц mono), lang (ru|uz)"),
    ("/marks", "post", "brain", "Голосовые/ручные отметки водителя (яма, люк, лежачий, не яма): привязка к событиям, разметка", "device", [], "marks[]: client_id, kind, lat, lon, heading, at"),
    ("/taxonomy", "get", "dictionaries", "Варианты «что это было?» с группами и названиями ru/uz, оценки ровности дороги", None, [], None),
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
    ("/algo/params", "get", "brain", "Параметры активной версии правил (приложение применяет на устройстве)", None, [], None),
]

# Админка: (путь, метод, описание, минимальная роль, тело)
ADMIN = [
    ("/admin/login", "post", "Вход сотрудника → токен (12 ч)", None, "username, password"),
    ("/admin/me", "get", "Текущий сотрудник и роль", "analyst", None),
    ("/admin/overview", "get", "Обзор: KPI, активность по дням, очереди", "analyst", None),
    ("/admin/clusters", "get", "Ямы: список с фильтрами и пагинацией", "analyst", None),
    ("/admin/clusters/merge", "post", "Объединить дубли ям", "labeler", "ids[], into"),
    ("/admin/clusters/create", "post", "Добавить яму вручную", "labeler", "lat, lon, type, level"),
    ("/admin/clusters/{cid}", "get", "Яма: события, волны, голоса, тихие проезды", "analyst", None),
    ("/admin/clusters/{cid}/patch", "patch", "Модерация: статус, тип, уровень, безопасная скорость", "labeler", "status, type, level, safe_speed"),
    ("/admin/roads", "get", "Реестр дорог", "analyst", None),
    ("/admin/roads/{rid}", "get", "Дорога: классы ровности, сегменты", "analyst", None),
    ("/admin/roads/{rid}/patch", "patch", "Править класс, покрытие, названия", "admin", "road_class, surface, name_ru, name_uz, speed_limit_kmh"),
    ("/admin/devices", "get", "Устройства", "analyst", None),
    ("/admin/devices/{did}", "get", "Карточка устройства", "analyst", None),
    ("/admin/devices/{did}/patch", "patch", "Роль, блокировка, доверие, положение, калибровка", "admin", "role, blocked, trust, mount, reset_calibration"),
    ("/admin/vehicles/{vid}/patch", "patch", "Профиль машины и подвески", "admin", "name, car_model_id, year, wheelbase_mm, rim_inch, tire_pressure_bar, suspension_note, suspension_cls"),
    ("/admin/trips", "get", "Поездки", "analyst", None),
    ("/admin/trips/{tid}", "get", "Поездка: события с волнами, сегменты", "analyst", None),
    ("/admin/car-models", "get", "Справочник моделей авто", "analyst", None),
    ("/admin/car-models/create", "post", "Добавить модель авто", "admin", "brand, model, wheelbase_mm, specs_verified, source_url"),
    ("/admin/car-models/{cid}/patch", "patch", "Править модель авто", "admin", "..."),
    ("/admin/complaints", "get", "Жалобы", "analyst", None),
    ("/admin/complaints/{cid}/patch", "patch", "Статус, номер обращения, срок ответа", "labeler", "status, external_number, due_at, text"),
    ("/admin/users", "get", "Сотрудники", "admin", None),
    ("/admin/users/create", "post", "Создать сотрудника", "admin", "username, password, role"),
    ("/admin/users/{uid}/patch", "patch", "Роль и активность сотрудника", "admin", "role, is_active"),
    ("/admin/users/{uid}/password", "post", "Сменить пароль сотрудника", "admin", "password"),
    ("/admin/audit", "get", "Журнал действий", "admin", None),
    ("/admin/brain/summary", "get", "Сводка «Мозга»", "analyst", None),
    ("/admin/brain/calibration", "get", "Границы уровней ям и классов ровности: текущие, предложенные по разметке, точность", "analyst", None),
    ("/admin/brain/calibration/apply", "post", "Применить границы {kind: levels|ri, bounds}", "admin", "kind, bounds"),
    ("/admin/brain/readiness", "get", "Готовность модели простыми словами и следующие шаги", "analyst", None),
    ("/admin/brain/timeline", "get", "Версии, метрики, снимки роста", "analyst", None),
    ("/admin/brain/graph", "get", "Граф для 3D-визуализации", "analyst", None),
    ("/admin/brain/questions", "get", "Очередь вопросов и разметки", "analyst", None),
    ("/admin/brain/label", "post", "Разметить событие", "labeler", "event_id, label"),
    ("/admin/brain/params", "get", "Параметры активной версии правил", "analyst", None),
    ("/admin/brain/params/save", "put", "Сохранить параметры как новую версию правил", "admin", "params, activate, notes"),
    ("/admin/brain/activate", "post", "Включить версию", "admin", "version_id, force"),
    ("/admin/brain/deactivate", "post", "Выключить версию", "admin", "version_id"),
    ("/admin/brain/train", "post", "Обучить на накопленной разметке", "admin", None),
    ("/admin/brain/uploads", "get", "Загруженные CSV", "analyst", None),
    ("/admin/brain/uploads/{rid}/review", "get", "Сигнал, события и путь записи", "analyst", None),
    ("/admin/brain/preview", "post", "Предпросмотр параметров на записи", "analyst", "raw_id, params"),
    ("/admin/brain/upload-csv", "post", "Загрузить CSV поездки на разбор (multipart)", "labeler", "file, wheelbase_m"),
]


def build_spec() -> dict:
    paths: dict = {}
    import re
    for path, method, summary, role, bod in ADMIN:
        params = [P(n, n) for n in re.findall(r"\{(\w+)\}", path)]
        op = dict(tags=["admin"], summary=summary, parameters=params, responses={"200": {"description": "OK", "content": {"application/json": {"schema": OBJ}}}})
        if role:
            op["security"] = [{"AdminToken": []}]
            op["description"] = f"Роль не ниже: {role}"
            op["responses"]["401"] = {"description": "нет токена"}
            op["responses"]["403"] = {"description": "роль ниже требуемой"}
        if bod:
            op["requestBody"] = {"description": bod, "content": {"application/json": {"schema": OBJ}}}
        paths.setdefault(path, {})[method] = op
    for path, method, tag, summary, auth, params, body in OPS:
        op = dict(tags=[tag], summary=summary, parameters=params, responses={"200": {"description": "OK", "content": {"application/json": {"schema": OBJ}}}})
        if auth == "device":
            op["security"] = [{"DeviceToken": []}]
            op["responses"]["401"] = {"description": "нет или неверный X-Device-Token"}
        if body:
            op["requestBody"] = {"description": body, "content": {"application/json": {"schema": OBJ}}}
        paths.setdefault(path, {})[method] = op
    return {
        "openapi": "3.0.3",
        "info": {"title": "Holescope API", "version": "1.0.0", "description": "API v1: приём поездок, карта ям, режим Drive, рейтинги. Данные обезличены: токен устройства без почты и номера."},
        "servers": [{"url": "/api/v1"}],
        "components": {"securitySchemes": {"DeviceToken": {"type": "apiKey", "in": "header", "name": "X-Device-Token"}, "AdminToken": {"type": "http", "scheme": "bearer"}}},
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
