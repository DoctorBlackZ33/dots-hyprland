#!/usr/bin/env python3
"""Persistent EasyOCR daemon for sub-second OCR from Hyprland keybinds.

The EasyOCR model is loaded once at startup; every request is a single OCR
pass, so the per-keystroke latency is inference time only (typically well
under a second on CPU) instead of a multi-second process + model reload.

Protocol (unix socket):
    request : b"OCRV" + <4s big-endian length> + payload
              payload is PNG bytes, or b"PING" for a health check
    response: b"OCRV" + <4s big-endian length> + UTF-8 text (or b"PONG")

Run via the hypr-ocr-daemon systemd user service, or auto-spawned by
paddle_ocr.sh when no daemon answers.

Env:
    OCR_LANGS  comma-separated easyocr languages (default: en,fr,de)

CLI:
    ocr-daemon.py [--socket PATH] [--device auto|gpu|cpu]
        --device gpu needs a CUDA build of torch; auto falls back to CPU
        whenever CUDA is unavailable (the installed venv ships CPU torch,
        since the system's 2080 Ti is normally occupied by the LLM server).
"""

import argparse
import os
import signal
import socket
import struct
import sys
import tempfile
import threading
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

MAGIC = b"OCRV"
PING = b"PING"
PONG = b"PONG"
HEADER = struct.Struct(">4sI")
OCR_LOCK = threading.Lock()


def parse_args():
    parser = argparse.ArgumentParser(description="Persistent EasyOCR daemon")
    parser.add_argument(
        "--socket",
        default=os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "hypr-ocr.sock"),
        help="unix socket path (default: $XDG_RUNTIME_DIR/hypr-ocr.sock)",
    )
    parser.add_argument(
        "--device",
        choices=["auto", "gpu", "cpu"],
        default="auto",
        help="device selection (default: auto)",
    )
    return parser.parse_args()


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(min(1 << 20, n - len(buf)))
        if not chunk:
            raise ConnectionError("client gone")
        buf += chunk
    return buf


def daemon_alive(sock_path):
    """True if a healthy daemon already answers PING on this socket."""
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(2.0)
            s.connect(sock_path)
            s.sendall(HEADER.pack(MAGIC, len(PING)) + PING)
            header = recv_exact(s, 8)
            if header[:4] != MAGIC:
                return False
            length = struct.unpack(">I", header[4:])[0]
            return recv_exact(s, length) == PONG
    except OSError:
        return False


def handle_request(run_ocr, conn):
    header = recv_exact(conn, 8)
    if header[:4] != MAGIC:
        raise ValueError(f"bad magic {header[:4]!r}")
    length = struct.unpack(">I", header[4:])[0]
    payload = recv_exact(conn, length)

    if payload == PING:
        out = PONG
    else:
        # OCR runs serialized; PING is answered concurrently so liveness
        # probes never queue behind a long inference.
        with OCR_LOCK:
            tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            try:
                tmp.write(payload)
                tmp.close()
                text = run_ocr(tmp.name) or ""
            finally:
                os.unlink(tmp.name)
        out = text.encode("utf-8")

    conn.sendall(HEADER.pack(MAGIC, len(out)) + out)


def worker(conn, run_ocr):
    try:
        handle_request(run_ocr, conn)
    except Exception:
        traceback.print_exc()
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    args = parse_args()
    gpu = {"gpu": True, "cpu": False}.get(args.device)

    # Fail fast if a healthy daemon is already serving (avoids socket races
    # between systemd restarts and client auto-spawns).
    if daemon_alive(args.socket):
        print(f"another ocr-daemon already serving on {args.socket}; exiting", file=sys.stderr)
        return 0

    print(f"loading EasyOCR reader (device={args.device}, langs=OCR_LANGS or en,fr,de) ...",
          file=sys.stderr, flush=True)
    from paddle_ocr import get_ocr, run_ocr

    reader = get_ocr(gpu=gpu)
    print(f"ocr-daemon ready on {args.socket}", file=sys.stderr, flush=True)

    try:
        os.unlink(args.socket)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(args.socket)
    srv.listen(8)

    def _term(_signum, _frame):
        try:
            srv.close()
            os.unlink(args.socket)
        except OSError:
            pass
        os._exit(0)

    signal.signal(signal.SIGTERM, _term)
    signal.signal(signal.SIGINT, _term)

    while True:
        conn, _addr = srv.accept()
        threading.Thread(target=worker, args=(conn, run_ocr), daemon=True).start()


if __name__ == "__main__":
    sys.exit(main() or 0)
