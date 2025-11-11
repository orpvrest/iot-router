#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && . "$ENV_FILE" && set +a
fi
PROJECT_NAME=${COMPOSE_PROJECT_NAME:-iot-router}
BACKUP_ROOT=${BACKUP_ROOT:-$PWD/backups}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_ROOT"

ARCHIVE_PATH="${BACKUP_ROOT}/${TIMESTAMP}_openvpn.tar.gz"
tar -czf "$ARCHIVE_PATH" data/openvpn data/certbot
echo "Stored PKI/certbot backup at $ARCHIVE_PATH"

for volume in grafana-storage prometheus-storage; do
  VOLUME_NAME="${PROJECT_NAME}_${volume}"
  DEST="${BACKUP_ROOT}/${TIMESTAMP}_${volume}.tar.gz"
  if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    docker run --rm -v "${VOLUME_NAME}:/volume" busybox sh -c "cd /volume && tar -czf - ." > "$DEST"
    echo "Dumped volume $VOLUME_NAME to $DEST"
  else
    echo "Skipping volume $VOLUME_NAME (not found)" >&2
  fi
done
