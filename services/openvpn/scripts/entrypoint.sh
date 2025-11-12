#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/common.sh"

function ensure_ip_forward() {
  if [[ "${ENABLE_IP_FORWARD,,}" == "false" ]]; then
    return
  fi
  if sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
    :
  else
    echo "[openvpn] Warning: failed to enable net.ipv4.ip_forward" >&2
  fi
}

function ensure_nat() {
  if [[ "${OPENVPN_ENABLE_NAT,,}" == "false" ]]; then
    return
  fi
  local iface=${OPENVPN_NAT_INTERFACE:-}
  if [[ -z "$iface" ]]; then
    echo "[openvpn] OPENVPN_NAT_INTERFACE is not set; skipping MASQUERADE" >&2
    return
  fi
  local source_cidr="${VPN_NETWORK}/${VPN_NETMASK}"
  if iptables -t nat -C POSTROUTING -s "$source_cidr" -o "$iface" -j MASQUERADE 2>/dev/null; then
    return
  fi
  if ! iptables -t nat -A POSTROUTING -s "$source_cidr" -o "$iface" -j MASQUERADE 2>/dev/null; then
    echo "[openvpn] Warning: failed to install MASQUERADE rule on ${iface}" >&2
  fi
}

ensure_ip_forward
ensure_nat

if list_port_forward_specs >/dev/null 2>&1; then
  "${SCRIPT_DIR}/port-forward.sh" &
fi

${SCRIPT_DIR}/bootstrap-pki.sh --once

exec /usr/sbin/openvpn --cd /etc/openvpn --config /etc/openvpn/server.conf
