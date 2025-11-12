#!/bin/sh
set -eu

TEMPLATE=/etc/nginx/templates/nginx.conf.tpl
SSL_PARAMS=/etc/nginx/templates/ssl-params.conf
SNIPPET=/etc/nginx/snippets/ssl-params.conf
NGINX_CONF=/etc/nginx/nginx.conf
mkdir -p /etc/nginx/snippets

if [ -z "${CERTBOT_CERT_NAME:-}" ]; then
  if [ -n "${SITE_SNI_DOMAIN:-}" ]; then
    CERTBOT_CERT_NAME="${SITE_SNI_DOMAIN}"
  else
    CERTBOT_CERT_NAME="${VPN_SNI_DOMAIN}"
  fi
fi
export CERTBOT_CERT_NAME

envsubst '$$VPN_SNI_DOMAIN $$SITE_SNI_DOMAIN $$CERTBOT_CERT_NAME' < "$TEMPLATE" > "$NGINX_CONF"
cp "$SSL_PARAMS" "$SNIPPET"
exec nginx -g 'daemon off;'
