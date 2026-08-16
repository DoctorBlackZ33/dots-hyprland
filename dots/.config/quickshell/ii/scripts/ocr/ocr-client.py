#!/usr/bin/env python3
"""Tiny client for ocr-daemon.py.

Stdlib only (no torch import) so it starts in milliseconds.

Usage:
    ocr-client.py ping SOCKET              # exit 0 if daemon answers PING
    ocr-client.py run SOCKET IMAGE_FILE    # prints recognized text to stdout
"""

import socket
import struct
import sys

MAGIC = b"OCRV"
PING = b"PING"
PONG = b"PONG"
RECV_TIMEOUT = 300  # s; generous bound for first-run model downloads


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(min(1 << 20, n - len(buf)))
        if not chunk:
            raise ConnectionError("daemon closed connection")
        buf += chunk
    return buf


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: ocr-client.py ping|run SOCKET [IMAGE_FILE]\n")
        sys.exit(2)
    cmd, sock_path = sys.argv[1], sys.argv[2]

    if cmd == "ping":
        payload = PING
    elif cmd == "run":
        if len(sys.argv) < 4:
            sys.stderr.write("usage: ocr-client.py run SOCKET IMAGE_FILE\n")
            sys.exit(2)
        with open(sys.argv[3], "rb") as f:
            payload = f.read()
    else:
        sys.stderr.write(f"unknown command: {cmd}\n")
        sys.exit(2)

    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(RECV_TIMEOUT)
            s.connect(sock_path)
            s.sendall(MAGIC + struct.pack(">I", len(payload)) + payload)
            header = recv_exact(s, 8)
            magic = header[:4]
            length = struct.unpack(">I", header[4:])[0]
            if magic != MAGIC:
                raise ConnectionError(f"bad response magic {magic!r}")
            out = recv_exact(s, length)
    except OSError as e:
        sys.stderr.write(f"ocr-client: {e}\n")
        sys.exit(1)

    if cmd == "ping":
        sys.exit(0 if out == PONG else 1)
    sys.stdout.write(out.decode("utf-8"))


if __name__ == "__main__":
    main()
