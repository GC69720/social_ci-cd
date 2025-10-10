#!/usr/bin/env bash
set -euo pipefail
# Copy backend env
cp -n backend/.env.sample backend/.env || true
# Ensure DB ready (dev via compose uses Postgres container)
export PYTHONPATH=backend/src
pushd backend >/dev/null
python manage.py migrate --noinput
# Create superuser (idempotent)
export DJANGO_SUPERUSER_USERNAME=admin
export DJANGO_SUPERUSER_EMAIL=admin@example.com
export DJANGO_SUPERUSER_PASSWORD=admin
python manage.py createsuperuser --noinput || true
popd >/dev/null
echo "Dev init done. Admin: admin/admin"
