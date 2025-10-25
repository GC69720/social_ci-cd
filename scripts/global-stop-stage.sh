#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# 🛑 Extinction complète de l'environnement STAGE
# Arrête et purge toutes les stacks Podman (infra + applicatif)
# -------------------------------------------------------------------

APP_PATH="${APP_PATH:-$HOME/DEV/social_applicatif}"
CI_PATH="${CI_PATH:-$HOME/DEV/social_ci-cd}"

echo "=============================================="
echo "🛑 [1/2] Arrêt de la stack CI/CD (infra)"
echo "=============================================="
cd "${CI_PATH}" || { echo "❌ Dossier introuvable : ${CI_PATH}"; exit 1; }

if [[ -x ./scripts/restart-stage.sh ]]; then
  ./scripts/restart-stage.sh --down || true
else
  echo "⚠️ Script restart-stage.sh introuvable dans ${CI_PATH}/scripts"
fi

echo
echo "=============================================="
echo "🛑 [2/2] Arrêt de la stack applicative"
echo "=============================================="
cd "${APP_PATH}" || { echo "❌ Dossier introuvable : ${APP_PATH}"; exit 1; }

if [[ -x ./scripts/restart-stage.sh ]]; then
  ./scripts/restart-stage.sh --down || true
else
  echo "⚠️ Script restart-stage.sh introuvable dans ${APP_PATH}/scripts"
fi

echo
echo "=============================================="
echo "🧹 Nettoyage global de Podman"
echo "=============================================="
podman stop -a >/dev/null 2>&1 || true
podman rm -a -f >/dev/null 2>&1 || true
podman pod rm -a -f >/dev/null 2>&1 || true
podman network rm podman_default >/dev/null 2>&1 || true
podman volume prune -f >/dev/null 2>&1 || true

echo
echo "✅ Environnement STAGE complètement arrêté."
echo "   Aucun conteneur en cours d'exécution."
podman ps
echo
