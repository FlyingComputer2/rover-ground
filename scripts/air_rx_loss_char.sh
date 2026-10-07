#!/usr/bin/env bash
# Characterize LC air-RX loss on upstream 2 (link-test probe), not video.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="${WINJECT_L3:-/home/ubuntu/development/winject-l3}/tools/air_rx_loss_char.py"
exec python3 "$TOOL" \
  --mgr-host 192.168.128.1 \
  --mgr-port 2424 \
  --upstream 2 \
  --label "rover-ground link-test upstream 2 (e5/f6)" \
  "$@"
