---- LOOK AND FEEL ----
-- Tuned 2026-11-15 for smoothness + low GPU cost (Iris Xe, 1080p60).
-- Original saved in ~/rice-backups/2026-11-15-pre-upgrade/  (run `rice-revert` to go back)

hl.config({ render = { expand_undersized_textures = false } })
hl.config({
    general = {
        gaps_in = 2,
        gaps_out = { top = 2, right = 3, bottom = 3, left = 3 },
        border_size = 0,
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 8,
        blur = {
            enabled = true,
            size = 3,            -- small kernel ...
            passes = 2,          -- ... with 2 passes: smoother than 1x5 and cheaper than 3x5
            noise = 0,           -- skip the noise pass
            vibrancy = 0.2,
            new_optimizations = true,
            xray = true,         -- floating windows blur the wallpaper only (big GPU saving)
            ignore_opacity = true,
        },
        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
        },
    },
    animations = { enabled = true },
})

-- Curves: all "ease-out" so motion starts instantly (feels responsive) and settles softly.
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1.0}, {0.32, 1.0} } })
hl.curve("easeOutCubic", { type = "bezier", points = { {0.33, 1.0}, {0.68, 1.0} } })
hl.curve("easeInOut",    { type = "bezier", points = { {0.65, 0.0}, {0.35, 1.0} } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0.0}, {0.10, 1.0} } })

-- speed unit = 100 ms
hl.animation({ leaf = "windowsIn",    enabled = true, speed = 4.0, bezier = "easeOutQuint", style = "popin 88%" })
hl.animation({ leaf = "windowsOut",   enabled = true, speed = 2.5, bezier = "easeOutCubic", style = "popin 90%" })
hl.animation({ leaf = "windowsMove",  enabled = true, speed = 4.0, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeIn",       enabled = true, speed = 3.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeOut",      enabled = true, speed = 2.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeSwitch",   enabled = true, speed = 3.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeShadow",   enabled = true, speed = 3.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeDim",      enabled = true, speed = 3.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "border",       enabled = true, speed = 3.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "borderangle",  enabled = false })
hl.animation({ leaf = "workspaces",   enabled = true, speed = 4.5, bezier = "easeOutQuint", style = "slidefade 20%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4.0, bezier = "easeOutQuint", style = "slidefadevert 20%" })
hl.animation({ leaf = "layersIn",     enabled = true, speed = 3.0, bezier = "easeOutQuint", style = "popin 94%" })
hl.animation({ leaf = "layersOut",    enabled = true, speed = 2.0, bezier = "easeOutCubic", style = "popin 94%" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeLayersOut",enabled = true, speed = 1.5, bezier = "easeOutCubic" })
