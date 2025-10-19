# Architecture — Réseau Social – Développement (Prod & R&D)

> Dépôt : `social_ci-cd`  
> Emplacement : `docs/architecture.md`

## 1. Objectifs
- Donner une vue d’ensemble (C4) : Contexte → Conteneurs → Composants.
- Documenter les décisions (ADR) et leurs impacts.
- Servir de référence pour les équipes Dev, Ops, Sécurité.

## 2. Contexte (C4 — Niveau Contexte)
- **Acteurs** : Visiteur, Utilisateur, Admin, Systèmes externes (Email, CDN, Observabilité).
- **Système** : Plateforme Réseau Social (Web + API + DB + Stockage).

```mermaid
flowchart LR
    user((Utilisateur)) -->|HTTPs| web[Frontend Web]
    web -->|REST/JSON| api[API Django]
    api -->|SQL| db[(PostgreSQL)]
    api -->|Objets| media[(Stockage médias)]
    api -->|SMTP/API| email[Service Email]
    web -->|CDN| cdn[CDN/Edge]
    api -->|Logs/Metrics| obs[Observabilité]
    user -.->|Notif| notif[Notifications]
