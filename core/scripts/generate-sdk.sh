#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/web/src/generated"
mkdir -p "$OUT"
npx --yes openapi-typescript "$ROOT/core/openapi/openapi.yaml" --output "$OUT/api-types.ts"
echo "SDK TS généré dans web/src/generated/api-types.ts"
