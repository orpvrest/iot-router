#!/bin/sh
set -euo pipefail

if [ "${ACME_STAGING:-false}" = "true" ]; then
  STAGING_FLAG="--staging"
else
  STAGING_FLAG=""
fi

certbot certonly --non-interactive --agree-tos \
  --webroot -w /var/www/certbot \
  -d "${VPN_SNI_DOMAIN}" -d "${SITE_SNI_DOMAIN}" \
  --email "${LE_EMAIL}" ${STAGING_FLAG}

certbot renew --dry-run ${STAGING_FLAG}
