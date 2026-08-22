-- Custom keybinds
-- https://wiki.hypr.land/Configuring/Binds/
-- Add keybinds here using hl.bind()

-- Override SUPER+SHIFT+X (OCR): quickshell regionOcr as primary, EasyOCR
-- daemon fallback (slurp + grim) only when quickshell is down.
--
-- The base hyprland/keybinds.lua binds SUPER+SHIFT+X to "quickshell:regionOcr"
-- OR a tesseract exec. Tesseract only has 'eng' installed here, so this
-- rebinds the fallback to the EasyOCR daemon (en/fr/de, ~1s warm) and keeps
-- quickshell as primary (its RegionSelector calls paddle_ocr.sh, which now
-- speaks to the same warm daemon).

local qsConfig = "ii"
local qsScripts = "$HOME/.config/quickshell/" .. qsConfig .. "/scripts"
local qsAlive = "qs -c " .. qsConfig .. " ipc call TEST_ALIVE"

hl.unbind("SUPER + SHIFT + X")

-- Primary: quickshell region selector -> paddle_ocr.sh (daemon) -> wl-copy
hl.bind(
	"SUPER + SHIFT + X",
	hl.dsp.global("quickshell:regionOcr"),
	{ description = "Utilities: Character recognition >> clipboard" }
)

-- Fallback: when quickshell is down, region-select with slurp, OCR via daemon.
-- Parentheses matter: `a || b && c` runs c when a succeeds, so the whole
-- pipeline must sit behind the liveness check or wl-copy clobbers the
-- clipboard with empty input on every OCR press.
hl.bind(
	"SUPER + SHIFT + X",
	hl.dsp.exec_cmd(
		qsAlive
			.. ' || ( pidof slurp || ( grim -g "$(slurp $SLURP_ARGS)" "/tmp/ocr_image.png" && '
			.. qsScripts
			.. '/ocr/paddle_ocr.sh "/tmp/ocr_image.png" | wl-copy && rm "/tmp/ocr_image.png" ) )'
	)
)

-- ===========================================================================
-- VIM-STYLE NAVIGATION & WORKSPACE MANAGEMENT
-- ===========================================================================

-- Monitor order (hardcoded from custom/general.lua):
--   1: DP-1
--   2: HDMI-A-1
--   3: HDMI-A-2
--   4: (none)

-- Cycle workspaces on current monitor (SUPER+[ / SUPER+])
local function cycleWorkspaceOnMonitor(direction)
	local activeWs = hl.get_active_workspace()
	local currentId = activeWs.id
	local monitorId = activeWs.monitor.id

	local allWs = hl.get_workspaces()
	local monitorWs = {}
	for _, ws in ipairs(allWs) do
		local wid = ws.id
		if ws.monitor.id == monitorId and type(wid) == "number" and wid > 0 then
			table.insert(monitorWs, wid)
		end
	end
	table.sort(monitorWs)

	if #monitorWs == 0 then
		return
	end

	local idx = nil
	for i, w in ipairs(monitorWs) do
		if w == currentId then
			idx = i
			break
		end
	end

	if idx == nil then
		idx = 1
	end

	local nextIdx
	if direction == "next" then
		nextIdx = (idx % #monitorWs) + 1
	else
		nextIdx = ((idx - 2) % #monitorWs) + 1
	end

	hl.dispatch(hl.dsp.focus({ workspace = tostring(monitorWs[nextIdx]) }))
end

-- Move current workspace to a specific monitor by name
local function moveWorkspaceToMonitor(monitorName)
	if monitorName then
		hl.dispatch(hl.dsp.workspace.move({ monitor = monitorName }))
	end
end

-- ===========================================================================
-- REMOVE OLD BRACKET BINDINGS
-- SUPER+[] for focus window left/right (redundant with hjkl)
-- CTRL+SUPER+[] for workspace +/-1 (replaced by SUPER+[] cycling)
-- ===========================================================================
hl.unbind("SUPER + BracketLeft")
hl.unbind("SUPER + BracketRight")
hl.unbind("CTRL + SUPER + BracketLeft")
hl.unbind("CTRL + SUPER + BracketRight")
-- ===========================================================================
-- UNBIND ORIGINALS (so relocated bindings take effect)
-- ===========================================================================
hl.unbind("SUPER + J") -- relocated to SUPER+Y
hl.unbind("SUPER + K") -- relocated to SUPER+U
hl.unbind("SUPER + L") -- relocated to SUPER+Semicolon
hl.unbind("SUPER + SHIFT + L") -- relocated to SUPER+SHIFT+Z

-- ===========================================================================
-- RELOCATED BINDINGS (keys moved to free hjkl)
-- ===========================================================================

-- SUPER+J was: Toggle bar → moved to SUPER+Y
hl.bind("SUPER + Y", hl.dsp.global("quickshell:barToggle"), { description = "Shell: Toggle bar" })

-- SUPER+K was: Toggle on-screen keyboard → moved to SUPER+U
hl.bind("SUPER + U", hl.dsp.global("quickshell:oskToggle"), { description = "Shell: Toggle on-screen keyboard" })

-- SUPER+L was: Lock screen → moved to SUPER+Semicolon
hl.bind("SUPER + Semicolon", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Session: Lock" })

-- SUPER+SHIFT+L was: Sleep → moved to SUPER+SHIFT+Z
hl.bind(
	"SUPER + SHIFT + Z",
	hl.dsp.exec_cmd("systemctl suspend || loginctl suspend"),
	{ locked = true, description = "Session: Sleep" }
)

-- ===========================================================================
-- NEW: VIM-STYLE WINDOW FOCUS (hjkl)
-- ===========================================================================
hl.bind("SUPER + H", hl.dsp.focus({ direction = "l" }), { description = "Window: Focus left" })
hl.bind("SUPER + J", hl.dsp.focus({ direction = "d" }), { description = "Window: Focus down" })
hl.bind("SUPER + K", hl.dsp.focus({ direction = "u" }), { description = "Window: Focus up" })
hl.bind("SUPER + L", hl.dsp.focus({ direction = "r" }), { description = "Window: Focus right" })

-- ===========================================================================
-- NEW: WINDOW MOVEMENT (SUPER+ALT+hjkl)
-- Replaces SUPER+SHIFT+arrows for moving windows
-- ===========================================================================
hl.bind("SUPER + ALT + H", hl.dsp.window.move({ direction = "l" }), { description = "Window: Move left" })
hl.bind("SUPER + ALT + J", hl.dsp.window.move({ direction = "d" }), { description = "Window: Move down" })
hl.bind("SUPER + ALT + K", hl.dsp.window.move({ direction = "u" }), { description = "Window: Move up" })
hl.bind("SUPER + ALT + L", hl.dsp.window.move({ direction = "r" }), { description = "Window: Move right" })

-- ===========================================================================
-- NEW: WORKSPACE CYCLING ON CURRENT MONITOR (SUPER+[ / SUPER+])
-- Cycles through workspaces on the same monitor in numeric order
-- ===========================================================================
hl.bind("SUPER + BracketLeft", function()
	cycleWorkspaceOnMonitor("prev")
end, { description = "Workspace: Previous on this monitor" })
hl.bind("SUPER + BracketRight", function()
	cycleWorkspaceOnMonitor("next")
end, { description = "Workspace: Next on this monitor" })

-- ===========================================================================
-- NEW: MOVE WORKSPACE TO SPECIFIC MONITOR (SUPER+SHIFT+hjkl)
-- h=DP-1, j=HDMI-A-1, k=HDMI-A-2, l=none
-- ===========================================================================
hl.bind("SUPER + SHIFT + H", function()
	moveWorkspaceToMonitor("DP-1")
end, { description = "Workspace: Move to DP-1" })
hl.bind("SUPER + SHIFT + J", function()
	moveWorkspaceToMonitor("HDMI-A-1")
end, { description = "Workspace: Move to HDMI-A-1" })
hl.bind("SUPER + SHIFT + K", function()
	moveWorkspaceToMonitor("HDMI-A-2")
end, { description = "Workspace: Move to HDMI-A-2" })

-- ===========================================================================
-- LEGACY BINDINGS (kept for arrow key / fn-layer compatibility)
-- Superseded by hjkl bindings above; remove when comfortable.
-- ===========================================================================

-- LEGACY: Window focus with arrow keys (replaced by SUPER+hjkl)
hl.bind("SUPER + Left", hl.dsp.focus({ direction = "l" }), { description = "Window: Focus Left" })
hl.bind("SUPER + Right", hl.dsp.focus({ direction = "r" }), { description = "Window: Focus Right" })
hl.bind("SUPER + Up", hl.dsp.focus({ direction = "u" }), { description = "Window: Focus Up" })
hl.bind("SUPER + Down", hl.dsp.focus({ direction = "d" }), { description = "Window: Focus Down" })

-- LEGACY: Window movement with SUPER+SHIFT+arrows (replaced by SUPER+ALT+hjkl)
hl.bind("SUPER + SHIFT + Left", hl.dsp.window.move({ direction = "l" }), { description = "Window: Move Left" })
hl.bind("SUPER + SHIFT + Right", hl.dsp.window.move({ direction = "r" }), { description = "Window: Move Right" })
hl.bind("SUPER + SHIFT + Up", hl.dsp.window.move({ direction = "u" }), { description = "Window: Move Up" })
hl.bind("SUPER + SHIFT + Down", hl.dsp.window.move({ direction = "d" }), { description = "Window: Move Down" })

-- LEGACY: Workspace focus relative with CTRL+SUPER+arrows
hl.bind("CTRL + SUPER + Left", hl.dsp.focus({ workspace = "r-1" }), { description = "Workspace: Focus left" })
hl.bind("CTRL + SUPER + Right", hl.dsp.focus({ workspace = "r+1" }), { description = "Workspace: Focus right" })
