from django.db import models
from fleet.models import Device


class AlgoVersion(models.Model):
    """Версия «мозга»: правила + параметры + (позже) модель. Активна одна."""
    version = models.CharField(max_length=20, unique=True)
    kind = models.CharField(max_length=10, default="rules")         # rules / gbm
    params = models.JSONField(default=dict)
    model_blob = models.BinaryField(null=True, blank=True)          # pickle модели
    metrics = models.JSONField(default=dict, blank=True)
    active = models.BooleanField(default=False)
    notes = models.TextField(blank=True)
    created = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.version} ({self.kind})"


class Question(models.Model):
    """Вопрос водителю после поездки: «это была яма?» Основной источник разметки."""
    STATUS = [("open", "ждёт ответа"), ("answered", "отвечено"), ("skipped", "пропущено"), ("expired", "истёк")]
    device = models.ForeignKey(Device, on_delete=models.CASCADE, related_name="questions")
    event = models.ForeignKey("telemetry.RoadEvent", on_delete=models.CASCADE, related_name="questions")
    prompt_kind = models.CharField(max_length=20, default="what_was_it")
    priority = models.FloatField(default=0.0)                       # выше = важнее (неопределённость × новизна)
    status = models.CharField(max_length=10, choices=STATUS, default="open")
    answer = models.CharField(max_length=20, blank=True)           # pothole_light / pothole_deep / bump / manhole / rail / joint / nothing / not_sure
    created = models.DateTimeField(auto_now_add=True)
    answered_at = models.DateTimeField(null=True, blank=True)


class Label(models.Model):
    """Единая таблица разметки: ответы водителей, разметка в админке, импорт labels_*.json."""
    SOURCES = [("driver", "ответ водителя"), ("admin", "разметка в админке"), ("import", "импорт файла"), ("server", "серверное правило")]
    event = models.ForeignKey("telemetry.RoadEvent", null=True, blank=True, on_delete=models.CASCADE, related_name="labels")
    source = models.CharField(max_length=10, choices=SOURCES)
    label = models.CharField(max_length=20)
    features = models.JSONField(default=dict, blank=True)           # копия признаков (если события в БД нет — импорт)
    trip_key = models.CharField(max_length=80, blank=True)          # для проверки «обучились на одних поездках, тест на другой»
    created = models.DateTimeField(auto_now_add=True)


class TrainingRun(models.Model):
    algo = models.ForeignKey(AlgoVersion, null=True, blank=True, on_delete=models.SET_NULL)
    n_labels = models.PositiveIntegerField(default=0)
    metrics = models.JSONField(default=dict)
    log = models.TextField(blank=True)
    created = models.DateTimeField(auto_now_add=True)


class BrainSnapshot(models.Model):
    """Ежедневный снимок «мозга» для дашборда: чему научился, сколько знает, как растёт точность."""
    day = models.DateField(unique=True)
    events_total = models.PositiveIntegerField(default=0)
    clusters_total = models.PositiveIntegerField(default=0)
    labels_total = models.PositiveIntegerField(default=0)
    km_total = models.FloatField(default=0.0)
    devices_active = models.PositiveIntegerField(default=0)
    precision = models.FloatField(null=True, blank=True)
    recall = models.FloatField(null=True, blank=True)
    segments_scored = models.PositiveIntegerField(default=0)
    data = models.JSONField(default=dict, blank=True)


class ModelAward(models.Model):
    """«Самая мягкая машина недели/месяца/года» (заготовка): медиана softness_score на модель, ≥10 машин и ≥500 км на модель."""
    PERIODS = [("week", "неделя"), ("month", "месяц"), ("year", "год")]
    period = models.CharField(max_length=6, choices=PERIODS)
    day = models.DateField()
    car_model = models.ForeignKey("fleet.CarModel", on_delete=models.CASCADE, related_name="awards")
    softness_median = models.FloatField()
    n_vehicles = models.PositiveIntegerField()
    km_total = models.FloatField()
    rank = models.PositiveSmallIntegerField(default=1)

    class Meta:
        unique_together = ("period", "day", "car_model")


class AuditLog(models.Model):
    """Журнал действий сотрудников в админке (кто, что, когда)."""
    user = models.ForeignKey("auth.User", null=True, on_delete=models.SET_NULL, related_name="+")
    action = models.CharField(max_length=40)
    target = models.CharField(max_length=60, blank=True)
    payload = models.JSONField(default=dict, blank=True)
    at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-at"]
