"""Посчитать «догадку» для событий, у которых её нет (старые данные), и обновить её после смены параметров: manage.py backfill_guess [--all]"""
from django.core.management.base import BaseCommand
from brain import guesser
from telemetry.models import RoadEvent


class Command(BaseCommand):
    def add_arguments(self, p):
        p.add_argument("--all", action="store_true", help="пересчитать у всех событий, а не только без догадки")

    def handle(self, *a, **kw):
        params = guesser.active_params()
        qs = RoadEvent.objects.select_related("cluster__segment")
        if not kw["all"]:
            qs = qs.filter(guess={})
        n = 0
        for e in qs.iterator(chunk_size=500):
            RoadEvent.objects.filter(pk=e.pk).update(guess=guesser.guess_for_event(e, params))
            n += 1
        self.stdout.write(f"догадка посчитана: {n} событий")
