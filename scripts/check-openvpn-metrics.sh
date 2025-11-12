#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE=${ENV_FILE:-${ROOT_DIR}/.env}

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC2046,SC1090
  set -a && source "$ENV_FILE" && set +a
fi

PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$(basename "$ROOT_DIR")}
NETWORK_NAME=${MONITOR_NETWORK_NAME:-${PROJECT_NAME}_monitor-net}
ENDPOINT=${1:-http://openvpn-exporter:9176/metrics}
IMAGE=${CURL_IMAGE:-curlimages/curl:latest}

echo "Using network: ${NETWORK_NAME}"
docker run --rm --network "${NETWORK_NAME}" "${IMAGE}" -s "${ENDPOINT}"
