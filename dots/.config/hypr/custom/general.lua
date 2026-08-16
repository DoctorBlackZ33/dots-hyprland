-- Custom environment variables
hl.env("NVD_BACKEND", "direct")
hl.env("WLR_DRM_NO_ATOMIC", "1")
hl.env("LIBVA_DRIVER_NAME", "amd")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "amd")

-- Monitors (matches original .conf: monitor = output, mode, position, scale)
-- The original "1" and "1#" were scale + preferred flag, NOT transforms.
hl.monitor({
	output = "HDMI-A-1",
	mode = "1920x1080@60",
	position = "0x430",
	scale = "1",
})

hl.monitor({
	output = "HDMI-A-2",
	mode = "1920x1080@60",
	position = "0x-650",
	scale = "1",
})

hl.monitor({
	output = "DP-1",
	mode = "2560x1440@240",
	position = "1920x0",
	scale = "1",
})

-- DP-2: disabled
hl.monitor({
	output = "DP-2",
	disabled = true,
})

-- Default workspaces on monitors (converted from hyprlang: workspace = N, monitor:M, default:true)
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1", default = true })
hl.workspace_rule({ workspace = "3", monitor = "HDMI-A-2", default = true })
hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true })

-- Input (overrides hyprland/general.lua defaults)
hl.config({
	input = {
		kb_layout = "us,ch",
		kb_variant = "intl",
		kb_options = "grp:win_space_toggle",
		numlock_by_default = true,
		repeat_delay = 250,
		repeat_rate = 35,
		accel_profile = "custom 0.15 0.0 0.1 0.21 0.33 0.46 0.6 0.744 0.896 1.056 1.224 1.4 1.584 1.776 1.976 2.184 2.4 2.624 2.856 3.096 3.344 3.6 3.864 4.136 4.416 4.704 5.0 5.2",
		follow_mouse = 1,
		off_window_axis_events = 2,
		touchpad = {
			natural_scroll = true,
			disable_while_typing = true,
			clickfinger_behavior = true,
			scroll_factor = 0.5,
		},
	},
})

-- Decoration config (blurs, rounding, shadow, dim) — no global opacity
-- Transparency is handled per-window via window rules in custom/rules.lua
hl.config({
	decoration = {
		rounding_power = 2.4,
		rounding = 18,

		-- Blur
		blur = {
			enabled = true,
			xray = false,
			special = false,
			new_optimizations = true,
			size = 2,
			passes = 3,
			brightness = 1,
			noise = 0.05,
			contrast = 0.89,
			vibrancy = 0.5,
			vibrancy_darkness = 0.5,
			popups = false,
			popups_ignorealpha = 0.6,
			input_methods = true,
			input_methods_ignorealpha = 0.8,
		},

		-- Shadow
		shadow = {
			enabled = true,
			range = 20,
			offset = { 0, 2 },
			render_power = 10,
			color = "rgba(00000020)",
		},

		-- Dim
		dim_inactive = false,
		dim_strength = 0.05,
		dim_special = 0.2,
	},
})
