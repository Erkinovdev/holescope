from django.urls import path
from . import views

urlpatterns = [
    path("devices/register", views.register),
    path("me/vehicle", views.me_vehicle),
    path("trips", views.upload_trip),
    path("trips/raw", views.upload_raw),
    path("questions/next", views.questions_next),
    path("questions/<int:qid>/answer", views.question_answer),
    path("map/clusters", views.map_clusters),
    path("drive/ahead", views.ahead),
    path("admin/brain/summary", views.admin_brain_summary),
    path("admin/brain/upload-csv", views.admin_upload_csv),
]
