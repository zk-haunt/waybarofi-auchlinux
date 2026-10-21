-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    -- Import display environment variables into systemd
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DISPLAY")

    -- Load the hyprpm plugins marked enabled (`hyprpm list`), e.g. Hypr3D on SUPER + ALT + 3.
    -- hyprpm loads them into the running session only; without this they are gone after
    -- a re-login. With none enabled it does nothing. -n: notify if a load fails.
    hl.exec_cmd("hyprpm reload -n")

    -- Start services via systemd user units
    hl.exec_cmd("systemctl --user start waybar")
    hl.exec_cmd("systemctl --user start hypridle")
    hl.exec_cmd("command -v swaync >/dev/null 2>&1 && systemctl --user start swaync || systemctl --user start dunst")
    
    -- Start daemons without systemd units directly
    hl.exec_cmd("pgrep -x xsettingsd >/dev/null || xsettingsd &")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("pgrep -x nm-applet >/dev/null || nm-applet --indicator")
    hl.exec_cmd("pgrep -x blueman-applet >/dev/null || blueman-applet &")
    hl.exec_cmd("command -v easyeffects >/dev/null 2>&1 && { pgrep -x easyeffects >/dev/null || easyeffects --gapplication-service & }")
    hl.exec_cmd("~/.config/hypr/scripts/clipboard-watch.sh")
    -- No pgrep guard: the script holds a flock and exits if already running.
    hl.exec_cmd("~/.config/hypr/scripts/battery-monitor.sh &")
    hl.exec_cmd("pypr")
    
    -- Bridge legacy X11 tray icons to Wayland (fixes Steam tray icon)
    hl.exec_cmd("pgrep -x xembedsniproxy >/dev/null || xembedsniproxy &")
    
    -- Start background applications in the system tray
    -- hl.exec_cmd("pgrep -x steam >/dev/null || steam -silent &")
    hl.exec_cmd("pgrep -x discord >/dev/null || discord --start-minimized &")
    hl.exec_cmd("pgrep -x keepassxc >/dev/null || keepassxc &")
    -- LocalSend (Wi-Fi file sharing). Uncomment to autostart; first enable
    -- "Minimize to tray" + "Launch at startup" inside LocalSend → Settings,
    -- otherwise its window pops up on every login.
    -- hl.exec_cmd("pgrep -x localsend_app >/dev/null || localsend_app &")
end)
