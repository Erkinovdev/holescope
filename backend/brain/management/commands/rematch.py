"""python manage.py rematch — привязать к дорожной сети кластеры и сегменты ровности, у которых сегмент ещё не определён
(например, после импорта сети) и пересчитать агрегаты сегментов."""
from django.core.management.base import BaseCommand
from brain import road_stats
from roadnet.geo import bearing
from roadnet.matching import get_index, reset_index
from telemetry.models import EventCluster, SegmentScore


class Command(BaseCommand):
    def handle(self, *a, **kw):
        reset_index()
        idx = get_index()
        n_c = 0
        for c in EventCluster.objects.filter(segment__isnull=True).iterator():
            m = idx.snap(c.lat, c.lon, c.heading)
            if m:
                EventCluster.objects.filter(pk=c.pk).update(segment_id=m.segment_id)
                n_c += 1
        touched, n_s = set(), 0
        for s in SegmentScore.objects.filter(segment__isnull=True).iterator():
            m = idx.snap((s.lat_a + s.lat_b) / 2, (s.lon_a + s.lon_b) / 2, bearing(s.lat_a, s.lon_a, s.lat_b, s.lon_b))
            if m:
                SegmentScore.objects.filter(pk=s.pk).update(segment_id=m.segment_id)
                touched.add(m.segment_id)
                n_s += 1
        road_stats.refresh_segments(touched)
        self.stdout.write(f"кластеров привязано: {n_c}, сегментов ровности: {n_s}, сегментов сети обновлено: {len(touched)}")
