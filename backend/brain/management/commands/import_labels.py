"""python manage.py import_labels [--dir ../analysis] — разметка labels_*.json и ручные отметки из CSV → таблица Label."""
from pathlib import Path
from django.core.management.base import BaseCommand
from brain.models import Label
from brain.training import import_labels_json, import_taps_csv


class Command(BaseCommand):
    def add_arguments(self, p):
        p.add_argument("--dir", default="../analysis")
        p.add_argument("--wheelbase", type=float, default=2.485)
        p.add_argument("--replace", action="store_true", help="удалить ранее импортированные метки")

    def handle(self, *a, dir, wheelbase, replace, **kw):
        d = Path(dir)
        if replace:
            Label.objects.filter(source="import").delete()
        for j in sorted(d.glob("labels_*.json")):
            self.stdout.write(str(import_labels_json(j, d, wheelbase)))
        done = {Path(j).stem.replace("labels_", "") for j in d.glob("labels_*.json")}
        for c in sorted(d.glob("pothole_*.csv")):
            if c.stem in done:
                continue                                  # по файлу уже есть полная разметка
            self.stdout.write(str(import_taps_csv(c, wheelbase)))
        self.stdout.write(f"всего меток: {Label.objects.count()}")
