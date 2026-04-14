FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
# Bundled dataset in image: repo `data/` with EEG/ and speech_data/ (see data/README.md)
ENV DATASET_PATH=/workspace/data
ENV PORT=8000
ENV FLASK_DEBUG=0
ENV FLASK_SSL_ADHOC=0

WORKDIR /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt /workspace/backend/requirements.txt
RUN pip install --no-cache-dir -r /workspace/backend/requirements.txt

COPY backend /workspace/backend
COPY models /workspace/models
COPY data /workspace/data

EXPOSE 8000

# Flask app lives in backend/api/app.py → module api.app, variable app
CMD ["gunicorn", "--config", "backend/gunicorn.conf.py", "--chdir", "backend", "api.app:app"]
