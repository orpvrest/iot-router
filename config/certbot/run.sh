#!/bin/sh
set -euo pipefail

CERT_NAME="${VPN_SNI_DOMAIN}"
LE_DIR=/etc/letsencrypt

if [ "${ACME_STAGING:-false}" = "true" ]; then
  STAGING_FLAG="--staging"
else
  STAGING_FLAG=""
fi

# Remove stale renewal configs if we are issuing a new lineage
rm -f "$LE_DIR/renewal/${CERT_NAME}.conf"

certbot certonly --non-interactive --agree-tos \
  --webroot -w /var/www/certbot \
  --cert-name "${CERT_NAME}" --expand \
  -d "${VPN_SNI_DOMAIN}" -d "${SITE_SNI_DOMAIN}" \
  --email "${LE_EMAIL}" ${STAGING_FLAG}

# Clean up any "-0001" style renewal files and ensure only our main cert remains
find "$LE_DIR/renewal" -maxdepth 1 -name "${CERT_NAME}-*.conf" -delete

certbot renew --dry-run ${STAGING_FLAG}
