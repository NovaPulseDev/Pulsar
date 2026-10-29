---------------------
---- KEYBINDINGS ----
---------------------

local mod         = "SUPER" -- Sets "Windows" key as main modifier

----------
-- APPS --
----------

local terminal    = "kitty"
local fileManager = "nautilus --new-window"
local browser     = "firefox"
local ide         = "codium"

hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + W", hl.dsp.exec_cmd(browser))
hl.bind(mod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. " + X", hl.dsp.exec_cmd(ide))

-------------
-- WINDOWS --
-------------

hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + J", hl.dsp.layout("togglesplit"))          -- dwindle only
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + A", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + D", hl.dsp.focus({ direction = "right" }))
hl.bind("ALT + Tab", hl.dsp.layout("cyclenext"))            -- monocle only
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mod .. " + ALT + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3, action = "toggle" }))

----------------
-- QUICKSHELL --
----------------

-- QUICKSHELL
local function ipc(action)
  return "qs -p ~/.config/quickshell/pulsar.qml ipc call pulsar " .. action
end

hl.bind(mod .. " + Y", hl.dsp.exec_cmd(ipc("theme")))
hl.bind(mod .. " + H", hl.dsp.exec_cmd(ipc("wallpaper")))
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(ipc("launcher")))
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd(ipc("power")))
hl.bind(mod .. " + C", hl.dsp.exec_cmd(ipc("control")))

----------------
-- WORKSPACES --
----------------

for i = 1, 10 do
  local key = i % 10 -- 10 maps to key 0
  hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- SPECIAL WORKSPACE
hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- SCROLL THROUGH WORKSPACES
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-----------------
-- LAPTOP KEYS --
-----------------

local raise_volume    = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+", { locked = true, repeating = true }
local lower_volume    = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", { locked = true, repeating = true }
local toggle_mute     = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", { locked = true, repeating = true }
local toggle_mic      = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", { locked = true, repeating = true }
local brightness_up   = "brightnessctl -e4 -n2 set 5%+", { locked = true, repeating = true }
local brightness_down = "brightnessctl -e4 -n2 set 5%-", { locked = true, repeating = true }
local take_screenshot = [[
    pgrep -x slurp >/dev/null || pgrep -x grim >/dev/null || ( \
        SELECTION=$(slurp) && sleep 0.25 && grim -g "$SELECTION" - | wl-copy \
        && wl-paste > ~/Pictures/Screenshots/Screenshot-$(date +%F_%T).png \
        && notify-send -a "Grim + Slurp" "Screenshot taken" "Saved into ~/Pictures/Screenshots" \
    )
]]

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(raise_volume))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(lower_volume))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(toggle_mute))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(toggle_mic))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(brightness_up))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("Print", hl.dsp.exec_cmd(take_screenshot))
