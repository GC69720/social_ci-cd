#!/usr/bin/env bash
set -euo pipefail

# Args
OWNER="${1:-}"
TPL_REPO="${2:-}"
APP_REPO="${3:-}"
COMPONENT="${4:-}"      # ex: oci-sbom-sign.yml (ou chemin complet .github/workflows/oci-sbom-sign.yml)
NEW_TAG="${5:-}"        # ex: v1.1.2
APP_BRANCH="${6:-main}"
GH_HOST="${7:-github.com}"

# Config
WORKDIR="$(pwd)"
TMP_DIR="${WORKDIR}/.tmp/release-template"
TPL_URL="https://${GH_HOST}/${OWNER}/${TPL_REPO}.git"
APP_URL="https://${GH_HOST}/${OWNER}/${APP_REPO}.git"

# Checks
command -v git >/dev/null 2>&1 || { echo "git requis"; exit 1; }
if ! command -v gh >/dev/null 2>&1; then
  echo "gh (GitHub CLI) non trouvé. Installe-le ou fais la PR manuellement."
  echo "-> https://cli.github.com/  puis 'gh auth login'"
fi

echo "=== Paramètres ==="
echo "OWNER=${OWNER}"
echo "TPL_REPO=${TPL_REPO}"
echo "APP_REPO=${APP_REPO}"
echo "COMPONENT=${COMPONENT}"
echo "NEW_TAG=${NEW_TAG}"
echo "APP_BRANCH=${APP_BRANCH}"
echo "GH_HOST=${GH_HOST}"
echo "=================="

# Normalise le chemin du composant
if [[ "${COMPONENT}" != ".github/workflows/"* ]]; then
  COMPONENT_PATH=".github/workflows/${COMPONENT}"
else
  COMPONENT_PATH="${COMPONENT}"
fi
COMPONENT_BASENAME="$(basename "${COMPONENT_PATH}")"

# Prépare espace de travail
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

# 1) Tag dans le repo templates
echo ">> Clone templates: ${TPL_URL}"
git clone --depth=1 "${TPL_URL}" "${TMP_DIR}/${TPL_REPO}"
pushd "${TMP_DIR}/${TPL_REPO}" >/dev/null

git fetch --tags --quiet

if [[ ! -f "${COMPONENT_PATH}" ]]; then
  echo "ERREUR: composant introuvable dans templates: ${COMPONENT_PATH}"
  exit 3
fi

# Si le tag existe déjà, on ne le recrée pas
if git rev-parse "${NEW_TAG}" >/dev/null 2>&1; then
  echo "Tag ${NEW_TAG} existe déjà dans ${TPL_REPO} -> on le réutilise."
else
  echo "Création du tag ${NEW_TAG} dans ${TPL_REPO}…"
  git tag -a "${NEW_TAG}" -m "${COMPONENT_BASENAME} ${NEW_TAG}"
  git push origin "${NEW_TAG}"
fi

# Résout le SHA (utile si tu veux pinner par SHA dans l'app)
NEW_SHA="$(git rev-list -n 1 "${NEW_TAG}")"
echo "Tag ${NEW_TAG} -> ${NEW_SHA}"
popd >/dev/null

# 2) Bump dans le repo applicatif + PR
echo ">> Clone app: ${APP_URL}"
git clone --depth=1 "${APP_URL}" "${TMP_DIR}/${APP_REPO}"
pushd "${TMP_DIR}/${APP_REPO}" >/dev/null

git fetch origin "${APP_BRANCH}" --quiet
git checkout -B "chore/bump-${COMPONENT_BASENAME}-${NEW_TAG}" "origin/${APP_BRANCH}"

# Remplacement ciblé: lignes 'uses: OWNER/TPL_REPO/.github/workflows/COMPONENT@<ref>'
echo "Mise à jour des workflows appelant ${COMPONENT_BASENAME} -> ${NEW_TAG}…"
shopt -s globstar nullglob
MODIFIED=0
for f in .github/workflows/**/*.yml .github/workflows/**/*.yaml; do
  [[ -f "$f" ]] || continue
  BEFORE="$(grep -nE "uses:\s*${OWNER}/${TPL_REPO}/\.github/workflows/${COMPONENT_BASENAME}@" "$f" || true)"
  if [[ -n "$BEFORE" ]]; then
    sed -i -E "s|(uses:\s*${OWNER}/${TPL_REPO}/\.github/workflows/${COMPONENT_BASENAME}@)[^[:space:]]+|\1${NEW_TAG}|g" "$f"
    AFTER="$(grep -nE "uses:\s*${OWNER}/${TPL_REPO}/\.github/workflows/${COMPONENT_BASENAME}@" "$f" || true)"
    echo "--- $f"
    echo "AVANT:"
    echo "$BEFORE"
    echo "APRES:"
    echo "$AFTER"
    MODIFIED=1
  fi
done

if [[ "${MODIFIED}" -eq 0 ]]; then
  echo "Aucun fichier workflow ne référence ${COMPONENT_BASENAME} — rien à mettre à jour."
  echo "On crée quand même une PR vide pour traçabilité ? (non)"
  popd >/dev/null
  echo "Terminé."
  exit 0
fi

git add .github/workflows
git commit -m "ci: bump ${COMPONENT_BASENAME} -> templates@${NEW_TAG}"
git push -u origin "chore/bump-${COMPONENT_BASENAME}-${NEW_TAG}"

if command -v gh >/dev/null 2>&1; then
  echo "Ouverture de la PR…"
  gh pr create --fill --base "${APP_BRANCH}" --title "ci: bump ${COMPONENT_BASENAME} -> templates@${NEW_TAG}" --body "Automatisation: tag ${NEW_TAG} dans ${OWNER}/${TPL_REPO} + bump du caller.\n\nComposant: ${COMPONENT_PATH}\nSHA du tag: ${NEW_SHA}"
  echo "PR créée. Review & merge quand la CI est verte."
else
  echo "GitHub CLI indisponible. Ouvre la PR manuellement depuis la branche: chore/bump-${COMPONENT_BASENAME}-${NEW_TAG}"
fi

popd >/dev/null

echo "✔ Done."
