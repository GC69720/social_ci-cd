diff --git a/README.md b/README.md
index 55eebb12ca4e71ebb92a8c3447a7ebb0f7094bb7..c09416146e619f32bacaec828d743a7847dcfab5 100644
--- a/README.md
+++ b/README.md
@@ -12,25 +12,30 @@ Projet de réseau social cross-plateforme avec :
 ## Structure du dépôt
 
 reseau-social/
 
 ### ├─ backend/ # Django apps et API
 
 ### ├─ frontend/ # Frontend web et mobile
 
 ### ├─ core/ # OpenAPI spec et SDK (Roadmap étape 4)
 
 ### ├─ infra/ # Compose, k8s, scripts
 
 ### ├─ .github/ # Workflows CI/CD
 
 ### ├─ RUNBOOK.md # Documentation des procédures
 
 ### └─ README.md # Ce fichier
 
 ## Démarrage rapide
 
 1. **Lancer Podman machine** (voir `RUNBOOK.md`)
 2. **Démarrer les services** :
    ```bash
    podman-compose -f infra/compose/podman-compose.yml up -d
    ```
+
+## Conformité & DevSecOps
+
+- Consulter [`docs/audit-compliance.md`](docs/audit-compliance.md) pour l'analyse RGPD/DevSecOps et la feuille de route de mise en
+  conformité.
