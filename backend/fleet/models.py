import secrets
from django.db import models


def new_token():
    return secrets.token_urlsafe(32)


class CarModel(models.Model):
    """Справочник моделей автомобилей (популярные в Узбекистане + добавляются администратором)."""
    brand = models.CharField(max_length=60)
    model = models.CharField(max_length=80)
    generation = models.CharField(max_length=60, blank=True)
    body = models.CharField(max_length=30, blank=True)
    is_ev = models.BooleanField(default=False)
    wheelbase_mm = models.PositiveIntegerField(null=True, blank=True)
    length_mm = models.PositiveIntegerField(null=True, blank=True)
    tire_size = models.CharField(max_length=30, blank=True)         # 205/60 R16
    rim_inch = models.PositiveSmallIntegerField(null=True, blank=True)
    popularity_rank = models.PositiveSmallIntegerField(null=True, blank=True)   # место по продажам в Узбекистане
    specs_verified = models.BooleanField(default=False)             # характеристики проверены по источнику
    source_url = models.URLField(blank=True)
    # накопленный «рейтинг мягкости» модели по данным всех машин этой модели
    softness_median = models.FloatField(null=True, blank=True)
    softness_n_vehicles = models.PositiveIntegerField(default=0)

    class Meta:
        unique_together = ("brand", "model", "generation")
        ordering = ["popularity_rank", "brand", "model"]

    def __str__(self):
        return f"{self.brand} {self.model} {self.generation}".strip()


class Vehicle(models.Model):
    """Профиль машины («резюме»): параметры, подвеска, накопленный отпечаток."""
    SUSP = [("S1", "жёсткая"), ("S2", "жёсткая-средняя"), ("S3", "средняя"), ("S4", "мягкая"), ("S5", "очень мягкая")]
    name = models.CharField(max_length=80, blank=True)
    car_model = models.ForeignKey(CarModel, null=True, blank=True, on_delete=models.SET_NULL, related_name="vehicles")
    model_guess = models.ForeignKey(CarModel, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    model_guess_conf = models.FloatField(default=0.0)               # авто-определение марки/модели
    year = models.PositiveSmallIntegerField(null=True, blank=True)
    rim_inch = models.PositiveSmallIntegerField(null=True, blank=True)
    tire_pressure_bar = models.FloatField(null=True, blank=True)
    wheelbase_mm = models.PositiveIntegerField(null=True, blank=True)
    suspension_note = models.CharField(max_length=120, blank=True)  # слова владельца: «чуть выше средней»
    suspension_cls = models.CharField(max_length=2, choices=SUSP, blank=True)
    softness_score = models.FloatField(null=True, blank=True)       # 0..100
    softness_conf = models.FloatField(default=0.0)
    zeta_median = models.FloatField(null=True, blank=True)
    f_body_median = models.FloatField(null=True, blank=True)
    km_total = models.FloatField(default=0.0)
    km_since_susp_eval = models.FloatField(default=0.0)
    fingerprint = models.JSONField(default=dict, blank=True)
    created = models.DateTimeField(auto_now_add=True)

    @property
    def wb_m(self):
        mm = self.wheelbase_mm or (self.car_model.wheelbase_mm if self.car_model else None)
        return (mm or 2600) / 1000.0

    def __str__(self):
        return self.name or str(self.car_model or f"Vehicle {self.pk}")


class Device(models.Model):
    """Устройство (телефон/логгер). Анонимный токен без почты и номера."""
    ROLES = [("driver", "водитель"), ("passenger", "пассажир / такси"), ("research", "исследовательский логгер")]
    token = models.CharField(max_length=64, unique=True, default=new_token)
    nickname = models.CharField(max_length=60, blank=True)          # «Тихий Сокол #4821»
    platform = models.CharField(max_length=20, blank=True)          # ios / android / web
    phone_model = models.CharField(max_length=80, blank=True)
    app_version = models.CharField(max_length=20, blank=True)
    role = models.CharField(max_length=12, choices=ROLES, default="driver")
    vehicle = models.ForeignKey(Vehicle, null=True, blank=True, on_delete=models.SET_NULL, related_name="devices")
    mount = models.CharField(max_length=20, blank=True)             # seat / cupholder / holder
    lang = models.CharField(max_length=2, default="ru")
    # калибровка устройства: сдвиг/множитель чувствительности (по люкам и рельсам как «эталонам»)
    calib_gain = models.FloatField(default=1.0)
    calib_n = models.PositiveIntegerField(default=0)
    trust = models.FloatField(default=0.5)                          # доверие 0..1 (подтверждения, антиспам)
    last_seen = models.DateTimeField(null=True, blank=True)
    created = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.nickname or f"device {self.pk}"
