#!/usr/bin/env bash

# GTK3 apps (thunar, ...) parse ~/.config/gtk-3.0/gtk.css once at
# startup and have NO runtime reload path: neither file changes nor the
# gsettings color-scheme flip used for GTK4 reach them. Two-stage:
#
#   1) gtk-theme-name toggle — a *change* of the theme name is the one
#      signal some GTK3 apps observe and use to reparse styles
#   2) restart of the apps listed in GTK3_RESTART — the only reliable
#      live-reload for the rest. Extend GTK3_RESTART with more GTK3
#      apps as needed (space separated)
GTK3_RESTART="thunar"

cur=$(gsettings get org.gnome.desktop.interface gtk-theme)
cur="${cur//\'/}"
[ -z "$cur" ] && cur="adw-gtk3"

if [ "$cur" = "Default" ]; then
    alt="adw-gtk3"
else
    alt="Default"
fi

gsettings set org.gnome.desktop.interface gtk-theme "$alt"
gsettings set org.gnome.desktop.interface gtk-theme "$cur"

for app in $GTK3_RESTART; do
    pgrep -x "$app" >/dev/null 2>&1 || continue
    pkill -x "$app" 2>/dev/null
    sleep 0.4
    setsid -f "$app" >/dev/null 2>&1 < /dev/null &
done
