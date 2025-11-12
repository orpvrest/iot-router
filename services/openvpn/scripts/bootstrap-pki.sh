#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/common.sh"

ONLY_PKI=false
REGENERATE_CLIENTS=false
ONCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only-pki)
      ONLY_PKI=true
      shift ;;
    --regenerate-clients)
      REGENERATE_CLIENTS=true
      shift ;;
    --once)
      ONCE=true
      shift ;;
    *)
      echo "[bootstrap] Unknown flag: $1" >&2
      exit 1 ;;
  esac
done

function write_vars() {
  cat > "${EASYRSA_VARS_FILE}" <<VARS
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "State"
set_var EASYRSA_REQ_CITY       "City"
set_var EASYRSA_REQ_ORG        "${VPN_ORG}"
set_var EASYRSA_REQ_EMAIL      "${VPN_EMAIL}"
set_var EASYRSA_REQ_OU         "IoT"
set_var EASYRSA_ALGO           "rsa"
set_var EASYRSA_DIGEST         "sha256"
VARS
}

function ensure_pki() {
  if [[ -f "${PKI_DIR}/ca.crt" ]]; then
    return
  fi

  echo "[bootstrap] Initializing PKI"
  write_vars
  umask 077
  "${EASYRSA_BIN}" --pki-dir="${PKI_DIR}" init-pki
  "${EASYRSA_BIN}" --pki-dir="${PKI_DIR}" --req-cn="${VPN_SERVER_CN}" build-ca nopass
  "${EASYRSA_BIN}" --pki-dir="${PKI_DIR}" gen-dh
  "${EASYRSA_BIN}" --pki-dir="${PKI_DIR}" build-server-full server nopass
  "${EASYRSA_BIN}" --pki-dir="${PKI_DIR}" gen-crl
}

function ensure_keys() {
  if [[ ! -f "${OVPN_DIR}/ta.key" ]]; then
    echo "[bootstrap] Generating tls-crypt key"
    umask 077
    /usr/sbin/openvpn --genkey secret "${OVPN_DIR}/ta.key"
  fi

  install -m 600 "${PKI_DIR}/private/server.key" "${OVPN_DIR}/server.key"
  install -m 644 "${PKI_DIR}/issued/server.crt" "${OVPN_DIR}/server.crt"
  install -m 644 "${PKI_DIR}/ca.crt" "${OVPN_DIR}/ca.crt"
  install -m 644 "${PKI_DIR}/dh.pem" "${OVPN_DIR}/dh.pem"
  install -m 644 "${PKI_DIR}/crl.pem" "${OVPN_DIR}/crl.pem"
}

function render_server_conf() {
  local config="${OVPN_DIR}/server.conf"
  umask 077
  cat > "$config" <<CFG
port ${OPENVPN_LOCAL_PORT}
proto tcp-server
dev tun
user nobody
group nogroup
persist-key
persist-tun
topology subnet
server ${VPN_NETWORK} ${VPN_NETMASK}
client-config-dir ${CCD_DIR}
ifconfig-pool-persist ${OVPN_DIR}/ipp.txt
status ${STATUS_DIR}/openvpn-status.log 10
status-version 2
log-append ${STATUS_DIR}/openvpn.log
verb 3
keepalive ${VPN_KEEPALIVE}
management ${VPN_MANAGEMENT_HOST} ${VPN_MANAGEMENT_PORT}
explicit-exit-notify 1
push "redirect-gateway def1 bypass-dhcp"
CFG

  if [[ -n "${VPN_PUSH_ROUTES}" ]]; then
    IFS="," read -ra routes <<< "${VPN_PUSH_ROUTES}"
    for route in "${routes[@]}"; do
      route=$(echo "$route" | xargs)
      [[ -z "$route" ]] && continue
      echo "push \"route ${route}\"" >> "$config"
    done
  fi

  IFS="," read -ra dns_servers <<< "${VPN_DNS}"
  for dns in "${dns_servers[@]}"; do
    dns=$(echo "$dns" | xargs)
    [[ -z "$dns" ]] && continue
    echo "push \"dhcp-option DNS ${dns}\"" >> "$config"
  done

  cat >> "$config" <<CFG
dh ${OVPN_DIR}/dh.pem
ca ${OVPN_DIR}/ca.crt
cert ${OVPN_DIR}/server.crt
key ${OVPN_DIR}/server.key
tls-crypt ${OVPN_DIR}/ta.key
crl-verify ${OVPN_DIR}/crl.pem
sndbuf 524288
rcvbuf 524288
client-to-client
max-clients 200
reneg-sec 0
cipher AES-256-GCM
auth SHA256
ncp-ciphers AES-256-GCM:AES-128-GCM
push "compress stub-v2"
allow-compression yes
compress stub-v2
CFG
}

function ensure_status_files() {
  touch "${STATUS_DIR}/openvpn-status.log"
  touch "${STATUS_DIR}/openvpn.log"
}

function generate_default_clients() {
  IFS="," read -ra clients <<< "${DEFAULT_CLIENTS}"
  for client in "${clients[@]}"; do
    client=$(echo "$client" | xargs)
    [[ -z "$client" ]] && continue
    validate_client_identifier "$client"
    if [[ "$REGENERATE_CLIENTS" == "true" ]]; then
      FORCE_REISSUE=true "${SCRIPT_DIR}/build-client.sh" "$client"
    else
      "${SCRIPT_DIR}/build-client.sh" "$client"
    fi
    ensure_static_ip_for_client "$client"
  done
}

ensure_pki
ensure_keys
render_server_conf
ensure_status_files

if [[ "$ONLY_PKI" != "true" ]]; then
  generate_default_clients
fi
