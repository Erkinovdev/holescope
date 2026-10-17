from django.core.management.base import BaseCommand
from brain.training import train


class Command(BaseCommand):
    help = "Обучает классификатор на накопленной разметке (запуск по расписанию)"

    def handle(self, *a, **kw):
        run = train()
        self.stdout.write(f"labels={run.n_labels} metrics={run.metrics} log={run.log}")
