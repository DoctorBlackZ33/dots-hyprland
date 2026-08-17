-- Custom window/layer/workspace rules
-- Converted from hyprlang to Lua

-- Waydroid: allow resizing, no fixed size || size and no_limit dont exist, broken at the moment, see https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for fix
-- hl.window_rule({ match = { class = "^Waydroid$" }, size = false })
-- hl.window_rule({ match = { class = "^Waydroid$" }, no_limit = true })

-- Window rules
-- Steam games: immediate rendering (tearing enabled)
hl.window_rule({ match = { class = "^steam_app_1422450$" }, immediate = true })
hl.window_rule({ match = { class = "^project8$" }, immediate = true })

-- Steam game blur rules (keep blur for games)
hl.window_rule({ match = { class = "^steam_app_1422450$" }, no_blur = true })
hl.window_rule({ match = { class = "^steam_app_1422450$" }, no_anim = true })

-- Re-enable blur for all windows (overrides the default no_blur=1 in hyprland/rules.lua)
hl.window_rule({ match = { class = ".*" }, no_blur = false })

-- Per-app opacity: transparency is per-window, not global
-- Firefox: explicitly opaque (doesn't support transparency)
hl.window_rule({ match = { class = "^(firefox)$" }, opacity = "1" })
hl.window_rule({ match = { class = "^(firefox)$" }, no_blur = false })

-- Kitty/Quickshell: let apps handle their own transparency (Kitty config, QS UI)
-- Don't force opacity here — that overrides app-level transparency

-- Layer rules: make ALL Quickshell layers non-xray (see-through to windows)
-- Quickshell UI layers (bars, sidepanels, settings, dock, etc.)
hl.layer_rule({ match = { namespace = "quickshell:.*" }, xray = false })
