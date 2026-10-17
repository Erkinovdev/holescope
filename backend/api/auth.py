import json
from functools import wraps
from django.contrib.auth import get_user_model
from django.core import signing
from django.http import JsonResponse
from fleet.models import Device

ADMIN_TOKEN_MAX_AGE = 12 * 3600
ROLE_LEVEL = {"analyst": 1, "labeler": 2, "admin": 3}
ROLE_NAMES = {"analyst": "аналитик", "labeler": "разметчик", "admin": "админ"}


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


def user_role(user) -> str | None:
    """Роль сотрудника: admin (суперпользователь или группа admin) > labeler > analyst; без группы is_staff → analyst."""
    if not user.is_active:
        return None
    if user.is_superuser:
        return "admin"
    names = set(user.groups.values_list("name", flat=True))
    for r in ("admin", "labeler", "analyst"):
        if r in names:
            return r
    return "analyst" if user.is_staff else None


def make_admin_token(user) -> str:
    return signing.dumps({"uid": user.pk}, salt="holescope-admin")


def _user_from_request(request):
    """Сотрудник из заголовка Authorization: Bearer <token> или из сессии Django."""
    h = request.headers.get("Authorization", "")
    if h.startswith("Bearer "):
        try:
            uid = signing.loads(h[7:], salt="holescope-admin", max_age=ADMIN_TOKEN_MAX_AGE)["uid"]
        except signing.BadSignature:
            return None
        return get_user_model().objects.filter(pk=uid, is_active=True).first()
    u = getattr(request, "user", None)
    return u if u is not None and u.is_authenticated else None


def role_required(min_role: str):
    """Доступ сотрудникам с ролью не ниже min_role (analyst < labeler < admin)."""
    def deco(view):
        @wraps(view)
        def wrapper(request, *a, **kw):
            u = _user_from_request(request)
            r = user_role(u) if u else None
            if not r:
                return JsonResponse({"error": "unauthorized"}, status=401)
            if ROLE_LEVEL[r] < ROLE_LEVEL[min_role]:
                return JsonResponse({"error": "forbidden", "need": min_role}, status=403)
            request.staff, request.staff_role = u, r
            return view(request, *a, **kw)
        return wrapper
    return deco


def staff_required(view):
    """Совместимость: любая роль сотрудника."""
    return role_required("analyst")(view)


def body(request):
    try:
        return json.loads(request.body or b"{}")
    except ValueError:
        return {}
