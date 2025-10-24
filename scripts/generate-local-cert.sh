#!/usr/bin/env bash
set -e

CERTS_DIR="$(dirname "$0")/../infra/podman/certs"
mkdir -p "$CERTS_DIR"

CRT_FILE="$CERTS_DIR/localhost.crt"
KEY_FILE="$CERTS_DIR/localhost.key"

if [[ -f "$CRT_FILE" && -f "$KEY_FILE" ]]; then
  echo "✅ Certificats déjà présents : $CERTS_DIR"
  exit 0
fi

echo "🔧 Génération du certificat auto-signé pour 'localhost'..."
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout "$KEY_FILE" -out "$CRT_FILE" -days 365 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

echo "✅ Certificats générés dans : $CERTS_DIR"
