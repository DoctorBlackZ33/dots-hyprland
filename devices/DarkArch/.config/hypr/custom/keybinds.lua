-- Custom keybinds
-- https://wiki.hypr.land/Configuring/Binds/
-- Add keybinds here using hl.bind()

-- Override OCR fallback (when quickshell is down) to use EasyOCR
local qsScripts = "$HOME/.config/quickshell/$qsConfig/scripts"
hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd(
    "pidof slurp || grim -g \"$(slurp $SLURP_ARGS)\" \"/tmp/ocr_image.png\" && " ..
    qsScripts .. "/ocr/paddle_ocr.sh \"/tmp/ocr_image.png\" | wl-copy && rm \"/tmp/ocr_image.png\""
))
