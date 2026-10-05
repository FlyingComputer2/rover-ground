#!/usr/bin/env bash
# Load rtl88xxau_wfb for the GS dongle and exec winject-radio-realtek (systemd runs as root).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFACE="wlx00c0cabce06f"
BIN="${WINJECT_RADIO_REALTEK_BIN:-/home/ubuntu/development/winject-radio-realtek/build/src/radio/winject-radio-realtek}"

ensure_wfb_driver_for_iface() {
    modprobe 88XXau_wfb

    local wfb="/sys/bus/usb/drivers/rtl88xxau_wfb"
    if [[ ! -d "$wfb" ]]; then
        echo "error: USB driver rtl88xxau_wfb not registered" >&2
        return 1
    fi

    local dev="/sys/class/net/${IFACE}/device"
    if [[ ! -e "$dev" ]]; then
        echo "error: interface ${IFACE} not found" >&2
        return 1
    fi

    dev="$(readlink -f "$dev")"
    local id
    id="$(basename "$dev")"

    if [[ -L "${dev}/driver" ]]; then
        local driver
        driver="$(basename "$(readlink "${dev}/driver")")"
        if [[ "$driver" == "rtl88xxau_wfb" ]]; then
            return 0
        fi
        if [[ "$driver" == "rtl88XXau" ]]; then
            local stock="/sys/bus/usb/drivers/rtl88XXau"
            if [[ -d "$stock" ]]; then
                echo "$id" >"${stock}/unbind"
                echo "$id" >"${wfb}/bind"
            fi
        fi
    fi

    modprobe -r 88XXau 2>/dev/null || true
}

ensure_wfb_driver_for_iface
nmcli device set "$IFACE" managed no 2>/dev/null || true
exec "$BIN" "${ROOT}/radio.cfg"
