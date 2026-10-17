from django.urls import path
from . import views, public, openapi

urlpatterns = [
    path("devices/register", views.register),
    path("me/vehicle", views.me_vehicle),
    path("me/stats", public.my_stats),
    path("trips", views.upload_trip),
    path("trips/raw", views.upload_raw),
    path("questions/next", views.questions_next),
    path("questions/<int:qid>/answer", views.question_answer),
    path("map/clusters", views.map_clusters),
    path("drive/ahead", views.ahead),
    path("rankings/streets", public.rankings_streets),
    path("rankings/districts", public.rankings_districts),
    path("reports/weekly", public.weekly_report),
    path("dictionaries", public.dictionaries),
    path("car-models", public.car_models),
    path("complaints", public.complaint_create),
    path("complaints/<int:cid>", public.complaint_detail),
    path("complaints/<int:cid>/send", public.complaint_send),
    path("admin/brain/summary", views.admin_brain_summary),
    path("admin/brain/upload-csv", views.admin_upload_csv),
    path("openapi.json", openapi.openapi_json),
    path("docs", openapi.docs),
]
