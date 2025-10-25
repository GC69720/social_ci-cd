#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# 🌐 Redémarrage complet de l'environnement STAGE
# Combine les stacks : infra (social_ci-cd) + applicatif (social_applicatif)
# -------------------------------------------------------------------

APP_PATH="${APP_PATH:-$HOME/DEV/social_applicatif}"
CI_PATH="${CI_PATH:-$HOME/DEV/social_ci-cd}"
API_TAG="${API_TAG:-stage}"
WEB_TAG="${WEB_TAG:-stage}"

echo "=============================================="
echo "🔻 [1/3] Arrêt complet de la stack STAGE (CI/CD)"
echo "=============================================="
cd "${CI_PATH}" || { echo "❌ Dossier introuvable : ${CI_PATH}"; exit 1; }

if [[ -x ./scripts/restart-stage.sh ]]; then
  ./scripts/restart-stage.sh --down || true
else
  echo "⚠️ Script restart-stage.sh introuvable dans ${CI_PATH}/scripts"
fi

echo
echo "=============================================="
echo "🚀 [2/3] Redémarrage complet de la stack applicative"
echo "=============================================="
cd "${APP_PATH}" || { echo "❌ Dossier introuvable : ${APP_PATH}"; exit 1; }

if [[ -x ./scripts/restart-stage.sh ]]; then
  API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" ./scripts/restart-stage.sh
else
  echo "⚠️ Script restart-stage.sh introuvable dans ${APP_PATH}/scripts"
fi

echo
echo "=============================================="
echo "✅ [3/3] Vérification de l'état des conteneurs"
echo "=============================================="
podman ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"

echo
echo "🎯 Environnement STAGE relancé avec succès."
echo "🌍 URLs typiques :"
echo "   → http://localhost:8080/"
echo "   → https://localhost:8443/"
echo "   → https://localhost:8443/api/health"
echo
