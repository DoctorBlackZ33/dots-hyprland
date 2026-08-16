# Device Overrides

Per-device config overlays applied on top of the general fork configuration.

## Structure

```
devices/
└── <device_name>/
    └── .config/
        ├── hypr/custom/          # Device-specific monitor, env, keybinds
        ├── quickshell/ii/        # Device-specific quickshell overrides
        │   └── scripts/ocr/      # Device-specific OCR config
        ├── kitty/                # Device-specific kitty config
        └── ...                   # Mirrors .config/ structure
```

## Usage

```bash
# Preview general + device overrides
system update --device mydesktop --dry-run

# Deploy general + device overrides
system update --device mydesktop
```

Interactive `system update` presents `General only` and every discovered
device directory as a menu. The explicit `--device` form is useful for
scripts; `--general` selects the common configuration without a device
overlay.

## What to put here

- Monitor configurations (different displays per device)
- GPU-specific environment variables
- Device-specific keybinds
- Any hardware-specific overrides

General end-4-owned configs stay in `dots/.config/`. Personal partial
overlays stay in `local/`. Only hardware-specific deltas go here.
