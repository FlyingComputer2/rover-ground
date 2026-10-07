#!/usr/bin/env python3
"""Paced UDP into rover manager upstream-2 bind (127.0.0.1:22100).

Payloads are opaque to the manager; LC sequencing is applied on air. Keep
--payload-size <= 1445 (manager app limit).
"""

from __future__ import annotations

import argparse
import socket
import struct
import time

MAGIC = b"LT01"
HDR = struct.Struct("!4sI")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dest", default="127.0.0.1:22100", help="rover upstream-2 bind")
    p.add_argument("--kbps", type=float, default=12000.0)
    p.add_argument("--payload-size", type=int, default=400)
    p.add_argument("--duration", type=float, default=0.0, help="0 = run until killed")
    args = p.parse_args()
    host, port_s = args.dest.rsplit(":", 1)
    port = int(port_s)
    if args.payload_size < HDR.size:
        raise SystemExit(f"--payload-size must be >= {HDR.size}")

    body = HDR.size + max(0, args.payload_size - HDR.size)
    interval = (body * 8.0) / (args.kbps * 1000.0)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    seq = 0
    start = time.monotonic()
    next_t = start
    sent = 0
    try:
        while True:
            now = time.monotonic()
            if args.duration > 0 and now - start >= args.duration:
                break
            if now < next_t:
                time.sleep(min(0.001, next_t - now))
                continue
            pkt = HDR.pack(MAGIC, seq)
            if args.payload_size > HDR.size:
                pkt += bytes(args.payload_size - HDR.size)
            sock.sendto(pkt, (host, port))
            seq += 1
            sent += 1
            next_t += interval
            if next_t < now - interval:
                next_t = now
    except KeyboardInterrupt:
        pass
    elapsed = max(time.monotonic() - start, 1e-6)
    print(f"sent={sent} elapsed={elapsed:.1f}s kbps~{(sent * body * 8) / elapsed / 1000:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
