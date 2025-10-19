# ADR-0001 — Séparation en deux dépôts (code vs. outillage/infra)
Date: 2025-10-19

## Contexte
Besoin de séparer le code produit (apps) des artefacts d’infrastructure, workflows, et documentation d’exploitation.

## Décision
- `social_applicatif` : backend/, frontend/, core/
- `social_ci-cd` : infra/, docs/, workflows/

## Conséquences
- Positives : responsabilités claires, droits d’accès distincts, réutilisabilité des workflows.
- Négatives : synchronisation inter-repos à gérer, complexité de versionnage.

## Alternatives
- Monorepo unique (simple au départ, moins modulable ensuite).

## Liens
- Runbook : `../runbook.md`
