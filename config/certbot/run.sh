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

if [ -n "${SITE_SNI_DOMAIN:-}" ] && [ "${CERT_NAME}" != "${SITE_SNI_DOMAIN}" ]; then
  ADDTL_DOMAINS="-d ${SITE_SNI_DOMAIN}"
else
  ADDTL_DOMAINS=""
fi

certbot certonly --non-interactive --agree-tos \
  --webroot -w /var/www/certbot \
  --cert-name "${CERT_NAME}" \
  -d "${CERT_NAME}" ${ADDTL_DOMAINS} \
  --email "${LE_EMAIL}" ${STAGING_FLAG}

certbot renew --dry-run ${STAGING_FLAG}
