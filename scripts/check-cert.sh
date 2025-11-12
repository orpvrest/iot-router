#!/usr/bin/env bash
set -euo pipefail

CERT_NAME=${CERTBOT_CERT_NAME:-${VPN_SNI_DOMAIN:-}}
if [[ -z "$CERT_NAME" ]]; then
  echo "CERTBOT_CERT_NAME or VPN_SNI_DOMAIN must be set" >&2
  exit 1
fi
TARGET=${1:-nginx-edge}
FILE=${2:-/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem}

docker compose exec "$TARGET" sh -c "apk add --no-cache openssl >/dev/null 2>&1 && openssl x509 -in $FILE -noout -text"
