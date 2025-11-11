#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <client-name>" >&2
  exit 1
fi

CLIENT_NAME=$1
if [[ ! "$CLIENT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; then
  echo "Client name '${CLIENT_NAME}' invalid. Allowed: alphanumerics plus ._- (max 64 chars)." >&2
  exit 1
fi
COMPOSE_BIN=${COMPOSE_BIN:-docker compose}

${COMPOSE_BIN} exec openvpn-core /opt/openvpn/scripts/build-client.sh "${CLIENT_NAME}"
