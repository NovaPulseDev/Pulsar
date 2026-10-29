-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
  hl.exec_cmd("qs -p ~/.config/quickshell/pulsar.qml")
  hl.exec_cmd("~/.config/hypr/scripts/restore-wallpaper.sh")
  hl.exec_cmd("hypridle")
end)
