#!/usr/bin/env bash

# Restores the last-used wallpaper at login using awww's animated
# wipe transition (same as the quickshell wallpaper picker).

STATE_FILE="$HOME/.cache/current_wallpaper"

restore() {
    # awww needs its daemon up before the first img call
    pgrep -x awww-daemon >/dev/null 2>&1 || setsid awww-daemon >/dev/null 2>&1 &
    for i in 1 2 3 4 5; do
        awww img "$1" --transition-fps 60 --transition-type wipe --transition-duration 2 >/dev/null 2>&1 && return 0
        sleep 0.25
    done
    return 1
}

if [ -f "$STATE_FILE" ]; then
    SAVED_WALLPAPER=$(cat "$STATE_FILE")
    if [ -f "$SAVED_WALLPAPER" ]; then
        restore "$SAVED_WALLPAPER"
        exit 0
    fi
fi

if [ -n "$DEFAULT_WALLPAPER" ] && [ -f "$DEFAULT_WALLPAPER" ]; then
    restore "$DEFAULT_WALLPAPER"
fi
