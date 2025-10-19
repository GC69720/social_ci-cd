# Runbook — Réseau Social – Développement (Prod & R&D)

> **Emplacement du fichier :** `social_ci-cd/docs/runbook.md`
>
> **Autres emplacements clés (référence) :**
>
> * `social_ci-cd/docs/architecture.md` (schémas/ADR)
> * `social_applicatif/core/openapi/openapi.yaml` (spec API)
> * `social_applicatif/core/scripts/generate-sdk.sh|ps1` (génération SDK)

---

## 1) Contexte & objectifs

Ce runbook est le document vivant de pilotage du projet **Réseau Social – Développement (Prod & R&D)**. Il trace :

* le périmètre fonctionnel (MVP),
* l’architecture technique, la sécurité et l’infra,
* le CI/CD, la qualité, et la conformité,
* la roadmap, les décisions (ADR) et l’historique des jalons.

> **Statut du projet :** Phase 0 → structure créée (6 conversations thématiques actives).

---

## 2) Organisation des dépôts (Option 2 retenue)

* **`social_applicatif/`** : code applicatif

  * `backend/` — API Django (auth JWT, posts, comments, follow, notifications)
  * `frontend/` — App Web (React)
  * `core/` — `openapi/openapi.yaml`, `scripts/generate-sdk.(sh|ps1)`
* **`social_ci-cd/`** : outillage & documentation

  * `infra/` — IaC, podman-compose, config NGINX
  * `docs/` — `runbook.md`, `architecture.md`, checklists
  * `workflows/` — modèles de pipelines GitHub Actions (backend/frontend)

---

## 3) Branches & conventions

* **Branches** : `main` (protégée) • `develop` • `feature/*`
* **Conventional Commits** : `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `ci:`
* **Versionnage** : SemVer (MAJOR.MINOR.PATCH)

---

## 4) Roadmap MVP (synthèse)

* **S1–S2** : Conception fonctionnelle + schéma API
* **S3–S4** : Backend (Auth JWT, Posts, Comments) + Frontend (Login, Register, Feed)
* **S5** : CI/CD stable (Podman), tests auto, scans (SAST/Déps)
* **S6** : Déploiement Staging + sécurité de base
* **S7–S8** : UX/perf/bugfix → MVP **Beta**

> ** Jalons :** MVP α → β → RC → 1.0

---

## 5) Conversations thématiques → livrables

### 5.1 Conception fonctionnelle

* **Livrables** : Cahier de conception (MVP), 3–4 personas, 5 parcours clés, backlog EPIC/US, critères d’acceptation (Gherkin)
* **Ébauches attendues** : 3 personas, 5 parcours, 10 US MVP (avec critères)
* **Lien de conversation** : *à renseigner*

### 5.2 Backend Django – API & Auth

* **Livrables** : Schéma ER, spec OpenAPI (MVP), app Django modulaire, tests unitaires/integration
* **Ébauches attendues** : ER minimal (User, Profile, Post, Comment, Follow, Like, Notification), JWT, CRUD posts/comments
* **Fichiers** : `social_applicatif/core/openapi/openapi.yaml`

### 5.3 Frontend React – App Web

* **Livrables** : Arbo React, pages clés, composants réutilisables, routes, tests E2E (Playwright)
* **Ébauches attendues** : Squelette routes/pages/composants, services API typés, gestion d’erreurs

### 5.4 CI/CD – Podman, Tests & Qualité

* **Livrables** : Workflows GitHub Actions (lint/test/build/scan), images Podman, badges, stratégie de branches
* **Ébauches attendues** : jobs séparés backend/frontend, gate sur qualité, scan dépendances
* **Fichiers** : `social_ci-cd/workflows/*.yml` (modèles)

### 5.5 Sécurité & Conformité (DevSecOps)

* **Livrables** : Politique secrets, checklist RGPD, CSP/Headers, sécurité JWT, rate limiting, plan réponse incident
* **Ébauches attendues** : snippets Django/NGINX (headers/throttling), conservation des logs, DPIA (si nécessaire)

### 5.6 Infrastructure & Déploiement (Rocky/AlmaLinux)

* **Livrables** : podman-compose (dev/stage/prod), reverse proxy NGINX, SSL, Postgres, observabilité
* **Ébauches attendues** : Architecture réseau, healthchecks, supervision (logs/metrics/alertes)
* **Fichiers** : `social_ci-cd/infra/podman-compose.prod.yml`, conf NGINX

---

## 6) Tableaux d’avancement (à jour)

### 6.1 Backlog minimal MVP (top 10 US)

| ID     | En tant que… | Je veux…           | Afin de…                  | Statut  | Lien  |
| ------ | ------------ | ------------------ | ------------------------- | ------- | ----- |
| US-001 | Visiteur     | Créer un compte    | Accéder à la plateforme   | À faire | *tbd* |
| US-002 | Utilisateur  | Me connecter       | Accéder à mon feed        | À faire | *tbd* |
| US-003 | Utilisateur  | Publier un post    | Partager du contenu       | À faire | *tbd* |
| US-004 | Utilisateur  | Commenter un post  | Interagir                 | À faire | *tbd* |
| US-005 | Utilisateur  | Suivre un profil   | Personnaliser mon feed    | À faire | *tbd* |
| US-006 | Utilisateur  | Aimer un post      | Signifier mon intérêt     | À faire | *tbd* |
| US-007 | Utilisateur  | Éditer mon profil  | Maintenir mes infos       | À faire | *tbd* |
| US-008 | Utilisateur  | Voir notifications | Suivre l’activité         | À faire | *tbd* |
| US-009 | Utilisateur  | Rechercher         | Trouver des posts/profils | À faire | *tbd* |
| US-010 | Admin        | Modérer du contenu | Sécurité et conformité    | À faire | *tbd* |

### 6.2 Checklist migration depuis « Préparatifs »

* [ ] Créer le projet **Réseau Social – Dev**
* [ ] Créer les 6 conversations thématiques
* [ ] Copier/adapter le runbook existant → `social_ci-cd/docs/runbook.md`
* [ ] Mettre à jour la roadmap (α → β → RC → 1.0)
* [ ] Repointer les pipelines CI/CD (repos/branches)
* [ ] Ouvrir 10 premières US dans GitHub (labels, milestones)

---

## 7) CI/CD (vue d’ensemble)

* **Pipelines** : workflows séparés backend/frontend (lint → test → build image → scan → push registry)
* **Conteneurisation** : Podman (rootless si possible), `podman-compose`
* **Qualité** : flake8/ruff, pytest, jest/playwright, scans dépendances (pip-audit, npm audit, trivy)
* **Artefacts** : images versionnées par tag `app@sha` et `vX.Y.Z`

**Répertoires cibles :** `social_ci-cd/workflows/` pour les modèles, référencés dans chaque repo via `/.github/workflows` ou reusables workflows.

---

## 8) Sécurité & conformité

* **Secrets** : GitHub Environments/Actions + rotation, pas de secrets en clair dans les repos
* **JWT** : algorithme robuste (RS256/EdDSA), TTL, refresh, blacklist en cas de révocation
* **Headers** : CSP, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
* **Rate limiting** : NGINX (ou DRF throttling) — profils par route sensible
* **RGPD** : registre traitements, politique conservation, droit à l’effacement, cookies/consentement
* **Logs & audit** : niveau, rétention, pseudonymisation, accès restreint

---

## 9) Environnements & déploiement

* **Dev** : images locales, hot-reload, db volatile
* **Staging** : proche prod, données masquées/anonymisées
* **Prod** : NGINX + API + WEB + Postgres, backups, monitoring

**Fichiers cibles** : `social_ci-cd/infra/podman-compose.{dev,stage,prod}.yml`, conf NGINX, scripts de déploiement Rocky/AlmaLinux

---

## 10) Architecture & ADR

* **`social_ci-cd/docs/architecture.md`** :

  * Diagrammes contexte/container/components (C4)
  * Décisions ADR (format court) — **répertoire** : `social_ci-cd/docs/adr/ADR-0001-<titre>.md`

**Modèle ADR (extrait)**

```
# ADR-XXXX — Titre
Date: YYYY-MM-DD
Contexte
Décision
Conséquences
Liens & Alternatives
```

---

## 11) Release & qualité (checklists)

**Avant merge vers `main` :**

* [ ] Tests unitaires & intégration verts
* [ ] Lint & format OK
* [ ] Scans dépendances sans vulnérabilités bloquantes
* [ ] Changelog mis à jour
* [ ] Version bump SemVer

**Avant déploiement prod :**

* [ ] Tag & image immutables
* [ ] Migration DB validée
* [ ] Rollback plan documenté
* [ ] Monitoring & alertes actifs

---

## 12) Historique des jalons

| Date       | Jalons             | Détails                |
| ---------- | ------------------ | ---------------------- |
| 2025-10-19 | Phase 0 structurée | 6 conversations créées |

---

## 13) Liens utiles (à compléter)

* Board GitHub : *tbd*
* Doc RGPD interne : *tbd*
* Registry de conteneurs : *tbd*

---

## 14) Annexes

* Modèle User Story : `En tant que [persona], je veux [objectif] afin de [valeur].` + critères Gherkin
* Glossaire minimal : MVP, ADR, CI/CD, SAST, IaC, etc.
