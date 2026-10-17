from django.contrib import admin
from .models import AlgoVersion, Question, Label, TrainingRun, BrainSnapshot
for m in (AlgoVersion, Question, Label, TrainingRun, BrainSnapshot): admin.site.register(m)
