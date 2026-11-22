-- Docs: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- To check class name, open the app and run:
-- hyprctl clients

hl.layer_rule({
    match = { namespace = "calendar" },
    blur = true,
    ignore_alpha = 0.2,
    no_anim = true,
})

hl.layer_rule({
    match = { namespace = "project-menu" },
    blur = true,
    ignore_alpha = 0.5,   -- blur only the card, not the full-screen dim layer (a full-screen blur every frame made everything stutter)
    no_anim = true,
})

hl.layer_rule({
    match = { namespace = "keyboard" },
    blur = true,
    ignore_alpha = 0.2,
    no_anim = true,   -- the keyboard slides itself
})

hl.layer_rule({
    match = { namespace = "wheel" },
    blur = true,
    ignore_alpha = 0.2,
    no_anim = true,   -- the wheel animates itself
})

hl.layer_rule({
    match = { namespace = "wallpaper-picker" },
    no_anim = true,   -- the picker animates itself; no blur: a full-screen blur under a moving carousel drops frames
})

hl.layer_rule({
    match = { namespace = "rofi" },
    blur = true,
    ignore_alpha = 0.15,
})

-- Opacity rules for all windows except fullscreen
hl.window_rule({
    match = { class = ".*" },
    opacity = "0.9 override",
})
hl.window_rule({
    match = { class = ".*", fullscreen = true },
    opacity = "1.0 override",
})

--hl.window_rule({
--    name = "brave-opaque",
--    match = { class = "^brave-browser$" },
--    opacity = "1.0 override",
--})

hl.window_rule({
    match = { class = "kitty" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "float-pavucontrol",
    match = { class = "^(pavucontrol)$" },
    float = true,
})

hl.window_rule({
    name = "float-nm-connection-editor",
    match = { class = "^(nm-connection-editor)$" },
    float = true,
})

hl.window_rule({
    name = "float-blueman-manager",
    match = { class = "^(blueman-manager)$" },
    float = true,
})

hl.window_rule({
    name = "float-open-file",
    match = { title = "^(Open File)$" },
    float = true,
})

hl.window_rule({
    name = "float-save-file",
    match = { title = "^(Save File)$" },
    float = true,
})

-- Scratchpad terminal (Super+Z): a floating kitty on a special workspace
hl.window_rule({
    name = "scratchpad",
    match = { class = "^scratchpad$" },
    workspace = "special:scratch",
    float = true,
    opacity = "0.92 override",
    suppress_event = "maximize fullscreen",
    size = "monitor_w*0.75 monitor_h*0.55",
    move = "monitor_w*0.125 monitor_h*0.06",
})

-- Per-app workspaces (silent: the app opens there without stealing focus)
hl.window_rule({ name = "ws-browser", match = { class = "^(zen|zen-browser|zen-beta)$" },    workspace = "1 silent" })
hl.window_rule({ name = "ws-editor",  match = { class = "^(code|Code|code-oss|md.obsidian.Obsidian|Eclipse)$" }, workspace = "2 silent" })
hl.window_rule({ name = "ws-chat",    match = { class = "^(discord|vesktop|org.telegram.desktop|Slack|WhatsApp.*)$" },    workspace = "3 silent" })


hl.layer_rule({
    match = { namespace = "cheatsheet" },
    blur = true,
    ignore_alpha = 0.2,
    no_anim = true,
})

-- These shell menus animate themselves; skip Hyprland's own layer pop-in so the two animations don't fight.
hl.layer_rule({ match = { namespace = "quickshell" }, no_anim = true })
-- They are translucent too, so blur what's behind each card (alpha > 0.5 only, never the whole screen).
for _, ns in ipairs({ "powermenu", "todo", "night-menu", "media-menu", "notifications", "quick-menu", "clipboard", "overview" }) do
    hl.layer_rule({ match = { namespace = ns }, no_anim = true, blur = true, ignore_alpha = 0.5 })
end

-- Settings is translucent: blur what's behind the card so window text doesn't show through it.
hl.layer_rule({ match = { namespace = "settings" }, blur = true, ignore_alpha = 0.5, no_anim = true })
