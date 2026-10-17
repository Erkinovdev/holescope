from django.db import models
from fleet.models import Device, Vehicle
from roadnet.models import Segment


class Trip(models.Model):
    STATUS = [("auto", "авто-старт"), ("manual", "вручную"), ("imported", "импорт CSV")]
    MODES = [("car", "авто"), ("bus_or_tram", "автобус / трамвай"), ("walk_or_bike", "пешком / велосипед"),
             ("train_or_highway", "поезд / трасса"), ("unknown", "не определено")]
    device = models.ForeignKey(Device, on_delete=models.CASCADE, related_name="trips")
    vehicle = models.ForeignKey(Vehicle, null=True, blank=True, on_delete=models.SET_NULL, related_name="trips")
    started_at = models.DateTimeField()
    ended_at = models.DateTimeField(null=True, blank=True)
    start_reason = models.CharField(max_length=10, choices=STATUS, default="auto")
    end_reason = models.CharField(max_length=20, blank=True)        # stopped / walking / signal_lost / manual
    mode = models.CharField(max_length=20, choices=MODES, default="car")
    mode_conf = models.FloatField(default=0.0)
    distance_km = models.FloatField(default=0.0)
    avg_speed_kmh = models.FloatField(default=0.0)
    mount = models.CharField(max_length=20, blank=True)
    algo_version = models.CharField(max_length=12, blank=True)
    app_version = models.CharField(max_length=20, blank=True)
    summary = models.JSONField(default=dict, blank=True)            # ровность, подвеска, числа
    client_id = models.CharField(max_length=64, blank=True, default="")   # идемпотентность повторной отправки с телефона
    created = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-started_at"]
        constraints = [models.UniqueConstraint(fields=["device", "client_id"], condition=~models.Q(client_id=""), name="uniq_trip_client")]


class RawUpload(models.Model):
    """Сырой CSV (исследовательские устройства или ручная загрузка в админке «Мозг»)."""
    device = models.ForeignKey(Device, null=True, blank=True, on_delete=models.SET_NULL)
    trip = models.ForeignKey(Trip, null=True, blank=True, on_delete=models.SET_NULL, related_name="raw")
    file = models.FileField(upload_to="raw/%Y/%m/")
    filename = models.CharField(max_length=200, blank=True)
    processed = models.BooleanField(default=False)
    algo_version = models.CharField(max_length=12, blank=True)
    report = models.JSONField(default=dict, blank=True)
    created = models.DateTimeField(auto_now_add=True)


class EventCluster(models.Model):
    """Яма / неровность как объект на карте (по нескольким проездам)."""
    STATUS = [("candidate", "кандидат"), ("confirmed", "подтверждена"), ("complaint", "жалоба подана"),
              ("fixed", "заделана"), ("false", "ложная")]
    TYPES = [("pothole", "яма / неровность"), ("bump", "лежачий"), ("manhole", "люк"), ("joint", "стык"),
             ("rail_tram", "трамвайные рельсы"), ("rail_train", "ж/д переезд"), ("rough_patch", "гребёнка"), ("rutting", "колейность")]
    lat = models.FloatField(); lon = models.FloatField()
    heading = models.FloatField(null=True, blank=True)
    segment = models.ForeignKey(Segment, null=True, blank=True, on_delete=models.SET_NULL, related_name="clusters")
    type = models.CharField(max_length=12, choices=TYPES, default="pothole")
    level = models.CharField(max_length=6, blank=True)              # light / mid / deep / danger
    status = models.CharField(max_length=10, choices=STATUS, default="candidate")
    passes = models.PositiveIntegerField(default=1)                 # проездов, давших удар
    quiet_passes = models.PositiveIntegerField(default=0)           # проездов без удара (для «заделана»)
    devices = models.PositiveIntegerField(default=1)
    score_median = models.FloatField(default=0.0)
    safe_speed_kmh = models.PositiveSmallIntegerField(null=True, blank=True)
    confidence = models.FloatField(default=0.0)
    first_seen = models.DateTimeField(auto_now_add=True)
    last_seen = models.DateTimeField(auto_now=True)
    last_hit = models.DateTimeField(null=True, blank=True)          # время последнего удара (не любое сохранение)
    fixed_at = models.DateTimeField(null=True, blank=True)
    type_votes = models.JSONField(default=dict, blank=True)         # голоса водителей по типу: {manhole: 3, pothole_light: 1}

    class Meta:
        indexes = [models.Index(fields=["lat", "lon"]), models.Index(fields=["status"])]


class RoadEvent(models.Model):
    """Одно срабатывание на одном проезде одного устройства."""
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="events")
    device = models.ForeignKey(Device, on_delete=models.CASCADE)
    cluster = models.ForeignKey(EventCluster, null=True, blank=True, on_delete=models.SET_NULL, related_name="events")
    t_offset = models.FloatField()                                  # секунд от начала поездки
    at = models.DateTimeField()
    lat = models.FloatField(); lon = models.FloatField()
    heading = models.FloatField(null=True, blank=True)
    speed_kmh = models.FloatField()
    type = models.CharField(max_length=12, default="pothole")
    level = models.CharField(max_length=6, blank=True)
    confidence = models.FloatField(default=0.0)
    peak = models.FloatField(); score = models.FloatField()
    features = models.JSONField(default=dict)                       # весь вектор признаков (для переобучения)
    wave = models.JSONField(default=list, blank=True)               # форма сигнала ±2 с (для вопросов и разбора)
    algo_version = models.CharField(max_length=12)
    low_conf = models.BooleanField(default=False)
    user_label = models.CharField(max_length=20, blank=True)        # ответ водителя
    created = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["lat", "lon"]), models.Index(fields=["at"])]


class SegmentScore(models.Model):
    """Индекс ровности сегмента на одном проезде."""
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="seg_scores")
    device = models.ForeignKey(Device, on_delete=models.CASCADE)
    segment = models.ForeignKey(Segment, null=True, blank=True, on_delete=models.SET_NULL)
    lat_a = models.FloatField(); lon_a = models.FloatField(); lat_b = models.FloatField(); lon_b = models.FloatField()
    speed_kmh = models.FloatField(); ri = models.FloatField(); cls = models.CharField(max_length=1)
    at = models.DateTimeField()


class QuietPass(models.Model):
    """Проезд мимо известной ямы БЕЗ удара (на достаточной скорости) — основа статуса «заделана»."""
    cluster = models.ForeignKey(EventCluster, on_delete=models.CASCADE, related_name="quiet")
    device = models.ForeignKey(Device, on_delete=models.CASCADE)
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="quiet_passes")
    at = models.DateTimeField()
    speed_kmh = models.FloatField()

    class Meta:
        constraints = [models.UniqueConstraint(fields=["cluster", "trip"], name="uniq_quiet_cluster_trip")]
        indexes = [models.Index(fields=["cluster", "at"])]


class Complaint(models.Model):
    """Жалоба по яме (группе ям). Текст и координаты готовятся автоматически; отправка во внешнюю систему — вручную/интеграцией."""
    CHANNELS = [("xalq_nazorati", "Xalq Nazorati"), ("mintrans", "Минтранс"), ("other", "другое")]
    STATUS = [("draft", "черновик"), ("filed", "подана"), ("review", "рассмотрение"), ("answered", "дан ответ"), ("fixed", "исправлено"), ("rejected", "отклонена")]
    cluster = models.ForeignKey(EventCluster, on_delete=models.CASCADE, related_name="complaints")
    device = models.ForeignKey(Device, null=True, blank=True, on_delete=models.SET_NULL)
    channel = models.CharField(max_length=20, choices=CHANNELS, default="xalq_nazorati")
    text = models.TextField()
    anonymous = models.BooleanField(default=True)
    status = models.CharField(max_length=10, choices=STATUS, default="draft")
    external_number = models.CharField(max_length=40, blank=True)   # номер обращения во внешней системе
    due_at = models.DateTimeField(null=True, blank=True)
    created = models.DateTimeField(auto_now_add=True)
    filed_at = models.DateTimeField(null=True, blank=True)
    answered_at = models.DateTimeField(null=True, blank=True)


class ClusterReport(models.Model):
    """Отметка водителя на карточке ямы: «на месте» / «заделана» (не за рулём, вручную)."""
    STATES = [("present", "яма на месте"), ("fixed", "заделана")]
    cluster = models.ForeignKey(EventCluster, on_delete=models.CASCADE, related_name="reports")
    device = models.ForeignKey(Device, on_delete=models.CASCADE)
    state = models.CharField(max_length=8, choices=STATES)
    at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["cluster", "at"])]
