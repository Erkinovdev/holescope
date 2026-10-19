"""Серверное распознавание голосовых команд: проверяет устройство и лимит, передаёт короткую запись во внутренний сервис stt и возвращает текст.
Запись нигде не сохраняется."""
from __future__ import annotations
import json
import os
import uuid
import urllib.error
import urllib.request
from django.db.models import F
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from telemetry.models import VoiceUsage
from .auth import device_required

MAX_BYTES = 1_500_000
DAILY_LIMIT = 400


def stt_url() -> str:
    return os.environ.get("STT_URL", "").rstrip("/")


def _multipart(data: bytes, lang: str) -> tuple[bytes, str]:
    b = uuid.uuid4().hex
    body = (f"--{b}\r\nContent-Disposition: form-data; name=\"lang\"\r\n\r\n{lang}\r\n"
            f"--{b}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n").encode() + data + f"\r\n--{b}--\r\n".encode()
    return body, f"multipart/form-data; boundary={b}"


def call_stt(data: bytes, lang: str, timeout: float = 25.0) -> dict:
    body, ctype = _multipart(data, lang)
    req = urllib.request.Request(stt_url() + "/transcribe", data=body, headers={"Content-Type": ctype}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:  # noqa: S310 (адрес внутренний, из настроек)
        return json.loads(r.read().decode("utf-8"))


@csrf_exempt
@device_required
@require_http_methods(["POST"])
def transcribe(request):
    """multipart: file=<wav 16 кГц mono>, lang=ru|uz → {"text": "...", "ms": 900, "engine": "whisper-base"}"""
    if not stt_url():
        return JsonResponse({"error": "stt disabled"}, status=503)
    f = request.FILES.get("file")
    if not f or f.size > MAX_BYTES or f.size < 1000:
        return JsonResponse({"error": "audio size"}, status=400)
    lang = "uz" if request.POST.get("lang") == "uz" else "ru"
    usage, _ = VoiceUsage.objects.get_or_create(device=request.device, day=timezone.localdate())
    if usage.count >= DAILY_LIMIT:
        return JsonResponse({"error": "daily limit"}, status=429)
    VoiceUsage.objects.filter(pk=usage.pk).update(count=F("count") + 1)
    try:
        res = call_stt(f.read(), lang)
    except urllib.error.HTTPError as e:
        return JsonResponse({"error": f"stt {e.code}"}, status=502)
    except (urllib.error.URLError, TimeoutError, OSError):
        return JsonResponse({"error": "stt unavailable"}, status=503)
    return JsonResponse({"text": res.get("text", ""), "ms": res.get("ms"), "engine": f"whisper-{res.get('model', '')}"})
