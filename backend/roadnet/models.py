from django.db import models


class District(models.Model):
    """Район города / область (иерархия: страна → область → район → махалля)."""
    LEVELS = [("country", "страна"), ("region", "область"), ("city", "город"), ("district", "район"), ("mahalla", "махалля")]
    code = models.CharField(max_length=20, unique=True)             # TSH-YUN, TSH-CHI ...
    name_ru = models.CharField(max_length=80)
    name_uz = models.CharField(max_length=80, blank=True)
    level = models.CharField(max_length=10, choices=LEVELS, default="district")
    parent = models.ForeignKey("self", null=True, blank=True, on_delete=models.CASCADE, related_name="children")
    bbox = models.JSONField(default=list, blank=True)               # [min_lat, min_lon, max_lat, max_lon]
    boundary = models.JSONField(null=True, blank=True)              # GeoJSON (позже → PostGIS geometry)

    def __str__(self):
        return self.name_ru


class Road(models.Model):
    """Дорога целиком: БКАД = R01. Сегменты по 50 м ссылаются на неё."""
    CLASSES = [("R", "кольцевые и скоростные"), ("A", "городские магистрали"), ("B", "районные"),
               ("C", "местные / махаллинские"), ("D", "дворы и проезды"), ("S", "служебные, грунт")]
    SURFACES = [("asphalt", "асфальт"), ("concrete", "бетонные плиты"), ("paving", "брусчатка"),
                ("gravel", "гравий"), ("dirt", "грунт"), ("unknown", "не известно")]
    code = models.CharField(max_length=12, unique=True)             # R01, A014, B203
    name_ru = models.CharField(max_length=120)
    name_uz = models.CharField(max_length=120, blank=True)
    road_class = models.CharField(max_length=1, choices=CLASSES)
    surface = models.CharField(max_length=10, choices=SURFACES, default="unknown")
    osm_way_ids = models.JSONField(default=list, blank=True)
    district = models.ForeignKey(District, null=True, blank=True, on_delete=models.SET_NULL)
    has_tram = models.BooleanField(default=False)
    has_level_crossing = models.BooleanField(default=False)
    speed_limit_kmh = models.PositiveSmallIntegerField(null=True, blank=True)

    def __str__(self):
        return f"{self.code} {self.name_ru}"


class Segment(models.Model):
    """Сегмент дороги ≈50 м в одном направлении. ID вида R01-0412."""
    road = models.ForeignKey(Road, on_delete=models.CASCADE, related_name="segments")
    index = models.PositiveIntegerField()
    direction = models.SmallIntegerField(default=1)                 # +1 / −1 вдоль дороги
    lat_a = models.FloatField(); lon_a = models.FloatField()
    lat_b = models.FloatField(); lon_b = models.FloatField()
    heading = models.FloatField(null=True, blank=True)
    district = models.ForeignKey(District, null=True, blank=True, on_delete=models.SET_NULL)
    ri_median = models.FloatField(null=True, blank=True)            # медиана индекса ровности по всем машинам
    ri_n = models.PositiveIntegerField(default=0)
    cls = models.CharField(max_length=1, blank=True)                # A..E
    updated = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("road", "index", "direction")
        indexes = [models.Index(fields=["lat_a", "lon_a"])]

    @property
    def code(self):
        return f"{self.road.code}-{self.index:04d}"

    def __str__(self):
        return self.code
