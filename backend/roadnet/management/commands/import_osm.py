"""python manage.py import_osm [--pbf data/uzbekistan.osm.pbf] [--cache data/tashkent_osm.json.gz] [--refresh]
Импорт дорожного графа Ташкента: Road (R01, A014…), Segment по 50 м (R01-0412), районы."""
from pathlib import Path
from django.core.management.base import BaseCommand
from roadnet.builder import build_network
from roadnet.osm_extract import extract, load_cache


class Command(BaseCommand):
    help = "Импорт дорожной сети Ташкента из OSM (Geofabrik .osm.pbf)"

    def add_arguments(self, p):
        p.add_argument("--pbf", default="data/uzbekistan.osm.pbf")
        p.add_argument("--cache", default="data/tashkent_osm.json.gz")
        p.add_argument("--refresh", action="store_true", help="заново разобрать PBF")
        p.add_argument("--keep", action="store_true", help="не удалять существующую сеть")

    def handle(self, *a, pbf, cache, refresh, keep, **kw):
        if refresh or not Path(cache).exists():
            if not Path(pbf).exists():
                raise SystemExit(f"нет {pbf}: скачайте https://download.geofabrik.de/asia/uzbekistan-latest.osm.pbf")
            data = extract(pbf, cache, log=self.stdout.write)
        else:
            data = load_cache(cache)
        build_network(data, log=self.stdout.write, replace=not keep)
