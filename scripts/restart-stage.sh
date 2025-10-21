#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Restart complet de la stack STAGE (podman-compose) sous Git Bash/Windows
# - Chemin RELATIF pour le compose (-f infra/podman/...)
# - Désactive la conversion MSYS des arguments (MSYS2_ARG_CONV_EXCL="*")
# - Auto-détection de curl/sleep (Git Bash compat)
# -------------------------------------------------------------------

# --- Auto-détection curl / sleep -----------------------------------
CURL_BIN="${CURL_BIN:-$(command -v curl  || true)}"
if [[ -z "${CURL_BIN}" && -x "/mingw64/bin/curl" ]]; then CURL_BIN="/mingw64/bin/curl"; fi
SLEEP_BIN="${SLEEP_BIN:-$(command -v sleep || true)}"
if [[ -z "${SLEEP_BIN}" && -x "/usr/bin/sleep" ]]; then SLEEP_BIN="/usr/bin/sleep"; fi
if [[ -z "${CURL_BIN}" || -z "${SLEEP_BIN}" ]]; then
  echo "ERREUR: 'curl' ou 'sleep' introuvable dans le PATH. Définis CURL_BIN/SLEEP_BIN ou installe-les." >&2
  exit 3
fi

# --- Chemins / config ----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REL_COMPOSE_FILE="infra/podman/podman-compose.stage.yml"   # <= RELATIF
COMPOSE_PATH="${REPO_ROOT}/${REL_COMPOSE_FILE}"

STAGE_HOST="preprod.social_applicatif.com"
HTTP_PORT="8080"
HTTPS_PORT="8443"

# Variables attendues par le compose (avec défauts sûrs)
: "${API_TAG:=dev}"
: "${WEB_TAG:=dev}"
: "${POSTGRES_PASSWORD:=change-me-strong}"

# Flags optionnels
NO_PULL="${NO_PULL:-0}"         # NO_PULL=1 pour sauter 'pull'
SKIP_CHECKS="${SKIP_CHECKS:-0}" # SKIP_CHECKS=1 pour sauter les checks curl

usage() {
  cat <<EOF
Usage:
  API_TAG=dev WEB_TAG=dev POSTGRES_PASSWORD='xxx' NO_PULL=1 SKIP_CHECKS=1 \\
  ${0##*/}

Vars:
  API_TAG / WEB_TAG          Tag des images (defaut: dev)
  POSTGRES_PASSWORD          Mot de passe Postgres (defaut: change-me-strong)
  NO_PULL=1                  Skip 'podman-compose pull'
  SKIP_CHECKS=1              Skip vérifications HTTP/HTTPS
  CURL_BIN / SLEEP_BIN       Chemins explicites si besoin
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi

echo "==> Repo root        : ${REPO_ROOT}"
echo "==> Compose (relatif): ${REL_COMPOSE_FILE}"
echo "==> API_TAG          : ${API_TAG}"
echo "==> WEB_TAG          : ${WEB_TAG}"
echo "==> POSTGRES_PASSWORD: (masqué)"
echo "==> NO_PULL          : ${NO_PULL}"
echo "==> SKIP_CHECKS      : ${SKIP_CHECKS}"
echo "==> curl              : ${CURL_BIN}"
echo "==> sleep             : ${SLEEP_BIN}"
echo

if [[ ! -f "${COMPOSE_PATH}" ]]; then
  echo "ERREUR: compose introuvable: ${COMPOSE_PATH}" >&2
  exit 1
fi

pushd "${REPO_ROOT}" >/dev/null

# Important sous Git Bash/Windows : éviter la conversion de chemins
export MSYS2_ARG_CONV_EXCL="*"

echo "==> [1/4] Arrêt de la stack (down)…"
podman-compose -f "${REL_COMPOSE_FILE}" down || true

if [[ "${NO_PULL}" != "1" ]]; then
  echo "==> [2/4] Pull des images…"
  API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  podman-compose -f "${REL_COMPOSE_FILE}" pull
else
  echo "==> [2/4] Pull SKIPPÉ (NO_PULL=1)…"
fi

echo "==> [3/4] Démarrage…"
API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
podman-compose -f "${REL_COMPOSE_FILE}" up -d

echo
echo "==> État des services :"
podman ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "podman_(db|api|web|nginx)_1" || true
echo

if [[ "${SKIP_CHECKS}" == "1" ]]; then
  echo "==> [4/4] Vérifications SKIPPÉES."
  popd >/dev/null
  exit 0
fi

echo "==> [4/4] Vérifications…"
set +e
# a) HTTP → redirection vers HTTPS
"${CURL_BIN}" -sS -I -H "Host: ${STAGE_HOST}" "http://localhost:${HTTP_PORT}" | head -n 1

# b) Page front en HTTPS (cert auto-signé → -k)
"${CURL_BIN}" -k -sS -I -H "Host: ${STAGE_HOST}" "https://localhost:${HTTPS_PORT}/" | head -n 1

# c) Health API via NGINX : on essaie /api/health puis /health
API_OK=0
for PATH in "/api/health" "/health"; do
  CODE=$("${CURL_BIN}" -k -s -o /dev/null -w "%{http_code}" -H "Host: ${STAGE_HOST}" "https://localhost:${HTTPS_PORT}${PATH}")
  echo "Check ${PATH}: HTTP ${CODE}"
  if [[ "${CODE}" == "200" ]]; then
    API_OK=1
    break
  fi
done

# d) Retry (jusqu'à 60s) si pas encore OK
if [[ "${API_OK}" -ne 1 ]]; then
  echo "Attente que l'API devienne healthy (jusqu'à 60s)…"
  for i in {1..12}; do
    "${SLEEP_BIN}" 5
    CODE=$("${CURL_BIN}" -k -s -o /dev/null -w "%{http_code}" -H "Host: ${STAGE_HOST}" "https://localhost:${HTTPS_PORT}/api/health")
    echo "Tentative $i: /api/health -> ${CODE}"
    if [[ "${CODE}" == "200" ]]; then
      API_OK=1
      break
    fi
  done
fi
set -e

if [[ "${API_OK}" -ne 1 ]]; then
  echo "⚠️  API non healthy. Regarde les logs :"
  echo "    podman logs podman_api_1 --tail=200"
  popd >/dev/null
  exit 2
fi

echo "✅ Stack STAGE opérationnelle."
popd >/dev/null
