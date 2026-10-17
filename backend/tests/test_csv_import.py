"""process_csv на реальной записи 17.10 (если файл на месте)."""
from pathlib import Path
import pytest
from django.core.management import call_command
from telemetry.models import Trip, RoadEvent, EventCluster, SegmentScore

CSV = Path(__file__).resolve().parents[2] / "analysis" / "pothole_2026-10-17_12-09-50.csv"


@pytest.mark.django_db
@pytest.mark.skipif(not CSV.exists(), reason="нет analysis/*.csv")
def test_process_csv_populates_db():
    call_command("process_csv", str(CSV), wheelbase=2.485)
    t = Trip.objects.get()
    assert 11 < t.distance_km < 12.5
    assert RoadEvent.objects.count() > 0
    assert EventCluster.objects.count() > 0
    assert SegmentScore.objects.count() > 100
