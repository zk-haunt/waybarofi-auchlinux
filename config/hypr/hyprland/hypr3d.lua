----------------
---- HYPR3D ----
----------------

-- Hypr3D (hyprpm plugin, toggled with SUPER + ALT + 3 — see luafunctions.toggle_hypr3d;
-- world picker on SUPER + H)
-- ships only an empty grid. The rooms, skies and characters in its screenshots are files
-- you point it at: a 360° image for the sky, and .glb/.gltf models for the scene and the
-- player. They live in ~/.local/share/hypr3d/, outside this repo (large, and under their
-- own licences); anything missing there is simply skipped.
--
-- hl.plugin.hypr3d exists only once hyprpm has loaded the plugin, and loading it reloads
-- this config, so the block below runs then.

local hypr3d = hl.plugin and hl.plugin.hypr3d
if not hypr3d then
    return
end

-- The worlds are listed in hyprland/hypr3d-worlds.lua; the one to load is named in
-- ~/.local/state/hypr3d/world, which the SUPER + H picker (scripts/hypr3d-world.sh)
-- writes. Without that file, Virtual City.
local home  = os.getenv("HOME") or ""
local dir   = (os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/hypr3d"
local state = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/hypr3d/world"

local function have(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function chosen_world()
    local f = io.open(state, "r")
    local id = f and f:read("*l")
    if f then
        f:close()
    end
    return (id and id ~= "") and id or "virtualcity"
end

local WORLD = chosen_world()
local world = nil
for _, w in ipairs(require("hyprland/hypr3d-worlds")) do
    if w.id == WORLD then
        world = w
    end
end

-- Every call sets the grid and the spawn point: hypr3d.config() merges plain options into
-- the previous call's, so leaving one out would keep the last world's value. The scene,
-- on the other hand, is replaced as a whole, so the old world's model goes away.
local cfg = { world = { grid = true }, scene = {}, player = { spawn = { 0, 0, 0 } } }

-- The sky: any equirectangular image. Currently Poly Haven's "Kloofendal 48d Partly
-- Cloudy (Pure Sky)", CC0, cut to 4096×2048 (the full 16K original is far too big a
-- texture for an iGPU). Worlds with their own sky dome (Virtual City) hide it.
if have(dir .. "/panorama.jpg") then
    cfg.world.panorama = dir .. "/panorama.jpg"
end

if world and world.path and have(dir .. "/" .. world.path) then
    -- The 40 × 40 m starter floor would cut through the world's own ground.
    cfg.world.grid = false
    cfg.scene[world.id] = {
        mesh = {
            path = dir .. "/" .. world.path,
            -- "origin" keeps the model's own coordinates, which the spawn points in
            -- hypr3d-worlds.lua are measured in. The default, "logical", centres the
            -- bounding box on {0, 0, 0} and would move the floor.
            center = "origin",
        },
        collision = true,
        static = true,
    }
    -- Flying is on by default, so the player doesn't fall from the spawn point.
    cfg.player.spawn = world.spawn or { 0, 0.5, 0 }
end

hypr3d.config(cfg)

-- Fullscreen inside the room crashes Hyprland. All three crashes on 2026-10-21 came from
-- a window going fullscreen while in 3D: twice Super + F, once YouTube's F key in Zen.
-- Each is a SEGV in CSurfacePassElement::needsLiveBlur → shouldUseNewBlurOptimizations →
-- getBlurTexture(m_renderData.pMonitor) → CMonitor::useFP16: Hyprland's render state has
-- no valid monitor while it draws. It is very likely Hypr3D's bug, from the window
-- snapshots it takes for the 3D view (makeSnapshotFB in HyprlandCompat/WindowCapture.cpp),
-- and nothing in this config can fix it. Turning blur off does not help either: Hyprland
-- calls shouldUseNewBlurOptimizations before it checks whether blur is on.
--
-- What this config can do is keep windows from going fullscreen while the room is open.
-- Super + F refuses (luafunctions.fullscreen); this rule makes Hyprland ignore apps that
-- ask for it themselves (a video's fullscreen button, YouTube's F key, games), and is only
-- on while the room is open. It did not stop the YouTube crash, so treat it as a partial
-- guard: avoid fullscreen video in 3D.
local no_fullscreen = hl.window_rule({
    name  = "hypr3d-no-fullscreen",
    match = { class = ".*" },
    suppress_event = "fullscreen",
})
no_fullscreen:set_enabled(false)

hypr3d.on_state(function(open)
    no_fullscreen:set_enabled(open)
end)
