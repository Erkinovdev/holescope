# Holescope backend (Django)

Стек: Django 5, PostgreSQL (PostGIS на этапе пилота), SQLite для разработки. Алгоритм — отдельный пакет `holescope_algo`
(чистый Python + numpy/pandas), его же можно запускать без Django.

## Запуск (разработка, SQLite)
```
python -m venv .venv && .venv\Scriptsctivate
pip install -r requirements.txt pytest pytest-django
python manage.py migrate            # миграции уже в репозитории
python manage.py createsuperuser    # пароль задаёте вы
python manage.py load_cars
python manage.py process_csv ../analysis/pothole_2026-10-17_12-09-50.csv --wheelbase 2.485
python manage.py runserver
pytest
```
Windows: если pip падает на кириллице, задайте `set PYTHONUTF8=1`.

## Запуск в Docker (Postgres/PostGIS + gunicorn)
```
copy .env.example .env   # заполните DJANGO_SECRET_KEY и PG_PASSWORD
docker compose up --build
```
**Статус (этап 0):** миграции созданы и применяются, `pytest` зелёный (17 тестов), `process_csv` на записи 17.10 пишет поездку,
события, кластеры и сегменты в БД, админка и API отвечают. Docker-файлы написаны, но **не запускались** (проверяйте на своей машине).

**Известные ограничения.** `process_csv` на записи 16.10 (20 МБ) упирается в память в средах с лимитом ~150 МБ на процесс; на обычной машине
это не воспроизводится. События типов `noise`/`touch` в БД не сохраняются (это отброс алгоритма, не дорога).

## План миграции на PostGIS (когда понадобится)
Сейчас координаты хранятся как `lat/lon` с индексами. Переход: (1) включить `django.contrib.gis`, образ БД уже `postgis/postgis`;
(2) добавить `PointField(srid=4326)` рядом с lat/lon у `EventCluster`, `RoadEvent`, `SegmentScore`, `LineStringField` у `Segment`;
(3) data-миграция `Point(lon, lat)` из существующих колонок; (4) заменить bbox-фильтры на `ST_DWithin`/`ST_ClusterDBSCAN`;
(5) убрать старые колонки после проверки. Начинать, когда появится map matching (этап 3).

## Этап 3: дорожный граф и «мозг»

**Дорожная сеть Ташкента** (OSM, экстракт Geofabrik `uzbekistan-latest.osm.pbf`, 125 МБ → `backend/data/`, не коммитится):
```
python manage.py import_osm            # первый раз: разбор PBF ≈4.5 мин, затем кэш data/tashkent_osm.json.gz; сборка сети ≈10 мин на Postgres
python manage.py import_osm --refresh  # заново разобрать PBF
python manage.py rematch               # привязать уже имеющиеся кластеры и сегменты ровности к сети
```
Результат на 2026-10-17: 4 804 дороги (R 5, A 179, B 523, C 445, D 3 640, S 12), 311 765 сегментов по ≈50 м (по направлениям), 12 районов.
ID сегмента: `R01-0412` (встречное направление — суффикс `r`). Классы R/A/B/C/D/S — эвристика по `highway` и названию (`roadnet/classify.py`),
правится в админке. **Покрытие (`surface`) в OSM по Ташкенту указано лишь у ≈8 % сегментов — остальное `unknown`.** Трамвайных путей в OSM
почти нет (3 сегмента рядом с путями), переездов найдено 424. **Махалли: границ в OSM-экстракте нет** (admin_level=10 в Узбекистане — не махалли),
TODO: найти официальный набор границ MFY и импортировать в `District(level="mahalla")`. 17 тыс. сегментов лежат внутри контура города, но вне 12 районов — граничные зоны, район не назначен.

**Привязка к дороге:** собственный матчинг (`roadnet/matching.py`): ближайший отрезок ≤30 м с учётом курса (±50°), встречные полосы — разные сегменты.
На реальной записи 17.10 привязалось 17 из 27 ям и 2 028 сегментов ровности. Valhalla/Meili — запасной вариант для плотных кварталов, сейчас не подключён.

**Приём поездки** (`brain/services.py`): проверка правдоподобия (`brain/validation.py`: лимиты, регион, скорость, плотность событий, не более 60 поездок в сутки),
идемпотентность по `client_id`, не-авто режимы не попадают в карту, калибровка силы удара устройства по ориентирам, подтверждают только устройства с доверием ≥ 0.3,
серверная модель (если включена) может отбросить событие.
**«Заделана»:** проезд ≥20 км/ч мимо ямы без удара = тихий проезд; яма `fixed`, когда после последнего удара прошло ≥24 ч, ≥3 тихих проездов, ≥2 разных устройств,
и их не меньше числа ударов. Новый удар по `fixed`-яме её открывает снова.
**Подвеска:** относительный индекс = −медиана ln(RI машины / медиана RI всех машин) по сегментам с ≥3 машинами (≥40 сегментов), пересчёт каждые 25 км.
**Обучение:** `train_brain` — классификатор «дорога/не дорога», проверка «обучились на одних поездках, тест на другой»; версия включается, только если
F1 выше правил на ≥0.02 при ≥2 поездках по ≥20 меток. `import_labels` — импорт `analysis/labels_*.json` и ручных отметок из CSV.
**Ночные задачи:** `nightly` (сервис `worker` в docker-compose): заделанные, калибровка, подвеска, обучение, снимок, награды.
**Каркас без данных:** автоопределение модели (`fleet/fingerprint.py`, включится при ≥30 машинах с известной моделью), награды «самая мягкая машина» (≥10 машин и ≥500 км на модель).

**Документация API:** `/api/v1/openapi.json`, Swagger UI — `/api/v1/docs`.

## API v1 (заголовок `X-Device-Token`)
| Метод | Путь | Что |
|---|---|---|
| POST | `/api/v1/devices/register` | анонимная регистрация → токен, ник |
| GET/PATCH | `/api/v1/me/vehicle` | профиль машины, положение телефона |
| POST | `/api/v1/trips` | результат поездки: события, сегменты, подвеска |
| POST | `/api/v1/trips/raw` | сырой CSV (исследовательские устройства) |
| GET | `/api/v1/questions/next` | вопросы «что это было?» |
| POST | `/api/v1/questions/<id>/answer` | ответ водителя → разметка |
| GET | `/api/v1/map/clusters?bbox=` | ямы на карте |
| GET | `/api/v1/drive/ahead?lat&lon&heading&dist` | предупреждения впереди |
| GET | `/api/v1/rankings/streets`, `/rankings/districts`, `/reports/weekly` | рейтинги и отчёт недели |
| POST/GET | `/api/v1/complaints`, `/complaints/<id>`, `/complaints/<id>/send` | жалобы |
| GET | `/api/v1/me/stats`, `/dictionaries`, `/car-models` | профиль, справочники |
| GET | `/api/v1/admin/brain/summary` | (staff) сводка «Мозга» |
| POST | `/api/v1/admin/brain/upload-csv` | (staff) загрузка CSV на разбор |

## Команды
`load_cars`, `process_csv <файл> [--wheelbase 2.485]`, `train_brain`, `brain_snapshot`.

## Структура
`holescope_algo/` — signal (оси автомобиля), detector, classify, roughness, suspension, trip_state, cluster, pipeline.
`fleet` — модели авто, машины, устройства. `roadnet` — районы, дороги, сегменты. `telemetry` — поездки, события, кластеры.
`brain` — версии алгоритма, вопросы, разметка, обучение, снимки.
