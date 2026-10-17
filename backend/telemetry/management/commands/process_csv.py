"""python manage.py process_csv путь.csv [--device ID] [--wheelbase 2.485]
Прогоняет CSV логгера через алгоритм и сохраняет поездку, события, кластеры, сегменты в БД."""
from datetime import timezone as dtz
from django.core.management.base import BaseCommand
from django.db import transaction
from fleet.models import Device
from brain.services import ingest_trip
from holescope_algo.pipeline import process_csv
from holescope_algo.params import Params
import pandas as pd


class Command(BaseCommand):
    def add_arguments(self, p):
        p.add_argument("csv"); p.add_argument("--device", type=int); p.add_argument("--wheelbase", type=float, default=2.6)

    @transaction.atomic
    def handle(self, *a, csv, device, wheelbase, **kw):
        r = process_csv(csv, Params(wheelbase_m=wheelbase))
        dev = Device.objects.filter(pk=device).first() if device else Device.objects.create(nickname="research-import", role="research")
        started = pd.Timestamp(r["meta"].get("started", "1970-01-01T00:00:00Z")).to_pydatetime()
        seg = r["segments"]
        payload = dict(started_at=started, duration_s=r["duration_s"], algo_version=r["algo_version"], distance_km=r["distance_km"],
                       start_reason="manual", events=r["events"], damping=r["damping"], suspension=r["suspension"],
                       segments=[dict(lat_a=x.lat_a, lon_a=x.lon_a, lat_b=x.lat_b, lon_b=x.lon_b, speed_kmh=x.speed_kmh, ri=x.ri, cls=x.cls, t0=x.t0)
                                 for x in seg.itertuples()] if len(seg) else [])
        trip = ingest_trip(dev, payload, validate=False)
        self.stdout.write(f"trip {trip.pk}: событий {trip.events.count()}, кластеров {trip.events.values('cluster').distinct().count()}")
