SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# ========================
# Variables (surpassables)
# ========================
OWNER       ?= GC69720
TPL_REPO    ?= social_ci-cd
APP_REPO    ?= social_applicatif
COMPONENT   ?= oci-sbom-sign.yml   # ex: oci-sbom-sign.yml ou python-django.yml
NEW_TAG     ?=                     # ex: v1.1.2  (OBLIGATOIRE)
APP_BRANCH  ?= main
GH_HOST     ?= github.com

# ================
# Targets publics
# ================
.PHONY: help
help:
	@echo "Targets:"
	@echo "  make release-template NEW_TAG=vX.Y.Z [COMPONENT=oci-sbom-sign.yml] [OWNER=GC69720] [TPL_REPO=social_ci-cd] [APP_REPO=social_applicatif]"
	@echo
	@echo "Exemples:"
	@echo "  make release-template NEW_TAG=v1.1.2 COMPONENT=oci-sbom-sign.yml"
	@echo "  make release-template NEW_TAG=v1.2.0 COMPONENT=python-django.yml"

.PHONY: release-template
release-template:
	@if [[ -z "$(NEW_TAG)" ]]; then \
		echo "ERREUR: NEW_TAG est obligatoire (ex: NEW_TAG=v1.1.2)"; exit 2; \
	fi
	@bash ./scripts/release-template.sh \
		"$(OWNER)" "$(TPL_REPO)" "$(APP_REPO)" \
		"$(COMPONENT)" "$(NEW_TAG)" \
		"$(APP_BRANCH)" "$(GH_HOST)"
