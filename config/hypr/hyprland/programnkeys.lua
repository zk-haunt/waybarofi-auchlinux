---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "~/.config/rofi/launcher/launcher.sh || pkill rofi"
local TerminalEmulator = "kitty"

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + SHIFT + q", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || (command -v uwsm >/dev/null 2>&1 && uwsm check is-active && uwsm stop || hyprctl dispatch exit)"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("~/.config/hypr/scripts/restart-waybar.sh"))
hl.bind("CTRL + Escape", hl.dsp.exec_cmd("pgrep -x waybar > /dev/null && killall waybar || waybar &"))
hl.bind(mainMod .. " + Backspace", hl.dsp.exec_cmd("~/.config/hypr/scripts/power-menu.sh"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("keepassxc"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("rofi -show calc -modi calc -no-show-match -no-sort -theme ~/.config/rofi/calc/style.rasi"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen({ mode = 1 }))
hl.bind(mainMod .. " + W", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("~/.config/hypr/scripts/clipboard-menu.sh history"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("~/.config/hypr/scripts/clipboard-menu.sh options"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only
hl.bind(mainMod .. " + N",             hl.dsp.exec_cmd("~/.config/hypr/scripts/nightlight.sh toggle"))
hl.bind(mainMod .. " + SHIFT + N",     hl.dsp.exec_cmd("~/.config/hypr/scripts/nightlight.sh warmer"))
hl.bind(mainMod .. " + ALT + N",       hl.dsp.exec_cmd("~/.config/hypr/scripts/nightlight.sh cooler"))
hl.bind(mainMod .. " + SHIFT + G",     hl.dsp.exec_cmd("~/.config/hypr/scripts/nightlight.sh gamma-up"))
hl.bind(mainMod .. " + ALT + G",       hl.dsp.exec_cmd("~/.config/hypr/scripts/nightlight.sh gamma-down"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper-picker.sh"))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("pypr toggle console"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/pin-window.sh"))
-- Color picker : hyprpicker, hex copied to clipboard (SUPER + SHIFT + C)
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a -f hex"))
-- Camera menu : webcam preview/snapshot/settings + phone-as-webcam (SUPER + ALT + C)
hl.bind(mainMod .. " + ALT + C", hl.dsp.exec_cmd("~/.config/hypr/scripts/camera-menu.sh"))
-- Android screen mirror : scrcpy over USB (audio incl.)   (SUPER + ALT + A)
hl.bind(mainMod .. " + ALT + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/mirror.sh"))
-- LocalSend : Wi-Fi file sharing, launch/focus            (SUPER + ALT + L)
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/localsend.sh"))
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("kitty --class sysmon-float -o remember_window_size=no -o initial_window_width=1024 -o initial_window_height=768 -e btop"))
-- Zsh Theme             : toggle starship/fastfetch     (toggle with SUPER + ALT + T)
hl.bind(mainMod .. " + ALT + T", luafunctions.toggle_zsh_theme)

-- GTK Theme Picker      : swap system themes            (open with SUPER + SHIFT + T)
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("~/.config/hypr/scripts/gtk-theme-picker.sh"))

-- Workflow Manager      : launch app groups             (open with SUPER + ALT + W)
hl.bind(mainMod .. " + ALT + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/workflow-manager.sh"))


-- Shader Picker         : apply screen filters          (open with SUPER + ALT + S)
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/shader-picker.sh"))

-- Media Player          : control media natively        (open with SUPER + ALT + M)
hl.bind(mainMod .. " + ALT + M", hl.dsp.exec_cmd("~/.config/hypr/scripts/media-player.sh"))

-- Quick Apps            : favorite apps launcher        (open with SUPER + ALT + Q)
hl.bind(mainMod .. " + ALT + Q", hl.dsp.exec_cmd("~/.config/hypr/scripts/quick-apps.sh"))
-- Quick Dock            : icon dock at the mouse cursor  (open with SUPER + R)
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/quickapps.sh"))
-- GTK Font Selector     : pick system font family + size (open with SUPER + SHIFT + F)
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("~/.config/hypr/scripts/gtk-font-picker.sh"))
-- File finder (rofi)     : SUPER + SHIFT + E (toggle)
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("pkill -x rofi || rofi -show filebrowser -theme ~/.config/rofi/launcher/style.rasi"))
hl.bind(mainMod .. " + CTRL + T", luafunctions.toggle_rofi_theme)
-- Rofi STYLE picker, visual grid (our themes as text tiles, lol ones as image previews)
-- Bound twice: D is the original, R matches the other theme pickers (SHIFT + B/W/T/Z).
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("~/.config/hypr/scripts/rofi-themeselect.sh"))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/rofi-themeselect.sh"))
hl.bind(mainMod .. " + ALT + D", hl.dsp.exec_cmd("~/.config/hypr/scripts/rofi-web-search.sh"))
-- Toggle Game Mode (custom Lua script)
-- Old gamemode kept for reference; binding commented out per request (will fold
-- in lol's waybar/rofi curve-flattening into toggle_gamemode2 later).
-- hl.bind(mainMod .. " + G", luafunctions.toggle_gamemode)
hl.bind(mainMod .. " + G", luafunctions.toggle_gamemode2)
hl.bind(mainMod .. " + comma", hl.dsp.exec_cmd("~/.config/hypr/scripts/glyph-picker.sh"))
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("~/.config/hypr/scripts/emoji-picker.sh"))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("swaync-client -t -sw"))
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd("python3 ~/.config/hypr/scripts/keybindings-hint.py"))

-- ═══════════════════ SCREENCAPTURE ═══════════════════
-- Two versions live side-by-side while you decide (~1 week). Pick one, then
-- comment the other. Same keys, different script + annotation editor:
--   OURS = poc/screenshot.sh  (swappy editor)   ← currently OFF
--   LOL  = screenshot_lol.sh  (satty editor, floats centered)  ← currently ON
--
-- ── OURS (swappy) — uncomment this block + comment the LOL one to switch back.
--    The poc/screenshot.sh script stays regardless; nothing is deleted.
-- hl.bind(mainMod .. " + P",        hl.dsp.exec_cmd("~/.config/hypr/scripts/poc/screenshot.sh s"))   -- snip an area
-- hl.bind(mainMod .. " + CTRL + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/poc/screenshot.sh w"))   -- pick a window
-- hl.bind(mainMod .. " + ALT + P",  hl.dsp.exec_cmd("~/.config/hypr/scripts/poc/screenshot.sh sf"))  -- snip an area, screen frozen
-- hl.bind("Print",                  hl.dsp.exec_cmd("~/.config/hypr/scripts/poc/screenshot.sh p"))   -- whole screen
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("~/.config/hypr/scripts/poc/screenshot.sh sc"))   -- OCR: snip a region, copy its TEXT to clipboard
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("~/.config/hypr/scripts/poc/screenshot.sh sq"))   -- QR: snip a region, decode the QR code

-- ── LOL-style (satty) — currently ACTIVE.  area modes: click a window to grab
--    just it, or drag for a custom region.
hl.bind(mainMod .. " + P",        hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_lol.sh s"))   -- snip an area / click a window
hl.bind(mainMod .. " + CTRL + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_lol.sh sf"))  -- same, but screen frozen first
hl.bind(mainMod .. " + ALT + P",  hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_lol.sh m"), { locked = true })   -- this monitor only
hl.bind("Print",                  hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_lol.sh p"), { locked = true })   -- all monitors
hl.bind(mainMod .. " + ALT + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenrecord.sh"))
hl.bind(mainMod .. " + ALT + SHIFT + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenrecord.sh --fullscreen"))

-- Zoom. Lua functions rather than shelling out to `hyprctl keyword`, which this
-- Hyprland rejects (non-legacy parser) — these binds did nothing before.
hl.bind(mainMod .. " + ALT + mouse_down", luafunctions.zoom_in)
hl.bind(mainMod .. " + ALT + mouse_up",   luafunctions.zoom_out)
hl.bind(mainMod .. " + ALT + 0",          luafunctions.zoom_reset)

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Smart-move active window with mainMod + SHIFT + CONTROL + arrows:
-- floating windows nudge by 30px, tiled windows move in the layout direction.
-- (Native lua dispatch via luafunctions.smart_move — this lua-Hyprland does not
--  accept `hyprctl dispatch moveactive` over the CLI.)
hl.bind(mainMod .. " + SHIFT + CONTROL + left",  hl.dsp.exec_cmd("~/.config/hypr/scripts/smart-move.sh left"))
hl.bind(mainMod .. " + SHIFT + CONTROL + right", hl.dsp.exec_cmd("~/.config/hypr/scripts/smart-move.sh right"))
hl.bind(mainMod .. " + SHIFT + CONTROL + up",    hl.dsp.exec_cmd("~/.config/hypr/scripts/smart-move.sh up"))
hl.bind(mainMod .. " + SHIFT + CONTROL + down",  hl.dsp.exec_cmd("~/.config/hypr/scripts/smart-move.sh down"))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- ── Overview & switcher ────────────────────────────────────────
-- Workspace overview (Super + A). Was hyprexpo, which no longer exists:
-- it was removed from hyprwm/hyprland-plugins upstream and Hyprland 0.56 has no
-- native expo, so there was nothing to dispatch to. This is a rofi list built
-- from `hyprctl workspaces`/`clients` instead — no plugin, so nothing to
-- recompile after a Hyprland update.
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/workspace-overview.sh"))
-- Window switcher (rofi)   : toggle with SUPER + TAB
hl.bind(mainMod .. " + Tab",   hl.dsp.exec_cmd("pkill -x rofi || rofi -show window -theme ~/.config/rofi/launcher/style.rasi"))

-- ── Update Checker ─────────────────────────────────────────────
-- SUPER + U : open Rofi update picker
hl.bind(mainMod .. " + U", hl.dsp.exec_cmd("~/.config/hypr/scripts/update-checker.sh"))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/volume.sh up"),       { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/volume.sh down"),     { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("~/.config/hypr/scripts/volume.sh mute"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("~/.config/hypr/scripts/volume.sh mic-mute"), { locked = true, repeating = true })
hl.bind(mainMod .. " + CTRL + M", luafunctions.mute_active_window)
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh down"), { locked = true, repeating = true })
hl.bind(mainMod .. " + SHIFT + F1", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh min"), { locked = true })
hl.bind(mainMod .. " + SHIFT + F2", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh max"), { locked = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("~/.config/hypr/scripts/media.sh next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("~/.config/hypr/scripts/media.sh play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("~/.config/hypr/scripts/media.sh play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("~/.config/hypr/scripts/media.sh previous"),   { locked = true })

-- ── New Feature Keybinds ────────────────────────────────────────
-- REMOVED: this was a SECOND bind on Super+N, duplicating the nightlight.sh
-- bind at the top of this file. It was harmless only because the shader it set
-- went through `hyprctl keyword`, which this Hyprland rejects — so it silently
-- did nothing. Making that script work (2026-10-02) turned the dead duplicate
-- live, and Super+N started stacking a fragment shader on top of hyprsunset's
-- gamma change, which flickers.
--
-- nightlight.sh is the better mechanism and the one to keep: hyprsunset sets a
-- colour-transform matrix via hyprland-ctm-control (no shader compile, no
-- re-render), and it also gives warmer/cooler/gamma steps and a waybar module.
-- toggle-blue-light.sh and its shader were deleted 2026-10-02 as redundant.
-- Super + Shift + A  → Pick animation preset via Rofi
hl.bind(mainMod .. " + SHIFT + A",     hl.dsp.exec_cmd("~/.config/hypr/scripts/change-animation.sh"))
-- Super + Shift + L  → Pick lock screen theme via Rofi
hl.bind(mainMod .. " + SHIFT + L",     hl.dsp.exec_cmd("~/.config/hypr/scripts/change-lockscreen.sh"))
-- Super + Ctrl + W   → Pick workflow preset via Rofi
hl.bind(mainMod .. " + CTRL + W",      hl.dsp.exec_cmd("~/.config/hypr/scripts/change-workflow.sh"))
-- Super + Shift + Z  → Pick SwayNC notification theme via Rofi
hl.bind(mainMod .. " + SHIFT + Z",     hl.dsp.exec_cmd("~/.config/hypr/scripts/change-swaync-theme.sh"))
-- Super + Shift + B  → Pick Waybar theme via Rofi
hl.bind(mainMod .. " + SHIFT + B",     hl.dsp.exec_cmd("~/.config/hypr/scripts/change-waybar-theme.sh"))
-- Super + Ctrl + G   → Pick and launch a Steam game via Rofi
hl.bind(mainMod .. " + CTRL + G",      hl.dsp.exec_cmd("~/.config/hypr/scripts/rofi-steam-launcher.sh"))


