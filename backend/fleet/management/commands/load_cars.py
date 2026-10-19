"""Справочник популярных автомобилей Узбекистана (порядок по данным Uzavtosanoat / kun.uz 2025–2026).
Колёсная база и размеры — по обзорам и базам (fastcarcheck, CarExpert, Wikipedia и др.); specs_verified=True только где источники совпали. Где источники расходятся или данных нет — пусто либо False. Остальное — задача админки
(кнопка «дополнить из интернета») и владельцев авто в профиле."""
from django.core.management.base import BaseCommand
from fleet.models import CarModel

CARS = [
    # brand, model, rank, is_ev, wheelbase_mm, length_mm, tire, rim, verified, source
    ('Chevrolet', 'Cobalt', 1, False, 2620, 4479, '', None, False, 'https://kun.uz/en/news/2026/07/06/passenger-car-production-rises-in-uzbekistan-as-cobalt-leads-the-market-d42fbd'),
    ('Chevrolet', 'Damas', 2, False, 1840, None, '', None, True, 'https://fastcarcheck.uk/'),
    ('Chevrolet', 'Tracker', 3, False, None, None, '', None, False, ''),
    ('Chevrolet', 'Onix', 4, False, 2600, None, '', None, True, 'https://en.wikipedia.org/wiki/Chevrolet_Onix'),
    ('Chevrolet', 'Labo', 5, False, None, None, '', None, False, ''),
    ('Kia', 'Sonet', 6, False, 2500, 3995, '', None, True, 'https://www.kia.com/'),
    ('BYD', 'Yuan Up', 7, True, None, None, '', None, False, ''),
    ('Haval', 'M6', 8, False, 2670, None, '', None, False, ''),
    ('Chery', 'Tiggo 7 Pro', 9, False, 2670, None, '', None, True, 'https://fastcarcheck.uk/'),
    ('Geely', 'Geometry E', None, True, 2485, 4006, '205/60 R16', 16, True, 'https://en.42how.com/?p=11959'),
    ('Chevrolet', 'Nexia R3', None, False, 2480, 4330, '', None, True, 'https://fastcarcheck.uk/'),
    ('Chevrolet', 'Lacetti', None, False, 2600, None, '', None, True, 'https://fastcarcheck.uk/'),
    ('Chevrolet', 'Captiva 5', None, False, 2750, 4655, '215/55 R18', 18, False, ''),
    ('Kia', 'Carnival', None, False, 3090, 5155, '235/65 R17', 17, True, 'https://www.carexpert.com.au/'),
    ('Kia', 'Seltos', None, False, 2630, 4385, '', None, True, 'https://www.carexpert.com.au/'),
    ('Kia', 'Sportage', None, False, 2755, 4660, '', None, True, 'https://www.carexpert.com.au/kia/sportage'),
    ('Hyundai', 'Tucson', None, False, 2755, 4630, '', None, True, 'https://www.carexpert.com.au/'),
    ('Hyundai', 'Elantra', None, False, 2720, None, '', None, True, 'https://www.carexpert.com.au/'),
    ('Hyundai', 'Santa Fe', None, False, 2765, None, '', None, True, 'https://www.carsales.com.au/'),
    ('Toyota', 'Camry', None, False, 2825, 4885, '', None, True, 'https://fastcarcheck.uk/'),
    ('Toyota', 'Land Cruiser 300', None, False, 2850, None, '', None, True, 'https://www.carexpert.com.au/'),
    ('Toyota', 'Land Cruiser Prado', None, False, 2790, 4760, '', None, True, 'https://fastcarcheck.uk/'),
    ('Toyota', 'RAV4', None, False, 2690, None, '', None, True, 'https://paultan.org/'),
    ('Chery', 'Tiggo 4 Pro', None, False, 2610, None, '', None, False, 'https://fastcarcheck.uk/'),
    ('Geely', 'Monjaro', None, False, 2845, None, '', None, True, 'https://fastcarcheck.uk/'),
    ('Geely', 'Coolray', None, False, 2600, None, '', None, True, 'https://zigwheels.ae/new-cars/geely/coolray/specifications'),
    ('Geely', 'Emgrand', None, False, 2650, 4638, '195/55 R16', 16, True, 'https://zigwheels.ae/'),
    ('Haval', 'Jolion', None, False, 2700, None, '', None, True, 'https://www.carexpert.com.au/'),
    ('Haval', 'H6', None, False, 2738, None, '', None, True, 'https://fastcarcheck.uk/'),
    ('Haval', 'Dargo', None, False, 2738, 4620, '', None, True, 'https://fastcarcheck.uk/'),
    ('Tesla', 'Model 3', None, True, 2875, None, '', None, False, ''),
    ('Tesla', 'Model Y', None, True, 2890, None, '', None, False, ''),
]


class Command(BaseCommand):
    help = "Загружает справочник автомобилей"

    def handle(self, *a, **kw):
        for b, m, r, ev, wb, ln, tire, rim, ver, src in CARS:
            obj, new = CarModel.objects.update_or_create(brand=b, model=m, generation="", defaults=dict(
                popularity_rank=r, is_ev=ev, wheelbase_mm=wb, length_mm=ln, tire_size=tire, rim_inch=rim, specs_verified=ver, source_url=src))
            self.stdout.write(("+ " if new else "= ") + str(obj))
