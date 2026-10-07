#!/usr/bin/env python3
"""UDP sink for GS upstream-2 connect_address (127.0.0.1:21100).

Keeps the manager client path active; prints throughput for bench checks.
RX loss investigation uses manager lur/get_metrics on upstream 2, not this process.
"""

from __future__ import annotations

import argparse
import socket
import time


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bind", default="127.0.0.1:21100")
    p.add_argument("--quiet", action="store_true")
    args = p.parse_args()
    host, port_s = args.bind.rsplit(":", 1)
    port = int(port_s)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((host, port))
    sock.settimeout(1.0)
    nbytes = 0
    npkts = 0
    t0 = time.monotonic()
    last = t0
    try:
        while True:
            try:
                data, _ = sock.recvfrom(65535)
                nbytes += len(data)
                npkts += 1
            except socket.timeout:
                pass
            now = time.monotonic()
            if not args.quiet and now - last >= 5.0:
                dt = now - last
                print(
                    f"sink pkts={npkts} Mbps~{(nbytes * 8) / (now - t0) / 1e6:.2f}",
                    flush=True,
                )
                last = now
    except KeyboardInterrupt:
        pass
    elapsed = max(time.monotonic() - t0, 1e-6)
    print(f"total pkts={npkts} bytes={nbytes} elapsed={elapsed:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
