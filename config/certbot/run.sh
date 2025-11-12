#!/bin/sh
set -euo pipefail

CERT_NAME="${CERTBOT_CERT_NAME:-${VPN_SNI_DOMAIN}}"
LE_DIR=/etc/letsencrypt

if [ "${ACME_STAGING:-false}" = "true" ]; then
  STAGING_FLAG="--staging"
else
  STAGING_FLAG=""
fi

# Remove stale lineages with the same cert name
rm -rf "$LE_DIR/live/${CERT_NAME}" "$LE_DIR/archive/${CERT_NAME}" "$LE_DIR/renewal/${CERT_NAME}.conf"

certbot certonly --non-interactive --agree-tos \
  --webroot -w /var/www/certbot \
  --cert-name "${CERT_NAME}" \
  -d "${VPN_SNI_DOMAIN}" -d "${SITE_SNI_DOMAIN}" \
  --email "${LE_EMAIL}" ${STAGING_FLAG}

certbot renew --dry-run ${STAGING_FLAG}
