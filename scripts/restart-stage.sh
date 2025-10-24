#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Restart complet de la stack STAGE (podman-compose) sous Git Bash/Windows
# - Chemin RELATIF pour le compose (-f infra/podman/...)
# - Désactive la conversion MSYS des arguments (MSYS2_ARG_CONV_EXCL="*")
# - Auto-détection de curl/sleep (Git Bash compat)
# - Optionnel : injection du certificat entreprise dans la VM Podman
# -------------------------------------------------------------------

die() {
  echo "ERREUR: $*" >&2
  exit 1
}

msg() {
  echo "$*"
}

# --- Auto-détection curl / sleep -----------------------------------
CURL_BIN="${CURL_BIN:-$(command -v curl  || true)}"
if [[ -z "${CURL_BIN}" && -x "/mingw64/bin/curl" ]]; then CURL_BIN="/mingw64/bin/curl"; fi
SLEEP_BIN="${SLEEP_BIN:-$(command -v sleep || true)}"
if [[ -z "${SLEEP_BIN}" && -x "/usr/bin/sleep" ]]; then SLEEP_BIN="/usr/bin/sleep"; fi
if [[ -z "${CURL_BIN}" || -z "${SLEEP_BIN}" ]]; then
  die "'curl' ou 'sleep' introuvable dans le PATH. Définis CURL_BIN/SLEEP_BIN ou installe-les."
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
INSTALL_ENTERPRISE_CA="${INSTALL_ENTERPRISE_CA:-0}" # 1 = (ré)injecter le CA entreprise dans la VM Podman
ENTERPRISE_CA_PATH="${ENTERPRISE_CA_PATH:-infra/certs/enterprise-root-ca.pem}"
PODMAN_MACHINE_NAME="${PODMAN_MACHINE_NAME:-}"
RESTART_PODMAN_AFTER_CA="${RESTART_PODMAN_AFTER_CA:-1}" # 1 = stop/start après maj du CA

usage() {
  cat <<EOF2
Usage:
  API_TAG=dev WEB_TAG=dev POSTGRES_PASSWORD='xxx' NO_PULL=1 SKIP_CHECKS=1 \\
  ${0##*/}

Vars:
  API_TAG / WEB_TAG             Tag des images (defaut: dev)
  POSTGRES_PASSWORD             Mot de passe Postgres (defaut: change-me-strong)
  NO_PULL=1                     Skip 'podman-compose pull'
  SKIP_CHECKS=1                 Skip vérifications HTTP/HTTPS
  INSTALL_ENTERPRISE_CA=1       Injecte infra/certs/enterprise-root-ca.pem dans la VM Podman
  ENTERPRISE_CA_PATH=<chemin>   Chemin du certificat à injecter (defaut: infra/certs/enterprise-root-ca.pem)
  PODMAN_MACHINE_NAME=<nom>     Nom explicite de la VM Podman (defaut: 1re machine listée)
  RESTART_PODMAN_AFTER_CA=0     Ne pas redémarrer la VM après injection du CA
  CURL_BIN / SLEEP_BIN          Chemins explicites si besoin
EOF2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi

msg "==> Repo root        : ${REPO_ROOT}"
msg "==> Compose (relatif): ${REL_COMPOSE_FILE}"
msg "==> API_TAG          : ${API_TAG}"
msg "==> WEB_TAG          : ${WEB_TAG}"
msg "==> POSTGRES_PASSWORD: (masqué)"
msg "==> NO_PULL          : ${NO_PULL}"
msg "==> SKIP_CHECKS      : ${SKIP_CHECKS}"
msg "==> INSTALL_CA       : ${INSTALL_ENTERPRISE_CA}"
msg "==> curl             : ${CURL_BIN}"
msg "==> sleep            : ${SLEEP_BIN}"
msg

[[ -f "${COMPOSE_PATH}" ]] || die "compose introuvable: ${COMPOSE_PATH}"

command -v podman >/dev/null 2>&1 || die "'podman' est introuvable dans le PATH. Installe Podman (voir README)."

ensure_podman_machine_running() {
  if podman info >/dev/null 2>&1; then
    return 0
  fi

  msg "==> Podman ne répond pas, tentative de démarrage de la VM…"

  if [[ -z "${PODMAN_MACHINE_NAME}" ]]; then
    PODMAN_MACHINE_NAME=$(podman machine list --format '{{.Name}}\t{{.Running}}' 2>/dev/null | head -n1 | cut -f1)
  fi

  if [[ -z "${PODMAN_MACHINE_NAME}" ]]; then
    die "Aucune VM Podman détectée. Lance 'podman machine init' puis 'podman machine start'."
  fi

  if ! podman machine inspect "${PODMAN_MACHINE_NAME}" >/dev/null 2>&1; then
    die "VM Podman '${PODMAN_MACHINE_NAME}' introuvable. Vérifie 'podman machine list'."
  fi

  podman machine start "${PODMAN_MACHINE_NAME}" >/dev/null || die "Échec du démarrage de la VM Podman '${PODMAN_MACHINE_NAME}'."

  if ! podman info >/dev/null 2>&1; then
    die "Podman reste inaccessible après le démarrage de la VM '${PODMAN_MACHINE_NAME}'."
  fi
}

install_enterprise_ca() {
  local ca_path="$1"

  [[ -f "${ca_path}" ]] || die "Certificat entreprise introuvable: ${ca_path}"

  if [[ -z "${PODMAN_MACHINE_NAME}" ]]; then
    PODMAN_MACHINE_NAME=$(podman machine list --format '{{.Name}}\t{{.Running}}' 2>/dev/null | head -n1 | cut -f1)
  fi

  if [[ -z "${PODMAN_MACHINE_NAME}" ]]; then
    die "Impossible de déterminer la VM Podman pour l'injection du CA. Utilise PODMAN_MACHINE_NAME=<nom>."
  fi

  local ca_basename
  ca_basename="$(basename "${ca_path}")"
  local dest="/etc/pki/ca-trust/source/anchors/${ca_basename}"

  msg "==> [CA] Injection de ${ca_basename} dans la VM Podman (${PODMAN_MACHINE_NAME})…"
  podman machine ssh "${PODMAN_MACHINE_NAME}" "sudo tee ${dest} >/dev/null" < "${ca_path}"
  podman machine ssh "${PODMAN_MACHINE_NAME}" "sudo update-ca-trust"

  if [[ "${RESTART_PODMAN_AFTER_CA}" == "1" ]]; then
    msg "==> [CA] Redémarrage de la VM Podman (${PODMAN_MACHINE_NAME})…"
    podman machine stop "${PODMAN_MACHINE_NAME}" >/dev/null 2>&1 || true
    podman machine start "${PODMAN_MACHINE_NAME}" >/dev/null || die "Impossible de redémarrer la VM Podman après l'injection du CA."
  fi

  ensure_podman_machine_running

  msg "==> [CA] Vérification de la présence du certificat…"
  podman machine ssh "${PODMAN_MACHINE_NAME}" "sudo ls -l /etc/pki/ca-trust/source/anchors/ | grep -i ${ca_basename}" || true
  podman machine ssh "${PODMAN_MACHINE_NAME}" "sudo trust list | grep -i ${ca_basename%.*}" || true
}

ensure_podman_machine_running

if [[ "${INSTALL_ENTERPRISE_CA}" == "1" ]]; then
  install_enterprise_ca "${ENTERPRISE_CA_PATH}"
fi

pushd "${REPO_ROOT}" >/dev/null

# Important sous Git Bash/Windows : éviter la conversion de chemins
export MSYS2_ARG_CONV_EXCL="*"

msg "==> [1/4] Arrêt de la stack (down)…"
podman-compose -f "${REL_COMPOSE_FILE}" down || true

if [[ "${NO_PULL}" != "1" ]]; then
  msg "==> [2/4] Pull des images…"
  API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  podman-compose -f "${REL_COMPOSE_FILE}" pull
else
  msg "==> [2/4] Pull SKIPPÉ (NO_PULL=1)…"
fi

msg "==> [3/4] Démarrage…"
API_TAG="${API_TAG}" WEB_TAG="${WEB_TAG}" POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
podman-compose -f "${REL_COMPOSE_FILE}" up -d

msg
msg "==> État des services :"
podman ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "podman_(db|api|web|nginx)_1" || true
msg

if [[ "${SKIP_CHECKS}" == "1" ]]; then
  msg "==> [4/4] Vérifications SKIPPÉES."
  popd >/dev/null
  exit 0
fi

msg "==> [4/4] Vérifications…"
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

msg "✅ Stack STAGE opérationnelle."
popd >/dev/null
