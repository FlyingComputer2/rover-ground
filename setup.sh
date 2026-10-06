#!/usr/bin/env bash
# Install rover-ground units and configs on this GS host (run as root).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART_USER="${SUDO_USER:-ubuntu}"
AUTOSTART_HOME="$(getent passwd "$AUTOSTART_USER" | cut -d: -f6)"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: run as root (sudo ./setup.sh)" >&2
    exit 1
fi

install -m 0644 "${ROOT}/systemd/modprobe.d/blacklist-88XXau.conf" \
    /etc/modprobe.d/blacklist-88XXau.conf
install -m 0644 "${ROOT}/systemd/winject-radio-realtek.service" \
    /etc/systemd/system/winject-radio-realtek.service
install -m 0644 "${ROOT}/systemd/winject-manager.service" \
    /etc/systemd/system/winject-manager.service
install -m 0644 "${ROOT}/systemd/gs-video-receiver.service" \
    /etc/systemd/system/gs-video-receiver.service
install -d /etc/systemd/system/wg-quick@winject.service.d
install -m 0644 "${ROOT}/systemd/wg-quick@winject.service.d/override.conf" \
    /etc/systemd/system/wg-quick@winject.service.d/override.conf

systemctl daemon-reload

if [[ ! -f /etc/wireguard/winject.conf ]]; then
    echo "error: /etc/wireguard/winject.conf missing; see ${ROOT}/wireguard/winject.conf.example" >&2
    exit 1
fi
if grep -q MASQUERADE /etc/wireguard/winject.conf; then
    echo "warning: /etc/wireguard/winject.conf still has MASQUERADE; rover would get internet via GS" >&2
fi

install -d -o "$AUTOSTART_USER" -g "$AUTOSTART_USER" \
    "${AUTOSTART_HOME}/.config/autostart"
install -m 0644 -o "$AUTOSTART_USER" -g "$AUTOSTART_USER" \
    "${ROOT}/autostart/gs-video-receiver.desktop" \
    "${AUTOSTART_HOME}/.config/autostart/gs-video-receiver.desktop"

enable_restart() {
    local unit="$1"
    systemctl enable "$unit"
    systemctl restart "$unit"
    if ! systemctl is-active --quiet "$unit"; then
        systemctl status "$unit" --no-pager || true
        exit 1
    fi
}

enable_restart wg-quick@winject.service
enable_restart winject-radio-realtek.service
enable_restart winject-manager.service

echo "Smoke checks (warnings only):"
ss -uln | grep -E ':2201|:2424' || echo "warning: expected UDP 127.0.0.1:2201 and 192.168.128.1:2424"
echo lur | nc -u -w1 192.168.128.1 2424 || echo "warning: manager console lur failed"
ping -c3 -W2 192.168.128.2 || echo "warning: ping 192.168.128.2 failed"

# Headless GS (no desktop session to run the autostart entry): the receiver unit drives HDMI
# through KMS/DRM on tty1.
if [[ "$(systemctl get-default)" == "multi-user.target" ]]; then
    enable_restart gs-video-receiver.service
    echo "Video: gs-video-receiver.service (KMS/DRM on tty1)."
else
    echo "Video: run ${ROOT}/receiver/start.sh from a desktop session (or log in for autostart)."
fi
