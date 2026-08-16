import os
import json
import math
import subprocess
import tempfile
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
from PIL import Image

# ⚠️ CHANGE THIS to your actual wallpaper folder
WALLPAPER_DIR = Path.home() / "Pictures/Wallpapers"
CACHE_FILE = WALLPAPER_DIR / ".oklab_cache.json"

SUPPORTED_IMAGES = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
SUPPORTED_VIDEOS = {".mp4", ".webm", ".mkv", ".gif"}


def rgb_to_oklab_lch(r, g, b):
    """Converts 0-255 RGB to OKLAB LCH (Lightness, Chroma, Hue)."""
    r, g, b = r / 255.0, g / 255.0, b / 255.0

    # 1. sRGB to Linear sRGB
    def linearize(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    rl, gl, bl = linearize(r), linearize(g), linearize(b)

    # 2. Linear sRGB to LMS
    l = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl
    m = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl
    s = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl

    # 3. Non-linear LMS
    l_ = l ** (1 / 3) if l > 0 else 0
    m_ = m ** (1 / 3) if m > 0 else 0
    s_ = s ** (1 / 3) if s > 0 else 0

    # 4. LMS to OKLAB
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

    # 5. Convert a, b to Chroma and Hue (Degrees)
    C = math.sqrt(a**2 + b**2)
    h = math.degrees(math.atan2(b, a))
    if h < 0:
        h += 360

    return round(L, 4), round(C, 4), round(h, 2)


def get_average_color_image(filepath):
    """Downscales image to 1x1 to instantly get the mathematical average color."""
    try:
        with Image.open(filepath) as img:
            img = img.convert("RGB").resize((1, 1), Image.Resampling.BILINEAR)
            return img.getpixel((0, 0))
    except Exception as e:
        print(f"Error processing image {filepath}: {e}")
        return None


def get_average_color_video(filepath):
    """Extracts 5 evenly spaced frames and averages their colors."""
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            # Tell ffmpeg to extract 5 frames at 1x1 resolution directly
            cmd = [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-i",
                str(filepath),
                "-vf",
                "select='not(mod(n,60))',scale=1:1",
                "-vframes",
                "5",
                f"{tmpdir}/%03d.png",
            ]
            subprocess.run(cmd, check=True)

            r_total, g_total, b_total, count = 0, 0, 0, 0
            for frame in Path(tmpdir).glob("*.png"):
                color = get_average_color_image(frame)
                if color:
                    r_total += color[0]
                    g_total += color[1]
                    b_total += color[2]
                    count += 1

            if count == 0:
                return None
            return (r_total // count, g_total // count, b_total // count)
    except Exception as e:
        print(f"Error processing video {filepath}: {e}")
        return None


def process_file(filepath):
    """Determines file type and calculates OKLAB."""
    ext = filepath.suffix.lower()
    rgb = None

    if ext in SUPPORTED_IMAGES:
        rgb = get_average_color_image(filepath)
    elif ext in SUPPORTED_VIDEOS:
        rgb = get_average_color_video(filepath)

    if not rgb:
        return None

    L, C, h = rgb_to_oklab_lch(*rgb)
    return {
        "path": str(filepath),
        "type": "video" if ext in SUPPORTED_VIDEOS else "image",
        "mtime": filepath.stat().st_mtime,
        "L": L,
        "C": C,
        "h": h,
    }


def main():
    if not WALLPAPER_DIR.exists():
        print(f"Directory not found: {WALLPAPER_DIR}")
        return

    # Load cache so we don't re-process files
    cache = {}
    if CACHE_FILE.exists():
        with open(CACHE_FILE, "r") as f:
            cache = json.load(f)

    all_files = [
        p
        for p in WALLPAPER_DIR.iterdir()
        if p.is_file() and p.suffix.lower() in SUPPORTED_IMAGES | SUPPORTED_VIDEOS
    ]
    to_process = []

    for f in all_files:
        path_str = str(f)
        mtime = f.stat().st_mtime
        if path_str not in cache or cache[path_str]["mtime"] != mtime:
            to_process.append(f)

    if not to_process:
        print("✅ Cache is up to date. No new wallpapers found.")
        return

    print(f"⚙️  Processing {len(to_process)} new wallpapers across all CPU cores...")

    with ProcessPoolExecutor() as executor:
        results = executor.map(process_file, to_process)

    for res in results:
        if res:
            cache[res["path"]] = res

    # Clean up deleted files from cache
    current_paths = {str(p) for p in all_files}
    cache = {k: v for k, v in cache.items() if k in current_paths}

    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=2)

    print(f"✅ Indexed {len(to_process)} wallpapers. Cache saved to {CACHE_FILE}")


if __name__ == "__main__":
    main()
