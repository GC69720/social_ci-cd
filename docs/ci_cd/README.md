# Guide d'intervention CI/CD — `social_ci-cd` & `social_applicatif`

## Objectif
Mettre fin aux échecs du job `app-ci` dans `social_applicatif` lorsque `pytest` ne collecte aucun test, tout en conservant la
chaîne DevSecOps actuelle (lint, sécurité, build Docker/CodeQL). Le correctif se déroule en deux temps :
1. **Adapter le workflow réutilisable** exposé par `social_ci-cd` pour tolérer le code retour `5` de `pytest` ("no tests collected").
2. **Mettre à jour le dépôt applicatif** pour pointer vers cette version corrigée et documenter le comportement de `pytest`.

## Pré-requis
- Accès en écriture aux deux dépôts GitHub : `GC69720/social_ci-cd` et `GC69720/social_applicatif`.
- Secrets déjà configurés côté organisation (GHCR/deploy) : à vérifier mais aucune modification n'est requise pour ce correctif.
- Optionnel : GitHub CLI (`gh`) et l'outil `act` si vous souhaitez simuler le workflow localement.

## Étapes côté `social_ci-cd`
1. **Cloner et préparer la branche**
   ```bash
   git clone git@github.com:GC69720/social_ci-cd.git
   cd social_ci-cd
   git checkout -b fix/pytest-exit-code-5
   ```
2. **Remplacer complètement** le fichier `.github/workflows/python-django.yml` par la version ci-dessous (copier/coller). Cela
   encapsule `pytest` pour considérer `exit code 5` comme un succès tout en conservant les autres contrôles.
3. **Contrôles rapides** (optionnel mais recommandé) :
   ```bash
   act workflow_call -W .github/workflows/python-django.yml \
     --input run_tests=true --input enable_codeql=false
   ```
   > `act` renverra un statut de succès même si aucun test n'est collecté.
4. **Commit & push**
   ```bash
   git status
   git add .github/workflows/python-django.yml
   git commit -m "Tolérer exit code 5 de pytest dans le workflow Python"
   git push --set-upstream origin fix/pytest-exit-code-5
   ```
5. **Créer un tag** après merge (ou directement sur la branche si vous publiez sans PR) :
   ```bash
   git checkout main
   git pull
   git tag v1.1
   git push origin v1.1
   ```
   > Le dépôt applicatif pointera vers `v1.1`.

### Fichier complet à coller dans `social_ci-cd/.github/workflows/python-django.yml`
```yaml
name: python-django

on:
  workflow_call:
    inputs:
      python_version:
        description: "Version de Python à utiliser"
        type: string
        default: "3.12"
      working_directory:
        description: "Chemin de travail (racine du projet Python/Django)"
        type: string
        default: "."
      run_tests:
        description: "Exécuter la suite de tests (pytest)"
        type: boolean
        default: true
      upload_test_artifacts:
        description: "Téléverser les rapports/artefacts de tests"
        type: boolean
        default: true
      django_settings_module:
        description: "Valeur de DJANGO_SETTINGS_MODULE (vide = ne pas exécuter de checks Django)"
        type: string
        default: ""
      requirements_file:
        description: "Chemin du fichier requirements (vide = auto-detect)"
        type: string
        default: ""
      extra_install_cmd:
        description: "Commande supplémentaire d'installation (ex: pip install -e .[dev])"
        type: string
        default: ""
      enable_codeql:
        description: "Activer CodeQL (SAST)"
        type: boolean
        default: false
      docker_image_name:
        description: "Nom d'image à builder/pousser (org/app). Vide = pas de build."
        type: string
        default: ""
      docker_context:
        description: "Contexte Docker"
        type: string
        default: "."
      dockerfile:
        description: "Chemin du Dockerfile"
        type: string
        default: "Dockerfile"
      docker_build_args:
        description: "Arguments de build Docker (ex: BUILDPLATFORM=linux/amd64)"
        type: string
        default: ""
    secrets:
      CLOUD_ROLE:
        required: false

permissions:
  contents: read
  packages: write
  security-events: write
  id-token: write

jobs:
  lint-test-build:
    name: Lint • Test • (Docker/CodeQL optionnels)
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      packages: write
      security-events: write
      id-token: write
    defaults:
      run:
        working-directory: ${{ inputs.working_directory }}
        shell: bash
    env:
      PIP_DISABLE_PIP_VERSION_CHECK: "1"
      PYTHONDONTWRITEBYTECODE: "1"
      PYTHONUNBUFFERED: "1"
      CLOUD_ROLE: ${{ secrets.CLOUD_ROLE }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python ${{ inputs.python_version }}
        uses: actions/setup-python@v5
        with:
          python-version: ${{ inputs.python_version }}
          cache: "pip"
          cache-dependency-path: |
            **/requirements*.txt
            **/pyproject.toml
            **/poetry.lock

      - name: Installer dépendances (requirements/pyproject)
        run: |
          set -euo pipefail
          if [[ -n "${{ inputs.requirements_file }}" && -f "${{ inputs.requirements_file }}" ]]; then
            echo ">> Installing from ${{ inputs.requirements_file }}"
            pip install -r "${{ inputs.requirements_file }}"
          else
            if [[ -f "requirements.txt" ]]; then
              echo ">> Installing from requirements.txt"
              pip install -r requirements.txt
            fi
            if [[ -f "requirements-dev.txt" ]]; then
              echo ">> Installing from requirements-dev.txt"
              pip install -r requirements-dev.txt
            fi
            if [[ -f "pyproject.toml" ]]; then
              echo ">> Installing project (pyproject)"
              pip install -e .
            fi
          fi
          if [[ -n "${{ inputs.extra_install_cmd }}" ]]; then
            echo ">> Running extra install: ${{ inputs.extra_install_cmd }}"
            eval "${{ inputs.extra_install_cmd }}"
          fi
          pip install pre-commit pytest

      - name: pre-commit (ruff/black/isort/…)
        run: |
          set -e
          if [[ -f ".pre-commit-config.yaml" ]]; then
            pre-commit run --all-files
          else
            echo "No .pre-commit-config.yaml found; skipping."
          fi

      - name: Checks Django (optionnel)
        if: ${{ inputs.django_settings_module != '' }}
        env:
          DJANGO_SETTINGS_MODULE: ${{ inputs.django_settings_module }}
        run: |
          python - <<'PY'
          import os, sys
          settings_mod = os.environ.get("DJANGO_SETTINGS_MODULE")
          if not settings_mod:
              sys.exit("DJANGO_SETTINGS_MODULE not set")
          print(f"Running Django checks for {settings_mod}…")
          try:
              import django
              from django.core.management import call_command
          except Exception as e:
              raise SystemExit(f"Django not installed or import error: {e}")
          django.setup()
          call_command("check")
          PY

      - name: Tests (pytest)
        if: ${{ inputs.run_tests }}
        run: |
          set -euo pipefail
          mkdir -p ./test-results ./coverage
          if pytest -q --maxfail=1 --disable-warnings --junitxml=./test-results/junit.xml; then
            echo "Pytest suite executed successfully."
          else
            status=$?
            if [[ "${status}" -eq 5 ]]; then
              echo "Pytest returned exit code 5 (no tests collected); treating as success."
            else
              echo "Pytest failed with exit code ${status}." >&2
              exit "${status}"
            fi
          fi

      - name: Upload artefacts tests
        if: ${{ inputs.run_tests && inputs.upload_test_artifacts }}
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: |
            ${{ inputs.working_directory }}/test-results/**
            ${{ inputs.working_directory }}/.pytest_cache/**
          if-no-files-found: ignore
          retention-days: 7

      - name: CodeQL init (Python)
        if: ${{ inputs.enable_codeql }}
        uses: github/codeql-action/init@v3
        with:
          languages: python

      - name: CodeQL analyze
        if: ${{ inputs.enable_codeql }}
        uses: github/codeql-action/analyze@v3

      - name: Login GHCR (si build image)
        if: ${{ inputs.docker_image_name != '' }}
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build & Push Docker image (optionnel)
        if: ${{ inputs.docker_image_name != '' }}
        uses: docker/build-push-action@v6
        with:
          context: ${{ inputs.docker_context }}
          file: ${{ inputs.dockerfile }}
          push: true
          tags: |
            ghcr.io/${{ inputs.docker_image_name }}:${{ github.sha }}
            ghcr.io/${{ inputs.docker_image_name }}:ci-${{ github.run_number }}
          build-args: ${{ inputs.docker_build_args }}
```

## Étapes côté `social_applicatif`
1. **Synchroniser le tag** :
   ```bash
   git clone git@github.com:GC69720/social_applicatif.git
   cd social_applicatif
   git checkout -b chore/update-ci-workflow
   ```
2. **Mettre à jour la référence du workflow** dans `.github/workflows/ci.yml` pour consommer le tag `v1.1` (ou la branche `main` si
   vous préférez suivre les mises à jour en continu).
3. **Documenter le comportement de `pytest`** à la ligne `run_tests` pour indiquer que les codes `0` et `5` sont traités comme succès.
4. **Vérifications** :
   - Confirmez que les secrets `SSH_*`, `DEPLOY_DIR`, `GHCR_TOKEN` sont toujours présents au niveau organisation/repo.
   - Optionnel : exécutez `act pull_request -W .github/workflows/ci.yml` pour vérifier la réussite du job `app-ci`.
5. **Commit & push**
   ```bash
   git add .github/workflows/ci.yml
   git commit -m "Consommer social_ci-cd v1.1 et documenter pytest"
   git push --set-upstream origin chore/update-ci-workflow
   ```

### Bloc complet à coller dans `social_applicatif/.github/workflows/ci.yml`
> Remplacez uniquement la section `uses:` si le reste du fichier doit rester identique.
```yaml
name: app-ci

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  python-django:
    uses: GC69720/social_ci-cd/.github/workflows/python-django.yml@v1.1
    with:
      python_version: "3.12"
      working_directory: backend
      run_tests: true             # pytest renvoie 0 ou 5 (aucun test); les deux sont gérés côté workflow
      upload_test_artifacts: true
      django_settings_module: "backend.settings"
      requirements_file: "backend/requirements.txt"
      extra_install_cmd: ""
      enable_codeql: false
      docker_image_name: "gc69720/social-backend"
      docker_context: "backend"
      dockerfile: "backend/Dockerfile"
      docker_build_args: ""
    secrets:
      CLOUD_ROLE: ${{ secrets.CLOUD_ROLE }}
```

## Contrôles finaux
- Déclenchez manuellement le workflow `app-ci` sur `social_applicatif` (onglet **Actions** → **Run workflow**) pour vérifier que le
  job passe lorsque la suite de tests est vide.
- Surveillez les premiers runs pour confirmer que le build Docker continue de fonctionner (les tags `ghcr.io/...` doivent être
  publiés comme avant).
- Conservez un changelog interne indiquant que le tag `v1.1` introduit la tolérance du code retour `5`.