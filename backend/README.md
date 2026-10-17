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
| GET | `/api/v1/admin/brain/summary` | (staff) сводка «Мозга» |
| POST | `/api/v1/admin/brain/upload-csv` | (staff) загрузка CSV на разбор |

## Команды
`load_cars`, `process_csv <файл> [--wheelbase 2.485]`, `train_brain`, `brain_snapshot`.

## Структура
`holescope_algo/` — signal (оси автомобиля), detector, classify, roughness, suspension, trip_state, cluster, pipeline.
`fleet` — модели авто, машины, устройства. `roadnet` — районы, дороги, сегменты. `telemetry` — поездки, события, кластеры.
`brain` — версии алгоритма, вопросы, разметка, обучение, снимки.
