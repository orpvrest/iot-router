#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  . "$ENV_FILE"
  set +a
fi

SCRIPT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE_DIR=${BASE_DIR:-${SCRIPT_ROOT}}
CERT_ROOT=${CERT_ROOT:-${BASE_DIR}/data/certbot/live}
mkdir -p "$CERT_ROOT"

declare -a domains=()
if [[ -n "${VPN_SNI_DOMAIN:-}" ]]; then
  domains+=("$VPN_SNI_DOMAIN")
fi
if [[ -n "${SITE_SNI_DOMAIN:-}" && "${SITE_SNI_DOMAIN}" != "${VPN_SNI_DOMAIN}" ]]; then
  domains+=("$SITE_SNI_DOMAIN")
fi

if [[ ${#domains[@]} -eq 0 ]]; then
  echo "No domains specified; set VPN_SNI_DOMAIN or SITE_SNI_DOMAIN" >&2
  exit 1
fi

for domain in "${domains[@]}"; do
  target="${CERT_ROOT}/${domain}"
  mkdir -p "$target"
  openssl req -x509 -nodes -newkey rsa:4096 \
    -subj "/CN=${domain}" \
    -keyout "${target}/privkey.pem" \
    -out "${target}/fullchain.pem" \
    -days 30 >/dev/null 2>&1
  cp "${target}/fullchain.pem" "${target}/cert.pem"
  echo "Generated self-signed certificate for ${domain} at ${target}"
done
