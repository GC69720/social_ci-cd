#!/usr/bin/env bash
# Script d’auto-validation (idempotent)
#Usage : 
# Démarre, valide, puis laisse l'environnement tournant
#   bash scripts/validate_repo.sh --start
#…ou démarre, valide et stoppe tout à la fin :
#   bash scripts/validate_repo.sh --start --stop
#

set -euo pipefail

COMPOSE=infra/podman/podman-compose.dev.yml
START="false"
STOP="false"
TIMEOUT="${TIMEOUT:-60}"

usage() {
  cat <<EOF
Usage: $0 [--start] [--stop] [--timeout SEC]
  --start     : démarrer le stack (podman-compose up -d)
  --stop      : arrêter le stack à la fin
  --timeout N : délai max pour attendre le backend (defaut: $TIMEOUT)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start) START="true"; shift;;
    --stop)  STOP="true"; shift;;
    --timeout) TIMEOUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Arg inconnu: $1"; usage; exit 1;;
  esac
done

log()  { printf "\033[36m[check]\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m[ ok ]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[warn]\033[0m %s\n" "$*"; }
err()  { printf "\033[31m[err ]\033[0m %s\n" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Start stack if requested
if [[ "$START" == "true" ]]; then
  log "Démarrage du stack (podman-compose)…"
  podman-compose -f "$COMPOSE" up -d --build
fi

# Wait for backend ready
log "Attente du backend /health (timeout ${TIMEOUT}s)…"
for i in $(seq 1 "$TIMEOUT"); do
  if curl -fsS http://localhost:8000/health >/dev/null 2>&1; then
    ok "Backend UP"
    break
  fi
  sleep 1
  [[ "$i" -eq "$TIMEOUT" ]] && { err "Backend KO (time out)"; exit 1; }
done

# Health JSON
JSON=$(curl -fsS http://localhost:8000/health || true)
[[ "$JSON" == *'"status":"ok"'* ]] && ok "Health JSON ok" || { err "Health JSON invalide: $JSON"; exit 1; }

# CSP headers backend
curl -fsSI http://localhost:8000/health | grep -iq '^Content-Security-Policy:' \
  && ok "CSP header côté Django présent" || warn "CSP header côté Django manquant"

# CSP headers Next.js
if curl -fsSI http://localhost:3000/ | grep -iq '^Content-Security-Policy:'; then
  ok "CSP header côté Next.js présent"
else
  warn "CSP header côté Next.js manquant (verifier que 'web' est démarré)"
fi

# ORM basic CRUD
LIST1=$(curl -fsS http://localhost:8000/users/orm || true)
echo "$LIST1" | grep -q "^\[" && ok "users/orm GET renvoie un JSON array" || { err "users/orm GET invalide: $LIST1"; exit 1; }
CREATE=$(curl -fsS -X POST -d "email=foo@example.com" http://localhost:8000/users/orm || true)
echo "$CREATE" | grep -q '"email":"foo@example.com"' && ok "users/orm POST 201" || { err "users/orm POST invalide: $CREATE"; exit 1; }

# JWT try (admin/admin)
TOKEN=$(curl -fsS -X POST -d "username=admin&password=admin" http://localhost:8000/auth/token | sed -n 's/.*"access":"\([^"]*\)".*/\1/p' || true)
if [[ -n "$TOKEN" ]]; then
  curl -fsS -H "Authorization: Bearer $TOKEN" http://localhost:8000/me >/dev/null && ok "/me OK avec JWT" || warn "/me KO avec JWT"
else
  warn "Impossible d'obtenir un token JWT (admin/admin). As-tu lancé scripts/init_dev.sh ?"
fi

# Redis ping
if have redis-cli; then
  redis-cli -h 127.0.0.1 -p 6379 ping | grep -q PONG && ok "Redis PONG (host)" || warn "Redis ping KO (host)"
else
  RID=$(podman-compose -f "$COMPOSE" ps -q redis 2>/dev/null || true)
  if [[ -n "$RID" ]]; then
    podman exec "$RID" redis-cli ping | grep -q PONG && ok "Redis PONG (container)" || warn "Redis ping KO (container)"
  else
    warn "Redis non trouvé dans le compose"
  fi
fi

# Postgres ready
DBID=$(podman-compose -f "$COMPOSE" ps -q db 2>/dev/null || true)
if [[ -n "$DBID" ]]; then
  podman exec "$DBID" pg_isready -h 127.0.0.1 -U app -d app >/dev/null 2>&1 && ok "Postgres ready" || warn "pg_isready KO"
else
  warn "DB non trouvée dans le compose"
fi

# Mongo ping (optionnel)
curl -fsS http://localhost:8000/ping/mongo >/dev/null 2>&1 && ok "Mongo ping endpoint" || warn "Mongo ping KO (optionnel)"

# Lint + tests (rapides)
have pre-commit && pre-commit run --all-files || warn "pre-commit non installé"
make lint || { err "Lint KO"; exit 1; }
make test || { err "Tests KO"; exit 1; }

ok "Validation terminée ✅"

# Stop stack if requested
if [[ "$STOP" == "true" ]]; then
  log "Arrêt du stack (podman-compose down)…"
  podman-compose -f "$COMPOSE" down
fi
