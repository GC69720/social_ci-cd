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
export API_TAG WEB_TAG

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

with_env() {
  local env_file="$1"
  shift
  (
    set -euo pipefail
    if [[ -n "$env_file" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "$env_file"
      set +a
    fi
    "$@"
  )
}

restart_stack() {
  local label="$1"
  local root="$2"
  local action="$3"
  local env_file
  env_file="$(find_env_file "$root")"

  log_section "$label"
  cd "$root" || { echo "❌ Dossier introuvable : $root"; exit 1; }

  if [[ -n "$env_file" ]]; then
    echo "[INFO] Chargement de l'environnement : $env_file"
  else
    echo "[WARN] Aucun fichier .env.stage trouvé pour $root"
  fi

  if [[ -x ./scripts/restart.sh ]]; then
    case "$action" in
      down)
        with_env "$env_file" ./scripts/restart.sh --env stage --down-only || true
        ;;
      restart)
        with_env "$env_file" ./scripts/restart.sh --env stage --down-only || true
        with_env "$env_file" ./scripts/restart.sh --env stage
        ;;
      up)
        with_env "$env_file" ./scripts/restart.sh --env stage
        ;;
      *)
        echo "⚠️ Action inconnue '$action' (attendu: down|restart|up)"
        ;;
    esac
  elif [[ -x ./scripts/restart-stage.sh ]]; then
    (
      set -euo pipefail
      if [[ -n "$env_file" ]]; then
        export ENV_FILE="$env_file"
      fi
      export STAGE_SSH_USER="${STAGE_SSH_USER:-$(id -un 2>/dev/null || echo "stage")}" || true
      case "$action" in
        down)
          ./scripts/restart-stage.sh --down || true
          ;;
        restart)
          ./scripts/restart-stage.sh --down || true
          ./scripts/restart-stage.sh
          ;;
        up)
          ./scripts/restart-stage.sh
          ;;
        *)
          echo "⚠️ Action inconnue '$action' (attendu: down|restart|up)"
          ;;
      esac
    )
  else
    echo "⚠️ Aucun script de restart trouvé dans $root/scripts (attendu: restart.sh ou restart-stage.sh)"
  fi
}

collect_urls() {
  local env_file="$1"
  local -n _urls_ref="$2"
  local value

  if [[ -n "$env_file" && -f "$env_file" ]]; then
    value=$(get_env_value "$env_file" "FRONTEND_URL")
    if [[ -n "$value" ]]; then
      _urls_ref+=("$value")
    fi
    value=$(get_env_value "$env_file" "BACKEND_URL")
    if [[ -n "$value" ]]; then
      local backend_base="${value%/}"
      _urls_ref+=("$backend_base" "${backend_base}/health" "${backend_base}/api/health")
    fi
    value=$(get_env_value "$env_file" "STAGE_HEALTHCHECK_URLS")
    if [[ -n "$value" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && _urls_ref+=("$line")
      done < <(printf '%s\n' "$value")
    fi
  fi
}

get_env_value() {
  local file="$1"
  local var_name="$2"
  (
    set -euo pipefail
    if [[ -f "$file" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "$file"
      set +a
      printf '%s' "${!var_name:-}"
    fi
  )
}

check_urls() {
  local -a urls=()
  local env_file
  env_file="$(find_env_file "$APP_PATH")"
  collect_urls "$env_file" urls

  if [[ ${#urls[@]} -eq 0 ]]; then
    urls=(
      "https://localhost:8443/"
      "https://localhost:8443/api/health"
      "http://localhost:8080/"
    )
  fi

  command -v curl >/dev/null 2>&1 || {
    echo "⚠️ curl est introuvable. Impossible de vérifier automatiquement les URLs."
    return
  }

  echo
  echo "🔎 Vérification des URLs principales"
  local url status
  for url in "${urls[@]}"; do
    if [[ -z "$url" ]]; then
      continue
    fi
    url="${url//[$'\r\n\t ']}"
    [[ -z "$url" ]] && continue
    printf '  • %s ... ' "$url"
    status=$(curl -k -s -o /dev/null -w '%{http_code}' "$url" || echo "000")
    if [[ "$status" == 2* || "$status" == 3* || "$status" == "200" ]]; then
      echo "OK (HTTP $status)"
    else
      echo "KO (HTTP $status)"
    fi
  done
}

restart_stack "🔻 [1/3] Arrêt complet de la stack STAGE (CI/CD)" "$CI_PATH" down
restart_stack "🚀 [2/3] Redémarrage complet de la stack applicative" "$APP_PATH" restart

log_section "✅ [3/3] Vérification de l'état des conteneurs"
podman ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"

check_urls

echo
echo "🎯 Environnement STAGE relancé. Ouvre les URLs ci-dessus pour valider l'accès."
echo
