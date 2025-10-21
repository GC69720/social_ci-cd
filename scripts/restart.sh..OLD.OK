#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Restart de la stack Podman-Compose par environnement (dev|stage|prod)
# - ENV choisit le fichier compose: infra/podman/podman-compose.${ENV}.yml
# - Vérifs HTTP/HTTPS (ignorable) + retry health API
# - Compat Git Bash (Windows) avec MSYS2_ARG_CONV_EXCL et auto-détection curl/sleep
# -------------------------------------------------------------------
##Exemples d’utilisation
##Depuis la racine de social_ci-cd
##
### Stage (par défaut)
##./scripts/restart.sh
##
### Dev (avec ports & host par défaut : 8081 / 8444 / localhost)
##ENV=dev ./scripts/restart.sh
### ou en forçant l’host (si tu as un vhost local)
##ENV=dev HOST=dev.social_applicatif.local ./scripts/restart.sh
##
### Prod (sur serveur, ports 80/443 ; tags latest par défaut)
##ENV=prod HOST=social_applicatif.com ./scripts/restart.sh
##
### Redémarrage sans pull (plus rapide)
##ENV=stage NO_PULL=1 ./scripts/restart.sh
##
### Sans vérifications curl
##ENV=stage SKIP_CHECKS=1 ./scripts/restart.sh
##
### Avec tags spécifiques (builds immuables en CI)
##ENV=stage API_TAG=<backend_sha> WEB_TAG=<frontend_sha> ./scripts/restart.sh


# ---------- Choix environnement ----------
ENV="${ENV:-stage}"  # dev | stage | prod

# ---------- Auto-détection curl / sleep ----------
CURL_BIN="${CURL_BIN:-$(command -v curl  || true)}"
if [[ -z "${CURL_BIN}" && -x "/mingw64/bin/curl" ]]; then CURL_BIN="/mingw64/bin/curl"; fi
SLEEP_BIN="${SLEEP_BIN:-$(command -v sleep || true)}"
if [[ -z "${SLEEP_BIN}" && -x "/usr/bin/sleep" ]]; then SLEEP_BIN="/usr/bin/sleep"; fi
if [[ -z "${CURL_BIN}" || -z "${SLEEP_BIN}" ]]; then
  echo "ERREUR: 'curl' ou 'sleep' introuvable. Définis CURL_BIN/SLEEP_BIN ou installe-les." >&2
  exit 3
fi

# ---------- Chemins ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REL_COMPOSE_FILE="infra/podman/podman-compose.${ENV}.yml"
COMPOSE_PATH="${REPO_ROOT}/${REL_COMPOSE_FILE}"

# ---------- Defaults par ENV (surchargables) ----------
case "${ENV}" in
  dev)
    DEFAULT_HOST="localhost"                    # tu peux mettre "dev.social_applicatif.local"
    DEFAULT_HTTP_PORT="8081"
    DEFAULT_HTTPS_PORT="8444"
    DEFAULT_API_TAG="${API_TAG:-dev}"
    DEFAULT_WEB_TAG="${WEB_TAG:-dev}"
    ;;
  stage)
    DEFAULT_HOST="${STAGE_HOST:-preprod.social_applicatif.com}"
    DEFAULT_HTTP_PORT="8080"
    DEFAULT_HTTPS_PORT="8443"
    DEFAULT_API_TAG="${API_TAG:-dev}"
    DEFAULT_WEB_TAG="${WEB_TAG:-dev}"
    ;;
  prod)
    DEFAULT_HOST="${PROD_HOST:-social_applicatif.com}"
    DEFAULT_HTTP_PORT="${HTTP_PORT:-80}"     # sur un serveur, ports 80/443
    DEFAULT_HTTPS_PORT="${HTTPS_PORT:-443}"
    DEFAULT_API_TAG="${API_TAG:-latest}"
    DEFAULT_WEB_TAG="${WEB_TAG:-latest}"
    ;;
  *)
    echo "ENV invalide: ${ENV}. Utilise dev|stage|prod." >&2
    exit 1
    ;;
esac

# ---------- Variables finales (surchargables depuis l'extérieur) ----------
HOST="${HOST:-${DEFAULT_HOST}}"
HTTP_PORT="${HTTP_PORT:-${DEFAULT_HTTP_PORT}}"
HTTPS_PORT="${HTTPS_PORT:-${DEFAULT_HTTPS_PORT}}"
API_TAG="${API_TAG:-${DEFAULT_API_TAG}}"
WEB_TAG="${WEB_TAG:-${DEFAULT_WEB_TAG}}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-change-me-strong}"

NO_PULL="${NO_PULL:-0}"         # NO_PULL=1 pour sauter 'pull'
SKIP_CHECKS="${SKIP_CHECKS:-0}" # SKIP_CHECKS=1 pour sauter les checks curl

usage() {
  cat <<EOF
Usage:
  ENV=stage API_TAG=dev WEB_TAG=dev POSTGRES_PASSWORD='xxx' NO_PULL=1 SKIP_CHECKS=1 \\
  ${0##*/}

Paramètres :
  ENV=dev|stage|prod            (defaut: stage)

Variables surchargables :
  HOST, HTTP_PORT, HTTPS_PORT   (déduites de ENV par défaut)
  API_TAG, WEB_TAG              (dev en dev/stage, latest en prod par défaut)
  POSTGRES_PASSWORD             (defaut: change-me-strong)
  NO_PULL=1                     (saute 'pull')
  SKIP_CHECKS=1                 (saute les vérifications HTTP/HTTPS)
  CURL_BIN, SLEEP_BIN           (chemins explicites si besoin)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi

echo "==> ENV               : ${ENV}"
echo "==> Repo root         : ${REPO_ROOT}"
echo "==> Compose (relatif) : ${REL_COMPOSE_FILE}"
echo "==> HOST              : ${HOST}"
echo "==> HTTP_PORT         : ${HTTP_PORT}"
echo "==> HTTPS_PORT        : ${HTTPS_PORT}"
echo "==> API_TAG           : ${API_TAG}"
echo "==> WEB_TAG           : ${WEB_TAG}"
echo "==> POSTGRES_PASSWORD : (masqué)"
echo "==> NO_PULL           : ${NO_PULL}"
echo "==> SKIP_CHECKS       : ${SKIP_CHECKS}"
echo "==> curl              : ${CURL_BIN}"
echo "==> sleep             : ${SLEEP_BIN}"
echo

if [[ ! -f "${COMPOSE_PATH}" ]]; then
  echo "ERREUR: compose introuvable: ${COMPOSE_PATH}" >&2
  exit 1
fi

pushd "${REPO_ROOT}" >/dev/null
export MSYS2_ARG_CONV_EXCL="*"

echo "==> [1/4] Arrêt (${ENV})…"
podman-compose -f "${REL_COMPOSE_FILE}" down || true

if [[ "${NO_PULL}" != "1" ]]; then
  echo "==> [2/4] Pull (${ENV})…"
  API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  podman-compose -f "${REL_COMPOSE_FILE}" pull
else
  echo "==> [2/4] Pull SKIPPÉ (NO_PULL=1)…"
fi

echo "==> [3/4] Démarrage (${ENV})…"
API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
podman-compose -f "${REL_COMPOSE_FILE}" up -d

echo
echo "==> État des services :"
podman ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "podman_(db|api|web|nginx)_1" || true
echo

if [[ "${SKIP_CHECKS}" == "1" ]]; then
  echo "==> [4/4] Vérifications SKIPPÉES."
  popd >/dev/null; exit 0
fi

echo "==> [4/4] Vérifications (${ENV})…"
set +e
# a) HTTP -> redirection vers HTTPS
"${CURL_BIN}" -sS -I -H "Host: ${HOST}" "http://localhost:${HTTP_PORT}" | head -n 1

# b) Page front HTTPS (self-signed en dev/stage -> -k)
CURL_SSL_FLAG=""
if [[ "${ENV}" != "prod" ]]; then CURL_SSL_FLAG="-k"; fi
"${CURL_BIN}" ${CURL_SSL_FLAG} -sS -I -H "Host: ${HOST}" "https://localhost:${HTTPS_PORT}/" | head -n 1

# c) Health API: /api/health puis /health
API_OK=0
for PATH in "/api/health" "/health"; do
  CODE=$("${CURL_BIN}" ${CURL_SSL_FLAG} -s -o /dev/null -w "%{http_code}" -H "Host: ${HOST}" "https://localhost:${HTTPS_PORT}${PATH}")
  echo "Check ${PATH}: HTTP ${CODE}"
  if [[ "${CODE}" == "200" ]]; then API_OK=1; break; fi
done

if [[ "${API_OK}" -ne 1 ]]; then
  echo "Attente que l'API devienne healthy (jusqu'à 60s)…"
  for i in {1..12}; do
    "${SLEEP_BIN}" 5
    CODE=$("${CURL_BIN}" ${CURL_SSL_FLAG} -s -o /dev/null -w "%{http_code}" -H "Host: ${HOST}" "https://localhost:${HTTPS_PORT}/api/health")
    echo "Tentative $i: /api/health -> ${CODE}"
    if [[ "${CODE}" == "200" ]]; then API_OK=1; break; fi
  done
fi
set -e

if [[ "${API_OK}" -ne 1 ]]; then
  echo "⚠️  API non healthy. Regarde les logs :"
  echo "    podman logs podman_api_1 --tail=200"
  popd >/dev/null; exit 2
fi

echo "✅ Stack ${ENV^^} opérationnelle."
popd >/dev/null
