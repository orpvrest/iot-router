#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/common.sh"

if list_port_forward_specs >/dev/null 2>&1; then
  "${SCRIPT_DIR}/port-forward.sh" &
fi

${SCRIPT_DIR}/bootstrap-pki.sh --once

exec /usr/sbin/openvpn --cd /etc/openvpn --config /etc/openvpn/server.conf
