#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/common.sh"

FORWARD_LOG_PREFIX="[forward]"
declare -a FORWARD_PIDS=()

function shutdown_forwarders() {
  for pid in "${FORWARD_PIDS[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
  done
}

trap shutdown_forwarders EXIT INT TERM

function ensure_client_ip() {
  local client=$1
  local resolved=""
  if resolved=$(get_static_ip_for_client "${client}" 2>/dev/null); then
    echo "${resolved}"
    return
  fi
  fatal "Forwarding requires static IP for client '${client}'."
}

function start_forwarder() {
  local label=$1
  local port=$2
  local client_ip=$3
  local target_port=$4
  (
    while true; do
      echo "${FORWARD_LOG_PREFIX} ${label}: listening on ${PORT_FORWARD_BIND_ADDR}:${port} -> ${client_ip}:${target_port}"
      if ! socat TCP-LISTEN:${port},fork,reuseaddr,bind=${PORT_FORWARD_BIND_ADDR} TCP:${client_ip}:${target_port}; then
        echo "${FORWARD_LOG_PREFIX} ${label}: socat exited unexpectedly; restarting in 2s" >&2
        sleep 2
      fi
    done
  ) &
  FORWARD_PIDS+=($!)
}

function run_forwarders() {
  local spec label port client target_port client_ip
  local count=0
  while IFS= read -r spec; do
    [[ -z "$spec" ]] && continue
    IFS=':' read -r label port client target_port <<< "$spec"
    client_ip=$(ensure_client_ip "$client")
    start_forwarder "$label" "$port" "$client_ip" "$target_port"
    count=$((count+1))
  done < <(list_port_forward_specs || true)

  if [[ $count -gt 0 ]]; then
    wait -n
  fi
}

run_forwarders
