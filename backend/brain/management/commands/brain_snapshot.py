"""Ежедневный снимок «мозга» для графика роста на дашборде."""
from django.core.management.base import BaseCommand
from django.db.models import Sum
from django.utils import timezone
from brain.models import BrainSnapshot, Label, TrainingRun
from telemetry.models import RoadEvent, EventCluster, Trip, SegmentScore
from fleet.models import Device


class Command(BaseCommand):
    def handle(self, *a, **kw):
        day = timezone.localdate(); last = TrainingRun.objects.exclude(metrics={}).order_by("-created").first()
        BrainSnapshot.objects.update_or_create(day=day, defaults=dict(
            events_total=RoadEvent.objects.count(), clusters_total=EventCluster.objects.count(), labels_total=Label.objects.count(),
            km_total=Trip.objects.aggregate(s=Sum("distance_km"))["s"] or 0.0,
            devices_active=Device.objects.filter(last_seen__gte=timezone.now() - timezone.timedelta(days=7)).count(),
            precision=(last.metrics.get("precision") if last else None), recall=(last.metrics.get("recall") if last else None),
            segments_scored=SegmentScore.objects.count()))
        self.stdout.write("snapshot ok")
