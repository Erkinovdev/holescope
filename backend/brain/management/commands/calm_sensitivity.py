"""Снижает чувствительность детектора: новая активная версия правил с более высокими порогами.

Ложные срабатывания на неровностях покрытия отсекаются порогом: floor (минимум, м/с²) и k_noise (во сколько раз всплеск выше фонового шума).
python manage.py calm_sensitivity [--floor 2.6] [--k 5.0]
"""
from django.core.management.base import BaseCommand
from api.admin_brain import active_params, validate_params
from brain.models import AlgoVersion


class Command(BaseCommand):
    help = "Новая версия правил с пониженной чувствительностью (применяется приложением при следующей синхронизации)"

    def add_arguments(self, parser):
        parser.add_argument("--floor", type=float, default=2.6)
        parser.add_argument("--k", type=float, default=5.0)

    def handle(self, *a, floor, k, **kw):
        cur = active_params()
        cur.update(floor=floor, k_noise=k)
        p, err = validate_params(cur)
        if err:
            raise SystemExit(err)
        n = AlgoVersion.objects.filter(kind="rules").count() + 1
        av = AlgoVersion.objects.create(version=f"rules-{n}", kind="rules", params=p, active=False,
                                        notes=f"Спокойная чувствительность: порог {floor} м/с², шум ×{k} (было {active_params()['floor']} / ×{active_params()['k_noise']})")
        AlgoVersion.objects.filter(kind="rules", active=True).update(active=False)
        av.active = True
        av.save(update_fields=["active"])
        self.stdout.write(f"активна {av.version}: floor={floor}, k_noise={k}")
