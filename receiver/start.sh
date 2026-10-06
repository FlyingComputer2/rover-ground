#!/usr/bin/env bash
# Wait for the WG address, then run sdl_stream_receiver with restarts.
# RECEIVER_DISPLAY: sdl (desktop session, default) or kmsdrm (headless; see gs-video-receiver.service).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SDL_STREAM_RECEIVER:-/home/ubuntu/development/vstreamer/out/gs/src/apps/sdl_stream_receiver/sdl_stream_receiver}"
WG_ADDR="192.168.128.1"
IFACE="winject"
DISPLAY_MODE="${RECEIVER_DISPLAY:-sdl}"

wait_wg_address() {
    local i
    for i in $(seq 1 120); do
        if ip -4 addr show dev "$IFACE" 2>/dev/null | grep -q "inet ${WG_ADDR}/"; then
            return 0
        fi
        sleep 1
    done
    echo "error: ${WG_ADDR} not on ${IFACE} after 120s" >&2
    return 1
}

wait_wg_address

while true; do
    "$BIN" \
        --listen 127.0.0.1:21082 \
        --max-datagram 1445 \
        --console "${WG_ADDR}:5091" \
        --display "$DISPLAY_MODE" \
        || true
    sleep 2
done
