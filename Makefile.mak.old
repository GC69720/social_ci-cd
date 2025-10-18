SHELL := /bin/bash
.DEFAULT_GOAL := help

help: ## Liste des commandes
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

init: ## Init dev (pre-commit + deps backend/web/mobile)
	python3 -m venv .venv && source .venv/bin/activate && pip install -U pip pre-commit
	pre-commit install
	cd backend && pip install -r requirements-dev.txt
	cd web && npm ci
	cd mobile && npm ci

dev: ## Lance podman-compose (backend + db + web + redis + mongo)
	podman-compose -f infra/podman/podman-compose.dev.yml up --build

down: ## Stoppe l'environnement dev
	podman-compose -f infra/podman/podman-compose.dev.yml down

test: ## Tests (backend)
	cd backend && PYTHONPATH=src pytest -q

lint: ## Lint (backend + web)
	cd backend && ruff check . && black --check .
	cd web && npm run lint

format: ## Format (backend + web)
	cd backend && ruff format . && black .
	cd web && npm run format

sdk: ## Génère SDK depuis OpenAPI
	bash core/scripts/generate-sdk.sh || pwsh core/scripts/generate-sdk.ps1

sbom: ## Génère SBOM (si syft installé)
	syft packages dir:. -o json > sbom.json || true
