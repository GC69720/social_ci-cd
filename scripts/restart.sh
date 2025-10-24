#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Restart de la stack Podman-Compose par environnement (dev|stage|prod)
# - --env choisit le fichier compose: infra/podman/podman-compose.${ENV}.yml
# - Vérifs HTTP/HTTPS (ignorables) + retry health API (jusqu'à 2 min)
# - Compat Git Bash (Windows) : force l'usage de /mingw64/bin/curl si dispo
# - Affiche les URLs de test à ouvrir dans le navigateur en fin
# ------------------------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }
msg() { echo -e "$*"; }

# -------- Defaults
ENV_NAME="stage"           # dev|stage|prod
NO_PULL=0                  # 1 = ne pas faire de podman-compose pull
SKIP_CHECKS=0              # 1 = sauter les vérifications curl
DEFAULT_POSTGRES_PASSWORD="change-me-strong"

# -------- Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_NAME="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL=1; shift ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage:
  ./scripts/restart.sh [--env dev|stage|prod] [--no-pull] [--skip-checks]

Options:
  --env           Environnement (defaut: stage)
  --no-pull       Ne pas faire 'podman-compose pull'
  --skip-checks   Ne pas faire les vérifications HTTP/HTTPS

Vars utiles (surchargent les defaults par ENV) :
  HOST, HTTP_PORT, HTTPS_PORT, API_TAG, WEB_TAG, POSTGRES_PASSWORD
EOF
      exit 0 ;;
    *) die "Argument inconnu: $1 (voir --help)";;
  esac
done

# -------- Chemins
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REL_COMPOSE_FILE="infra/podman/podman-compose.${ENV_NAME}.yml"
COMPOSE_PATH="${REPO_ROOT}/${REL_COMPOSE_FILE}"

# -------- Defaults par ENV (surchargables via variables d'env)
case "${ENV_NAME}" in
  dev)
    HOST="${HOST:-dev.social_applicatif.com}"
    HTTP_PORT="${HTTP_PORT:-8081}"
    HTTPS_PORT="${HTTPS_PORT:-8444}"
    API_TAG="${API_TAG:-dev}"
    WEB_TAG="${WEB_TAG:-dev}"
    DEFAULT_POSTGRES_PASSWORD="app"
    ;;
  stage)
    HOST="${HOST:-preprod.social_applicatif.com}"
    HTTP_PORT="${HTTP_PORT:-8080}"
    HTTPS_PORT="${HTTPS_PORT:-8443}"
    API_TAG="${API_TAG:-dev}"
    WEB_TAG="${WEB_TAG:-dev}"
    DEFAULT_POSTGRES_PASSWORD="MyStrongPwd123!"
    ;;
  prod)
    HOST="${HOST:-prod.social_applicatif.com}"
    HTTP_PORT="${HTTP_PORT:-80}"
    HTTPS_PORT="${HTTPS_PORT:-443}"
    API_TAG="${API_TAG:-latest}"
    WEB_TAG="${WEB_TAG:-latest}"
    DEFAULT_POSTGRES_PASSWORD="change-me-strong"
    ;;
  *) die "ENV invalide: ${ENV_NAME} (attendu: dev|stage|prod)";;
esac

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-${DEFAULT_POSTGRES_PASSWORD}}"

# -------- Auto-detect curl / sleep
# Priorité à /mingw64/bin/curl (Git Bash), sinon 'which curl'
if [[ -x "/mingw64/bin/curl" ]]; then
  CURL_BIN="/mingw64/bin/curl"
else
  CURL_BIN="${CURL_BIN:-$(command -v curl  || true)}"
fi
SLEEP_BIN="${SLEEP_BIN:-$(command -v sleep || true)}"

# -------- Affichage paramètres
msg "==> ENV               : ${ENV_NAME}"
msg "==> Repo root         : ${REPO_ROOT}"
msg "==> Compose (relatif) : ${REL_COMPOSE_FILE}"
msg "==> HOST              : ${HOST}"
msg "==> HTTP_PORT         : ${HTTP_PORT}"
msg "==> HTTPS_PORT        : ${HTTPS_PORT}"
msg "==> API_TAG           : ${API_TAG}"
msg "==> WEB_TAG           : ${WEB_TAG}"
msg "==> POSTGRES_PASSWORD : (masqué)"
msg "==> --no-pull         : ${NO_PULL}"
msg "==> --skip-checks     : ${SKIP_CHECKS}"
msg "==> curl              : ${CURL_BIN:-<absent>}"
msg "==> sleep             : ${SLEEP_BIN:-<absent>}\n"
