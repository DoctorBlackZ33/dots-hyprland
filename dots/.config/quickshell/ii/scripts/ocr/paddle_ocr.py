#!/usr/bin/env python3
"""
EasyOCR wrapper for screen region OCR.
Reads an image from stdin or a file path argument, runs EasyOCR, outputs text to stdout.
Uses GPU when available (CUDA for NVIDIA, will use CPU for AMD ROCm until support improves).

Usage:
    paddle_ocr.sh <image_path>          # File path argument
    cat image.png | paddle_ocr.sh       # stdin mode
    paddle_ocr.sh                       # stdin mode (no args)

Output: Plain text to stdout (pipe to wl-copy for clipboard)
"""

import sys
import os
import tempfile
import warnings

# Suppress PyTorch deprecation warnings
warnings.filterwarnings("ignore", category=UserWarning, module="torch")

try:
    import easyocr
except ImportError:
    print("ERROR: EasyOCR not installed.", file=sys.stderr)
    print("Install with: pip3 install easyocr", file=sys.stderr)
    sys.exit(1)

# Detect available GPU
use_gpu = False
try:
    import torch
    if torch.cuda.is_available():
        use_gpu = True
    # Check for ROCm (AMD GPU)
    elif hasattr(torch.version, 'hip') and torch.version.hip is not None:
        use_gpu = True
except Exception:
    pass

# Override with environment variable
if os.environ.get("OCR_GPU") == "0":
    use_gpu = False
elif os.environ.get("OCR_GPU") == "1":
    use_gpu = True

# Languages to recognize - English, French, German
# Override with OCR_LANGS env (comma separated), e.g. OCR_LANGS=en
LANGS = [l.strip() for l in os.environ.get("OCR_LANGS", "en,fr,de").split(",") if l.strip()]

# Initialize OCR reader (cached across calls)
_ocr = None
_ocr_gpu = None

def get_ocr(gpu=None):
    """Return a cached EasyOCR reader.

    gpu: True/False to force a device; None = use auto-detected `use_gpu`.
    The reader is only rebuilt when the requested device differs from the cache.
    """
    global _ocr, _ocr_gpu
    eff_gpu = use_gpu if gpu is None else bool(gpu)
    if _ocr is not None and _ocr_gpu != eff_gpu:
        _ocr = None
    if _ocr is None:
        _ocr = easyocr.Reader(
            LANGS,
            gpu=eff_gpu,
            verbose=False,
            download_enabled=True,
        )
        _ocr_gpu = eff_gpu
    return _ocr


def _group_lines(results):
    """Order detected boxes into lines: cluster by y-center, then sort by x.

    Clustering against the cluster's first box keeps a slightly drifting line
    together; the y-threshold scales with the median box height (min 10 px) so
    it works for both small UI text and large screenshots.
    """
    boxes = []
    for bbox, text, confidence in results:
        if confidence < 0.5:
            continue
        x_center = sum(p[0] for p in bbox) / 4
        y_center = sum(p[1] for p in bbox) / 4
        height = max(p[1] for p in bbox) - min(p[1] for p in bbox)
        boxes.append((y_center, x_center, height, text))
    if not boxes:
        return ""

    boxes.sort(key=lambda b: b[0])
    heights = sorted(b[2] for b in boxes)
    y_threshold = max(10.0, 0.6 * heights[len(heights) // 2])

    clusters = []  # [y_ref, [(x_center, text), ...]]
    for y_center, x_center, _h, text in boxes:
        if clusters and abs(y_center - clusters[-1][0]) <= y_threshold:
            clusters[-1][1].append((x_center, text))
        else:
            clusters.append([y_center, [(x_center, text)]])

    return "\n".join(" ".join(t for _, t in sorted(items)) for _y, items in clusters)


def run_ocr(image_path):
    """Run OCR on image and return extracted text."""
    reader = get_ocr()
    results = reader.readtext(
        image_path,
        text_threshold=0.5,       # Confidence threshold for text detection
        low_text=0.3,             # Low text threshold
        canvas_size=1280,         # Max image size
        batch_size=1,
        workers=0,                # in-process DataLoader; workers>0 spawns a
                                  # forkserver subprocess per call on py3.14
        detail=1,                 # Return detailed results
    )

    if not results:
        return ""
    return _group_lines(results)


def main():
    # Determine image source
    if len(sys.argv) > 1:
        # File path argument
        image_path = sys.argv[1]
        if not os.path.exists(image_path):
            print(f"ERROR: File not found: {image_path}", file=sys.stderr)
            sys.exit(1)
        temp_file = None
    else:
        # Read from stdin
        if not sys.stdin.isatty():
            temp_file = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            temp_file.write(sys.stdin.buffer.read())
            temp_file.close()
            image_path = temp_file.name
        else:
            print("ERROR: No input provided. Pass image path or pipe image data.", file=sys.stderr)
            print("Usage: paddle_ocr.sh <image_path>  OR  cat image.png | paddle_ocr.sh", file=sys.stderr)
            sys.exit(1)

    try:
        text = run_ocr(image_path)
        if text:
            print(text)
        else:
            print("No text detected.", file=sys.stderr)
    except Exception as e:
        print(f"OCR error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Clean up temp file if we created one
        if temp_file:
            try:
                os.unlink(image_path)
            except OSError:
                pass


if __name__ == "__main__":
    main()
