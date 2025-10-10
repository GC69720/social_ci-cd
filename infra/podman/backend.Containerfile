FROM docker.io/library/python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Outils système (bash pour entrypoint, libpq dev pour certains wheels)
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash gcc libpq-dev curl \
 && rm -rf /var/lib/apt/lists/*

# Dépendances Python (toujours via "python -m pip")
COPY backend/requirements.txt backend/requirements-dev.txt /app/backend/
RUN python -m pip install --upgrade pip \
 && python -m pip install --no-cache-dir -r /app/backend/requirements-dev.txt \
 #  Drivers Postgres installés explicitement dans le même interpréteur
 && python -m pip install --no-cache-dir "psycopg[binary]==3.2.10" "psycopg2-binary==2.9.9"

# Code applicatif
COPY backend /app/backend

# Entrypoint hors volume, normalisé LF
COPY backend/compose/entrypoint.sh /usr/local/bin/backend-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/backend-entrypoint.sh \
 && chmod +x /usr/local/bin/backend-entrypoint.sh

EXPOSE 8000
