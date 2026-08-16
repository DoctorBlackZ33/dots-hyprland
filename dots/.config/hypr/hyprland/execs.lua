-- Custom exec-once commands
-- Converted from hyprlang exec-once to Lua hl.on('hyprland.start')
hl.on("hyprland.start", function ()
    hl.exec_cmd("sleep 10 && xrandr --output DP-2 --primary")
    hl.exec_cmd("sleep 10 && kdeconnectd")
    hl.exec_cmd("sleep 20 && sunshine")
end)
