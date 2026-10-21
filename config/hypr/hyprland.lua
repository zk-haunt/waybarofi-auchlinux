require("hyprland/monitor")
require("hyprland/autostart")
require("hyprland/input")
require("hyprland/env_var")
require("hyprland/luascript/luafunctions")
require("hyprland/programnkeys")
require("hyprland/anim")

-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = 0,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = true, -- If true disables the random hyprland logo / anime girl background. :(
    },
})


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    -- Table form: the old "20 monitor_h-120" string is silently ignored by the
    -- Lua config (same as the PiP and sticky-note rules below).
    move  = { 20, "monitor_h - 120" },
    float = true,
})


-- Float Pavucontrol (both GTK and Qt) — centered, sensible size
hl.window_rule({
    name   = "pavucontrol-float",
    match  = { class = "^(org.pulseaudio.pavucontrol|pavucontrol-qt)$" },
    float  = true,
    center = true,
    size   = "625 454",
})

-- Float Satty (screenshot annotation) — centered, sized to most screenshots
hl.window_rule({
    name   = "satty-float",
    match  = { class = "^(com.gabm.satty)$" },
    float  = true,
    center = true,
})

-- Float Blueman Manager
hl.window_rule({
    name  = "blueman-manager-float",
    match = { class = "blueman-manager" },
    float = true,
})

-- Float Pyprland Dropdown Scratchpad
hl.window_rule({
    name  = "pyprland-scratchpad",
    match = { class = "console-dropdown" },
    float = true,
})

-- Float System Monitor
hl.window_rule({
    name  = "sysmon-float",
    match = { class = "sysmon-float" },
    float = true,
    size  = "1000 650",
    center = true,
})

-- ── Pin autostarted apps to their workspaces ───────────────────
-- KeePassXC → ws9, Discord → ws10. "silent" sends them there in the
-- background without pulling focus away during boot.
-- Match BOTH spellings: KeePassXC reports "org.keepassxc.KeePassXC" as a native
-- Wayland app_id, but plain "keepassxc" under XWayland (which is what you get
-- when QT_QPA_PLATFORM isn't set to wayland). A rule that names only one of them
-- fails silently on the other and the window lands on whatever workspace is
-- focused at boot — usually ws1.
hl.window_rule({
    name      = "keepassxc-ws9",
    match     = { class = "^(org\\.keepassxc\\.KeePassXC|keepassxc|KeePassXC)$" },
    workspace = "9 silent",
})
hl.window_rule({
    name      = "discord-ws10",
    match     = { class = "^(discord|vesktop|WebCord)$" },
    workspace = "10 silent",
})

-- ── Per-App Opacity ────────────────────────────────────────────
-- Browsers: slight transparency for depth
hl.window_rule({ name = "opacity-browser",   match = { class = "^(firefox|brave-browser|chromium|zen)$" }, opacity = "0.92 0.85" })
-- Terminal: frosted glass feel
hl.window_rule({ name = "opacity-kitty",     match = { class = "^kitty$" },                                opacity = "0.88 0.80" })
-- Editor: slightly transparent
hl.window_rule({ name = "opacity-code",      match = { class = "^(code-oss|[Cc]ode)$" },                  opacity = "0.88 0.80" })
-- File Manager
hl.window_rule({ name = "opacity-dolphin",   match = { class = "^org.kde.dolphin$" },                     opacity = "0.90 0.82" })

-- ── Picture-in-Picture ─────────────────────────────────────────
-- Any window titled "Picture in Picture" floats, pins, snaps to bottom-right
hl.window_rule({
    name             = "picture-in-picture",
    match            = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" },
    float            = true,
    keep_aspect_ratio = true,
    pin              = true,
    -- Bottom-right, 20 px in. Table form with constants: the old
    -- "(100%-w-20) (100%-h-20)" string was silently ignored (the window landed
    -- centred, checked 2026-10-10), and window_w/h aren't this size yet when
    -- move runs — so the offsets are 640 + 20 and 360 + 20.
    move             = { "monitor_w - 660", "monitor_h - 380" },
    size             = "640 360",
})

-- ── Sticky notes ───────────────────────────────────────────────
-- Notes pinned from the notes menu (scripts/notes-menu.sh): small floating
-- kittys on every workspace (pin). notes-menu.sh gives each the first free
-- slot, sticky-note-1..3, and each slot sits lower down the right edge, so
-- two pinned notes don't land on top of each other. Lua rules take move as a
-- table; the old "(100%-w-20) 70" string form is silently ignored. And
-- window_w isn't the 380 below yet when move runs (it's kitty's first 640), so
-- the x offset is the constant 380 + 20.
hl.window_rule({
    name    = "sticky-note",
    match   = { class = "^sticky-note-[0-9]+$" },
    float   = true,
    pin     = true,
    size    = "380 240",
    opacity = "0.95 0.90",
})
hl.window_rule({ name = "sticky-note-1", match = { class = "^sticky-note-1$" }, move = { "monitor_w - 400", 70 } })
hl.window_rule({ name = "sticky-note-2", match = { class = "^sticky-note-2$" }, move = { "monitor_w - 400", 330 } })
hl.window_rule({ name = "sticky-note-3", match = { class = "^sticky-note-3$" }, move = { "monitor_w - 400", 590 } })

-- ── Phone mirror / camera preview (scrcpy) ──────────────────────
-- Floating, so scrcpy sizes its window to the phone's picture itself — upright
-- or sideways. Both layouts are wanted, so it's per title: mirror.sh opens the
-- mirror as "Phone" (floats) or "Phone · tiled" (no rule → tiles), whichever
-- the phone menu last saw; the webcam preview is "Webcam" and always floats.
hl.window_rule({
    name  = "scrcpy-float",
    match = { class = "^scrcpy$", title = "^(Phone|Webcam)$" },
    float = true,
})

-- Hypr3D world, sky and fullscreen guard (hyprpm plugin; does nothing when it isn't loaded).
require("hyprland/hypr3d")
