-- ~/.config/hypr/hyprland.lua
-- Docs: https://wiki.hypr.land/Configuring/Start/

---- MY PROGRAMS ----

mainMod    = "SUPER"
terminal   = "kitty"
menu       = "rofi -show drun"
fileManager = "thunar"
browser    = "zenq"

---- AUTOSTART ----

hl.on("hyprland.start", function()
    -- hl.exec_cmd("dunst") replaced with quickshell 
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")

    hl.exec_cmd("sleep 4 && " .. os.getenv("HOME") .. "/dotfiles/dotfiles/.config/hypr/bin/tab-extend watch") -- plug in an Android tablet over USB = extra screen
    hl.exec_cmd(os.getenv("HOME") .. "/dotfiles/dotfiles/.config/hypr/bin/night restore") -- re-apply the blue-light filter if it was on
    hl.exec_cmd("hypridle") -- idle/lock/sleep handling (was lost in the .conf -> Lua migration)

    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper-restore.sh")
    -- basic render loop: one shared GL context for all shell windows (the threaded loop gives
    -- every popup its own render thread + context, ~2x the memory, no smoother)
    hl.exec_cmd("sleep 0.5 && QSG_RENDER_LOOP=basic qs")
    hl.exec_cmd("~/.local/bin/boost restore")
    hl.exec_cmd("~/.local/bin/power-limit restore")
    hl.exec_cmd("~/.local/bin/power-auto")
    hl.exec_cmd("~/.local/bin/rotate-auto")
    hl.exec_cmd("sleep 3 && ~/.local/bin/touch-gestures") -- touchscreen edge/multi-finger gestures + tablet-mode switch
end)

---- ENVIRONMENT VARIABLES ----

hl.env("XCURSOR_SIZE", "14")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

---- INPUT ----

hl.config({
    input = {
        kb_layout = "us,latam,ara",
        follow_mouse = 1,
        sensitivity = -0.5,
        touchpad = {
            natural_scroll = true,
            scroll_factor = 0.7, -- 1.0 = default; lower = slower scrolling
            tap_to_click = true,
        },
    },
})

-- TOUCH & GESTURES
hl.config({
    gestures = {
        workspace_swipe_touch = true,            -- touchscreen: swipe in from the left/right edge to change workspace
        workspace_swipe_distance = 320,
        workspace_swipe_cancel_ratio = 0.25,
        workspace_swipe_min_speed_to_force = 20,
    },
    cursor = { hide_on_touch = true },
})
-- touchpad (touchscreen gestures live in ~/.local/bin/touch-gestures)
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up",   action = function() hl.exec_cmd("qs ipc call wheel toggle") end })
hl.gesture({ fingers = 3, direction = "down", action = function() hl.exec_cmd("qs ipc call calendar toggle") end })
hl.gesture({ fingers = 4, direction = "up",   action = function() hl.exec_cmd("qs ipc call overview toggle") end })
hl.gesture({ fingers = 4, direction = "down", action = "fullscreen" })

-- Touchpad-only sensitivity (global -0.5 keeps the mouse slow)
hl.device({
    name = "elan0749:00-04f3:31a5-touchpad",
    sensitivity = 0.3,
})

-- LAYOUT
hl.config({
    dwindle = { preserve_split = true },
})
hl.config({
    master = { new_status = "master" },
})

-- MISC
hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        -- If hyprlock ever crashes/stalls, let a fresh hyprlock take over the
        -- session lock instead of leaving the screen permanently locked.
        allow_session_lock_restore = true,
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
    },
})

---- SPLIT-OUT FILES ----

require("monitors")
require("keybinds")
require("look")
require("rules")

-- HyprMod managed settings
require("hyprland-gui")

-- brightness boost (see ~/.local/bin/boost): re-apply the saved shader after every reload
do
    local home = os.getenv("HOME")
    local f = io.open(home .. "/.config/quickshell/state/boost", "r")
    if f then
        local v = f:read("*l"); f:close()
        if v and v ~= "1.0" then
            hl.config({ decoration = { screen_shader = home .. "/.config/quickshell/state/boost.frag" } })
        end
    end
end
