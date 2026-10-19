"""Сервис распознавания коротких голосовых команд Холи (faster-whisper, CPU, int8).
Внутренний: наружу не открыт, его вызывает Django (/api/v1/voice/transcribe) после проверки токена устройства.
Звук нигде не сохраняется: приходит, распознаётся в памяти и удаляется."""
from __future__ import annotations
import io
import os
import re
import time
import threading

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from faster_whisper import WhisperModel

MODEL = os.environ.get("STT_MODEL", "base")
THREADS = int(os.environ.get("STT_THREADS", "2"))
MAX_BYTES = 1_500_000  # ≈ 45 с WAV 16 кГц mono

# Подсказка с лексикой команд: Whisper лучше узнаёт слова, которые уже «слышал» в контексте (проверено на русском и узбекском: 78 % → 91 %).
# Подсказка короткая: длинный список он иногда зачитывает вместо ответа — такой ответ отбрасывается (см. leaked).
PROMPT = {
    "ru": "яма, глубокая яма, лежачий полицейский, люк, отмена, да, нет",
    "uz": "o'ra, chuqur o'ra, yotiq politsiyachi, lyuk, bekor, ha, yo'q",
}

app = FastAPI(title="holescope-stt")
_model: WhisperModel | None = None
_lock = threading.Lock()  # одна фраза за раз: два потока на двух ядрах быстрее, чем много параллельных


def model() -> WhisperModel:
    global _model
    if _model is None:
        _model = WhisperModel(MODEL, device="cpu", compute_type="int8", cpu_threads=THREADS)
    return _model


def dedupe(text: str) -> str:
    """Whisper на коротких фразах иногда зацикливается («люк, люк, люк…») — оставляем каждую фразу один раз."""
    parts = [p.strip() for p in re.split(r"[,.!?;]+", text) if p.strip()]
    seen, out = set(), []
    for p in parts:
        k = p.lower()
        if k not in seen:
            seen.add(k)
            out.append(p)
    return ", ".join(out[:6])


def leaked(text: str, lang: str) -> bool:
    """Модель зачитала подсказку вместо ответа (на тишине или невнятной речи): три и более слов подсказки подряд."""
    items = {p.strip().lower() for p in PROMPT[lang].split(",")}
    parts = [p.strip().lower() for p in re.split(r"[,.!?;]+", text) if p.strip()]
    return len(parts) >= 3 and sum(1 for p in parts if p in items) >= 3


def transcribe_bytes(data: bytes, lang: str) -> dict:
    lang = "uz" if lang == "uz" else "ru"
    t0 = time.time()
    with _lock:
        segs, info = model().transcribe(
            io.BytesIO(data),
            language=lang,
            beam_size=1,
            temperature=0,
            condition_on_previous_text=False,
            initial_prompt=PROMPT[lang],
            max_new_tokens=24,
        )
        text = " ".join(s.text.strip() for s in segs).strip()
    text = "" if leaked(text, lang) else dedupe(text)
    return dict(text=text, lang=lang, ms=int((time.time() - t0) * 1000), duration=round(info.duration, 2), model=MODEL)


@app.get("/health")
def health():
    model()
    return {"ok": True, "model": MODEL}


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...), lang: str = Form("ru")):
    data = await file.read()
    if not data or len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="audio size")
    try:
        return transcribe_bytes(data, lang)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"decode failed: {type(e).__name__}")
