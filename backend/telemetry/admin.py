from django.contrib import admin
from .models import Trip, RawUpload, EventCluster, RoadEvent, SegmentScore
for m in (Trip, RawUpload, EventCluster, RoadEvent, SegmentScore): admin.site.register(m)
