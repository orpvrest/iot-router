#!/usr/bin/env bash
set -euo pipefail

OVPN_DIR=${OVPN_DIR:-/etc/openvpn}
PKI_DIR=${PKI_DIR:-${OVPN_DIR}/pki}
CLIENTS_DIR=${CLIENTS_DIR:-${OVPN_DIR}/clients}
STATUS_DIR=${STATUS_DIR:-${OVPN_DIR}/status}
CCD_DIR=${CCD_DIR:-${OVPN_DIR}/ccd}
EASYRSA_DIR=${EASYRSA_DIR:-/usr/share/easy-rsa}
EASYRSA_BIN=${EASYRSA_BIN:-/usr/share/easy-rsa/easyrsa}
VPN_SERVER_CN=${VPN_SERVER_CN:-vpn.local}
VPN_ORG=${VPN_ORG:-IoT Router}
VPN_EMAIL=${VPN_EMAIL:-ops@example.com}
VPN_NETWORK=${VPN_NETWORK:-10.8.0.0}
VPN_NETMASK=${VPN_NETMASK:-255.255.255.0}
VPN_PUBLIC_ENDPOINT=${VPN_PUBLIC_ENDPOINT:-vpn.example.com}
VPN_SNI_DOMAIN=${VPN_SNI_DOMAIN:-vpn.example.com}
VPN_DNS=${VPN_DNS:-1.1.1.1,8.8.8.8}
VPN_PUSH_ROUTES=${VPN_PUSH_ROUTES:-}
VPN_STATIC_CLIENTS=${VPN_STATIC_CLIENTS:-}
DEFAULT_CLIENTS=${DEFAULT_CLIENTS:-core-admin}
OPENVPN_TCP_PORT=${OPENVPN_TCP_PORT:-1194}
OPENVPN_UDP_PORT=${OPENVPN_UDP_PORT:-1194}
OPENVPN_LOCAL_PORT=${OPENVPN_LOCAL_PORT:-1194}
VPN_MANAGEMENT_HOST=${VPN_MANAGEMENT_HOST:-127.0.0.1}
VPN_MANAGEMENT_PORT=${VPN_MANAGEMENT_PORT:-5555}
OPENVPN_USER=${OPENVPN_USER:-nobody}
OPENVPN_GROUP=${OPENVPN_GROUP:-nogroup}
VPN_KEEPALIVE=${VPN_KEEPALIVE:-10 120}
OUTPUT_DIR=${OUTPUT_DIR:-${CLIENTS_DIR}/packages}
EDGE_TLS_PORT=${EDGE_TLS_PORT:-443}
VPN_FORWARD_TCP=${VPN_FORWARD_TCP:-}
FORWARD_TCP_RANGE_PRIMARY=${FORWARD_TCP_RANGE_PRIMARY:-20020-20039}
FORWARD_TCP_RANGE_SECONDARY=${FORWARD_TCP_RANGE_SECONDARY:-20060-20079}

mkdir -p "${OVPN_DIR}" "${PKI_DIR}" "${CLIENTS_DIR}" "${STATUS_DIR}" "${CCD_DIR}" "${OUTPUT_DIR}"

declare -Ag STATIC_CLIENT_MAP=()
declare -Ag STATIC_IP_OWNER=()
declare -a PORT_FORWARD_SPECS=()
declare -a FORWARD_PORT_RANGES=()

function fatal() {
  echo "[openvpn-common] $*" >&2
  exit 1
}

function validate_client_identifier() {
  local name=$1
  if [[ -z "${name}" || ! "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; then
    fatal "Client name '${name}' is invalid. Allowed: alphanumerics, dots, dashes, underscores (max 64 chars)."
  fi
}

function validate_ipv4() {
  local ip=$1
  if [[ ! "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    fatal "IP '${ip}' is invalid."
  fi
  IFS='.' read -r o1 o2 o3 o4 <<< "${ip}"
  for octet in $o1 $o2 $o3 $o4; do
    if (( octet < 0 || octet > 255 )); then
      fatal "IP '${ip}' octet '${octet}' out of range."
    fi
  done
}

function validate_port() {
  local port=$1 field=$2
  if [[ ! "${port}" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    fatal "Port '${port}' for ${field} must be between 1 and 65535."
  fi
}

function _register_forward_range() {
  local range=$1 label=$2
  [[ -z "${range}" ]] && return
  if [[ ! "${range}" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
    fatal "Forward range '${range}' (${label}) must be in start-end format."
  fi
  local start=${BASH_REMATCH[1]}
  local end=${BASH_REMATCH[2]}
  if (( start > end )); then
    fatal "Forward range '${range}' (${label}) start > end."
  fi
  validate_port "${start}" "${label} start"
  validate_port "${end}" "${label} end"
  FORWARD_PORT_RANGES+=("${start}-${end}")
}

function _port_in_allowed_ranges() {
  local port=$1
  for range in "${FORWARD_PORT_RANGES[@]}"; do
    local start=${range%-*}
    local end=${range#*-}
    if (( port >= start && port <= end )); then
      return 0
    fi
  done
  return 1
}

function _parse_static_clients() {
  [[ -z "${VPN_STATIC_CLIENTS}" ]] && return
  IFS=',' read -ra entries <<< "${VPN_STATIC_CLIENTS}"
  for entry in "${entries[@]}"; do
    entry=$(echo "${entry}" | xargs || true)
    [[ -z "${entry}" ]] && continue
    IFS=':' read -r name ip <<< "${entry}"
    name=$(echo "${name:-}" | xargs || true)
    ip=$(echo "${ip:-}" | xargs || true)
    [[ -z "${name}" || -z "${ip}" ]] && fatal "Malformed VPN_STATIC_CLIENTS entry '${entry}'."
    validate_client_identifier "${name}"
    validate_ipv4 "${ip}"
    if [[ -n "${STATIC_IP_OWNER[${ip}]:-}" && "${STATIC_IP_OWNER[${ip}]}" != "${name}" ]]; then
      fatal "IP '${ip}' assigned to multiple clients (${STATIC_IP_OWNER[${ip}]} and ${name})."
    fi
    STATIC_CLIENT_MAP["${name}"]="${ip}"
    STATIC_IP_OWNER["${ip}"]="${name}"
  done
}

function get_static_ip_for_client() {
  local client=$1
  if [[ -n "${STATIC_CLIENT_MAP[$client]:-}" ]]; then
    echo "${STATIC_CLIENT_MAP[$client]}"
    return 0
  fi
  return 1
}

function ensure_static_ip_for_client() {
  local client=$1
  local ip
  if ip=$(get_static_ip_for_client "${client}"); then
    local lease_file="${CCD_DIR}/${client}"
    cat > "${lease_file}" <<EOF
ifconfig-push ${ip} ${VPN_NETMASK}
EOF
    chown "${OPENVPN_USER}:${OPENVPN_GROUP}" "${lease_file}"
    chmod 640 "${lease_file}"
  fi
}

function _parse_port_forward_specs() {
  _register_forward_range "${FORWARD_TCP_RANGE_PRIMARY}" "FORWARD_TCP_RANGE_PRIMARY"
  _register_forward_range "${FORWARD_TCP_RANGE_SECONDARY}" "FORWARD_TCP_RANGE_SECONDARY"
  [[ -z "${VPN_FORWARD_TCP}" ]] && return
  IFS=',' read -ra entries <<< "${VPN_FORWARD_TCP}"
  for entry in "${entries[@]}"; do
    entry=$(echo "${entry}" | xargs || true)
    [[ -z "${entry}" ]] && continue
    IFS=':' read -r label public_port client target_port <<< "${entry}"
    label=${label:-forward}
    public_port=$(echo "${public_port:-}" | xargs || true)
    client=$(echo "${client:-}" | xargs || true)
    target_port=$(echo "${target_port:-}" | xargs || true)
    [[ -z "${public_port}" || -z "${client}" || -z "${target_port}" ]] && fatal "Malformed VPN_FORWARD_TCP entry '${entry}'."
    validate_port "${public_port}" "public port (${label})"
    validate_port "${target_port}" "target port (${label})"
    validate_client_identifier "${client}"
    if [[ ${#FORWARD_PORT_RANGES[@]} -gt 0 ]] && ! _port_in_allowed_ranges "${public_port}"; then
      fatal "Port ${public_port} for '${label}' not within allowed ranges ${FORWARD_PORT_RANGES[*]}"
    fi
    if [[ -z "${STATIC_CLIENT_MAP[${client}]:-}" ]]; then
      fatal "Client '${client}' must have a static IP to use forwarding (VPN_STATIC_CLIENTS)."
    fi
    PORT_FORWARD_SPECS+=("${label}:${public_port}:${client}:${target_port}")
  done
}

function list_port_forward_specs() {
  if [[ ${#PORT_FORWARD_SPECS[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${PORT_FORWARD_SPECS[@]}"
}

_parse_static_clients
_parse_port_forward_specs
