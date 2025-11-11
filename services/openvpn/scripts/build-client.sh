#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/common.sh"

umask 077

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <client-name>" >&2
  exit 1
fi

CLIENT_NAME=$1
validate_client_identifier "${CLIENT_NAME}"
FORCE=${FORCE_REISSUE:-false}
CLIENT_DIR="${CLIENTS_DIR}/${CLIENT_NAME}"
PKI_CLIENT_CERT="${PKI_DIR}/issued/${CLIENT_NAME}.crt"
PKI_CLIENT_KEY="${PKI_DIR}/private/${CLIENT_NAME}.key"

if [[ -f "$PKI_CLIENT_CERT" && "$FORCE" != "true" ]]; then
  echo "[client] ${CLIENT_NAME} already exists; skipping"
else
  echo "[client] Generating certificates for ${CLIENT_NAME}"
  EASYRSA_BATCH=1 "${EASYRSA_BIN}" --pki-dir="${PKI_DIR}" build-client-full "${CLIENT_NAME}" nopass
fi

mkdir -p "${CLIENT_DIR}"
CA_BUNDLE="${PKI_DIR}/ca.crt"
TLS_CRYPT="${OVPN_DIR}/ta.key"

function render_standard_profile() {
  cat <<OVPN
client
dev tun
proto tcp-client
remote ${VPN_PUBLIC_ENDPOINT} ${OPENVPN_TCP_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
compress stub-v2
verb 3
<ca>
$(cat "$CA_BUNDLE")
</ca>
<cert>
$(cat "$PKI_CLIENT_CERT")
</cert>
<key>
$(cat "$PKI_CLIENT_KEY")
</key>
<tls-crypt>
$(cat "$TLS_CRYPT")
</tls-crypt>
OVPN
}

function render_stunnel_profile() {
  cat <<OVPN
client
dev tun
proto tcp-client
remote 127.0.0.1 ${OPENVPN_LOCAL_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
compress stub-v2
verb 3
<ca>
$(cat "$CA_BUNDLE")
</ca>
<cert>
$(cat "$PKI_CLIENT_CERT")
</cert>
<key>
$(cat "$PKI_CLIENT_KEY")
</key>
<tls-crypt>
$(cat "$TLS_CRYPT")
</tls-crypt>
OVPN
}

function render_stunnel_conf() {
  cat <<CONF
client = yes
verifyChain = no
foreground = no
[openvpn]
accept = 127.0.0.1:${OPENVPN_LOCAL_PORT}
connect = ${VPN_SNI_DOMAIN}:${EDGE_TLS_PORT}
retry = yes
TIMEOUTclose = 0
CONF
}

render_standard_profile > "${CLIENT_DIR}/${CLIENT_NAME}.ovpn"
render_stunnel_profile > "${CLIENT_DIR}/${CLIENT_NAME}-stunnel.ovpn"
render_stunnel_conf > "${CLIENT_DIR}/${CLIENT_NAME}.stunnel.conf"

OUTPUT_FILE="${OUTPUT_DIR}/${CLIENT_NAME}.tar.gz"
mkdir -p "${OUTPUT_DIR}"
tar -C "${CLIENT_DIR}" -czf "$OUTPUT_FILE" .

ensure_static_ip_for_client "${CLIENT_NAME}"

echo "[client] Bundle available at ${OUTPUT_FILE}"
