# Sourced, not run: dropdown placement shared by sec-picker.sh and
# phone-menu.sh — the rofi menus that open under their Waybar button.
#
# anchor_under_cursor WIDTH — prints a rofi -theme-str that puts a WIDTH-px
# window under the cursor (which is on the button, since a click opened it),
# just below the bar, kept 10 px inside the monitor's edges.
#
# Waybar doesn't tell a click command where the button is, hence the cursor.
# rofi's y-offset counts from the top of the usable area, i.e. already below
# the bar's reserved strip, so only the part of the bar that sticks out past
# that strip (plus a 6 px gap) is added. Measured 2026-10-10: offset 40 with
# the bar reserving 34 put the window at y=74.
anchor_under_cursor() {
    local w=$1 cx cy mon mx my mw rtop bar x y
    read -r cx cy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
    read -r mon mx my mw rtop < <(hyprctl monitors -j | jq -r --argjson x "$cx" --argjson y "$cy" '
        .[] | select($x >= .x and $x < .x + .width and $y >= .y and $y < .y + .height)
            | "\(.name) \(.x) \(.y) \(.width) \(.reserved[1])"' | head -n1)
    bar=$(hyprctl layers -j | jq -r --arg m "${mon:-}" \
        '(.[$m].levels // {})[][]? | select(.namespace == "waybar") | .y + .h' | sort -n | tail -n1)
    x=$(( cx - ${mx:-0} - w / 2 ))
    (( x > ${mw:-1920} - w - 10 )) && x=$(( ${mw:-1920} - w - 10 ))
    (( x < 10 )) && x=10
    y=$(( ${bar:-34} - ${my:-0} - ${rtop:-0} + 6 ))
    (( y < 6 )) && y=6
    printf 'window { location: north west; anchor: north west; x-offset: %dpx; y-offset: %dpx; width: %dpx; }' "$x" "$y" "$w"
}
