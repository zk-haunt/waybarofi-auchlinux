#!/usr/bin/env lua

local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "/root"
local mode_file = home .. "/.config/zsh/zsh_theme_mode"
local starship_dir = home .. "/.config/starship"
local fastfetch_dir = home .. "/.config/fastfetch"
local kitty_dir = home .. "/.config/kitty"

local cycle = {"lol", "newpr", "onmeds", "end4"}
local labels = {
    lol = "lol    → Starship (lol) + fastfetch",
    newpr = "newpr  → Starship Minimal + fastfetch",
    onmeds = "onmeds → Starship Powerline + fastfetch",
    end4 = "end4   → Starship End4 + fastfetch (End4 Black layout)"
}

-- Read current layout
local current = "lol"
local f = io.open(mode_file, "r")
if f then
    current = f:read("*l") or "lol"
    f:close()
end

local input = arg[1]

-- If no argument provided, show helper menu
if not input then
    print("🎨 Zsh Theme Switcher Help")
    print("--------------------------")
    print("Current active theme: " .. current)
    print("")
    print("Available themes:")
    
    for _, theme in ipairs(cycle) do
        local lbl = labels[theme]
        local indicator = "  "
        if theme == current then
            indicator = "* "
            print(string.format("%s%s (active)", indicator, lbl))
        else
            print(string.format("%s%s", indicator, lbl))
        end
    end
    print("\nUsage:")
    print("  zsh-theme <name>  ➔  Switch to specific theme (e.g. zsh-theme lol)")
    print("  zsh-theme cycle   ➔  Cycle to the next theme")
    print("  zsh-theme status  ➔  Show the current active theme")
    os.exit(0)
elseif input == "status" then
    print("Current theme: " .. current)
    os.exit(0)
end

-- Resolve target theme
local target = nil
if input == "cycle" then
    local current_idx = 1
    for i, theme in ipairs(cycle) do
        if theme == current then
            current_idx = i
            break
        end
    end
    local next_idx = (current_idx % #cycle) + 1
    target = cycle[next_idx]
else
    -- Match specific theme
    for _, theme in ipairs(cycle) do
        if theme == input then
            target = theme
            break
        end
    end
    if not target then
        print("Unknown theme '" .. input .. "'. Available: lol, newpr, onmeds, end4")
        os.exit(1)
    end
end

-- Apply the target layout
local f_mode = io.open(mode_file, "w")
if f_mode then
    f_mode:write(target)
    f_mode:close()
end

-- Update starship config symlink
os.execute("ln -sf '" .. starship_dir .. "/starship_" .. target .. ".toml' '" .. starship_dir .. "/starship.toml' 2>/dev/null")

-- Update fastfetch config symlink
os.execute("ln -sf '" .. fastfetch_dir .. "/config_" .. target .. ".jsonc' '" .. fastfetch_dir .. "/config.jsonc' 2>/dev/null")

-- Update kitty theme
local kitty_src = kitty_dir .. "/kitty_" .. target .. ".conf"
local kitty_dst = kitty_dir .. "/kitty_theme.conf"
local kitty_fallback = kitty_dir .. "/kitty_lol.conf"
os.execute("cp '" .. kitty_src .. "' '" .. kitty_dst .. "' 2>/dev/null || cp '" .. kitty_fallback .. "' '" .. kitty_dst .. "' 2>/dev/null")
os.execute("pkill -USR1 kitty 2>/dev/null")

-- Trigger desktop notification
os.execute("notify-send -a 'Zsh Theme' -i 'dialog-information' 'Zsh Theme Switcher' 'Switched to " .. target .. "' 2>/dev/null")

print("✓ Switched to: " .. target)
print("  Open a new terminal to apply the theme.")
print("")
print("  Themes:")
for _, theme in ipairs(cycle) do
    print("    " .. labels[theme])
end
