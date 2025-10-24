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
ACTION="restart"          # restart|down|up
DEFAULT_POSTGRES_PASSWORD="change-me-strong"

# -------- Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_NAME="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL=1; shift ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    --down-only)
      [[ "${ACTION}" == "up" ]] && die "--down-only et --up-only sont mutuellement exclusifs"
      ACTION="down"
      shift ;;
    --up-only)
      [[ "${ACTION}" == "down" ]] && die "--up-only et --down-only sont mutuellement exclusifs"
      ACTION="up"
      shift ;;
    -h|--help)
      cat <<'EOF'
Usage:
  ./scripts/restart.sh [--env dev|stage|prod] [--no-pull] [--skip-checks]

Options:
  --env           Environnement (defaut: stage)
  --no-pull       Ne pas faire 'podman-compose pull'
  --skip-checks   Ne pas faire les vérifications HTTP/HTTPS
  --down-only     Arrêter uniquement les services (pas de pull/up)
  --up-only       Démarrer uniquement (sans arrêt préalable)

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
msg "==> Action            : ${ACTION}"
msg "==> curl              : ${CURL_BIN:-<absent>}"
msg "==> sleep             : ${SLEEP_BIN:-<absent>}\n"

[[ -f "${COMPOSE_PATH}" ]] || die "Compose introuvable: ${COMPOSE_PATH}"

pushd "${REPO_ROOT}" >/dev/null
export MSYS2_ARG_CONV_EXCL="*"

# -------- Down (optionnel)
if [[ "${ACTION}" == "down" || "${ACTION}" == "restart" ]]; then
  msg "==> Arrêt (${ENV_NAME})…"
  podman-compose -f "${REL_COMPOSE_FILE}" down || true
  if [[ "${ACTION}" == "down" ]]; then
    msg "✅ Stack ${ENV_NAME^^} arrêtée."
    popd >/dev/null
    exit 0
  fi
fi

# -------- Pull (optionnel)
if [[ "${ACTION}" != "down" ]]; then
  if [[ ${NO_PULL} -eq 0 ]]; then
    msg "==> Pull (${ENV_NAME})…"
    API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    podman-compose -f "${REL_COMPOSE_FILE}" pull
  else
    msg "==> Pull SKIP (--no-pull)…"
  fi
fi

# -------- Up (optionnel)
if [[ "${ACTION}" != "down" ]]; then
  msg "==> Démarrage (${ENV_NAME})…"
  API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  podman-compose -f "${REL_COMPOSE_FILE}" up -d

  msg "\n==> État des services :"
  podman ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "podman_(db|api|web|nginx)_1" || true
  msg ""
fi

# -------- Checks
if [[ "${ACTION}" != "down" ]]; then
  if [[ ${SKIP_CHECKS} -eq 1 || -z "${CURL_BIN:-}" || -z "${SLEEP_BIN:-}" ]]; then
    msg "==> Vérifications SKIP (flag ou curl/sleep absents)."
  else
    msg "==> Vérifications (${ENV_NAME})…"
    set +e

    # a) HTTP -> redirection vers HTTPS
    "${CURL_BIN}" -sS -I -H "Host: ${HOST}" "http://localhost:${HTTP_PORT}" | head -n 1

    # b) Page front HTTPS (self-signed en dev/stage -> -k)
    CURL_SSL_FLAG=""
    [[ "${ENV_NAME}" != "prod" ]] && CURL_SSL_FLAG="-k"
    "${CURL_BIN}" ${CURL_SSL_FLAG} -sS -I -H "Host: ${HOST}" "https://localhost:${HTTPS_PORT}/" | head -n 1

    # c) Health API: /api/health puis /health, retry 24 * 5s = 120s
    API_OK=0
    for PATH in "/api/health" "/health"; do
      CODE=$("${CURL_BIN}" ${CURL_SSL_FLAG} -s -o /dev/null -w "%{http_code}" -H "Host: ${HOST}" "https://localhost:${HTTPS_PORT}${PATH}")
      echo "Check ${PATH}: HTTP ${CODE}"
      [[ "${CODE}" == "200" ]] && API_OK=1 && break
    done
    if [[ ${API_OK} -ne 1 ]]; then
      echo "Attente que l'API devienne healthy (jusqu'à 120s)…"
      for i in {1..24}; do
        "${SLEEP_BIN}" 5
        CODE=$("${CURL_BIN}" ${CURL_SSL_FLAG} -s -o /dev/null -w "%{http_code}" -H "Host: ${HOST}" "https://localhost:${HTTPS_PORT}/api/health")
        echo "Tentative $i: /api/health -> ${CODE}"
        [[ "${CODE}" == "200" ]] && API_OK=1 && break
      done
    fi
    set -e

    if [[ ${API_OK} -ne 1 ]]; then
      echo "⚠️  API non healthy. Aides au debug :"
      echo "    podman logs podman_api_1 --tail=150"
      echo "    podman exec -it podman_nginx_1 sh -c 'apk add --no-cache curl >/dev/null 2>&1 || true; curl -s -I http://api:8000/health || true'"
      popd >/dev/null
      exit 2
    fi
  fi
fi

# -------- URLs à tester dans le navigateur
echo
echo "============================================================"
echo "URLs à tester (${ENV_NAME}) :"
if [[ "${ENV_NAME}" == "prod" ]]; then
  echo "  - HTTPS  : https://${HOST}/"
  echo "  - Health : https://${HOST}/api/health"
  echo "  - HTTP   : http://${HOST}/   -> redirige 301 vers HTTPS"
else
  echo "  - HTTPS  : https://${HOST}:${HTTPS_PORT}/"
  echo "  - Health : https://${HOST}:${HTTPS_PORT}/api/health"
  echo "  - HTTP   : http://${HOST}:${HTTP_PORT}/   -> redirige 301 vers HTTPS"
fi
echo "============================================================"
echo

msg "✅ Stack ${ENV_NAME^^} opérationnelle."
popd >/dev/null
