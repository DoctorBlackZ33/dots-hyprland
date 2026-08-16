#!/bin/bash
# OCR wrapper script (EasyOCR + PyTorch on NVIDIA RTX 2080 Ti)
# Usage: paddle_ocr.sh <image_path>
#        cat image.png | paddle_ocr.sh
# Outputs extracted text to stdout
#
# GPU control:
#   OCR_GPU=0  Force CPU
#   OCR_GPU=1  Force GPU
#   (unset)    Auto-detect: use GPU if >2GB VRAM free on 2080 Ti

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/ocr-venv"

# Auto-detect GPU availability if not explicitly set
if [ -z "$OCR_GPU" ]; then
    # Check if nvidia-smi is available and 2080 Ti has >2GB free
    if command -v nvidia-smi &>/dev/null; then
        # Get free VRAM in MiB (total - used)
        gpu_info=$(nvidia-smi --query-gpu=memory.total,memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$gpu_info" ]; then
            total_mem=$(echo "$gpu_info" | cut -d',' -f1 | tr -d ' ')
            used_mem=$(echo "$gpu_info" | cut -d',' -f2 | tr -d ' ')
            free_mem=$((total_mem - used_mem))
            # Use GPU if >2048 MB free
            if [ "$free_mem" -gt 2048 ]; then
                export OCR_GPU=1
            else
                export OCR_GPU=0
            fi
        else
            export OCR_GPU=0
        fi
    else
        export OCR_GPU=0
    fi
fi

# Use venv Python if it exists, otherwise fall back to system python
if [ -x "$VENV_DIR/bin/python3" ]; then
    PYTHON="$VENV_DIR/bin/python3"
else
    PYTHON="${PYTHON:-python3}"
fi

exec "$PYTHON" "$SCRIPT_DIR/paddle_ocr.py" "$@"
