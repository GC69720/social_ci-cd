#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Restart de la stack Podman-Compose par environnement (dev|stage|prod)
# - --env choisit le fichier compose: infra/podman/podman-compose.${ENV}.yml
# - Vérifs HTTP/HTTPS (ignorables) + retry health API (jusqu'à 2 min)
# - Compat Git Bash (Windows) : force l'usage de /mingw64/bin/curl si dispo
# - Injection optionnelle du certificat entreprise dans la VM Podman
# - Affiche les URLs de test à ouvrir dans le navigateur en fin
# ------------------------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }
msg() { echo -e "$*"; }

# -------- Defaults (surchargés ensuite)
ENV_NAME="stage"           # dev|stage|prod
NO_PULL=0                  # 1 = ne pas faire de podman-compose pull
SKIP_CHECKS=0              # 1 = sauter les vérifications curl
ACTION="restart"          # restart|down|up
DEFAULT_POSTGRES_PASSWORD="change-me-strong"
INSTALL_ENTERPRISE_CA="${INSTALL_ENTERPRISE_CA:-0}" # 1 = (ré)injecter le CA entreprise
ENTERPRISE_CA_PATH="${ENTERPRISE_CA_PATH:-infra/certs/enterprise-root-ca.pem}"
PODMAN_MACHINE_NAME="${PODMAN_MACHINE_NAME:-}"
RESTART_PODMAN_AFTER_CA="${RESTART_PODMAN_AFTER_CA:-1}"

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
      cat <<'EOF2'
Usage:
  ./scripts/restart.sh [--env dev|stage|prod] [--no-pull] [--skip-checks] [--down-only|--up-only]

Options:
  --env           Environnement (defaut: stage)
  --no-pull       Ne pas faire 'podman-compose pull'
  --skip-checks   Ne pas faire les vérifications HTTP/HTTPS
  --down-only     Arrêter uniquement les services (pas de pull/up)
  --up-only       Démarrer uniquement (sans arrêt préalable)

Vars utiles (surchargent les defaults par ENV) :
  HOST, HTTP_PORT, HTTPS_PORT, API_TAG, WEB_TAG, POSTGRES_PASSWORD

Vars additionnelles :
  INSTALL_ENTERPRISE_CA=1     Injecte infra/certs/enterprise-root-ca.pem dans la VM Podman
  ENTERPRISE_CA_PATH=<chemin> Certificat entreprise alternatif à injecter
  PODMAN_MACHINE_NAME=<nom>   Nom explicite de la VM Podman
  RESTART_PODMAN_AFTER_CA=0   Ne pas redémarrer la VM après injection du CA
  CURL_BIN / SLEEP_BIN        Chemins explicites si besoin
EOF2
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
msg "==> INSTALL_CA        : ${INSTALL_ENTERPRISE_CA}"
msg "==> curl              : ${CURL_BIN:-<absent>}"
msg "==> sleep             : ${SLEEP_BIN:-<absent>}\n"

[[ -f "${COMPOSE_PATH}" ]] || die "Compose introuvable: ${COMPOSE_PATH}"
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
