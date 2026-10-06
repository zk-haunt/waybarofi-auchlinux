#!/usr/bin/env python3
import os
import re
import subprocess
import logging

def parse_bind_line(line):
    if not line.startswith("hl.bind("):
        return None
    
    # Strip "hl.bind(" from start and ")" from end
    content = line[8:]
    if content.endswith(")"):
        content = content[:-1]
    
    # Split by top-level commas
    parts = []
    current = []
    depth = 0
    in_quotes = False
    quote_char = None
    
    i = 0
    while i < len(content):
        char = content[i]
        if in_quotes:
            if char == quote_char and (i == 0 or content[i-1] != '\\'):
                in_quotes = False
            current.append(char)
        else:
            if char in ['"', "'"]:
                in_quotes = True
                quote_char = char
                current.append(char)
            elif char in ['(', '{', '[']:
                depth += 1
                current.append(char)
            elif char in [')', '}', ']']:
                depth -= 1
                current.append(char)
            elif char == ',' and depth == 0:
                parts.append("".join(current).strip())
                current = []
            else:
                current.append(char)
        i += 1
    if current:
        parts.append("".join(current).strip())
        
    if len(parts) >= 2:
        keys_expr = parts[0]
        action_expr = parts[1]
        return keys_expr, action_expr
    return None

def main():
    log_file = os.path.expanduser("~/keybindings-hint.log")
    logging.basicConfig(filename=log_file, level=logging.DEBUG, 
                        format='%(asctime)s - %(levelname)s - %(message)s')
    logging.debug("Keybindings hint script started")
    
    # Toggle behavior: if rofi is already running, kill it and exit
    user_name = os.environ.get("USER", "newpr")
    proc_check = subprocess.run(["pgrep", "-u", user_name, "-x", "rofi"], capture_output=True)
    if proc_check.returncode == 0:
        subprocess.run(["pkill", "-u", user_name, "-x", "rofi"])
        logging.debug("Rofi was already running, killed process (toggle off)")
        return
        
    lua_path = os.path.expanduser("~/.config/hypr/hyprland/programnkeys.lua")
    if not os.path.exists(lua_path):
        logging.error(f"Configuration file not found: {lua_path}")
        subprocess.run(["notify-send", "Keybinds Hint", "Configuration file not found"])
        return

    with open(lua_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Parse local variables (e.g. local terminal = "kitty")
    variables = {
        'mouse_down': 'mouse_down',
        'mouse_up': 'mouse_up',
    }
    var_pattern = re.compile(r'local\s+(\w+)\s*=\s*"([^"]+)"')
    for line in content.splitlines():
        m = var_pattern.search(line)
        if m:
            variables[m.group(1)] = m.group(2)
            
    logging.debug(f"Parsed variables: {variables}")

    binds = []
    main_mod = "SUPER"
    mod_match = re.search(r'local\s+mainMod\s*=\s*"([^"]+)"', content)
    if mod_match:
        main_mod = mod_match.group(1)

    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("--") or not line.startswith("hl.bind"):
            continue
        
        parsed = parse_bind_line(line)
        if parsed:
            keys_expr, action_expr = parsed
            
            # Skip loop bindings since we generate them cleanly
            if "key" in keys_expr or " i" in action_expr or "key " in keys_expr:
                continue
                
            # Clean keys representation
            keys = keys_expr.replace('mainMod', main_mod).replace('..', '+').replace('"', '').replace("'", "").strip()
            # Replace multiple consecutive pluses (e.g. "+ +") with a single "+"
            keys = re.sub(r'\s*\+\s*\+\s*', ' + ', keys)
            keys = re.sub(r'\s*\+\s*', ' + ', keys)
            if keys.endswith(" +"):
                keys = keys[:-2]
                
            # Resolve action variables
            resolved_action = action_expr
            for var_name, var_val in variables.items():
                resolved_action = re.sub(r'\b' + var_name + r'\b', f'"{var_val}"', resolved_action)
                
            binds.append((keys, resolved_action))

    # Add the workspace loop binds manually
    for i in range(1, 11):
        key = str(i % 10)
        binds.append((f"SUPER + {key}", f"hl.dsp.focus({{ workspace = {i} }})"))
        binds.append((f"SUPER + SHIFT + {key}", f"hl.dsp.window.move({{ workspace = {i} }})"))

    logging.debug(f"Parsed {len(binds)} keybindings")

    # Mapping of actions/commands to descriptions
    description_map = {
        # Shell scripts & tools
        "kitty": "Launch Kitty Terminal",
        "dolphin": "Launch Dolphin File Manager",
        "keepassxc": "Launch KeePassXC Password Manager",
        "hyprlock": "Lock the Screen",
        "pypr toggle console": "Toggle Dropdown Terminal (Scratchpad)",
        "~/.config/hypr/scripts/gamemode.sh": "Toggle Game Mode (Performance Mode)",
        "~/.config/hypr/scripts/glyph-picker.sh": "Launch Glyph Picker",
        "~/.config/hypr/scripts/emoji-picker.sh": "Launch Emoji Picker",
        "~/.config/hypr/scripts/power-menu.sh": "Launch Power Menu",
        "~/.config/hypr/scripts/restart-waybar.sh": "Restart Waybar Status Bar",
        "~/.config/hypr/scripts/wallpaper-picker.sh": "Launch Wallpaper Picker",
        "~/.config/hypr/scripts/update-checker.sh": "Check System Updates",
        "~/.config/hypr/scripts/clipboard-menu.sh history": "Launch Clipboard History",
        "~/.config/hypr/scripts/clipboard-menu.sh options": "Launch Clipboard Actions Menu",
        "~/.config/hypr/scripts/nightlight.sh toggle": "Toggle Nightlight Filter",
        "~/.config/hypr/scripts/nightlight.sh warmer": "Increase Nightlight Warmth",
        "~/.config/hypr/scripts/nightlight.sh cooler": "Decrease Nightlight Warmth",
        "~/.config/hypr/scripts/nightlight.sh gamma-up": "Increase Screen Gamma",
        "~/.config/hypr/scripts/nightlight.sh gamma-down": "Decrease Screen Gamma",
        "~/.config/hypr/scripts/brightness.sh up": "Increase Screen Brightness",
        "~/.config/hypr/scripts/brightness.sh down": "Decrease Screen Brightness",
        "~/.config/hypr/scripts/brightness.sh min": "Set Screen Brightness to Minimum",
        "~/.config/hypr/scripts/brightness.sh max": "Set Screen Brightness to Maximum",
        "~/.config/hypr/scripts/volume.sh up": "Increase Volume",
        "~/.config/hypr/scripts/volume.sh down": "Decrease Volume",
        "~/.config/hypr/scripts/volume.sh mute": "Mute/Unmute Volume",
        "~/.config/hypr/scripts/volume.sh mic-mute": "Mute/Unmute Microphone",
        "~/.config/hypr/scripts/media.sh play-pause": "Media Play / Pause",
        "~/.config/hypr/scripts/media.sh next": "Media Next Track",
        "~/.config/hypr/scripts/media.sh previous": "Media Previous Track",
        "pgrep -x waybar > /dev/null && killall waybar || waybar &": "Toggle Waybar Visibility",
        "~/.config/hypr/scripts/poc/screenshot.sh s": "Capture Selected Area Screenshot",
        "~/.config/hypr/scripts/poc/screenshot.sh sf": "Capture Selected Area Screenshot (Freeze)",
        "~/.config/hypr/scripts/poc/screenshot.sh w": "Capture Window Screenshot",
        "~/.config/hypr/scripts/poc/screenshot.sh p": "Capture Fullscreen Screenshot",
        "~/.config/hypr/scripts/poc/screenshot.sh sc": "Capture Clipboard Screenshot",
        "~/.config/hypr/scripts/poc/screenshot.sh sq": "Capture Quick Screenshot",
        "~/.config/hypr/scripts/screenrecord.sh": "Toggle Screen Recording (Region)",
        "~/.config/hypr/scripts/screenrecord.sh --fullscreen": "Toggle Screen Recording (Fullscreen)",
        
        # Hyprland dispatchers
        "hl.dsp.window.close()": "Close Focused Window",
        "hl.dsp.window.fullscreen({ mode = 0 })": "Toggle Fullscreen (Actual Fullscreen)",
        "hl.dsp.window.fullscreen({ mode = 1 })": "Toggle Fullscreen (Maximized)",
        "hl.dsp.window.float({ action = \"toggle\" })": "Toggle Floating Window State",
        "hl.dsp.layout(\"togglesplit\")": "Toggle Dwindle Split Direction",
        "hl.dsp.workspace.toggle_special(\"magic\")": "Toggle Special Scratchpad Workspace",
        "hl.dsp.window.move({ workspace = \"special:magic\" })": "Move Active Window to Special Workspace",
        "hl.dsp.focus({ direction = \"left\" })": "Focus Window (Left)",
        "hl.dsp.focus({ direction = \"right\" })": "Focus Window (Right)",
        "hl.dsp.focus({ direction = \"up\" })": "Focus Window (Up)",
        "hl.dsp.focus({ direction = \"down\" })": "Focus Window (Down)",
        "hl.dsp.focus({ workspace = \"e+1\" })": "Switch to Next Workspace",
        "hl.dsp.focus({ workspace = \"e-1\" })": "Switch to Previous Workspace",
    }

    # Generate the Rofi entries list
    rofi_entries = []
    max_key_len = max(len(k) for k, _ in binds) if binds else 25
    # Cap spacing to 28
    max_key_len = min(max_key_len, 28)

    for keys, action in binds:
        action_type = "lua"
        action_payload = action
        display_action = action
        
        # Determine if it is a shell command
        if "hl.dsp.exec_cmd" in action:
            action_type = "shell"
            # Extract content between quotes
            match = re.search(r'exec_cmd\("([^"]+)"\)', action)
            if match:
                action_payload = match.group(1)
            else:
                match = re.search(r"exec_cmd\('([^']+)'\)", action)
                if match:
                    action_payload = match.group(1)
                else:
                    action_payload = action.replace('hl.dsp.exec_cmd(', '').rstrip(')')
                    if (action_payload.startswith('"') and action_payload.endswith('"')) or \
                       (action_payload.startswith("'") and action_payload.endswith("'")):
                        action_payload = action_payload[1:-1]
            display_action = action_payload
        
        # User friendly description
        desc = description_map.get(display_action, display_action)
        if desc.startswith("hl.dsp.focus"):
            m_ws = re.search(r'workspace = (\d+|"e[+-]\d+")', display_action)
            if m_ws:
                desc = f"Switch to Workspace {m_ws.group(1)}"
        elif desc.startswith("hl.dsp.window.move"):
            m_ws = re.search(r'workspace = (\d+)', display_action)
            if m_ws:
                desc = f"Move Window to Workspace {m_ws.group(1)}"
        elif desc.startswith("rofi -show calc"):
            desc = "Launch Calculator"
            
        display_str = f"{keys:<{max_key_len}} ➔   {desc}"
        rofi_entries.append(f"{display_str} ::: {action_type} ::: {action_payload}")

    rofi_input = "\n".join(rofi_entries)
    
    # Rofi theme configuration
    theme = os.path.expanduser("~/.config/rofi/clipboard/style.rasi")
    
    # Theme overrides matching lol user:
    # Width: 35em, Height: 35em, Lines: 13, Placeholder: \t⌨️ Keybindings
    theme_override = (
        "window { location: center; anchor: center; width: 35em; height: 35em; x-offset: 0px; y-offset: 0px; } "
        "listview { lines: 13; } "
        "entry { placeholder: \"\\t⌨️ Keybindings \"; }"
    )

    logging.debug("Launching Rofi dialog")
    try:
        proc = subprocess.Popen(
            [
                "rofi", "-dmenu", "-i", "-no-custom",
                "-p", " Keybinds",
                "-display-columns", "1",
                "-display-column-separator", ":::",
                "-theme", theme,
                "-theme-str", theme_override
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = proc.communicate(input=rofi_input)
        
        if proc.returncode == 0 and stdout.strip():
            selected = stdout.strip()
            logging.debug(f"User selected: '{selected}'")
            parts = [p.strip() for p in selected.split(":::")]
            if len(parts) >= 3:
                action_type = parts[1]
                action_payload = parts[2]
                
                logging.info(f"Executing selected action: type='{action_type}', payload='{action_payload}'")
                
                if action_type == "shell":
                    subprocess.Popen(action_payload, shell=True)
                elif action_type == "lua":
                    # Execute dispatcher using hyprctl eval
                    lua_cmd = f"hl.dispatch({action_payload})"
                    subprocess.Popen(["hyprctl", "eval", lua_cmd])
            else:
                logging.warning(f"Could not parse selection parts from: '{selected}'")
        else:
            if proc.returncode != 0 and stderr.strip():
                logging.error(f"Rofi exited with error: {stderr.strip()}")
            else:
                logging.debug("Rofi exited with no selection (ESC or closed)")
    except Exception as e:
        logging.exception("Exception running Rofi process")

if __name__ == "__main__":
    main()
