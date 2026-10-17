import json
from functools import wraps
from django.http import JsonResponse
from fleet.models import Device


def device_required(view):
    @wraps(view)
    def wrapper(request, *a, **kw):
        tok = request.headers.get("X-Device-Token", "")
        dev = Device.objects.filter(token=tok).first() if tok else None
        if not dev:
            return JsonResponse({"error": "unauthorized"}, status=401)
        request.device = dev
        return view(request, *a, **kw)
    return wrapper


def staff_required(view):
    @wraps(view)
    def wrapper(request, *a, **kw):
        if not (request.user.is_authenticated and request.user.is_staff):
            return JsonResponse({"error": "forbidden"}, status=403)
        return view(request, *a, **kw)
    return wrapper


def body(request):
    try:
        return json.loads(request.body or b"{}")
    except ValueError:
        return {}
