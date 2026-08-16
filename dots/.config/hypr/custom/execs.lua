-- Custom exec-once commands
-- Converted from hyprlang exec-once to Lua hl.on('hyprland.start')
hl.on("hyprland.start", function()
	hl.exec_cmd("sleep 10 && xrandr --output DP-2 --primary")
	hl.exec_cmd("sleep 10 && kdeconnectd")
	hl.exec_cmd("sleep 20 && sunshine")

	-- OpenRGB server and color application
	hl.exec_cmd("sleep 5 && nohup openrgb --server >$HOME/.config/OpenRGB/server.log 2>&1 &")
	hl.exec_cmd("sleep 15 && bash $HOME/.config/OpenRGB/openrgb_apply.sh 2>/dev/null || true")

	hl.exec_cmd("sleep 15 && nohup cpulimit -l 56 -- /home/black/.local/bin/huenicorn >$HOME/.local/share/huenicorn/startup.log 2>&1 &")
end)
