#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# 🚀 Restart complet de la stack STAGE (Podman Compose)
# Compatible Git Bash (Windows)
# -------------------------------------------------------------------

die() { echo "ERREUR: $*" >&2; exit 1; }
msg() { echo -e "$*"; }

CURL_BIN="${CURL_BIN:-$(command -v curl || true)}"
SLEEP_BIN="${SLEEP_BIN:-$(command -v sleep || true)}"
[[ -z "${CURL_BIN}" || -z "${SLEEP_BIN}" ]] && die "curl ou sleep introuvable dans le PATH."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REL_COMPOSE_FILE="infra/podman/podman-compose.stage.yml"
COMPOSE_PATH="${REPO_ROOT}/${REL_COMPOSE_FILE}"

STAGE_HOST="preprod.social_applicatif.com"
HTTP_PORT=8080
HTTPS_PORT=8443

: "${API_TAG:=stage}"
: "${WEB_TAG:=stage}"
: "${POSTGRES_PASSWORD:=MyStrongPwd123!}"

msg "==> Repo root        : ${REPO_ROOT}"
msg "==> Compose (relatif): ${REL_COMPOSE_FILE}"
msg "==> API_TAG          : ${API_TAG}"
msg "==> WEB_TAG          : ${WEB_TAG}"
msg

# -------------------------------------------------------------------
# [1] Purge Podman
# -------------------------------------------------------------------
msg "==> [Préflight] Purge de l'environnement Podman..."
podman stop -a >/dev/null 2>&1 || true
podman rm -a -f >/dev/null 2>&1 || true
podman pod rm -a -f >/dev/null 2>&1 || true
podman network rm podman_default >/dev/null 2>&1 || true
podman volume prune -f >/dev/null 2>&1 || true
msg "✅ Environnement nettoyé."
msg

# -------------------------------------------------------------------
# [2] Certificats SSL auto-signés
# -------------------------------------------------------------------
msg "==> [Préflight] Vérification des certificats SSL..."
CERTS_DIR="${REPO_ROOT}/infra/podman/certs"

# création du dossier Windows-safe
if [[ ! -d "${CERTS_DIR}" ]]; then
  msg "Création du dossier certificats via Windows..."
  cmd.exe /C "mkdir \"$(cygpath -w "${CERTS_DIR}")\"" >/dev/null 2>&1 || true
fi

CRT_FILE="${CERTS_DIR}/localhost.crt"
KEY_FILE="${CERTS_DIR}/localhost.key"

CRT_FILE_WIN="$(cygpath -m "${CRT_FILE}")"
KEY_FILE_WIN="$(cygpath -m "${KEY_FILE}")"

if [[ ! -f "${CRT_FILE}" || ! -f "${KEY_FILE}" ]]; then
  msg "🔧 Génération du certificat auto-signé pour 'localhost'..."
  export MSYS_NO_PATHCONV=1
  export MSYS2_ARG_CONV_EXCL="*"
  openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "${KEY_FILE_WIN}" -out "${CRT_FILE_WIN}" -days 365 \
    -subj "//CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    || die "Échec de la génération du certificat SSL."
  msg "✅ Certificats générés dans : ${CERTS_DIR}"
else
  msg "✅ Certificats déjà présents dans : ${CERTS_DIR}"
fi
msg

# -------------------------------------------------------------------
# [3] Copie vers NGINX
# -------------------------------------------------------------------
msg "==> [Préflight] Synchronisation des certificats vers NGINX..."
NGINX_CERTS_DIR="${REPO_ROOT}/infra/podman/nginx/certs"
mkdir -p "${NGINX_CERTS_DIR}"
cp -f "${CRT_FILE}" "${NGINX_CERTS_DIR}/server.crt"
cp -f "${KEY_FILE}" "${NGINX_CERTS_DIR}/server.key"
msg "✅ Certificats copiés dans : ${NGINX_CERTS_DIR}"
msg

# -------------------------------------------------------------------
# [4] Redémarrage stack
# -------------------------------------------------------------------
[[ -f "${COMPOSE_PATH}" ]] || die "Fichier compose introuvable : ${COMPOSE_PATH}"
command -v podman >/dev/null 2>&1 || die "'podman' introuvable dans le PATH."

pushd "${REPO_ROOT}" >/dev/null
export MSYS2_ARG_CONV_EXCL="*"

msg "==> [1/4] Arrêt de la stack (down)…"
podman-compose -f "${REL_COMPOSE_FILE}" down || true

msg "==> [2/4] Pull des images (si nécessaire)…"
API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
podman-compose -f "${REL_COMPOSE_FILE}" pull || true

msg "==> [3/4] Démarrage des services…"
API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
podman-compose -f "${REL_COMPOSE_FILE}" up -d

msg "==> [4/4] Vérification du statut des containers…"
sleep 5
podman ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "podman_(db|api|web|nginx)_1" || true
msg

# -------------------------------------------------------------------
# [5] Vérifications
# -------------------------------------------------------------------
msg "==> [Post-check] Vérifications de santé..."
"${CURL_BIN}" -sS -I "http://localhost:${HTTP_PORT}" | head -n 1 || true
"${CURL_BIN}" -k -sS -I "https://localhost:${HTTPS_PORT}/" | head -n 1 || true

API_OK=0
for PATH in "/api/health" "/health"; do
  CODE=$("${CURL_BIN}" -k -s -o /dev/null -w "%{http_code}" "https://localhost:${HTTPS_PORT}${PATH}" || true)
  echo "Check ${PATH}: HTTP ${CODE}"
  [[ "${CODE}" == "200" ]] && API_OK=1 && break
done

if [[ "${API_OK}" -ne 1 ]]; then
  echo "⏳ Attente que l'API devienne healthy (jusqu’à 60 s)…"
  for i in {1..12}; do
    sleep 5
    CODE=$("${CURL_BIN}" -k -s -o /dev/null -w "%{http_code}" "https://localhost:${HTTPS_PORT}/api/health" || true)
    echo "Tentative $i: /api/health -> ${CODE}"
    [[ "${CODE}" == "200" ]] && API_OK=1 && break
  done
fi

if [[ "${API_OK}" -ne 1 ]]; then
  echo "⚠️  API non healthy après démarrage. Consulte :"
  echo "    podman logs podman_api_1 --tail=200"
  popd >/dev/null; exit 2
fi

msg "✅ Stack STAGE opérationnelle et accessible sur :"
msg "   → http://localhost:${HTTP_PORT}/"
msg "   → https://localhost:${HTTPS_PORT}/"
msg "   → https://localhost:${HTTPS_PORT}/api/health"
msg
popd >/dev/null
