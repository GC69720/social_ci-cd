#!/usr/bin/env bash
# Restart the staging environment end-to-end (build, deploy, health-check).
#
# The script assumes passwordless SSH access (public key) to the staging host and
# requires a container runtime that supports the `compose` subcommand (Docker or
# Podman 4.0+). All parameters can be provided through environment variables or a
# dotenv file (see `ENV_FILE`).
set -Eeuo pipefail

# ----------------------------- configuration ---------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

DEFAULT_ENV_FILE="$ROOT_DIR/.env.stage"
if [[ ! -f "$DEFAULT_ENV_FILE" && -f "$SCRIPT_DIR/.env.stage" ]]; then
  DEFAULT_ENV_FILE="$SCRIPT_DIR/.env.stage"
fi
ENV_FILE=${ENV_FILE:-$DEFAULT_ENV_FILE}

log() {
  local level="$1"; shift
  printf '[%s] [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$*" >&2
}

die() {
  local code=${2:-1}
  log "ERROR" "$1"
  exit "$code"
}

if [[ -n "${ENV_FILE:-}" && -f "$ENV_FILE" ]]; then
  log INFO "Loading environment from $ENV_FILE"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  log INFO "No env file found at ${ENV_FILE:-<unset>} (skipping)"
fi

# Required configuration keys
REQUIRED_VARS=(
  STAGE_SSH_HOST
  STAGE_SSH_USER
  STAGE_PROJECT_DIR
  STAGE_COMPOSE_FILE
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    die "Missing required variable: $var"
  fi
done

# Optional configuration with defaults
STAGE_SSH_PORT=${STAGE_SSH_PORT:-22}
STAGE_RUNTIME=${STAGE_RUNTIME:-docker}
STAGE_SSH_OPTIONS=${STAGE_SSH_OPTIONS:-"-o BatchMode=yes"}
STAGE_REMOTE_ENV_FILE=${STAGE_REMOTE_ENV_FILE:-}
STAGE_PRE_DEPLOY_HOOK=${STAGE_PRE_DEPLOY_HOOK:-}
STAGE_POST_DEPLOY_HOOK=${STAGE_POST_DEPLOY_HOOK:-}
STAGE_HEALTHCHECK_URLS=${STAGE_HEALTHCHECK_URLS:-}
STAGE_HEALTHCHECK_TIMEOUT=${STAGE_HEALTHCHECK_TIMEOUT:-300}
STAGE_HEALTHCHECK_INTERVAL=${STAGE_HEALTHCHECK_INTERVAL:-5}
STAGE_HEALTHCHECK_EXPECT=${STAGE_HEALTHCHECK_EXPECT:-200}

# ------------------------------ validations ----------------------------------
for bin in ssh curl "$STAGE_RUNTIME"; do
  if ! command -v ${bin%% *} >/dev/null 2>&1; then
    die "Required binary '$bin' not found in PATH"
  fi
done

SSH_TARGET="${STAGE_SSH_USER}@${STAGE_SSH_HOST}"
COMPOSE_FILE="$STAGE_COMPOSE_FILE"

# --------------------------- helper functions --------------------------------
run_remote() {
  local description="$1"
  log INFO "$description"
  ssh $STAGE_SSH_OPTIONS -p "$STAGE_SSH_PORT" "$SSH_TARGET" bash -se -- \
    "$STAGE_REMOTE_ENV_FILE" \
    "$STAGE_RUNTIME" \
    "$STAGE_PROJECT_DIR" \
    "$COMPOSE_FILE" \
    "$STAGE_PRE_DEPLOY_HOOK" \
    "$STAGE_POST_DEPLOY_HOOK" <<'__REMOTE_SCRIPT__'
STAGE_REMOTE_ENV_FILE="$1"
RUNTIME="$2"
PROJECT_DIR="$3"
COMPOSE_FILE="$4"
PRE_HOOK="$5"
POST_HOOK="$6"
set -Eeuo pipefail
if [[ -n "$STAGE_REMOTE_ENV_FILE" && -f "$STAGE_REMOTE_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STAGE_REMOTE_ENV_FILE"
fi
cd "$PROJECT_DIR"
if [[ -n "$PRE_HOOK" ]]; then
  printf '[%s] [REMOTE] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "Running pre-deploy hook"
  eval "$PRE_HOOK"
fi
"$RUNTIME" compose -f "$COMPOSE_FILE" pull --quiet
"$RUNTIME" compose -f "$COMPOSE_FILE" up -d --remove-orphans
if [[ -n "$POST_HOOK" ]]; then
  printf '[%s] [REMOTE] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "Running post-deploy hook"
  eval "$POST_HOOK"
fi
__REMOTE_SCRIPT__
}

wait_for_health() {
  local url="$1"
  local deadline=$((SECONDS + STAGE_HEALTHCHECK_TIMEOUT))
  while (( SECONDS < deadline )); do
    local status
    status=$(curl --silent --show-error --max-time 10 --output /dev/null --write-out '%{http_code}' "$url" || true)
    if [[ "$status" == "$STAGE_HEALTHCHECK_EXPECT" ]]; then
      log INFO "Healthcheck succeeded for $url"
      return 0
    fi
    sleep "$STAGE_HEALTHCHECK_INTERVAL"
  done
  return 1
}

# ------------------------------ deployment -----------------------------------
run_remote "Restarting services on $SSH_TARGET"

# ----------------------------- health checks ---------------------------------
if [[ -n "$STAGE_HEALTHCHECK_URLS" ]]; then
  log INFO "Running health checks"
  IFS=$'\n' read -r -d '' -a urls < <(printf '%s\0' "$STAGE_HEALTHCHECK_URLS") || true
  for url in "${urls[@]}"; do
    if [[ -z "$url" ]]; then
      continue
    fi
    if ! wait_for_health "$url"; then
      die "Healthcheck failed for $url"
    fi
  done
else
  log INFO "No healthcheck URLs configured"
fi

log INFO "Stage restart completed successfully"
