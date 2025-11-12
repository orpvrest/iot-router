#!/bin/sh
set -euo pipefail

CERT_NAME="${VPN_SNI_DOMAIN}"
LE_DIR=/etc/letsencrypt

if [ "${ACME_STAGING:-false}" = "true" ]; then
  STAGING_FLAG="--staging"
else
  STAGING_FLAG=""
fi

certbot certonly --non-interactive --agree-tos \
  --webroot -w /var/www/certbot \
  --cert-name "${CERT_NAME}" --expand \
  -d "${VPN_SNI_DOMAIN}" -d "${SITE_SNI_DOMAIN}" \
  --email "${LE_EMAIL}" ${STAGING_FLAG} || true

certbot renew --dry-run ${STAGING_FLAG}
