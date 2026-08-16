#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_term() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/sequences.txt
  done

  sed -i "s/\$alpha/$term_alpha/g" "$STATE_DIR/user/generated/terminal/sequences.txt"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
        cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } &
      disown || true
    fi
  done
}

apply_qt() {
  sh "$CONFIG_DIR/scripts/kvantum/materialQT.sh"          # generate kvantum theme
  python "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" # apply config colors
}

apply_discord() {
  if [ ! -f "$SCRIPT_DIR/terminal/discord-template.css" ]; then
    echo "Discord template not found. Skipping."
    return
  fi

  mkdir -p ~/.config/vesktop/themes/
  cp "$SCRIPT_DIR/terminal/discord-template.css" "$STATE_DIR/user/generated/discord.theme.css"

  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR/user/generated/discord.theme.css"
  done

  cp "$STATE_DIR/user/generated/discord.theme.css" ~/.config/vesktop/themes/dynamic-rice.theme.css
}

apply_nvim() {
  if [ ! -f "$SCRIPT_DIR/terminal/nvim-template.lua" ]; then
    echo "Nvim template not found. Skipping."
    return
  fi

  mkdir -p ~/.config/nvim/lua/config/
  cp "$SCRIPT_DIR/terminal/nvim-template.lua" "$STATE_DIR/user/generated/dynamic_colors.lua"

  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR/user/generated/dynamic_colors.lua"
  done

  cp "$STATE_DIR/user/generated/dynamic_colors.lua" ~/.config/nvim/lua/config/dynamic_colors.lua
}

apply_starship() {
  if [ ! -f "$SCRIPT_DIR/terminal/starship-template.toml" ]; then
    echo "Starship template not found. Skipping."
    return
  fi

  cp "$SCRIPT_DIR/terminal/starship-template.toml" "$STATE_DIR/user/generated/starship.toml"

  # Replace specific Material color tokens with wallpaper-derived values
  # Starship's own $variables (cmd_duration, directory, etc.) are preserved
  python3 -c "
import sys

# Read color values from material_colors.scss
colors = {}
with open('$STATE_DIR/user/generated/material_colors.scss') as f:
    for line in f:
        if ':' in line and line.strip() and not line.startswith('#'):
            key = line.split(':')[0].strip()
            val = line.split(':')[1].strip().split(';')[0].strip().split()[-1]
            if key.startswith('\$'):
                colors[key] = val

# Read template
with open('$STATE_DIR/user/generated/starship.toml', 'r') as f:
    content = f.read()

# Replace only Material color tokens, never starship's own variables
replacements = {
    '\$primary': colors.get('\$primary', ''),
    '\$secondary': colors.get('\$secondary', ''),
    '\$tertiary': colors.get('\$tertiary', ''),
    '\$error': colors.get('\$error', ''),
    '\$success': colors.get('\$success', ''),
    '\$onSurface': colors.get('\$onSurface', ''),
}

for token, color in replacements.items():
    if color:
        content = content.replace(token, color if color.startswith('#') else '#' + color)

with open('$STATE_DIR/user/generated/starship.toml', 'w') as f:
    f.write(content)
"

  cp "$STATE_DIR/user/generated/starship.toml" ~/.config/starship.toml
}

apply_yazi() {
  if [ ! -f "$SCRIPT_DIR/terminal/yazi-template.toml" ]; then
    echo "Yazi template not found. Skipping."
    return
  fi

  cp "$SCRIPT_DIR/terminal/yazi-template.toml" "$STATE_DIR/user/generated/yazi-theme.toml"

  # Replace specific Material color tokens with wallpaper-derived values
  python3 -c "
import sys

# Read color values from material_colors.scss
colors = {}
with open('$STATE_DIR/user/generated/material_colors.scss') as f:
    for line in f:
        if ':' in line and line.strip() and not line.startswith('#'):
            key = line.split(':')[0].strip()
            val = line.split(':')[1].strip().split(';')[0].strip().split()[-1]
            if key.startswith('\$'):
                colors[key] = val

# Read template
with open('$STATE_DIR/user/generated/yazi-theme.toml', 'r') as f:
    content = f.read()

# Replace only Material color tokens
replacements = {
    '\$primary': colors.get('\$primary', ''),
    '\$secondary': colors.get('\$secondary', ''),
    '\$tertiary': colors.get('\$tertiary', ''),
    '\$error': colors.get('\$error', ''),
    '\$success': colors.get('\$success', ''),
    '\$onSurface': colors.get('\$onSurface', ''),
    '\$onSecondaryContainer': colors.get('\$onSecondaryContainer', ''),
    '\$surfaceContainerLow': colors.get('\$surfaceContainerLow', ''),
    '\$surfaceContainer': colors.get('\$surfaceContainer', ''),
    '\$outline': colors.get('\$outline', ''),
}

for token, color in replacements.items():
    if color:
        content = content.replace(token, color if color.startswith('#') else '#' + color)

with open('$STATE_DIR/user/generated/yazi-theme.toml', 'w') as f:
    f.write(content)
"

  # Create yazi config dir and copy theme
  mkdir -p ~/.config/yazi
  cp "$STATE_DIR/user/generated/yazi-theme.toml" ~/.config/yazi/theme.toml
}

apply_openrgb() {
  # Check if OpenRGB theming is explicitly disabled in config
  CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
  if [ -f "$CONFIG_FILE" ]; then
    disable_openrgb=$(jq -r '.appearance.wallpaperTheming.enableOpenRGB // "true"' "$CONFIG_FILE")
    if [ "$disable_openrgb" = "false" ]; then
      echo "OpenRGB theming disabled in config. Skipping."
      return
    fi
  fi

  # Check if openrgb binary exists
  if ! command -v openrgb &>/dev/null; then
    echo "OpenRGB not found. Skipping."
    return
  fi

  # Read colors from generated material colors
  MATERIAL_COLORS="$STATE_DIR/user/generated/material_colors.scss"
  if [ ! -f "$MATERIAL_COLORS" ]; then
    echo "Material colors file not found. Skipping."
    return
  fi

  # Extract color values (format: $primary: #FFFFFF;)
  PRIMARY=$(grep -E '^\s*\$primary' "$MATERIAL_COLORS" | head -1 | grep -oE '#[0-9a-fA-F]{6}')
  SECONDARY=$(grep -E '^\s*\$secondary' "$MATERIAL_COLORS" | head -1 | grep -oE '#[0-9a-fA-F]{6}')
  TERTIARY=$(grep -E '^\s*\$tertiary' "$MATERIAL_COLORS" | head -1 | grep -oE '#[0-9a-fA-F]{6}')

  for color_var in PRIMARY SECONDARY TERTIARY; do
    eval "COLOR=\$$color_var"
    if [[ -z "$COLOR" || ! "$COLOR" =~ ^#[0-9a-fA-F]{6}$ ]]; then
      echo "Could not extract $color_var from $MATERIAL_COLORS. Skipping OpenRGB."
      return
    fi
  done

  # Create OpenRGB config directory
  mkdir -p "$XDG_CONFIG_HOME/OpenRGB"

  # Generate the color application script
  APPLY_SCRIPT="$XDG_CONFIG_HOME/OpenRGB/openrgb_apply.sh"
  cat >"$APPLY_SCRIPT" <<'OPENRGB_SCRIPT'
#!/usr/bin/env bash
# Auto-generated by applycolor.sh - Do not edit manually
OPENRGB_SCRIPT

  # Strip leading # for openrgb CLI (expects FFFFFF not #FFFFFF)
  PRIMARY_HEX=$(echo "$PRIMARY" | sed 's/^#//')
  SECONDARY_HEX=$(echo "$SECONDARY" | sed 's/^#//')
  TERTIARY_HEX=$(echo "$TERTIARY" | sed 's/^#//')

  {
    echo "openrgb --device 0 --mode direct --brightness 40 --color $PRIMARY_HEX &>/dev/null"
    echo "openrgb --device 1 --mode static --brightness 20 --color $SECONDARY_HEX &>/dev/null"
    echo "openrgb --device 2 --mode direct --brightness 40 --color $TERTIARY_HEX &>/dev/null"
  } >>"$APPLY_SCRIPT"

  # Apply the colors (server should already be running from boot)
  bash "$APPLY_SCRIPT"
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
    apply_discord &
    apply_nvim &
    apply_starship &
    apply_yazi &
    apply_openrgb
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
  apply_discord &
  apply_nvim &
  apply_openrgb
fi

# apply_qt & # Qt theming is already handled by kde-material-colors
