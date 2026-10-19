FROM python:3.10-slim
ENV PYTHONUNBUFFERED=1 HF_HOME=/models
WORKDIR /app
RUN pip install --no-cache-dir faster-whisper==1.2.1 fastapi==0.115.6 "uvicorn[standard]==0.34.0" python-multipart==0.0.20
ARG STT_MODEL=base
ENV STT_MODEL=${STT_MODEL}
# модель скачивается при сборке образа: контейнер сразу готов и не ходит в интернет
RUN python -c "from faster_whisper import WhisperModel; WhisperModel('${STT_MODEL}', device='cpu', compute_type='int8')"
COPY app.py .
EXPOSE 9000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "9000", "--workers", "1"]
