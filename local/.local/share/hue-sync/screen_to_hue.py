#!/usr/bin/env python3
"""
Screen-to-Hue ambient lighting sync for Wayland.
Captures screen via grim, extracts colors, sends to Hue bridge via API v1.
"""

import subprocess
import sys
import time
import json
import os
import signal
from pathlib import Path

import numpy as np
from PIL import Image

# ── Configuration ──────────────────────────────────────────────────────────

BRIDGE_IP = "192.168.1.107"
API_KEY = os.environ.get("HUE_API_KEY", "n8bg5lkSIOfUQVwMxaGA5G44zVvnaWjgdOWS8h3h")
SCREEN_OUTPUT = os.environ.get("HUE_SCREEN_OUTPUT", "DP-2")

# Zones defined as (x, y, width, height) in screen pixel coords
# Default: horizontal strips across the full screen
# Override via HUE_ZONES env var as JSON:
#   '[[0,0,2560,200],[0,200,2560,200],[0,400,2560,200],[0,600,2560,200],[0,800,2560,200],[0,1000,2560,200]]'
DEFAULT_ZONES = [
    (0, 0, 2560, 200),
    (0, 200, 2560, 200),
    (0, 400, 2560, 200),
    (0, 600, 2560, 200),
    (0, 800, 2560, 200),
    (0, 1000, 2560, 200),
]

LIGHT_MAP = {
    0: 2,   # top strip -> Hue lightstrip
    1: 2,   # upper -> Hue lightstrip
    2: 2,   # upper-mid -> Hue lightstrip
    3: 5,   # lower-mid -> Hue play 1
    4: 6,   # lower -> Hue play 2
    5: 6,   # bottom -> Hue play 2
}

FPS = int(os.environ.get("HUE_SYNC_FPS", "5"))
CAPTURE_WIDTH = int(os.environ.get("HUE_CAPTURE_WIDTH", "2560"))
CAPTURE_HEIGHT = int(os.environ.get("HUE_CAPTURE_HEIGHT", "1440"))

# ── Globals ────────────────────────────────────────────────────────────────

running = True


def signal_handler(sig, frame):
    global running
    running = False


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

# ── Helpers ────────────────────────────────────────────────────────────────


def parse_zones():
    """Parse zones from env var or use defaults."""
    zones_env = os.environ.get("HUE_ZONES")
    if zones_env:
        try:
            return json.loads(zones_env)
        except json.JSONDecodeError:
            print(f"Invalid HUE_ZONES JSON: {zones_env}, using defaults")
    return DEFAULT_ZONES


def get_screen_size():
    """Get screen dimensions from Hyprland."""
    try:
        result = subprocess.run(
            ["hyprctl", "monitors", "-j"],
            capture_output=True, text=True, timeout=5
        )
        monitors = json.loads(result.stdout)
        for m in monitors:
            if m.get("name") == SCREEN_OUTPUT:
                return m.get("width", 2560), m.get("height", 1440)
    except (FileNotFoundError, json.JSONDecodeError, subprocess.TimeoutExpired):
        pass
    return CAPTURE_WIDTH, CAPTURE_HEIGHT


def capture_screen(zones):
    """Capture screen via grim and crop to zone areas."""
    import tempfile

    # Determine total capture area
    min_x = max(0, min(z[0] for z in zones))
    min_y = max(0, min(z[1] for z in zones))
    max_x = min(CAPTURE_WIDTH, max(z[0] + z[2] for z in zones))
    max_y = min(CAPTURE_HEIGHT, max(z[1] + z[3] for z in zones))

    capture_w = max_x - min_x
    capture_h = max_y - min_y

    # Capture full output, then crop
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        # Capture full output to temp file (grim geometry is broken in 1.5.0)
        # Use -s 1 to get full resolution (default applies scale factor)
        cmd = ["grim", "-s", "1", "-o", SCREEN_OUTPUT, tmp_path]
        proc = subprocess.run(cmd, capture_output=True, timeout=3)
        if proc.returncode != 0 or not os.path.exists(tmp_path):
            return None

        # Load and crop
        img = Image.open(tmp_path).convert("RGB")
        cropped = img.crop((min_x, min_y, max_x, max_y))
        return np.array(cropped)
    except (subprocess.TimeoutExpired, Exception) as e:
        print(f"Capture error: {e}")
        return None
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def extract_zone_colors(image, zones, offsets):
    """Extract mean color from each zone."""
    colors = {}
    for i, zone in enumerate(zones):
        x, y, w, h = zone
        # Apply offset to map zone to image coordinates
        img_x = x - offsets[0]
        img_y = y - offsets[1]

        if img_x < 0: img_x = 0
        if img_y < 0: img_y = 0

        # Clip to image bounds
        if img_x >= image.shape[1] or img_y >= image.shape[0]:
            continue

        zone_img = image[
            img_y:img_y + h,
            img_x:img_x + w
        ]

        if zone_img.size > 0:
            # Extract dominant color using k-means with k=3
            pixels = zone_img.reshape(-1, 3).astype(np.float32)
            # Simple mean is fast and good enough
            mean_color = np.mean(pixels, axis=0)
            colors[i] = tuple(int(c) for c in mean_color)
    return colors


def rgb_to_xy(r, g, b):
    """Convert RGB to CIE xy color coordinates for Hue."""
    # sRGB to linear
    def linearize(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    r_lin = linearize(r)
    g_lin = linearize(g)
    b_lin = linearize(b)

    # Linear RGB to XYZ (D65)
    x = r_lin * 0.4124564 + g_lin * 0.3575761 + b_lin * 0.1804375
    y = r_lin * 0.2126729 + g_lin * 0.7151522 + b_lin * 0.0721750
    z = r_lin * 0.0193339 + g_lin * 0.1191920 + b_lin * 0.9503041

    # XYZ to xy
    sum_xyz = x + y + z
    if sum_xyz == 0:
        return 0.5, 0.5  # fallback white

    return x / sum_xyz, y / sum_xyz


def update_hue_light(light_id, r, g, b, brightness=123):
    """Update a Hue light via API v1."""
    xy = rgb_to_xy(r, g, b)

    url = f"http://{BRIDGE_IP}/api/{API_KEY}/lights/{light_id}/state"
    payload = {
        "on": True,
        "xy": list(xy),
        "bri": brightness,
        "transitiontime": 2,  # ~0.5s transition
    }

    try:
        import requests
        resp = requests.put(url, json=payload, timeout=5)
        if resp.ok:
            return True
        else:
            print(f"  Light {light_id} error: {resp.status_code} {resp.text[:80]}")
            return False
    except requests.RequestException as e:
        print(f"  Light {light_id} request error: {e}")
        return False


def print_usage():
    """Print usage information."""
    print("""
Usage: screen_to_hue.py [COMMAND]

Commands:
  start     Start screen-to-Hue sync (default)
  stop      Stop running sync process
  status    Check if sync is running
  test      Test single frame capture and color update

Environment Variables:
  HUE_API_KEY       Hue API key (default: from settings.json)
  HUE_ZONES         Zone config as JSON array
  HUE_SCREEN_OUTPUT Screen output name (default: DP-2)
  HUE_SYNC_FPS      Target FPS (default: 5)
  HUE_CAPTURE_WIDTH Capture width (default: 2560)
  HUE_CAPTURE_HEIGHT Capture height (default: 1440)
""")


# ── Main ──────────────────────────────────────────────────────────────────


def run_sync():
    """Run the screen-to-Hue sync loop."""
    zones = parse_zones()
    offsets = (0, 0)  # offset from capture start

    print(f"Starting screen-to-Hue sync")
    print(f"  Zones: {len(zones)}")
    print(f"  FPS: {FPS}")
    print(f"  Light map: {LIGHT_MAP}")

    last_update = 0
    frame_count = 0

    while running:
        # Capture screen
        image = capture_screen(zones)
        if image is None:
            time.sleep(0.1)
            continue

        # Extract colors
        colors = extract_zone_colors(image, zones, offsets)
        if not colors:
            time.sleep(0.1)
            continue

        # Update lights
        frame_count += 1
        if frame_count % FPS == 0:
            for zone_idx, color in colors.items():
                light_id = LIGHT_MAP.get(zone_idx)
                if light_id and color:
                    update_hue_light(light_id, *color)

        last_update = time.time()
        time.sleep(1.0 / FPS)

    print("Sync stopped.")


def test_sync():
    """Test single frame capture and update."""
    zones = parse_zones()

    print("Testing single frame capture...")
    image = capture_screen(zones)
    if image is None:
        print("FAILED: Could not capture screen")
        return

    print(f"Captured: {image.shape}")

    colors = extract_zone_colors(image, zones, (0, 0))
    print(f"Extracted {len(colors)} zone colors:")
    for i, color in colors.items():
        xy = rgb_to_xy(*color)
        light_id = LIGHT_MAP.get(i)
        print(f"  Zone {i}: RGB{color} -> xy{xy} -> light {light_id}")

    print("\nUpdating lights...")
    for zone_idx, color in colors.items():
        light_id = LIGHT_MAP.get(zone_idx)
        if light_id and color:
            success = update_hue_light(light_id, *color)
            print(f"  Light {light_id}: {'OK' if success else 'FAIL'}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd == "start":
            run_sync()
        elif cmd == "stop":
            pid_file = Path("/tmp/hue-sync.pid")
            if pid_file.exists():
                pid = int(pid_file.read_text().strip())
                try:
                    os.kill(pid, signal.SIGTERM)
                    print(f"Stopped sync (PID {pid})")
                except ProcessLookupError:
                    print("Sync already stopped")
                pid_file.unlink()
            else:
                print("No sync running")
        elif cmd == "status":
            pid_file = Path("/tmp/hue-sync.pid")
            if pid_file.exists():
                pid = int(pid_file.read_text().strip())
                try:
                    os.kill(pid, 0)
                    print(f"Sync running (PID {pid})")
                except ProcessLookupError:
                    print("Sync not running (stale PID file)")
            else:
                print("Sync not running")
        elif cmd == "test":
            test_sync()
        elif cmd == "help" or cmd == "-h":
            print_usage()
        else:
            print(f"Unknown command: {cmd}")
            print_usage()
    else:
        run_sync()
