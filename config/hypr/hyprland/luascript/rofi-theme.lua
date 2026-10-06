#!/usr/bin/env lua

local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "/root"
local rofi_launcher_dir = home .. "/.config/rofi/launcher"
local mode_file = rofi_launcher_dir .. "/rofi_theme_mode"

-- Scan the directory for style_*.rasi themes
local available_styles = {}
local handle = io.popen("ls -1 " .. rofi_launcher_dir .. "/style_*.rasi 2>/dev/null")
if handle then
    for line in handle:lines() do
        local filename = line:match("([^/]+)$")
        if filename then
            local theme_name = filename:match("^style_(.*)%.rasi$")
            if theme_name then
                table.insert(available_styles, theme_name)
            end
        end
    end
    handle:close()
end

-- Natural sort helper
table.sort(available_styles, function(a, b)
    local function chunkify(s)
        local chunks = {}
        for chunk, num in s:gmatch("([^0-9]*)([0-9]*)") do
            if chunk ~= "" then table.insert(chunks, chunk) end
            if num ~= "" then table.insert(chunks, tonumber(num)) end
        end
        return chunks
    end

    local a_chunks = chunkify(a)
    local b_chunks = chunkify(b)
    
    for i = 1, math.max(#a_chunks, #b_chunks) do
        local ac = a_chunks[i]
        local bc = b_chunks[i]
        if not ac then return true end
        if not bc then return false end
        if type(ac) ~= type(bc) then
            return type(ac) == "string"
        elseif ac ~= bc then
            return ac < bc
        end
    end
    return false
end)

-- Title case helper
local function titlecase(str)
    local words = {}
    for w in str:gmatch("[^%s_-]+") do
        table.insert(words, w:sub(1,1):upper() .. w:sub(2):lower())
    end
    return table.concat(words, " ")
end

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
    print("🎨 Rofi Launcher Theme Switcher")
    print("------------------------------")
    print("Current active layout: " .. current)
    print("")
    print("Available layouts:")
    
    local name_descs = {
        lol = "lol Default",
        auch = "Classic",
        newpr = "Centered Grid",
        onmeds = "Capsule-Pill",
        rofi = "Sidebar Dock"
    }

    for i, theme in ipairs(available_styles) do
        local name_desc = name_descs[theme]
        if not name_desc then
            name_desc = theme:gsub("[_-]", " ")
            name_desc = titlecase(name_desc)
        end
        
        local indicator = "  "
        if theme == current then
            indicator = "* "
        end
        io.write(string.format("%s%3d. %s (%s)\n", indicator, i - 1, theme, name_desc))
    end
    print("\nUsage:")
    print("  rofi-theme <number|name|shortcut|cycle|status>")
    os.exit(0)
elseif input == "status" then
    print("Current layout: " .. current)
    os.exit(0)
end

-- Resolve target layout
local target = nil

if input == "cycle" then
    local current_idx = 1
    for i, theme in ipairs(available_styles) do
        if theme == current then
            current_idx = i
            break
        end
    end
    local next_idx = (current_idx % #available_styles) + 1
    target = available_styles[next_idx]
else
    -- 1. Index check
    local idx = tonumber(input)
    if idx and idx >= 0 and idx < #available_styles then
        target = available_styles[idx + 1]
    end
    
    -- 2. Direct exact match
    if not target then
        local file_check = io.open(rofi_launcher_dir .. "/style_" .. input .. ".rasi", "r")
        if file_check then
            file_check:close()
            target = input
        end
    end
    
    -- 3. Shorthand map: e.g. 2_10 or t2s10 -> rofi_type-2_style-10
    if not target then
        local t, s = input:match("^t?([0-9]+)[_s-]?([0-9]+)$")
        if t and s then
            target = "rofi_type-" .. t .. "_style-" .. s
        end
    end
    
    -- 4. lol suffix map: e.g. bright -> lol_bright
    if not target then
        local file_check = io.open(rofi_launcher_dir .. "/style_lol_" .. input .. ".rasi", "r")
        if file_check then
            file_check:close()
            target = "lol_" .. input
        end
    end
    
    -- 5. Substring match
    if not target then
        local matches = {}
        for _, theme in ipairs(available_styles) do
            if theme:find(input, 1, true) then
                table.insert(matches, theme)
            end
        end
        if #matches == 1 then
            target = matches[1]
        elseif #matches > 1 then
            print("Ambiguous match '" .. input .. "'. Multiple layouts matched: " .. table.concat(matches, ", "))
            os.exit(1)
        end
    end
end

-- Validate target exists
if not target then
    print("Unknown layout '" .. input .. "'. Available layouts: " .. table.concat(available_styles, ", "))
    os.exit(1)
else
    local file_check = io.open(rofi_launcher_dir .. "/style_" .. target .. ".rasi", "r")
    if not file_check then
        print("Unknown layout '" .. input .. "'. Available layouts: " .. table.concat(available_styles, ", "))
        os.exit(1)
    else
        file_check:close()
    end
end

-- Apply the target layout
local f_mode = io.open(mode_file, "w")
if f_mode then
    f_mode:write(target)
    f_mode:close()
end

os.execute("ln -sf '" .. rofi_launcher_dir .. "/style_" .. target .. ".rasi' '" .. rofi_launcher_dir .. "/style.rasi' 2>/dev/null")

-- Trigger desktop notification
os.execute("notify-send -a 'Rofi Theme' -i 'preferences-desktop-theme' 'Rofi Layout Switched' 'Active theme: " .. target .. "' 2>/dev/null")

print("✓ Switched Rofi layout to: " .. target)
