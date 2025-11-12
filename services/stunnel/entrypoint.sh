#!/bin/sh
set -eu
TEMPLATE=/etc/stunnel/stunnel.conf.tpl
TARGET=/etc/stunnel/stunnel.conf

CERTBOT_CERT_NAME=${CERTBOT_CERT_NAME:-${VPN_SNI_DOMAIN:-vpn.example.com}}
DEFAULT_CERT_DIR="/certs/live/${CERTBOT_CERT_NAME}"
if [ -z "${STUNNEL_CERT_FILE:-}" ]; then
  STUNNEL_CERT_FILE="${DEFAULT_CERT_DIR}/fullchain.pem"
fi
if [ -z "${STUNNEL_KEY_FILE:-}" ]; then
  STUNNEL_KEY_FILE="${DEFAULT_CERT_DIR}/privkey.pem"
fi
if [ -z "${STUNNEL_CA_FILE:-}" ]; then
  STUNNEL_CA_FILE="${DEFAULT_CERT_DIR}/fullchain.pem"
fi
if [ -z "${STUNNEL_ACCEPT_PORT:-}" ]; then
  STUNNEL_ACCEPT_PORT=8443
fi
if [ -z "${STUNNEL_FORWARD_PORT:-}" ]; then
  STUNNEL_FORWARD_PORT=1194
fi
if [ -z "${STUNNEL_ACCEPT_HOST:-}" ]; then
  STUNNEL_ACCEPT_HOST="0.0.0.0"
fi
if [ -z "${STUNNEL_FORWARD_HOST:-}" ]; then
  STUNNEL_FORWARD_HOST="host.docker.internal"
fi
if [ -z "${STUNNEL_VERIFY_CHAIN:-}" ]; then
  STUNNEL_VERIFY_CHAIN="yes"
fi

export STUNNEL_CERT_FILE STUNNEL_KEY_FILE STUNNEL_CA_FILE STUNNEL_ACCEPT_PORT STUNNEL_FORWARD_PORT STUNNEL_ACCEPT_HOST STUNNEL_FORWARD_HOST VPN_SNI_DOMAIN STUNNEL_VERIFY_CHAIN

if [ ! -f "$TEMPLATE" ]; then
  echo "Template $TEMPLATE not found" >&2
  exit 1
fi

mkdir -p /etc/stunnel
envsubst < "$TEMPLATE" > "$TARGET"
exec stunnel "$TARGET"
