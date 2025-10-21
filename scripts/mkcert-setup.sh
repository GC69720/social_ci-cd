#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# mkcert-setup.sh
# Génère des certificats TLS locaux avec mkcert pour dev|stage|prod|all.
# - Fonctionne sous Git Bash (Windows) / Linux / macOS
# - Utilisation:
#     ./scripts/mkcert-setup.sh --env stage --restart-nginx
#     ./scripts/mkcert-setup.sh --env stage --domains preprod.social_applicatif.com,api.preprod.social_applicatif.com
#     ./scripts/mkcert-setup.sh --env all
# -------------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }
msg() { echo -e "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

CERTS_DIR="${REPO_ROOT}/infra/certs"
PODMAN_DIR="${REPO_ROOT}/infra/podman"

ENV_NAME="stage"          # dev|stage|prod|all
DOMAINS_CSV=""            # ex: "preprod.example.com,api.preprod.example.com"
RESTART_NGINX=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/mkcert-setup.sh [--env dev|stage|prod|all] [--domains d1,d2,...] [--restart-nginx]

Options:
  --env            Environnement cible (defaut: stage). "all" traite dev+stage+prod.
  --domains        Liste de domaines CSV pour l'env (sinon valeurs par défaut).
  --restart-nginx  Redémarre nginx via podman-compose pour l'env ciblé (si compose existe).
  -h|--help        Aide.

Exemples:
  ./scripts/mkcert-setup.sh --env stage --restart-nginx
  ./scripts/mkcert-setup.sh --env stage --domains preprod.social_applicatif.com,api.preprod.social_applicatif.com
  ./scripts/mkcert-setup.sh --env all
EOF
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_NAME="${2:-}"; shift 2 ;;
    --domains) DOMAINS_CSV="${2:-}"; shift 2 ;;
    --restart-nginx) RESTART_NGINX=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argument inconnu: $1 (voir --help)";;
  esac
done

# --- Pré-requis ---
command -v mkcert >/dev/null 2>&1 || die $'mkcert introuvable.\nInstalle-le (ex: choco install mkcert) puis relance.\nLien: https://github.com/FiloSottile/mkcert'

# --- Env list ---
case "${ENV_NAME}" in
  dev|stage|prod) ENVS=("${ENV_NAME}") ;;
  all)            ENVS=("dev" "stage" "prod") ;;
  *) die "ENV invalide: ${ENV_NAME} (attendu: dev|stage|prod|all)";;
esac

# --- Domaines par défaut ---
default_domains_for_env() {
  case "$1" in
    dev)   echo "dev.social_applicatif.com" ;;
    stage) echo "preprod.social_applicatif.com" ;;
    prod)  echo "prod.social_applicatif.com" ;;
    *)     die "env inconnu: $1" ;;
  esac
}

# --- CA locale mkcert (idempotent) ---
msg ">> Installation/MàJ de la CA locale mkcert (une fois par machine)…"
mkcert -install

# --- Génération certs ---
mkdir -p "${CERTS_DIR}"

for ENVX in "${ENVS[@]}"; do
  TARGET_DIR="${CERTS_DIR}/${ENVX}"
  mkdir -p "${TARGET_DIR}"

  # Domaines
  if [[ -n "${DOMAINS_CSV}" ]]; then
    IFS=',' read -r -a DOMAINS <<< "${DOMAINS_CSV}"
  else
    IFS=',' read -r -a DOMAINS <<< "$(default_domains_for_env "${ENVX}")"
  fi
  [[ ${#DOMAINS[@]} -gt 0 ]] || die "Aucun domaine pour l'env ${ENVX}"

  msg "\n=== ENV: ${ENVX} ==="
  msg "Domaine(s): ${DOMAINS[*]}"

  # mkcert génère <domain>.pem et <domain>-key.pem
  ( cd "${TARGET_DIR}" && mkcert "${DOMAINS[@]}" )

  msg "Fichiers générés dans ${TARGET_DIR}:"
  ls -1 "${TARGET_DIR}"/*.pem "${TARGET_DIR}"/*-key.pem 2>/dev/null || true

  FIRST_DOMAIN="${DOMAINS[0]}"
  msg "Chemins NGINX (volume /etc/nginx/certs) à utiliser pour ${ENVX}:"
  msg "  ssl_certificate     /etc/nginx/certs/${FIRST_DOMAIN}.pem"
  msg "  ssl_certificate_key /etc/nginx/certs/${FIRST_DOMAIN}-key.pem"

  # Redémarrage NGINX (optionnel)
  if [[ ${RESTART_NGINX} -eq 1 ]]; then
    COMPOSE_FILE="${PODMAN_DIR}/podman-compose.${ENVX}.yml"
    if [[ -f "${COMPOSE_FILE}" ]]; then
      msg "\n>> Redémarrage NGINX via podman-compose (${ENVX})…"
      MSYS2_ARG_CONV_EXCL="*" podman-compose -f "infra/podman/podman-compose.${ENVX}.yml" restart nginx
    else
      msg "(!) Compose introuvable pour ${ENVX}: ${COMPOSE_FILE} — skip restart."
    fi
  fi
done

msg "\n✅ Certificats OK."
msg "Rappels:"
msg " - Vérifie infra/nginx/<env>.conf pour pointer sur le bon .pem et -key.pem"
msg " - Redémarre la stack si la conf change: ENV=${ENV_NAME} ./scripts/restart.sh"
