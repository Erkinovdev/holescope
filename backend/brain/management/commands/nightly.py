"""Ночные задачи «мозга» (запускать раз в сутки: cron или сервис worker в docker-compose).
Порядок: «заделана» → калибровка устройств → подвеска машин → обучение → снимок → награды."""
from datetime import timedelta
from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone
from brain import awards, road_stats
from fleet.models import Device, Vehicle
from telemetry.models import SegmentScore


class Command(BaseCommand):
    def handle(self, *a, **kw):
        out = self.stdout.write
        from telemetry.marks import apply_pending
        out(f"отметки водителей: {apply_pending(now=timezone.now() + timedelta(hours=3))}")
        out(f"заделаны: {road_stats.evaluate_all_fixed()}")
        recent = timezone.now() - timedelta(days=2)
        seg_ids = SegmentScore.objects.filter(at__gte=recent, segment__isnull=False).values_list("segment_id", flat=True).distinct()
        out(f"сегментов пересчитано: {road_stats.refresh_segments(list(seg_ids))}")
        cal = [road_stats.update_calibration(d) for d in Device.objects.filter(last_seen__gte=recent)]
        out(f"калибровка: {sum(c is not None for c in cal)} устройств")
        n = 0
        for v in Vehicle.objects.filter(km_since_susp_eval__gt=0, softness_conf__lt=1.0)[:500]:
            if road_stats.recompute_vehicle_suspension(v):
                n += 1
        out(f"подвеска: {n} машин; моделей с оценкой: {road_stats.refresh_car_model_stats()}")
        call_command("train_brain", stdout=self.stdout)
        call_command("brain_snapshot", stdout=self.stdout)
        for p in ("week", "month", "year"):
            out(f"награды {p}: {len(awards.compute_awards(p))}")
