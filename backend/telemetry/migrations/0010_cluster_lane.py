from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("telemetry", "0009_challenge")]
    operations = [
        migrations.AddField(model_name="eventcluster", name="lane", field=models.JSONField(blank=True, default=dict)),
    ]
