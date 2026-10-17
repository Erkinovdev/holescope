from django.core.management.base import BaseCommand
from brain.inference import reprocess_events
from brain.training import train


class Command(BaseCommand):
    help = "Обучает классификатор на накопленной разметке; включает версию только если она лучше правил на отложенных поездках"

    def add_arguments(self, p):
        p.add_argument("--no-reprocess", action="store_true")

    def handle(self, *a, no_reprocess=False, **kw):
        run = train()
        self.stdout.write(f"labels={run.n_labels} log={run.log}")
        self.stdout.write(f"metrics={run.metrics}")
        if run.algo and run.algo.active and not no_reprocess:
            self.stdout.write(f"переобработка: {reprocess_events()}")
