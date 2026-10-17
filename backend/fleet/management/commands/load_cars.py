"""Справочник популярных автомобилей Узбекистана (порядок по данным Uzavtosanoat / kun.uz 2025–2026).
Характеристики заполнены ТОЛЬКО там, где они проверены по источнику (specs_verified=True). Остальное — задача админки
(кнопка «дополнить из интернета») и владельцев авто в профиле."""
from django.core.management.base import BaseCommand
from fleet.models import CarModel

CARS = [
    # brand, model, rank, is_ev, wheelbase_mm, length_mm, tire, rim, verified, source
    ("Chevrolet", "Cobalt", 1, False, None, None, "", None, False, "https://kun.uz/en/news/2026/07/06/passenger-car-production-rises-in-uzbekistan-as-cobalt-leads-the-market-d42fbd"),
    ("Chevrolet", "Damas", 2, False, None, None, "", None, False, ""),
    ("Chevrolet", "Tracker", 3, False, None, None, "", None, False, ""),
    ("Chevrolet", "Onix", 4, False, None, None, "", None, False, ""),
    ("Chevrolet", "Labo", 5, False, None, None, "", None, False, ""),
    ("Kia", "Sonet", 6, False, None, None, "", None, False, ""),
    ("BYD", "Yuan Up", 7, True, None, None, "", None, False, ""),
    ("Haval", "M6", 8, False, None, None, "", None, False, ""),
    ("Chery", "Tiggo 7 Pro", 9, False, None, None, "", None, False, ""),
    ("Geely", "Geometry E", None, True, 2485, 4006, "205/60 R16", 16, True, "https://en.42how.com/?p=11959"),
]


class Command(BaseCommand):
    help = "Загружает справочник автомобилей"

    def handle(self, *a, **kw):
        for b, m, r, ev, wb, ln, tire, rim, ver, src in CARS:
            obj, new = CarModel.objects.update_or_create(brand=b, model=m, generation="", defaults=dict(
                popularity_rank=r, is_ev=ev, wheelbase_mm=wb, length_mm=ln, tire_size=tire, rim_inch=rim, specs_verified=ver, source_url=src))
            self.stdout.write(("+ " if new else "= ") + str(obj))
