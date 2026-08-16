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
LANGS = ["en", "fr", "de"]

# Initialize OCR reader (cached across calls)
_ocr = None

def get_ocr():
    global _ocr
    if _ocr is None:
        _ocr = easyocr.Reader(
            LANGS,
            gpu=use_gpu,
            verbose=False,
            download_enabled=True,
        )
    return _ocr


def run_ocr(image_path):
    """Run OCR on image and return extracted text."""
    reader = get_ocr()
    results = reader.readtext(
        image_path,
        text_threshold=0.5,       # Confidence threshold for text detection
        low_text=0.3,             # Low text threshold
        canvas_size=1280,         # Max image size
        batch_size=1,
        workers=1,
        detail=1,                 # Return detailed results
    )

    if not results:
        return ""

    # Sort by y-position (top to bottom), then x-position (left to right)
    # Group lines by y-coordinate
    lines = []
    for bbox, text, confidence in results:
        if confidence >= 0.5:
            # Get center y for sorting
            y_center = sum(point[1] for point in bbox) / 4
            lines.append((y_center, text, confidence))

    # Sort by y position
    lines.sort(key=lambda x: x[0])

    # Group lines that are on the same horizontal line
    grouped = []
    current_line = ""
    last_y = None
    y_threshold = 10  # pixels

    for y_center, text, confidence in lines:
        if last_y is None or abs(y_center - last_y) > y_threshold:
            if current_line:
                grouped.append(current_line)
            current_line = text
            last_y = y_center
        else:
            # Same line, append with space
            if current_line and not current_line.endswith((' ', '\t')):
                current_line += " "
            current_line += text

    if current_line:
        grouped.append(current_line)

    return "\n".join(grouped)


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
