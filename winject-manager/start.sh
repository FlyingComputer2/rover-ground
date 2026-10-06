#!/usr/bin/env bash
# Wait for the radio m-plane, then exec winject-manager.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${WINJECT_MANAGER:-/home/ubuntu/development/winject-l3/build_manager_arm/winject-manager}"
RADIO_CONSOLE="127.0.0.1:2201"

wait_udp_bind() {
    local i
    for i in $(seq 1 30); do
        # ss prints the state first (UNCONN ...); match the local-address column.
        if ss -H -uln sport = :2201 | awk '$4 == "127.0.0.1:2201" { found = 1 } END { exit !found }'; then
            return 0
        fi
        sleep 1
    done
    echo "error: ${RADIO_CONSOLE} not bound after 30s" >&2
    return 1
}

wait_udp_bind
exec "$BIN" "${ROOT}/config.cfg"
