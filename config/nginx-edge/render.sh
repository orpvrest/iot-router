#!/bin/sh
set -eu

TEMPLATE=/etc/nginx/templates/nginx.conf.tpl
SSL_PARAMS=/etc/nginx/templates/ssl-params.conf
SNIPPET=/etc/nginx/snippets/ssl-params.conf
NGINX_CONF=/etc/nginx/nginx.conf
TMP_STREAMS=$(mktemp)
trap 'rm -f "$TMP_STREAMS"' EXIT

mkdir -p /etc/nginx/snippets
: > "$TMP_STREAMS"

FORWARD_TARGET=${OPENVPN_FORWARD_HOST:-openvpn-core}

if [ -n "${VPN_FORWARD_TCP:-}" ]; then
  printf '%s' "${VPN_FORWARD_TCP}" | tr ',' '\n' | while IFS=':' read -r _ port _ _; do
    port=$(echo "${port}" | xargs)
    [ -z "$port" ] && continue
    cat <<EOS >> "$TMP_STREAMS"
  server {
    listen 0.0.0.0:${port};
    proxy_pass ${FORWARD_TARGET}:${port};
  }
EOS
  done
fi

export FORWARD_STREAMS="$(cat "$TMP_STREAMS")"

if [ -z "${CERTBOT_CERT_NAME:-}" ]; then
  if [ -n "${SITE_SNI_DOMAIN:-}" ]; then
    CERTBOT_CERT_NAME="${SITE_SNI_DOMAIN}"
  else
    CERTBOT_CERT_NAME="${VPN_SNI_DOMAIN}"
  fi
fi
export CERTBOT_CERT_NAME

envsubst '$$VPN_SNI_DOMAIN $$SITE_SNI_DOMAIN $$FORWARD_STREAMS $$CERTBOT_CERT_NAME' < "$TEMPLATE" > "$NGINX_CONF"
cp "$SSL_PARAMS" "$SNIPPET"
exec nginx -g 'daemon off;'
