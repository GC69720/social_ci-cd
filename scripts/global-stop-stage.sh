#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# 🛑 Extinction complète de l'environnement STAGE
# Arrête et purge toutes les stacks Podman (infra + applicatif)
# -------------------------------------------------------------------

APP_PATH="${APP_PATH:-$HOME/DEV/social_applicatif}"
CI_PATH="${CI_PATH:-$HOME/DEV/social_ci-cd}"

log_section() {
  local title="$1"
  echo
  echo "=============================================="
  echo "$title"
  echo "=============================================="
}

find_env_file() {
  local root="$1"
  if [[ -f "$root/.env.stage" ]]; then
    printf '%s/.env.stage' "$root"
  elif [[ -f "$root/scripts/.env.stage" ]]; then
    printf '%s/scripts/.env.stage' "$root"
  else
    printf ''
  fi
}

run_stack_action() {
  local label="$1"
  local root="$2"
  local env_file
  env_file="$(find_env_file "$root")"

  log_section "🛑 ${label}"
  cd "$root" || { echo "❌ Dossier introuvable : $root"; exit 1; }

  if [[ -n "$env_file" ]]; then
    echo "[INFO] Chargement de l'environnement : $env_file"
  else
    echo "[WARN] Aucun fichier .env.stage trouvé pour $root"
  fi

  if [[ -x ./scripts/restart.sh ]]; then
    (
      set -euo pipefail
      if [[ -n "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
      fi
      ./scripts/restart.sh --env stage --down-only || true
    )
  elif [[ -x ./scripts/restart-stage.sh ]]; then
    (
      set -euo pipefail
      if [[ -n "$env_file" ]]; then
        export ENV_FILE="$env_file"
      fi
      export STAGE_SSH_USER="${STAGE_SSH_USER:-$(id -un 2>/dev/null || echo "stage")}" || true
      ./scripts/restart-stage.sh --down || true
    )
  else
    echo "⚠️ Aucun script de restart trouvé dans $root/scripts (attendu: restart.sh ou restart-stage.sh)"
  fi
}

run_stack_action "[1/2] Arrêt de la stack CI/CD (infra)" "$CI_PATH"
run_stack_action "[2/2] Arrêt de la stack applicative" "$APP_PATH"

log_section "🧹 Nettoyage global de Podman"
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
