-- ----------------------------------------------------
--  Workflow presets (Super + Ctrl + W)
-- ----------------------------------------------------
--
-- Replaces config/hypr/workflows/*.conf, which could never be applied. The old
-- change-workflow.sh ran:
--     hyprctl --batch "source <file>"
-- `source` is a hyprlang keyword, and this config is pure Lua, so Hyprland
-- rejected it; the command fell through to a bare `hyprctl reload`, which just
-- re-read the Lua config and discarded whatever the preset wanted. The menu
-- appeared, notified "Active: gaming", and changed nothing.
--
-- Why a table of FULL value sets rather than deltas: hl.config has no "unset",
-- so switching gaming -> snappy cannot un-apply gaming's blur change. Every
-- preset therefore states every field it or any sibling touches, and `default`
-- carries the real config values from anim.lua. That makes switching idempotent
-- in any order, which a delta-based design would not be.
--
-- The .conf files are kept as provenance (they carry upstream credit headers and
-- the $WORKFLOW_ICON/$WORKFLOW_DESCRIPTION metadata) but nothing reads them now.

local M = {}

-- Namespaces whose layer effects the presets toggle. Taken verbatim from the
-- .conf files so behaviour matches what they intended.
local LAYERS = "^(rofi|notifications|swaync-(notification-window|control-center)|logout_dialog|waybar)$"
local LAYERS_GAMING = "^(rofi|notifications|swaync-(notification-window|control-center)|logout_dialog|waybar|.*www-daemon)$"

-- Defaults mirror the hl.config block in hyprland/anim.lua. If you change the
-- look there, change it here too or `default` will quietly drift.
local DEFAULTS = {
    icon = "",
    description = "Balanced — gaps, blur, shadows, animations",
    config = {
        general    = { gaps_in = 5, gaps_out = 10, border_size = 2 },
        decoration = {
            rounding = 10,
            active_opacity = 0.96,
            inactive_opacity = 0.88,
            fullscreen_opacity = 1.0,
            shadow = { enabled = true },
            blur   = { enabled = true, xray = false },
        },
        animations = { enabled = true },
    },
    -- nil opacity rule = drop the force-opaque rule the other presets add
    opaque = false,
    layer  = { namespace = LAYERS, blur = true, no_anim = false },
}

local function perf_config(opts)
    return {
        general    = { gaps_in = 0, gaps_out = 0, border_size = 1 },
        decoration = {
            rounding = 0,
            active_opacity = 1,
            inactive_opacity = 1,
            fullscreen_opacity = 1,
            shadow = { enabled = opts.shadow },
            blur   = { enabled = opts.blur, xray = opts.xray },
        },
        animations = { enabled = opts.animations },
    }
end

M.presets = {
    default = DEFAULTS,

    gaming = {
        icon = "",
        description = "Performance — no blur, shadows, gaps or animations",
        config = perf_config({ shadow = false, blur = false, xray = true, animations = false }),
        opaque = true,
        layer  = { namespace = LAYERS_GAMING, blur = false, no_anim = true },
    },

    powersaver = {
        icon = "",
        description = "Minimum power — all effects off, readability kept",
        config = perf_config({ shadow = false, blur = false, xray = true, animations = false }),
        opaque = true,
        layer  = { namespace = LAYERS, blur = false, no_anim = true },
    },

    snappy = {
        icon = "\u{F04C5}",
        description = "Snappy — square corners, no gaps, no animations",
        -- snappy.conf deliberately leaves blur and shadows ALONE; only rounding,
        -- gaps and animations change. Shadow/blur are still stated explicitly so
        -- switching out of gaming restores them.
        config = {
            general    = { gaps_in = 0, gaps_out = 0, border_size = 1 },
            decoration = {
                rounding = 0,
                active_opacity = 0.96,
                inactive_opacity = 0.88,
                fullscreen_opacity = 1.0,
                shadow = { enabled = true },
                blur   = { enabled = true, xray = false },
            },
            animations = { enabled = false },
        },
        opaque = false,
        layer  = { namespace = LAYERS, blur = true, no_anim = false },
    },

    editing = {
        icon = "",
        description = "Writing/editing — blur on, fully opaque for true colour",
        config = {
            general    = { gaps_in = 5, gaps_out = 10, border_size = 2 },
            decoration = {
                rounding = 10,
                -- Opaque so colour picking and contrast are accurate.
                active_opacity = 1,
                inactive_opacity = 1,
                fullscreen_opacity = 1,
                shadow = { enabled = true },
                blur   = { enabled = true, xray = false },
            },
            animations = { enabled = true },
        },
        opaque = true,
        layer  = { namespace = LAYERS, blur = true, no_anim = false },
    },
}

-- Rule names are reused per preset so re-applying replaces rather than stacks.
local OPAQUE_RULE = "workflow_opaque"
local LAYER_RULE  = "workflow_layer"

function M.list()
    -- Stable order for the menu; `default` first since it is the reset.
    return { "default", "gaming", "powersaver", "snappy", "editing" }
end

function M.apply(name)
    local p = M.presets[name]
    if not p then
        -- error(), not `return`: `hyprctl eval` prints "ok" and discards the
        -- function's return value, so a returned error string is invisible to
        -- the caller. A raised error DOES reach stdout as "error: ...", which is
        -- what change-workflow.sh greps for.
        error("unknown workflow: " .. tostring(name), 0)
    end

    hl.config(p.config)

    -- Force every window opaque. The .conf files used
    --   windowrule = opaque true,match:class (.*)
    -- There is no way to delete a rule at runtime, so the rule is always
    -- (re)declared under one stable name and its value flipped instead.
    hl.window_rule({
        name    = OPAQUE_RULE,
        match   = { class = "(.*)" },
        opaque  = p.opaque and true or false,
    })

    hl.layer_rule({
        name    = LAYER_RULE,
        match   = { namespace = p.layer.namespace },
        blur    = p.layer.blur,
        no_anim = p.layer.no_anim,
    })

    return string.format("%s: %s", name, p.description)
end

return M
