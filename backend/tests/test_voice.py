"""Серверное распознавание команд: проверка устройства, лимитов и пересылки (сам Whisper подменён)."""
import io
import pytest
from django.test import Client
from api import voice
from tests.test_api import register

pytestmark = pytest.mark.django_db


@pytest.fixture
def c():
    return Client()


def post(c, tok, data=b"RIFF" + b"\0" * 4000, lang="ru"):
    f = io.BytesIO(data)
    f.name = "speech.wav"
    return c.post("/api/v1/voice/transcribe", {"file": f, "lang": lang}, HTTP_X_DEVICE_TOKEN=tok)


def test_requires_token(c):
    assert c.post("/api/v1/voice/transcribe", {}).status_code == 401


def test_disabled_without_service(c, monkeypatch):
    monkeypatch.delenv("STT_URL", raising=False)
    assert post(c, register(c)).status_code == 503


def test_forwards_and_returns_text(c, monkeypatch):
    monkeypatch.setenv("STT_URL", "http://stt:9000")
    seen = {}

    def fake(data, lang, timeout=25.0):
        seen.update(n=len(data), lang=lang)
        return {"text": "глубокая яма", "ms": 800, "model": "base"}
    monkeypatch.setattr(voice, "call_stt", fake)
    r = post(c, register(c), lang="uz")
    assert r.status_code == 200 and r.json()["text"] == "глубокая яма" and r.json()["engine"] == "whisper-base"
    assert seen["lang"] == "uz" and seen["n"] == 4004


def test_rejects_tiny_and_huge(c, monkeypatch):
    monkeypatch.setenv("STT_URL", "http://stt:9000")
    tok = register(c)
    assert post(c, tok, data=b"x" * 10).status_code == 400
    assert post(c, tok, data=b"x" * 1_600_000).status_code == 400


def test_daily_limit(c, monkeypatch):
    monkeypatch.setenv("STT_URL", "http://stt:9000")
    monkeypatch.setattr(voice, "call_stt", lambda *a, **k: {"text": "да", "model": "base"})
    monkeypatch.setattr(voice, "DAILY_LIMIT", 2)
    tok = register(c)
    assert [post(c, tok).status_code for _ in range(3)] == [200, 200, 429]


def test_service_down_gives_503(c, monkeypatch):
    import urllib.error
    monkeypatch.setenv("STT_URL", "http://stt:9000")

    def boom(*a, **k):
        raise urllib.error.URLError("down")
    monkeypatch.setattr(voice, "call_stt", boom)
    assert post(c, register(c)).status_code == 503
