# rover-ground

Ground station on the Orange Pi 5 (RK3588): **winject-l3** manager and **winject-radio-realtek**
on a local RTL8812AU, WireGuard to the rover, and **vstreamer** `sdl_stream_receiver` for
video on the desktop.

```
GS (Orange Pi 5)                                              Rover (H3)
sdl_stream_receiver ─┐                                     ┌─ uvc_stream_sender
                     ├─ winject-manager ─ winject-radio-realtek ~~air~~ radio ─ winject-manager ─┤
wg (winject iface) ──┘   (winject-l3)    (RTL8812AU)                            (winject-l3)    └─ wg (winject iface)
```

## Upstreams

Same upstream ids on both ends; buses swap at the peer.

| id | Stream | GS (tx / rx, host) | Rover (tx / rx, host) | Manager FEC |
|----|--------|--------------------|------------------------|-------------|
| 0 | WireGuard | `a1` / `b2`, connect `127.0.0.1:51820` | `b2` / `a1`, bind `127.0.0.1:22180` | RS k=1 n=3 |
| 1 | Video RTP + reverse telemetry | `d4` / `c3`, connect `127.0.0.1:21082` | `c3` / `d4`, bind `127.0.0.1:22081` | NONE |

## Ports

| Service | Address | Notes |
|---------|---------|--------|
| WireGuard | `192.168.128.1:51820` / iface `winject` | MTU 1280 |
| Radio m-plane | `127.0.0.1:2201` | winject-radio-realtek |
| Radio d-plane | `127.0.0.1:9000` | inject + forward |
| Manager console | `192.168.128.1:2424` | UDP, replies to source |
| Video app (GS) | listen `127.0.0.1:21082` | `sdl_stream_receiver` |
| Video app (rover) | peer `127.0.0.1:22081` | `uvc_stream_sender` |
| Receiver console | `192.168.128.1:5091` | vstreamer metrics |
| Sender console (rover) | `192.168.128.2:5090` | rover-side |

Air: channel **13**, **OFDM_54M**, power **20**, domain **0xB00B**, `max_rate_kbps = 80000`.
`winject-manager/config.cfg` currently carries the bench override (**OFDM_36M**, power **2**: at
short range 20 dBm overloads the receiver); restore 54M / 20 in the field.

Both managers must run winject-l3 **v1.0.1** or later: the LC header carries the FEC flag and
the FEC shard header is 5 bytes, which v1.0.0 cannot read.
Use `--max-datagram 1445` on all vstreamer apps.

## Build

From sibling checkouts (not vendored here):

```bash
# vstreamer GS receiver
cd /home/ubuntu/development/vstreamer
cmake -S . -B out/gs -DENABLE_NOISE_SOURCE=OFF -DENABLE_V4L2_SOURCE=OFF \
      -DENABLE_JPEG_DECODER_MULTICORE=OFF -DENABLE_SDL_SINK=ON
cmake --build out/gs -j"$(nproc)"

# winject-manager
cd /home/ubuntu/development/winject-l3
cmake -S src/manager -B build_manager_arm -DCMAKE_BUILD_TYPE=Release
cmake --build build_manager_arm -j"$(nproc)"

# winject-radio-realtek
cd /home/ubuntu/development/winject-radio-realtek
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
ctest --test-dir build
```

## Install

```bash
sudo ./setup.sh
```

Requires `/etc/wireguard/winject.conf` (see `wireguard/winject.conf.example`). Cold boot
brings up WireGuard, radio, and manager; video does not start until the desktop receiver runs.

## Video

From a logged-in desktop session (SDL window):

```bash
/home/ubuntu/development/rover-ground/receiver/start.sh
```

Or log in as `ubuntu` for XDG autostart (`autostart/gs-video-receiver.desktop`).

## Debug

- Logs: `journalctl -u winject-radio-realtek`, `journalctl -u winject-manager`,
  `journalctl -u wg-quick@winject`
- Manager console: `echo lur | nc -u -w1 192.168.128.1 2424` (also `lut`, `radio_stats`,
  `get_metrics`)
- Receiver console: UDP `192.168.128.1:5091`
- Oversized app datagrams: manager metric `upstream_<id>_app_rx_oversize_pkt` (keep at 0 with
  `--max-datagram 1445`)

## Rover counterpart

Mirror upstreams with buses swapped and server binds on the rover host:

- Upstream 0: `tx_bus = b2`, `rx_bus = a1`, bind `127.0.0.1:22180`, FEC RS k=1 n=3
- Upstream 1: `tx_bus = c3`, `rx_bus = d4`, bind `127.0.0.1:22081`, `fec.type = NONE`
- Same air settings: channel 13, `OFDM_54M`, `max_rate_kbps = 80000`, domain `0xB00B`
- Use `winject.dplane_port` and `net.dplane_port` (not legacy `inject_port` / `forward_port`)
- Manager console: bind `192.168.128.2:2424`
- Sender: `uvc_stream_sender --peer 127.0.0.1:22081 --max-datagram 1445
  --console 192.168.128.2:5090`
- WireGuard client: drop split `0.0.0.0/1` + `128.0.0.0/1` routes; use
  `AllowedIPs = 192.168.128.1/32` (no internet through the GS)
