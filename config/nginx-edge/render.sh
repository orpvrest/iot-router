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

if [ -n "${VPN_FORWARD_TCP:-}" ]; then
  printf '%s' "${VPN_FORWARD_TCP}" | tr ',' '\n' | while IFS=':' read -r _ port _ _; do
    port=$(echo "${port}" | xargs)
    [ -z "$port" ] && continue
    cat <<EOS >> "$TMP_STREAMS"
  server {
    listen 0.0.0.0:${port};
    proxy_pass openvpn-core:${port};
  }
EOS
  done
fi

export FORWARD_STREAMS="$(cat "$TMP_STREAMS")"

envsubst '$$VPN_SNI_DOMAIN $$SITE_SNI_DOMAIN $$FORWARD_STREAMS' < "$TEMPLATE" > "$NGINX_CONF"
cp "$SSL_PARAMS" "$SNIPPET"
exec nginx -g 'daemon off;'
