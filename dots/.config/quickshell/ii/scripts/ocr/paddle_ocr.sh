#!/bin/bash
# OCR client: talks to a persistent EasyOCR daemon (ocr-daemon.py) so that
# per-keystroke latency is inference time only (~1s) instead of a multi-second
# python + model reload. The daemon is auto-spawned on first use if it is not
# already running, and kept warm by the hypr-ocr-daemon systemd user service.
#
# Usage: paddle_ocr.sh <image_path>     or    cat image.png | paddle_ocr.sh
# Outputs extracted text to stdout (pipe to wl-copy for the clipboard)
#
# Environment:
#   OCR_GPU=0|1      force CPU / GPU (GPU needs a CUDA build of torch;
#                    unset = auto: CPU unless nvidia-smi shows >2GB VRAM free)
#   OCR_LANGS        comma-separated easyocr languages (default: en,fr,de)
#   OCR_SOCKET       daemon socket path (default: $XDG_RUNTIME_DIR/hypr-ocr.sock)
#   OCR_START_TIMEOUT seconds to wait for a freshly spawned daemon (default 30)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# venv lives in XDG_STATE_HOME so the dots-hyprland update (rsync --delete on
# ~/.config/quickshell) can never wipe it
VENV_DIR="${OCR_VENV:-$HOME/.local/state/quickshell/ocr-venv}"

if [ ! -x "$VENV_DIR/bin/python3" ]; then
    echo "ERROR: OCR venv missing: $VENV_DIR" >&2
    exit 1
fi
PYTHON="$VENV_DIR/bin/python3"

# ---- resolve image: path argument or stdin --------------------------------
CLEANUP=""
if [ -n "$1" ]; then
    IMAGE="$1"
    if [ ! -f "$IMAGE" ]; then
        echo "ERROR: File not found: $IMAGE" >&2
        exit 1
    fi
else
    if [ -t 0 ]; then
        echo "ERROR: No input provided. Pass image path or pipe image data." >&2
        echo "Usage: paddle_ocr.sh <image_path>  OR  cat image.png | paddle_ocr.sh" >&2
        exit 1
    fi
    IMAGE="$(mktemp /tmp/ocr_input.XXXXXX).png"
    cat > "$IMAGE"
    CLEANUP="$IMAGE"
fi

# ---- daemon settings -------------------------------------------------------
DEVICE=""
case "${OCR_GPU:-auto}" in
    1|true|gpu) DEVICE="gpu" ;;
    0|false|cpu) DEVICE="cpu" ;;
esac

SOCKET="${OCR_SOCKET:-${XDG_RUNTIME_DIR:-/tmp}/hypr-ocr.sock}"
START_TIMEOUT="${OCR_START_TIMEOUT:-30}"

daemon_alive() {
    "$PYTHON" "$SCRIPT_DIR/ocr-client.py" ping "$SOCKET" >/dev/null 2>&1
}

ocr_request() {
    "$PYTHON" "$SCRIPT_DIR/ocr-client.py" run "$SOCKET" "$IMAGE"
}

spawn_daemon() {
    # spawn detached so the daemon outlives this script (and the keybind)
    (
        setsid nohup "$PYTHON" "$SCRIPT_DIR/ocr-daemon.py" --socket "$SOCKET" \
            ${DEVICE:+--device "$DEVICE"} >> "$SCRIPT_DIR/ocr-daemon.log" 2>&1 &
    )
    # wait until it answers (model loading happens on first start)
    local tries=$((START_TIMEOUT * 5))  # 0.2s polling
    while [ "$tries" -gt 0 ] && ! daemon_alive; do
        sleep 0.2
        tries=$((tries - 1))
    done
    daemon_alive
}

# ---- serve -----------------------------------------------------------------
if ! daemon_alive; then
    if ! spawn_daemon; then
        echo "ERROR: OCR daemon did not become ready in ${START_TIMEOUT}s (see $SCRIPT_DIR/ocr-daemon.log)" >&2
        [ -n "$CLEANUP" ] && rm -f "$CLEANUP"
        exit 1
    fi
fi

if ! ocr_request; then
    # daemon died mid-request (e.g. OOM kill): respawn and retry once
    echo "WARN: OCR daemon lost the request; respawning and retrying" >&2
    rm -f "$SOCKET" 2>/dev/null
    if ! spawn_daemon || ! ocr_request; then
        echo "ERROR: OCR request failed" >&2
        [ -n "$CLEANUP" ] && rm -f "$CLEANUP"
        exit 1
    fi
fi

if [ -n "$CLEANUP" ]; then rm -f "$CLEANUP"; fi
exit 0
