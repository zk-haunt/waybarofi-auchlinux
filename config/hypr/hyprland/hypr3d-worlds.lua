-- Hypr3D worlds: one entry per model in ~/.local/share/hypr3d/ (paths are relative to it).
-- Read by hyprland/hypr3d.lua (which world to load) and by scripts/hypr3d-world.sh (the
-- SUPER + H picker, which loads this file with plain `lua`), so no `hl` in here.
--
-- The models live outside the repo: they're large, and most are licensed for personal
-- use only, so they must not be published with it.
--
-- spawn: feet position, in the model's own coordinates (hypr3d.lua places every model with
-- center = "origin", untransformed). Each was picked by ray-casting the model for a floor
-- near its middle with at least 2.2 m of headroom, then lifting it 0.3 m.
-- Hypr3D 0.5.0 can't read Draco-compressed geometry or WebP textures: compressed models
-- are left out, and WebP textures have to be converted to PNG/JPEG first. Two rendering
-- bugs (src/Render/MapModel.cpp) also need working around, which is what the "-fixed.glb"
-- copies are:
--   * a material with no base colour texture is drawn with texture 0 bound, which samples
--     black, so it renders solid black whatever its colour: those materials get a 1x1
--     white texture;
--   * colour factors (baseColorFactor, emissiveFactor) go on screen without the
--     linear-to-sRGB step glTF expects, so they come out far too dark (the dungeon's walls
--     are 0.03): they are stored pre-encoded to sRGB.
-- Fully textured models (Sponza, the FPS level) need neither.

return {
    {
        -- Khronos glTF sample. 3DRT testing licence: personal use. Fixed for Hypr3D (see
        -- the top): 20 untextured materials.
        id = "virtualcity", name = "Virtual City",
        path = "virtualcity/VirtualCity-fixed.glb", spawn = { 0, 0.5, 0 },
        about = "city block, 166 m across, own sky dome",
    },
    {
        -- "Space Ship Hallway" by yeeyeeman (Sketchfab), CC-BY-4.0; from three.js's examples.
        -- Fixed for Hypr3D (see the top).
        id = "spaceship", name = "Spaceship hallway",
        path = "spaceship/space_ship_hallway-fixed.glb", spawn = { 20.1, -2.66, -11.0 },
        about = "sci-fi corridor, 29 m long",
    },
    {
        -- "Dungeon - Low Poly Game Level Challenge" by Warkarma (Sketchfab), from three.js's
        -- examples; no licence stated, so personal use only. Its 25 WebP textures were
        -- converted to JPEG, then fixed for Hypr3D (see the top).
        id = "dungeon", name = "Dungeon",
        path = "dungeon/dungeon-fixed.glb", spawn = { 1.7, 2.14, 1.7 },
        about = "low-poly dungeon, open roof",
    },
    {
        -- collision-world.glb from three.js's games_fps example.
        id = "fpslevel", name = "FPS test level",
        path = "fpslevel/collision-world.glb", spawn = { 2.0, -1.44, 3.05 },
        about = "blocky arena with ramps and stairs",
    },
    {
        -- Khronos glTF sample. Crytek, CryEngine licence: personal use.
        id = "sponza", name = "Sponza",
        path = "sponza/Sponza.gltf", spawn = { 0, 0.5, 0 },
        about = "palace courtyard, 51 MB",
    },
    {
        id = "none", name = "Empty grid",
        about = "just the sky and the grid floor",
    },
}
