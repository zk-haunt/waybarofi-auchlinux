-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
local colors = require("hyprland/colors")

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,

        border_size = 2,

        col = {
            active_border   = { colors = {colors.primary, colors.secondary}, angle = 45 },
            inactive_border = colors.inactive,
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = true,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 0.96,
        inactive_opacity = 0.88,

        shadow = {
            enabled      = true,
            range        = 10,
            render_power = 4,
            color        = 0x66000000,
        },

        blur = {
            enabled           = true,
            size              = 8,
            passes            = 3,
            ignore_opacity    = true,
            noise             = 0.02,
            contrast          = 1.0,
            xray              = false,
            new_optimizations = true,
            vibrancy          = 0.2,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Curves and animations — the "SmoothSnap" preset.
-- Mirrors config/hypr/animations/smoothsnap.conf; that file is the classic-conf
-- copy for the preset library, this is what actually loads at startup.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("smoothOut",     { type = "bezier", points = { {0.36, 0},  {0.66, -0.56} } })
hl.curve("smoothIn",      { type = "bezier", points = { {0.25, 1},  {0.5, 1}      } })
hl.curve("overshot",      { type = "bezier", points = { {0.05, 0.9},{0.1, 1.05}   } })
hl.curve("softSnap",      { type = "bezier", points = { {0.4, 0},   {0.2, 1}      } })
hl.curve("fluent",        { type = "bezier", points = { {0.0, 0.0}, {0.2, 1.0}    } })
hl.curve("easeInOutExpo", { type = "bezier", points = { {0.87, 0},  {0.13, 1}     } })

-- Windows
hl.animation({ leaf = "windows",     enabled = true, speed = 5, bezier = "overshot",  style = "popin 80%" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 5, bezier = "overshot",  style = "popin 80%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 4, bezier = "smoothOut", style = "popin 95%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "softSnap" })

-- Layers
hl.animation({ leaf = "layersIn",    enabled = true, speed = 7, bezier = "smoothIn", style = "slide right" })
hl.animation({ leaf = "layersOut",   enabled = true, speed = 8, bezier = "softSnap", style = "slide right" })

-- Fade
hl.animation({ leaf = "fade",        enabled = true, speed = 4, bezier = "smoothIn" })
hl.animation({ leaf = "fadeIn",      enabled = true, speed = 4, bezier = "smoothIn" })
hl.animation({ leaf = "fadeOut",     enabled = true, speed = 4, bezier = "smoothOut" })
hl.animation({ leaf = "fadeSwitch",  enabled = true, speed = 4, bezier = "smoothIn" })
hl.animation({ leaf = "fadeShadow",  enabled = true, speed = 4, bezier = "smoothIn" })
hl.animation({ leaf = "fadeDim",     enabled = true, speed = 4, bezier = "smoothIn" })
hl.animation({ leaf = "fadeDpms",    enabled = true, speed = 4, bezier = "smoothIn" })
hl.animation({ leaf = "fadeLayers",  enabled = true, speed = 3, bezier = "softSnap" })

-- Workspaces
hl.animation({ leaf = "workspaces",       enabled = true, speed = 5, bezier = "overshot", style = "slidefade 30%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "overshot", style = "slidefadevert 30%" })

-- Not in the preset; kept from the previous config so they don't fall back to
-- the built-in default curve.
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.animation({ leaf = "border",     enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7,    bezier = "softSnap" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})
