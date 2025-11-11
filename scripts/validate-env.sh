#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file $ENV_FILE not found" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

REQUIRED_VARS=(
  VPN_SERVER_CN
  VPN_PUBLIC_ENDPOINT
  VPN_SNI_DOMAIN
  SITE_SNI_DOMAIN
  DEFAULT_CLIENTS
  GRAFANA_ADMIN_PASSWORD
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required variable: $var" >&2
    exit 1
  fi
done

echo "Environment looks good."
