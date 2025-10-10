#!/usr/bin/env bash
set -euo pipefail

export PYTHONUNBUFFERED=1
export PYTHONPATH=${PYTHONPATH:-/app/backend/src}

cd /app/backend

# Migrations & collectstatic (idempotent)
python manage.py migrate --noinput
python manage.py collectstatic --noinput --clear || true

# Demarrage
if [ "${DEBUG:-1}" = "1" ]; then
  echo "[dev] Starting Django runserver on 0.0.0.0:8000"
  exec python manage.py runserver 0.0.0.0:8000
else
  echo "[prod] Starting gunicorn on 0.0.0.0:8000"
  exec gunicorn app.wsgi:application --bind 0.0.0.0:8000 --workers 3
fi