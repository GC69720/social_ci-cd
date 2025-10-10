#!/usr/bin/env bash
# scripts/push_to_github.sh
#
# Usage:
#   bash scripts/push_to_github.sh \
#     --owner YOUR_GH_USER_OR_ORG \
#     --name template_projet \
#     --visibility private \
#     --protocol https \
#     --set-template true \
#     --set-secrets false \
#     --ssh-host 1.2.3.4 --ssh-user deploy --ssh-key-path ~/.ssh/id_ed25519 --deploy-dir /opt/template_projet \
#     --ghcr-token ''   # vide = on n'envoie pas ce secret (GITHUB_TOKEN par défaut suffit souvent)
#
# Idempotent:
#  - Le script détecte un remote/dépôt déjà configuré et n’écrase rien.
#  - n'écrase pas un remote origin existant (le réutilise)
#  - crée le repo GitHub s'il n'existe pas (avec gh), sinon saute
#  - définit is_template=true si demandé (ignore l'erreur si déjà fait)
#  - crée les secrets si demandés et disponibles, sinon saute
#  - pousse la branche locale (main par défaut) sans force
#
#usage :
# Exemple simple (création + push + template) :
# bash scripts/push_to_github.sh --owner GC69720 --name template_projet --visibility private --set-template true
#
#Exemple avec secrets de déploiement :
# bash scripts/push_to_github.sh \
#  --owner YOUR_GH_USER --name template_projet \
#  --set-template true --set-secrets true \
#  --ssh-host 1.2.3.4 --ssh-user deploy \
#  --ssh-key-path ~/.ssh/id_ed25519 \
#  --deploy-dir /opt/template_projet
#



set -euo pipefail

# --- Defaults ---
OWNER=""
REPO_NAME="template_projet"
VISIBILITY="private"          # private|public|internal
PROTOCOL="https"              # https|ssh
SET_TEMPLATE="true"
SET_SECRETS="false"

SSH_HOST="${SSH_HOST:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
DEPLOY_DIR="${DEPLOY_DIR:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"  # Optionnel: beaucoup de cas fonctionnent avec GITHUB_TOKEN par défaut

# --- Helpers ---
log()  { printf "\033[36m[push]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[warn]\033[0m %s\n" "$*" >&2; }
err()  { printf "\033[31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || return 1; }

usage() {
  sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="${2:-}"; shift 2;;
    --name) REPO_NAME="${2:-}"; shift 2;;
    --visibility) VISIBILITY="${2:-}"; shift 2;;
    --protocol) PROTOCOL="${2:-}"; shift 2;;
    --set-template) SET_TEMPLATE="${2:-}"; shift 2;;
    --set-secrets)  SET_SECRETS="${2:-}"; shift 2;;
    --ssh-host) SSH_HOST="${2:-}"; shift 2;;
    --ssh-user) SSH_USER="${2:-}"; shift 2;;
    --ssh-key-path) SSH_KEY_PATH="${2:-}"; shift 2;;
    --deploy-dir) DEPLOY_DIR="${2:-}"; shift 2;;
    --ghcr-token) GHCR_TOKEN="${2:-}"; shift 2;;
    -h|--help) usage;;
    *) warn "Arg inconnu: $1"; shift;;
  esac
done

# --- Sanity checks ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Initialisation d'un dépôt Git local…"
  git init
fi

# Déterminer la branche courante, fallback sur main
if ! CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)"; then
  CURRENT_BRANCH="main"
  git checkout -b "$CURRENT_BRANCH" >/dev/null 2>&1 || true
fi

# Commit initial si aucun commit
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  log "Aucun commit détecté → commit initial"
  git add -A
  git commit -m "chore: bootstrap"
fi

# Déduire OWNER/REPO depuis le remote origin s'il existe déjà
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ -n "$REMOTE_URL" ]]; then
  log "Remote origin déjà présent: $REMOTE_URL"
  if [[ "$REMOTE_URL" =~ github\.com[:/]+([^/]+)/([^/.]+)(\.git)?$ ]]; then
    OWNER="${OWNER:-${BASH_REMATCH[1]}}"
    REPO_NAME="${REPO_NAME:-${BASH_REMATCH[2]}}"
  fi
fi

# Essayer d'inférer OWNER via gh si non fourni
if [[ -z "$OWNER" ]] && need gh; then
  if gh auth status >/dev/null 2>&1; then
    OWNER="$(gh api user -q .login 2>/dev/null || true)"
  fi
fi

if [[ -z "$OWNER" ]]; then
  if [[ -n "$REMOTE_URL" ]]; then
    log "OWNER déduit du remote."
  else
    err "OWNER introuvable. Passe --owner YOUR_GH_USER (ou configure un origin GitHub avant)."
  fi
fi

# Construire l'URL remote selon le protocole souhaité (s'il faut créer)
REMOTE_HTTPS="https://github.com/${OWNER}/${REPO_NAME}.git"
REMOTE_SSH="git@github.com:${OWNER}/${REPO_NAME}.git"
TARGET_REMOTE="$REMOTE_HTTPS"
[[ "$PROTOCOL" == "ssh" ]] && TARGET_REMOTE="$REMOTE_SSH"

# --- Création du repo si besoin (avec gh) ---
REPO_EXISTS="false"
if need gh && gh auth status >/dev/null 2>&1; then
  if gh repo view "${OWNER}/${REPO_NAME}" >/dev/null 2>&1; then
    REPO_EXISTS="true"
    log "Repo GitHub ${OWNER}/${REPO_NAME} existe déjà → ok"
  else
    log "Création du repo GitHub ${OWNER}/${REPO_NAME} (visibility=${VISIBILITY})…"
    CREATE_FLAGS=( "--${VISIBILITY}" "--source=." "--disable-issues=false" )
    # gh repo create échoue si --source=. ET repo non vide ; on fallback vers --confirm + ajouter remote ensuite
    if ! gh repo create "${OWNER}/${REPO_NAME}" "${CREATE_FLAGS[@]}" --public 2>/dev/null; then
      # Fallback robuste : créer sans --source puis lier/pousser
      gh repo create "${OWNER}/${REPO_NAME}" "--${VISIBILITY}" --confirm
    fi
    REPO_EXISTS="true"
  fi
else
  warn "gh non disponible ou non connecté → skip création/paramétrage GitHub."
fi

# --- Config remote origin (idempotent) ---
if [[ -z "$REMOTE_URL" ]]; then
  log "Ajout du remote origin → $TARGET_REMOTE"
  git remote add origin "$TARGET_REMOTE"
else
  log "Remote origin conservé (pas de modification)."
fi

# --- Pousser la branche courante ---
log "Push vers origin ${CURRENT_BRANCH}…"
git push -u origin "$CURRENT_BRANCH" || {
  warn "Push non réussi (divergence ?). Essayez un pull/rebase puis relancez."
  exit 1
}

# --- Marquer en template si demandé & possible ---
if [[ "$SET_TEMPLATE" == "true" ]] && need gh && [[ "$REPO_EXISTS" == "true" ]]; then
  log "Marquage du dépôt en Template repository…"
  if ! gh api -X PATCH "repos/${OWNER}/${REPO_NAME}" -f is_template=true >/dev/null 2>&1; then
    warn "Impossible de définir is_template=true (droits/org ?). Étape ignorée."
  fi
else
  [[ "$SET_TEMPLATE" == "true" ]] || log "Marquage template non demandé."
fi

# --- Secrets CI/CD (optionnels) ---
if [[ "$SET_SECRETS" == "true" ]]; then
  if ! need gh; then
    warn "gh requis pour définir des secrets → étape ignorée."
  else
    log "Définition des secrets (si valeurs fournies)…"
    # Secrets déploiement SSH
    [[ -n "$SSH_HOST"    ]] && gh secret set SSH_HOST   -b"$SSH_HOST"   -R "${OWNER}/${REPO_NAME}" || true
    [[ -n "$SSH_USER"    ]] && gh secret set SSH_USER   -b"$SSH_USER"   -R "${OWNER}/${REPO_NAME}" || true
    [[ -n "$DEPLOY_DIR"  ]] && gh secret set DEPLOY_DIR -b"$DEPLOY_DIR" -R "${OWNER}/${REPO_NAME}" || true
    if [[ -n "$SSH_KEY_PATH" && -r "$SSH_KEY_PATH" ]]; then
      gh secret set SSH_KEY -R "${OWNER}/${REPO_NAME}" < "$SSH_KEY_PATH" || true
    fi
    # GHCR token optionnel
    [[ -n "$GHCR_TOKEN"  ]] && gh secret set GHCR_TOKEN -b"$GHCR_TOKEN" -R "${OWNER}/${REPO_NAME}" || true
  fi
fi

log "Terminé ✅"
log "Repo: https://github.com/${OWNER}/${REPO_NAME}"
