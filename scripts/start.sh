#!/usr/bin/env bash
# Manually start the GS stack in the foreground: radio, winject-manager (l3), then the video
# receiver. Ctrl-C (or any component exiting) stops all three. Nothing is enabled at boot.
#
#   sudo scripts/start.sh             # refuse if a radio/manager/receiver is already running
#   sudo scripts/start.sh --replace   # stop those first
#
# Env: RECEIVER_DISPLAY=kmsdrm|sdl (default kmsdrm, HDMI via tty1), LOG_DIR (default
# /tmp/rover-ground). WireGuard (wg-quick@winject) is started if it is not up.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-/tmp/rover-ground}"
DISPLAY_MODE="${RECEIVER_DISPLAY:-kmsdrm}"
UNITS=(gs-video-receiver.service winject-manager.service winject-radio-realtek.service)
# Anchored on the command itself (binary path or `bash <script>`), so shells, editors or ssh
# sessions that merely mention these names are not matched.
PATTERN='^(\S*/)?(winject-radio-realtek|winject-manager|sdl_stream_receiver)( |$)|^(\S*/)?bash \S*rover-ground/(radio|winject-manager|receiver)/start\.sh'

replace=0
case "${1:-}" in
    --replace) replace=1 ;;
    "") ;;
    *) echo "usage: sudo $0 [--replace]" >&2; exit 2 ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo --preserve-env=RECEIVER_DISPLAY,LOG_DIR "$0" "$@"
fi

existing_pids() {
    pgrep -f -- "$PATTERN" | grep -vx "$$" || true
}

# Never run beside the systemd units or an earlier manual start: they share the dongle and ports.
busy=()
for unit in "${UNITS[@]}"; do
    if systemctl is-active --quiet "$unit"; then
        busy+=("$unit")
    fi
done
pids="$(existing_pids)"
if [[ ${#busy[@]} -gt 0 || -n "$pids" ]]; then
    if [[ $replace -eq 0 ]]; then
        echo "error: GS stack already running; rerun with --replace to stop it:" >&2
        for unit in "${busy[@]}"; do
            echo "  unit $unit" >&2
        done
        if [[ -n "$pids" ]]; then
            ps -o pid=,args= -p "${pids//$'\n'/,}" | sed 's/^/  pid /' >&2
        fi
        exit 1
    fi
    for unit in "${busy[@]}"; do
        systemctl stop "$unit"
    done
    if [[ -n "$pids" ]]; then
        kill $pids 2>/dev/null || true
        for _ in $(seq 1 50); do
            [[ -z "$(existing_pids)" ]] && break
            sleep 0.1
        done
        pids="$(existing_pids)"
        [[ -n "$pids" ]] && kill -KILL $pids 2>/dev/null || true
    fi
fi

if ! systemctl is-active --quiet wg-quick@winject.service; then
    systemctl start wg-quick@winject.service
fi

mkdir -p "$LOG_DIR"
declare -A comp_pid=()
order=()
getty_stopped=0

# Each component runs in its own session so teardown can signal its whole process group (the
# receiver script loops around the binary). Output goes to $LOG_DIR/<name>.log and, tagged, here.
launch() {
    local name="$1"
    shift
    setsid "$@" > >(tee -a "${LOG_DIR}/${name}.log" | sed -u "s/^/[${name}] /") 2>&1 &
    comp_pid[$name]=$!
    order+=("$name")
    echo "started ${name} (pid ${comp_pid[$name]}, log ${LOG_DIR}/${name}.log)"
}

cleanup() {
    trap - INT TERM EXIT
    echo "stopping GS stack"
    local i name
    for ((i = ${#order[@]} - 1; i >= 0; i--)); do
        name="${order[$i]}"
        kill -TERM -- "-${comp_pid[$name]}" 2>/dev/null || true
    done
    for _ in $(seq 1 50); do
        local alive=0
        for name in "${order[@]}"; do
            kill -0 -- "-${comp_pid[$name]}" 2>/dev/null && alive=1
        done
        [[ $alive -eq 0 ]] && break
        sleep 0.1
    done
    for name in "${order[@]}"; do
        kill -KILL -- "-${comp_pid[$name]}" 2>/dev/null || true
    done
    if [[ $getty_stopped -eq 1 ]]; then
        systemctl start getty@tty1.service || true
    fi
}
trap cleanup INT TERM EXIT

launch radio "${ROOT}/radio/start.sh"
launch l3 "${ROOT}/winject-manager/start.sh"

if [[ "$DISPLAY_MODE" == "kmsdrm" ]] && systemctl is-active --quiet getty@tty1.service; then
    # The receiver takes tty1 for KD_GRAPHICS; the login prompt would draw over the video.
    systemctl stop getty@tty1.service
    getty_stopped=1
fi
launch streamer env RECEIVER_DISPLAY="$DISPLAY_MODE" "${ROOT}/receiver/start.sh"

echo "GS stack up; Ctrl-C to stop"
set +e
wait -n "${comp_pid[@]}"
status=$?
for name in "${order[@]}"; do
    if ! kill -0 "${comp_pid[$name]}" 2>/dev/null; then
        echo "${name} exited (status ${status}); stopping the rest" >&2
    fi
done
exit "$status"
