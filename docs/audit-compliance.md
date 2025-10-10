diff --git a//dev/null b/docs/audit-compliance.md
index 0000000000000000000000000000000000000000..0ce9407356faed4c69b19ebc10c708fe174beea3 100644
--- a//dev/null
+++ b/docs/audit-compliance.md
@@ -0,0 +1,116 @@
+# Audit & recommandations DevSecOps / RGPD
+
+Ce document fournit une analyse du template de projet **reseau-social** et liste les actions prioritaires pour atteindre un niveau de conformité DevSecOps « security & privacy by design » attendu dans un contexte européen (RGPD, CNIL), tout en s’alignant sur les bonnes pratiques GitHub Actions, OWASP ASVS 4.0.3 et ISO/IEC 27001:2022.
+
+## 1. Gouvernance & documentation
+
+| Domaine | Constats | Actions recommandées |
+| --- | --- | --- |
+| Gouvernance | Documentation éparse (README, RUNBOOK) mais absence de _policies_ sécurité/gestion des données. | • Créer une charte sécurité (Security Policy) et un process de divulgation responsable (`SECURITY.md`).<br>• Ajouter un fichier `docs/architecture.md` et un _threat model_ (STRIDE ou LINDDUN) versionné.<br>• Documenter les responsabilités (RACI) incluant DPO, RSSI, équipe produit.<br>• Mettre en place une matrice de permissions GitHub (branch protection, CODEOWNERS). |
+| Gestion de la configuration | Pas de référence à une CMDB ni de mécanisme de traçabilité pour les secrets. | • Intégrer GitOps (ArgoCD/Flux) pour l’infra.<br>• Utiliser un gestionnaire de secrets (HashiCorp Vault, AWS Secrets Manager).<br>• Couvrir la rotation des secrets dans le runbook. |
+| Continuité | RUNBOOK existant mais pas de PCA/PRA. | • Ajouter scénarios de reprise, RTO/RPO et procédures de tests de PRA (au moins annuel). |
+
+## 2. CI/CD & qualité
+
+### 2.1 Couverture actuelle
+
+- Un seul job GitHub Actions (`pre-commit`) qui déclenche uniquement des hooks de formattage (ruff, black, prettier).
+- Absence de tests automatiques, de build d’images, de publication d’artefacts ou de politique de dépendances.
+
+### 2.2 Roadmap d’amélioration
+
+1. **Sécurisation des workflows**
+   - Activer les _environments_ GitHub pour séparer `dev`, `staging`, `prod` (avec approbation manuelle). Cf. [GitHub Actions Environment Protection Rules, 2024](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment).
+   - Forcer `permissions: contents: read` par défaut et octroyer les permissions minimales par job.
+   - Activer `OIDC` pour les déploiements cloud afin d’éviter les secrets statiques.
+2. **Pipeline CI complète (DevSecOps)**
+   - **Analyse statique (SAST)** : intégrer `bandit` (Python), `semgrep` (policies OWASP Top 10, GDPR data leak), `eslint`/`tsc` pour le frontend.
+   - **Gestion des dépendances** : `pip-audit`, `npm audit --omit=dev`, `safety`, `poetry export` si adoption d’un lockfile. Activer Dependabot (security & version updates) et GitHub Advanced Security (si licence).
+   - **Tests unitaires & intégration** : exécuter `pytest`/`pytest-django`, `jest`, `react-testing-library` avec coverage >80%. Publier la couverture (`coverage.xml`) et intégrer Codecov ou SonarQube.
+   - **Analyse dynamique (DAST)** : intégrer ZAP Baseline pour les PR sur l’API (après démarrage container).
+   - **IaC Security** : `checkov` ou `tfsec` sur manifests Compose/K8s, `trivy config` sur Dockerfiles.
+   - **Build & scan images** : utiliser `docker/build-push-action@v5` ou `redhat-actions/buildah-build` puis scanner avec `trivy image` (CVE + secrets + misconfiguration). Signer les images avec `cosign` (Sigstore) et publier attestations SLSA.
+   - **Policy as Code** : brancher Open Policy Agent (Conftest) sur YAML (K8s, GitHub).
+3. **CD & déploiement**
+   - Envisager un pipeline multi-stage (dev → staging → prod) avec promotion via artefacts immutables.
+   - Tester les migrations (Django `manage.py migrate`) dans un job isolé avant déploiement.
+   - Déployer via Helm/Kustomize; inclure tests de fumée (`pytest --lf`, `cypress`).
+
+## 3. Sécurité applicative & infrastructure
+
+### 3.1 Backend Django
+
+- **Durcissement** :
+  - Activer `SECURE_*` headers (`SECURE_HSTS_SECONDS`, `SECURE_SSL_REDIRECT`, `CSRF_COOKIE_SECURE`, `SESSION_COOKIE_SECURE`).
+  - Charger la configuration via variables d’environnement et `.env` chiffré (ex: SOPS + age).
+  - Séparer settings par environnement (`settings/base.py`, `settings/production.py`, `settings/development.py`).
+- **Gestion des données** : cartographier les données personnelles (profil, messages, photos), créer un _Record of Processing Activities_ (ROPA) conforme CNIL.
+- **Journalisation** : configurer log structuré (JSON) compatible SIEM (Elastic, Splunk) et activer traçabilité admin.
+- **API** : documenter via OpenAPI/DRF Spectacular, mettre en place rate limiting (ex: `django-ratelimit`), contrôle d’accès ABAC ou RBAC.
+
+### 3.2 Frontend Web & Mobile
+
+- Appliquer CSP strictes, Subresource Integrity, désactiver `dangerouslySetInnerHTML`.
+- Pour React Native : gérer chiffrement du stockage (SecureStore/Keychain) et _certificate pinning_.
+- Prévoir tests d’accessibilité (axe-core, react-axe) et conformité RGAA/WCAG 2.2 AA.
+
+### 3.3 Conteneurs & infrastructure
+
+- Utiliser des images de base minimales (Debian slim, distroless). Appliquer `USER` non-root.
+- Définir des _resource requests/limits_ (CPU/mémoire) et `seccomp`/`AppArmor` profiles.
+- Ajouter `infra/terraform` ou `infra/k8s` versionné, contrôler via pipelines (plan/apply).
+- Sur Podman/Docker Compose : utiliser volumes chiffrés, secrets via `podman secret`.
+
+## 4. Conformité RGPD & privacy by design
+
+1. **Base légale & consentement**
+   - Documenter les bases légales (consentement, intérêt légitime) pour chaque traitement. Mettre en place un gestionnaire de consentement (CMP) côté frontend conforme _TCF v2.2_.
+2. **Minimisation des données**
+   - Revue de chaque champ utilisateur, définir politiques de rétention (ex: suppression compte → purge sous 30 jours).
+   - Implémenter anonymisation/pseudonymisation (hashage sel + rotation). Utiliser `django-anonymize` pour environnements de test.
+3. **Droits des personnes**
+   - Créer endpoints/API pour exporter (portabilité) et supprimer les données (droit à l’oubli) avec traçabilité.
+   - Automatiser la réponse sous 30 jours et journaliser les demandes.
+4. **Sécurité des données**
+   - Chiffrement en transit (TLS 1.3) et au repos (PostgreSQL TDE, LUKS, ou chiffrement Cloud provider). Gérer les clés via HSM/KMS.
+   - Réaliser un DPIA (Analyse d’Impact) en identifiant risques (profilage, géolocalisation, mineurs). Mettre en place mesures (privacy UX, restriction d’accès).
+5. **Transferts internationaux**
+   - Vérifier localisation des données (UE) et clauses contractuelles (SCC 2021) si prestataires hors UE.
+6. **Journal de traitements**
+   - Maintenir un registre dans `docs/rgpd/registre-traitements.xlsx` (à créer) et automatiser la mise à jour via pipeline (ex: extraction à partir du modèle de données).
+
+## 5. Observabilité & réponse à incident
+
+- Mettre en place `OpenTelemetry` (trace + metrics) côté backend et frontend, exporter vers Grafana Tempo/Loki/Prometheus.
+- Configurer alerting (SLO/SLI) : latence API, taux d’erreur, durée de traitement des demandes RGPD.
+- Définir un plan de réponse à incident (IRP) incluant runbooks pour fuite de données, indisponibilité, compromission de compte.
+- Ajouter tests de chaos engineering (Litmus, Chaos Mesh) sur environnements pré-production.
+
+## 6. Checklist de mise en conformité (phase MVP)
+
+| Priorite | Action | Responsable | Echeance suggeree |
+| --- | --- | --- | --- |
+| **P0** | Securiser secrets GitHub (OIDC, Dependabot, branch protection) | DevSecOps Lead | Semaine 1 |
+| **P0** | Mettre en place SAST (bandit, semgrep) & tests unitaires automatises | Equipe Backend/Frontend | Semaine 2 |
+| **P0** | DPO : lancer DPIA, creer registre des traitements | DPO | Semaine 2 |
+| **P1** | Politique securite (`SECURITY.md`), plan de reponse incident | RSSI | Mois 1 |
+| **P1** | CI/CD : build & scan images, IaC scanning, cosign | DevSecOps | Mois 1 |
+| **P1** | Consentement utilisateur & gestion des droits RGPD | Product Owner + Frontend | Mois 2 |
+| **P2** | Observabilite unifiee (OpenTelemetry, Grafana) | SRE | Mois 2 |
+| **P2** | Tests d'intrusion externes & revues de code tierces | Partenaire securite | Avant mise en prod |
+
+## 7. Prochaines étapes proposées
+
+1. **Sprint 0 Sécurité** : ateliers _threat modeling_, définition des politiques, backlog sécurité priorisé dans Jira/Linear.
+2. **Implémentation CI/CD** : créer pipeline multi-jobs (`lint`, `test`, `build`, `scan`, `deploy`) avec matrices et caches.
+3. **RGPD** : initier DPIA, intégrer exigences CNIL dans les user stories (étiquette `privacy`).
+4. **Revue trimestrielle** : audit interne aligné ISO 27001 A.5-A.18, suivi des KPIs (taux de vulnérabilité corrigée <30 jours, couverture tests >85%).
+
+---
+
+**Références principales**
+- CNIL, « Privacy by design : 7 étapes pour intégrer la protection des données », 2023.
+- ANSSI, « Guide d’hygiène informatique », version 2.3 (2024).
+- OWASP ASVS 4.0.3 (2023), OWASP SAMM 2.1 (2023).
+- GitHub Docs, « Security hardening for GitHub Actions », 2024.
+- ENISA, « Guidelines on Security Measures for Digital Services », 2024.
