#!/usr/bin/env bash
# Phone menu — the phone button in the tray pill of the "auchsec" Waybar layout,
# and the "Phone" row of the shield dropdown (sec-picker.sh). A click opens a
# dropdown under the button: mirror the screen, use the phone as a webcam, or
# watch it in a device monitor (battery + live top) — mirror.sh and
# phone-camera.sh do that work. After ppk's adb-phone and osintdroid it also
# has device info, apps (disable / remove / restore), privacy (telemetry
# settings, reversible), files (the phone's Download folder), phone data
# (accounts, contacts, calls, SMS — shown, never saved) and reboot.
#
#   phone-menu.sh            the dropdown
#   phone-menu.sh --status   one JSON line for the Waybar button
#   phone-menu.sh monitor    the device monitor (runs inside kitty)
#
# The bar button never runs adb: that would leave adb's server running for
# good. It spots a phone by its USB-debugging interface in /sys (class ff,
# subclass 42, protocol 01 — what adb itself looks for). adb only starts once
# the dropdown is opened with such a phone plugged in.

# -u and pipefail, but NOT -e — same reasoning as clipboard-menu.sh: bound to a
# click, and `set -e` turns a cosmetic failure into a dead button.
set -uo pipefail

S="$HOME/.config/hypr/scripts"
theme="$HOME/.config/rofi/picker/style.rasi"
PICKER_W=520
SIGNAL=13                                 # "signal" of custom/phone in config/waybar/phone.jsonc
LOOPDEV="${PHONECAM_DEV:-/dev/video10}"   # same default as phone-camera.sh
USB_SYSFS="${PHONE_USB_SYSFS:-/sys/bus/usb/devices}"   # overridable to test without a phone

# Shared helpers: pick/ask/confirm/list_rows/emit/…, and anchor_under_cursor.
MENU_APP="Phone"; MENU_ICON="󰄜"
source "$S/menu-lib.sh"
# Help texts are long; give them longer than menu-lib's 3 s.
notify()  { notify-send -a "Phone" -u low -t 7000 "󰄜  Phone" "$1"; }
refresh() { pkill -u "$USER" -RTMIN+"$SIGNAL" waybar 2>/dev/null || true; }

WIFI_LAST="$AUCH_CACHE/phone/wifi-address"   # the last address a phone answered on
LAYOUT_FILE="$AUCH_CACHE/phone/mirror-layout" # float | tile — how mirror.sh opens the next mirror

# The open mirror window as "ADDRESS true|false" (floating?), if there is one.
mirror_window() {
    hyprctl clients -j 2>/dev/null |
        jq -r '.[] | select(.class == "scrcpy" and (.title | test("^Phone( · tiled)?$"))) | "\(.address) \(.floating)"' | head -n1
}
remember_layout() { mkdir -p "${LAYOUT_FILE%/*}"; printf '%s\n' "$1" >"$LAYOUT_FILE"; }   # float|tile
# Float ⇄ tile the open mirror and remember it for the next one. Focus by
# address and the toggle go in one hyprctl batch, so nothing can take focus in
# between: a dispatcher that acts on "the focused window" must only ever meet
# the Phone window (hl.dsp.window.close ignored a bad argument and closed the
# focused browser, 2026-10-10). Super+W does the same by hand.
toggle_layout() {
    local addr floating
    read -r addr floating < <(mirror_window)
    [[ -n $addr ]] || { notify "The Phone window isn't open"; return; }
    hyprctl --batch "dispatch hl.dsp.focus({ window = \"address:$addr\" }) ; dispatch hl.dsp.window.float({ action = \"toggle\" })" >/dev/null
    if [[ $floating == true ]]; then remember_layout tile; else remember_layout float; fi
}

# Phones on adb over Wi-Fi: IP:port serials, or the mDNS names Android 11+
# wireless debugging uses. Only asks a server that's already running — a Wi-Fi
# connection can't exist without one, and the bar must never start it.
wifi_serials() {
    pgrep -x adb >/dev/null || return 0
    adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" && $1 ~ /:[0-9]+$|_adb-tls-connect/ { print $1 }'
}
is_wifi() { [[ $1 =~ :[0-9]+$|_adb-tls-connect ]]; }

# Wi-Fi connections that died (phone restarted, Wireless debugging switched
# off) stay in adb as "offline" and are retried every 3 s forever, unusable
# (2026-10-11: a dead :35047 kept retrying). Dropped when the dropdown opens.
drop_stale() {
    local s
    pgrep -x adb >/dev/null || return 0
    for s in $(adb devices 2>/dev/null | awk 'NR > 1 && $2 == "offline" && $1 ~ /:[0-9]+$/ { print $1 }'); do
        adb disconnect "$s" >/dev/null 2>&1
    done
}

# The same phone on USB and Wi-Fi at once is two adb devices, and plain `adb`
# then refuses ("more than one device"). Prefer the cable; adb, scrcpy and
# everything below honour ANDROID_SERIAL.
pick_device() {
    local devs=() usb
    mapfile -t devs < <(adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }')
    (( ${#devs[@]} > 1 )) || return 0
    usb=$(printf '%s\n' "${devs[@]}" | grep -vE ':[0-9]+$|_adb-tls-connect' | head -n1)
    export ANDROID_SERIAL=${usb:-${devs[0]}}
}

usb_debug_present() {
    local d
    for d in "$USB_SYSFS"/*:*; do
        [[ -r $d/bInterfaceClass ]] || continue
        [[ $(<"$d/bInterfaceClass") == ff && $(<"$d/bInterfaceSubClass") == 42 \
           && $(<"$d/bInterfaceProtocol") == 01 ]] && return 0
    done
    return 1
}
# By process name first, then arguments: a bare `pgrep -f` pattern also matches
# any shell or editor that has the text in its command line (it killed the
# test shell, 2026-10-10). One `ps -C` call covers all three names — every
# pgrep walks the whole process list (~25 ms each) and the bar asks every 5 s.
# mirror.sh titles its scrcpy window "Phone"; the webcam scrcpy/ffmpeg write
# into the loopback device. scan_procs first, then ask.
PROCS=""
scan_procs()  { PROCS=$(ps -o pid=,comm=,args= -C scrcpy,ffmpeg,droidcam-cli 2>/dev/null); }
mirror_pids() { awk '$2 == "scrcpy" && /--window-title=Phone( · tiled)?( |$)/ { print $1 }' <<<"$PROCS"; }
mirroring()   { [[ -n $(mirror_pids) ]]; }
webcam_on() {
    awk -v dev="$LOOPDEV" '($2 == "scrcpy" && index($0, "--v4l2-sink=" dev)) || ($2 == "ffmpeg" && index($0, dev)) \
                           || $2 == "droidcam-cli" { found = 1 } END { exit !found }' <<<"$PROCS"
}

# These need adb up and a phone in "device" state.
model() { adb shell getprop ro.product.model 2>/dev/null | tr -d '\r'; }
battery_info() {   # "82% · charging · 31°C"
    adb shell dumpsys battery 2>/dev/null | tr -d '\r' | awk -F': *' '
        /^ *level:/ { lvl = $2 }  /^ *status:/ { st = $2 }  /^ *temperature:/ { t = $2 }
        END {
            s = (st == 2) ? "charging" : (st == 5) ? "full" : (st == 3 || st == 4) ? "on battery" : ""
            if (lvl == "") exit
            printf "%s%%%s%s", lvl, (s ? " · " s : ""), (t ? sprintf(" · %.0f°C", t / 10) : "")
        }'
}

# ── Waybar status ───────────────────────────────────────────────────────────
status() {
    local nl=$'\n'
    scan_procs
    if mirroring; then
        emit "󰦉" active "<b>Phone · mirroring</b>${nl}The phone screen is in the \"Phone\" window.${nl}${nl}<i>Click: phone menu</i>" "mirroring the screen"
    elif webcam_on; then
        emit "󰖠" active "<b>Phone · webcam on</b>${nl}Streaming into \"Phone Camera\" ($LOOPDEV).${nl}${nl}<i>Click: phone menu</i>" "webcam on"
    elif usb_debug_present; then
        emit "󰄜" connected "<b>Phone connected</b> · USB debugging on${nl}${nl}<i>Click: mirror, webcam, apps, privacy, files and more</i>" "connected · USB debugging on"
    elif [[ -n $(wifi_serials) ]]; then
        emit "󰄜" connected "<b>Phone connected</b> · over Wi-Fi ($(wifi_serials | head -n1))${nl}${nl}<i>Click: mirror, apps, privacy, files and more</i>" "connected over Wi-Fi"
    else
        emit "󰄜" none "<b>No phone</b>${nl}Plug it in with USB debugging on — or use the webcam over Wi-Fi.${nl}${nl}<i>Click: phone menu</i>" "not connected"
    fi
}

# ── the device monitor (inside kitty) ───────────────────────────────────────
monitor() {
    local state
    adb start-server >/dev/null 2>&1
    trap 'exit 0' INT TERM
    while :; do
        state=$(adb get-state 2>/dev/null)
        printf '\033[H\033[2J'
        if [[ $state != device ]]; then
            printf 'No phone (adb: %s). Plug it in with USB debugging on.   Ctrl+C closes.\n' "${state:-nothing attached}"
        else
            printf '\033[1m%s\033[0m   %s   \033[2m(every 2 s · Ctrl+C closes)\033[0m\n\n' "$(model)" "$(battery_info)"
            adb shell top -b -n 1 -m 30 2>/dev/null | tr -d '\r'
        fi
        sleep 2
    done
}

# ── phone tools — after ppk's adb-phone and osintdroid ──────────────────────
# Never offered for removal: ppk's protected list, plus the name patterns his
# adb-phone treats as system-critical.
PROTECTED=(android com.android.systemui com.android.settings com.android.phone
    com.android.providers.telephony com.android.providers.media com.android.providers.settings
    com.android.packageinstaller com.android.keychain com.android.shell com.android.permissioncontroller
    com.android.vending com.android.bluetooth com.android.nfc com.android.se com.android.inputmethod.latin
    com.google.android.gms com.google.android.setupwizard com.google.android.documentsui
    com.google.android.apps.restore com.google.android.health.connect.backuprestore
    com.samsung.android.incallui com.samsung.android.launcher com.samsung.android.dialer
    com.samsung.android.app.contacts com.sec.android.app.camera com.sec.android.app.launcher
    com.sec.android.app.clockpackage com.sec.android.app.myfiles com.miui.home)
PROTECTED_RE='\.overlay\.|\.networkstack|\.mainline\.|\.permissioncontroller|\.webview|\.cellbroadcast|\.captiveportallogin|\.sdksandbox|\.modulemetadata|\.configupdater|\.onetimeinitializer|\.server\.deviceconfig|\.federatedcompute|\.adservices|\.ondevicepersonalization|\.providers\.|\.photopicker|\.printservice|\.packageinstaller|\.safetycenter|\.connectivity\.resources|\.ext\.shared|\.ext\.services|\.gsf|\.as\.oss|\.feedback|\.partnersetup|\.hardware\.|\.system\.|\.framework\.|vendor\.|qualcomm|samsung\.framework|sec\.android\.provider'
declare -A IS_PROTECTED=()
for _p in "${PROTECTED[@]}"; do IS_PROTECTED[$_p]=1; done; unset _p
is_protected() { [[ -n ${IS_PROTECTED[$1]:-} || ${1,,} =~ $PROTECTED_RE ]]; }
declare -A FRIENDLY=(
    [com.google.android.gm]="Gmail" [com.google.android.apps.docs]="Google Drive"
    [com.google.android.apps.tachyon]="Google Meet" [com.google.android.projection.gearhead]="Android Auto"
    [com.google.android.googlequicksearchbox]="Google Search" [com.google.android.tts]="Google Text-to-Speech"
    [com.google.android.as]="Android System Intelligence" [com.google.android.turbo]="Device Health Services"
    [com.google.android.gms]="Google Play Services" [com.google.ar.lens]="Google Lens"
    [com.android.chrome]="Chrome" [com.google.android.youtube]="YouTube"
    [com.google.android.apps.photos]="Google Photos" [com.google.android.apps.messaging]="Messages"
    [com.google.android.apps.maps]="Google Maps" [com.google.android.calendar]="Google Calendar"
    [com.google.android.keep]="Google Keep" [com.google.android.apps.youtube.music]="YouTube Music"
    [com.google.android.videos]="Google TV" [com.google.android.apps.wellbeing]="Digital Wellbeing"
    [com.android.vending]="Play Store"
    [com.facebook.katana]="Facebook" [com.facebook.orca]="Messenger" [com.facebook.appmanager]="Facebook App Manager"
    [com.facebook.system]="Facebook App Installer" [com.facebook.services]="Facebook Services"
    [com.instagram.android]="Instagram" [com.whatsapp]="WhatsApp" [org.telegram.messenger]="Telegram"
    [com.microsoft.skydrive]="OneDrive" [com.linkedin.android]="LinkedIn" [com.netflix.mediaclient]="Netflix"
    [com.spotify.music]="Spotify")
friendly() {   # PKG -> a readable name, printed and left in FN (the app list
    local last  # calls it a few hundred times; no subshell each time)
    if [[ -n ${FRIENDLY[$1]:-} ]]; then FN=${FRIENDLY[$1]}
    else
        last=${1##*.}
        [[ $last == android || $last == app ]] && { last=${1%.*}; last=${last##*.}; }
        FN=${last^}
    fi
    printf '%s\n' "$FN"
}
pkglist() { adb shell pm list packages "$@" 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' | sort -u; }

device_info() {
    local p
    mapfile -t p < <(adb shell 'getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.build.version.security_patch; getprop ro.serialno; getprop ro.build.display.id' 2>/dev/null | tr -d '\r')
    printf '%s\n' \
        "󰄜  ${p[0]:-?} ${p[1]:-?}" \
        "󰀲  Android ${p[2]:-?} (API ${p[3]:-?}) · build ${p[6]:-?}" \
        "󰒃  Security patch: ${p[4]:-unknown}" \
        "󰁹  Battery: $(battery_info)" \
        "󰋊  Storage: $(adb shell df -h /data 2>/dev/null | tr -d '\r' | awk 'NR == 2 { print $3 " used of " $2 " (" $5 ")" }')" \
        "󰈏  Serial: ${p[5]:-$(adb get-serialno 2>/dev/null | tr -d '\r')}" |
        list_rows "Device info" "Pick a line to copy it"
}

app_action() {   # PKG STATE GROUP
    local pkg=$1 state=$2 warn="" i opts=() cmds=() asks=() name
    name=$(friendly "$pkg")
    [[ $3 == google ]] && warn=" Google apps can take others down with them (Maps, Pay, Messages lean on them) — Disable is the safer choice."
    case $state in
        active)   opts=("󰜺  Disable · reversible, survives a reboot" "󰆴  Remove for this user · Restore brings it back")
                  cmds=("pm disable-user --user 0 $pkg" "pm uninstall -k --user 0 $pkg")
                  asks=("Disable $name?" "Remove $name for this user?") ;;
        disabled) opts=("󰄬  Enable it again"); cmds=("pm enable --user 0 $pkg") ;;
        removed)  opts=("󰑐  Restore it"); cmds=("cmd package install-existing $pkg") ;;
    esac
    i=$(printf '%s\n' "${opts[@]}" | pick "$name" "$pkg · $state") || return
    if [[ $state == active ]]; then
        confirm "${asks[i]}$warn" || return
    fi
    if adb shell "${cmds[i]}" 2>&1 | tr -d '\r' | grep -qiE 'success|disabled|enabled|installed for user'; then
        notify "$name: done"
    else
        notify "$name: the phone refused (${cmds[i]%% *})"
    fi
}

app_list() {   # google | third | all
    local group=$1 i rows=() pkgs=() states=() list=() p st icon
    local -A inst=() dis=() third=()
    while :; do
        rows=(); pkgs=(); states=(); inst=(); dis=(); third=()
        mapfile -t list < <(pkglist);   for p in "${list[@]}"; do inst[$p]=1; done
        mapfile -t list < <(pkglist -d); for p in "${list[@]}"; do dis[$p]=1; done
        if [[ $group == third ]]; then mapfile -t list < <(pkglist -3 -u); for p in "${list[@]}"; do third[$p]=1; done; fi
        mapfile -t list < <(pkglist -u)
        for p in "${list[@]}"; do
            [[ -n $p ]] || continue
            case $group in
                google) [[ $p =~ ^com\.google\.|^com\.android\.(chrome|vending)$ ]] || continue ;;
                third)  [[ -n ${third[$p]:-} ]] || continue ;;
            esac
            if [[ -z ${inst[$p]:-} ]]; then st=removed; icon="󰆴"
            elif [[ -n ${dis[$p]:-} ]]; then st=disabled; icon="󰜺"
            else st=active; icon="󰄬"; fi
            is_protected "$p" && icon="󰌾"
            friendly "$p" >/dev/null
            pkgs+=("$p"); states+=("$st")
            rows+=("$icon  $FN — $p · $st")
        done
        (( ${#rows[@]} )) || { notify "No apps in that list"; return; }
        i=$(printf '%s\n' "${rows[@]}" | pick "Apps" "${#rows[@]} apps · type to search · 󰌾 the phone needs it — not removable") || return
        # A protected app that is already off can still be turned back on.
        if is_protected "${pkgs[i]}" && [[ ${states[i]} == active ]]; then
            notify "$(friendly "${pkgs[i]}") is protected — the phone needs it"; continue
        fi
        app_action "${pkgs[i]}" "${states[i]}" "$group"
    done
}

apps_menu() {
    local i groups=(google third all)
    i=$(printf '%s\n' "󰊭  Google apps" "󰀻  Third-party apps" "󰏗  All apps · type to search" |
        pick "Apps" "Disable and remove are both reversible — removing is per user, Restore brings it back") || return
    app_list "${groups[i]}"
}

# ppk's telemetry list: NAME|namespace|key|privacy value. A key the phone
# doesn't have ("null") is left alone; the first change of each key saves the
# original, so it can be put back.
PRIVACY=(
    "App crash reports|system|send_action_app_error|0"
    "Security diagnostic reports|system|send_security_reports|0"
    "Samsung diagnostics agreement|system|samsung_errorlog_agree|0"
    "Personalisation service API|global|settings_use_psd_api|0"
    "External provider analytics|global|settings_use_external_provider_api|0"
    "Network recommendation scoring|global|network_recommendations_enabled|0"
    "Limit ad tracking|global|limit_ad_tracking|1"
    "Auto-upload of debug logs|system|upload_debug_log|0"
    "Device data sent with app checks|secure|package_verifier_include_device_data|0"
    "Full feedback reports|system|user_full_report|0"
)
privacy_menu() {
    local serial bak vals=() rows=() i j e name ns key want cur orig cmd n ok
    serial=$(adb get-serialno 2>/dev/null | tr -d '\r')
    bak="$AUCH_CACHE/phone/${serial:-unknown}-settings.tsv"; mkdir -p "${bak%/*}"
    while :; do
        cmd=""; for e in "${PRIVACY[@]}"; do IFS='|' read -r _ ns key _ <<<"$e"; cmd+="settings get $ns $key; "; done
        mapfile -t vals < <(adb shell "$cmd" 2>/dev/null | tr -d '\r')
        rows=(); n=0
        for i in "${!PRIVACY[@]}"; do
            IFS='|' read -r name ns key want <<<"${PRIVACY[i]}"
            cur=${vals[i]:-null}
            if [[ $cur == null ]]; then rows+=("󰘥  $name · not on this phone")
            elif [[ $cur == "$want" ]]; then rows+=("󰄬  $name · private")
            else rows+=("󰀪  $name · on (value $cur)"); n=$((n + 1)); fi
        done
        rows+=("󰒃  Make all private · $( ((n)) && echo "$n still on" || echo "all done")" "󰑐  Put back everything changed here")
        i=$(printf '%s\n' "${rows[@]}" | pick "Privacy" "Telemetry settings on the phone · each change is reversible") || return
        if (( i < ${#PRIVACY[@]} )); then
            IFS='|' read -r name ns key want <<<"${PRIVACY[i]}"; cur=${vals[i]:-null}
            [[ $cur == null ]] && continue
            if [[ $cur == "$want" ]]; then
                orig=$(awk -F'\t' -v n="$ns" -v k="$key" '$1 == n && $2 == k { print $3 }' "$bak" 2>/dev/null | tail -n1)
                [[ -n $orig ]] || { notify "$name was already private — there's no earlier value to put back"; continue; }
                adb shell settings put "$ns" "$key" "$orig" >/dev/null 2>&1 && notify "$name: back to $orig" || notify "$name: the phone refused"
            else
                grep -qP "^$ns\t$key\t" "$bak" 2>/dev/null || printf '%s\t%s\t%s\n' "$ns" "$key" "$cur" >>"$bak"
                adb shell settings put "$ns" "$key" "$want" >/dev/null 2>&1 && notify "$name: private" || notify "$name: the phone refused"
            fi
        elif (( i == ${#PRIVACY[@]} )); then
            (( n )) || { notify "All of them are private already"; continue; }
            confirm "Make all $n private? Each original value is saved, so this can be undone." || continue
            ok=0
            for j in "${!PRIVACY[@]}"; do
                IFS='|' read -r name ns key want <<<"${PRIVACY[j]}"; cur=${vals[j]:-null}
                [[ $cur == null || $cur == "$want" ]] && continue
                grep -qP "^$ns\t$key\t" "$bak" 2>/dev/null || printf '%s\t%s\t%s\n' "$ns" "$key" "$cur" >>"$bak"
                adb shell settings put "$ns" "$key" "$want" </dev/null >/dev/null 2>&1 && ok=$((ok + 1))
            done
            notify "$ok of $n settings made private"
        else
            [[ -s $bak ]] || { notify "Nothing changed here yet"; continue; }
            confirm "Put every setting changed here back to its original value?" || continue
            # </dev/null: adb shell forwards stdin, and would swallow the rest of the file.
            while IFS=$'\t' read -r ns key orig; do adb shell settings put "$ns" "$key" "$orig" </dev/null >/dev/null 2>&1; done <"$bak"
            rm -f "$bak"; notify "Original values restored"
        fi
    done
}

phone_get() {
    local names=() i
    mapfile -t names < <(adb shell ls -1t /sdcard/Download 2>/dev/null | tr -d '\r' | grep -v '^$')
    (( ${#names[@]} )) || { notify "The phone's Download folder is empty"; return; }
    i=$(printf '󰈔  %s\n' "${names[@]}" | pick "Phone downloads" "Newest first · a pick copies it to ~/Downloads") || return
    adb pull "/sdcard/Download/${names[i]}" "$HOME/Downloads/" >/dev/null 2>&1 &&
        notify "Saved to ~/Downloads/${names[i]}" || notify "Couldn't copy ${names[i]}"
}
phone_send() {
    local files=() i
    mapfile -t files < <(find "$HOME/Downloads" -maxdepth 1 -type f -printf '%T@\t%f\n' 2>/dev/null | sort -rn | head -n 60 | cut -f2-)
    (( ${#files[@]} )) || { notify "~/Downloads is empty"; return; }
    i=$(printf '󰈔  %s\n' "${files[@]}" | pick "Send to phone" "From ~/Downloads, newest first · goes to the phone's Download folder") || return
    adb push "$HOME/Downloads/${files[i]}" /sdcard/Download/ >/dev/null 2>&1 &&
        notify "Sent ${files[i]} to the phone" || notify "Couldn't send ${files[i]}"
}
files_menu() {
    local i
    i=$(printf '%s\n' "󰇚  Get a file from the phone ›" "󰕒  Send a file to the phone ›" "󰒃  Scan the phone's Download folder for viruses · copies it here first" |
        pick "Files" "The phone's Download folder (/sdcard/Download)") || return
    case $i in
        0) phone_get ;;
        1) phone_send ;;
        2) command -v clamscan >/dev/null || { notify "Needs ClamAV — install it from Virus scan in the shield menu"; return; }
           # The copy stays in the cache (replaced each scan), so Virus scan's results point at real files.
           in_terminal "Scan phone downloads" "d='$AUCH_CACHE/phone/scan'; rm -rf \"\$d\" && mkdir -p \"\$d\" && echo \"Copying the phone's Download folder…\" && adb pull /sdcard/Download \"\$d\" >/dev/null && '$S/virus-menu.sh' scan \"\$d/Download\" && echo && echo 'These are copies: anything found is still on the phone — delete it there.'" ;;
    esac
}

# shown TITLE MESSAGE — list_rows, or a note when the phone sent nothing back.
shown() {
    local rows=()
    mapfile -t rows
    (( ${#rows[@]} )) || { notify "Nothing came back — it's empty, or this Android doesn't allow reading it over USB"; return; }
    printf '%s\n' "${rows[@]}" | list_rows "$1" "$2"
}

phone_data() {   # ppk's osintdroid views
    local i
    i=$(printf '%s\n' "󰇮  Accounts" "󰀉  Contacts" "󰏲  Call log" "󰍦  Messages (SMS)" |
        pick "Phone data" "Read from the phone over USB — shown here, saved nowhere") || return
    case $i in
        0) adb shell dumpsys account 2>/dev/null | tr -d '\r' | grep -oE 'Account \{name=[^,]+, type=[^}]+\}' |
               sed -E 's/Account \{name=(.*), type=(.*)\}/󰇮  \1 · \2/' | sort -u | shown "Accounts" "Accounts signed in on the phone" ;;
        1) adb shell content query --uri content://com.android.contacts/data/phones --projection display_name:data1 2>/dev/null | tr -d '\r' |
               sed -nE 's/^Row: [0-9]+ display_name=(.*), data1=(.*)$/󰀉  \1 · \2/p' | sort -u | shown "Contacts" "Name · number" ;;
        2) adb shell content query --uri content://call_log/calls --projection date:type:name:number --sort "date DESC" 2>/dev/null | tr -d '\r' |
               sed -nE 's/^Row: [0-9]+ date=([0-9]+), type=([0-9]+), name=(.*), number=(.*)$/\1\x1f\2\x1f\3\x1f\4/p' | head -n 300 |
               while IFS=$'\x1f' read -r d t n num; do
                   case $t in 1) t="in";; 2) t="out";; 3) t="missed";; 5) t="declined";; *) t="?";; esac
                   [[ $n == NULL ]] && n=""
                   printf '󰏲  %s · %s · %s\n' "$(date -d "@$((d / 1000))" '+%F %H:%M')" "$t" "${n:+$n }$num"
               done | shown "Call log" "Newest first, up to 300" ;;
        3) adb shell content query --uri content://sms --projection date:type:address:body --sort "date DESC" 2>/dev/null | tr -d '\r' |
               sed -nE 's/^Row: [0-9]+ date=([0-9]+), type=([0-9]+), address=([^,]*), body=(.*)$/\1\x1f\2\x1f\3\x1f\4/p' | head -n 300 |
               while IFS=$'\x1f' read -r d t a b; do
                   [[ $t == 2 ]] && t="to" || t="from"
                   printf '󰍦  %s · %s %s · %s\n' "$(date -d "@$((d / 1000))" '+%F %H:%M')" "$t" "$a" "${b:0:120}"
               done | shown "Messages" "Newest first, up to 300 · a pick copies one" ;;
    esac
}

# Safe mode starts the phone with every downloaded app switched off — to find
# an app that crashes it or drains the battery; the next normal restart leaves
# it. Android enters it from a boot flag (persist.sys.safemode) that its own
# power menu sets, and most phones don't let adb set that flag. So: try, read
# it back, and reboot only if it took; otherwise say how to do it on the phone.
safe_mode() {
    confirm "Restart into safe mode? Downloaded apps stay off until the next normal restart." || return
    adb shell setprop persist.sys.safemode 1 >/dev/null 2>&1
    if [[ $(adb shell getprop persist.sys.safemode 2>/dev/null | tr -d '\r') == 1 ]]; then
        if adb reboot; then notify "Restarting into safe mode — a normal restart leaves it"
        else adb shell setprop persist.sys.safemode 0 >/dev/null 2>&1; notify "The restart didn't go through — safe mode is off again"; fi
    else
        notify "This phone doesn't let a computer start safe mode. On the phone: open the power menu, touch and hold Power off (or Restart), then tap OK."
    fi
}

reboot_menu() {
    local i modes=("" recovery bootloader safe) names=("Restart" "Recovery mode" "Bootloader (fastboot)" "Safe mode")
    i=$(printf '%s\n' "󰜉  Restart" "󰑓  Recovery mode" "󰘚  Bootloader (fastboot)" "󰒃  Safe mode · downloaded apps off until a normal restart" |
        pick "Reboot" "Mirroring and the webcam stop while it restarts · over Wi-Fi it comes back on a new port") || return
    if [[ ${modes[i]} == safe ]]; then safe_mode; return; fi
    confirm "${names[i]}: the phone restarts now." || return
    adb reboot ${modes[i]} && notify "${names[i]}…"
}

# ── finding the phone's port ────────────────────────────────────────────────
# With Wireless debugging on, the phone announces its connect port — and while
# the pairing popup is open, its pairing port — on the network (DNS-SD over
# mDNS: _adb-tls-connect._tcp / _adb-tls-pairing._tcp). Arch's adb is built
# without mDNS, but systemd-resolved speaks it on this Wi-Fi, so ask it. Prints
# "IP:PORT" per phone. Connect ports are checked live first (2 s TCP): the
# resolver can remember an old port. Pairing ports are never touched — a stray
# connection could close the popup. Best effort: a network that blocks
# multicast gives nothing, and the menu asks for the port as before.
mdns_find() {   # connect|pairing [IP]
    local svc="_adb-tls-$1._tcp.local" want=${2:-} inst port target ip
    local q=(timeout 4 resolvectl query --protocol=mdns --legend=no)
    while read -r inst; do
        read -r port target < <("${q[@]}" -t SRV "$inst" 2>/dev/null | awk '$2 == "IN" && $3 == "SRV" { print $6, $7; exit }')
        [[ $port =~ ^[0-9]+$ && -n $target ]] || continue
        while read -r ip; do
            [[ -z $want || $ip == "$want" ]] || continue
            if [[ $1 == connect ]]; then timeout 2 bash -c "</dev/tcp/$ip/$port" 2>/dev/null || continue; fi
            echo "$ip:$port"
        done < <("${q[@]}" -t A "$target" 2>/dev/null | awk '$2 == "IN" && $3 == "A" { print $4 }')
    done < <("${q[@]}" -t PTR "$svc" 2>/dev/null | awk '$2 == "IN" && $3 == "PTR" { print $4 }' | sort -u)
}

# ── mirroring over Wi-Fi ────────────────────────────────────────────────────
# USB -> Wi-Fi: note the phone's address for next time, then `scrcpy --tcpip`
# turns on adb's TCP mode on the phone (port 5555), reconnects over it and
# mirrors; the cable can come out once the window is up. TCP mode lasts until
# the phone restarts.
wifi_switch() {
    local ip
    ip=$(adb shell ip -f inet addr show wlan0 2>/dev/null | tr -d '\r' | awk '/inet / { sub(/\/.*/, "", $2); print $2; exit }')
    [[ -n $ip ]] || { notify "The phone isn't on Wi-Fi — join the same network as this laptop first"; return; }
    mkdir -p "${WIFI_LAST%/*}"; printf '%s:5555\n' "$ip" >"$WIFI_LAST"
    notify "Moving to Wi-Fi ($ip) — unplug the cable once the Phone window opens"
    env -u ANDROID_SERIAL setsid -f "$S/mirror.sh" switch >/dev/null 2>&1
}

# adb connect's answers, as this adb words them (checked 2026-10-11):
#   "connected to X" / "already connected to X"   in
#   "failed to connect to 'X': Connection refused" nothing listening at that port
#   "failed to connect to X" (no reason)           the phone answered and turned
#                                                  this laptop away: not paired yet
wifi_connect() {   # ADDRESS[:PORT] [after-pair] — connect, then reopen the dropdown
    local addr=$1 out
    [[ $addr == *:* ]] || addr="$addr:5555"
    out=$(timeout 8 adb connect "$addr" 2>&1)
    case $out in
        *"connected to"*) ;;
        *"refused"*)
            notify "Nothing is listening at $addr. Wireless debugging is off, or its port changed — it changes every time it's switched on; the main Wireless debugging screen shows the current one. Older phones: plug in once and pick Switch to Wi-Fi."
            return 1 ;;
        ""|*"timed out"*|*"No route"*|*"unreachable"*)
            notify "No answer from $addr — is the phone on this Wi-Fi network?"
            return 1 ;;
        *)
            if [[ -z ${2:-} ]]; then
                notify "The phone answered, but doesn't know this laptop yet — pair it: open the pairing popup on the phone"
                wifi_pair "$addr"
                return
            fi
            notify "Paired, but the phone still turned the laptop away at $addr — check that address on the main Wireless debugging screen"
            return 1 ;;
    esac
    if [[ $(adb -s "$addr" get-state 2>/dev/null) != device ]]; then
        notify "Connected, but the phone hasn't allowed it — accept the prompt on the phone, then try again"
        return 1
    fi
    mkdir -p "${WIFI_LAST%/*}"; printf '%s\n' "$addr" >"$WIFI_LAST"
    # Connecting and mirroring are separate steps: connected, the dropdown
    # comes back with every row — mirror, webcam, apps… Connecting used to
    # start the mirror straight away, so after a disconnect there was no way to
    # the webcam or the tools without mirroring first (2026-10-11).
    notify "Connected over Wi-Fi ($addr)"
    exec "$S/phone-menu.sh"
}

# Android 11+, no cable ever: Developer options → Wireless debugging → "Pair
# device with pairing code" pops up an IP:port and a six-digit code. That port
# is for pairing only — the one to connect to afterwards is on the main
# Wireless debugging screen, and typing that one here fails the handshake
# (2026-10-11: :32905 from the main screen). The popup's code and port change
# every time it opens and it closes if you leave it, so both go in one prompt.
# Arch's adb has no mDNS, so nothing can be discovered — it's typed.
lan_prefix() {   # "172.16.2." — this laptop's LAN, skipping VPN and bridge interfaces
    ip -4 -o addr show scope global 2>/dev/null |
        awk '$2 !~ /^(wg|tun|tap|tailscale|docker|br-|virbr|veth)/ { split($4, a, "."); print a[1] "." a[2] "." a[3] "."; exit }'
}
wifi_pair() {   # [CONNECT-ADDRESS] — known already when a connect led here
    local last pre input t addr="" code="" out conn
    last=$(head -n1 "$WIFI_LAST" 2>/dev/null)
    pick "Pair" "On the phone: Developer options → Wireless debugging → Pair device with pairing code — keep that popup open" \
        <<<"󰐊  The pairing popup is open" >/dev/null || return
    pre=$(mdns_find pairing | head -n1)
    if [[ -n $pre ]]; then
        input=$(ask "Pair" "Found the pairing popup at $pre — type the six-digit code it shows" "$pre ") || return
    else
        pre=$( [[ -n $last ]] && echo "${last%:*}:" || lan_prefix)
        input=$(ask "Pair" "Type the POPUP's IP:port and code, e.g. 172.16.2.35:37123 482915" "$pre") || return
    fi
    # Forgiving: the box starts filled in, and typing the whole address after it
    # gave "172.16.2.172.16.2.35:…" (2026-10-11) — so take the last IP:port found
    # anywhere, or "IP port"; the code is the six-digit run (ports have ≤5 digits).
    addr=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{2,5}' <<<"$input" | tail -n1)
    if [[ -z $addr && $input =~ (([0-9]{1,3}\.){3}[0-9]{1,3})[[:space:]]+([0-9]{2,5})([^0-9]|$) ]]; then
        addr="${BASH_REMATCH[1]}:${BASH_REMATCH[3]}"
    fi
    code=$(grep -oE '[0-9]{6}' <<<"${input//"${addr%:*}"/ }" | tail -n1)
    [[ -n $addr ]] || { notify "No IP:port in “$input” — type the popup's address, e.g. 172.16.2.35:37123, then the code"; return; }
    [[ -n $code ]] || code=$(ask "Pairing code" "The six-digit code in the popup" "") || return
    out=$(timeout 15 adb pair "$addr" "$code" 2>&1)
    if [[ $out != *"Successfully paired"* ]]; then
        case $out in
            *"Wrong password"*|*"dropped"*)
                notify "The phone refused the pairing. Either the code didn't match — the popup's code and port change each time it opens, and it closes when you leave it or the screen locks — or the address was the main screen's instead of the popup's. Open the popup again and type both while it's up. No-pairing route: plug in once and pick Switch to Wi-Fi." ;;
            *)  notify "Nothing answered at $addr — use the address in the pairing popup. (${out:-no answer})" ;;
        esac
        return
    fi
    if [[ -n ${1:-} ]]; then notify "Paired — connecting to $1"; wifi_connect "$1" after-pair; return; fi
    conn=$(mdns_find connect "${addr%:*}" | head -n1)
    if [[ -n $conn ]]; then notify "Paired — connecting to $conn"; wifi_connect "$conn" after-pair; return; fi
    conn=$(ask "Connect address" "Paired. Now the IP:port on the main Wireless debugging screen (the popup has closed)" "${addr%:*}:") || return
    wifi_connect "$conn" after-pair
}

# The saved port goes stale whenever Wireless debugging restarts — after a phone
# restart, or switching it off and on (2026-10-11: 32905 → 41127). So check it
# first (a 2 s TCP probe, no adb): open → connect; refused → the phone is there
# but on a new port, ask for it; no answer → the phone isn't on this network.
wifi_reconnect() {
    local last ip port rc addr
    last=$(head -n1 "$WIFI_LAST" 2>/dev/null); [[ -n $last ]] || return
    ip=${last%:*}; port=${last##*:}
    timeout 2 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; rc=$?
    case $rc in
        0)   wifi_connect "$last" ;;
        124) # No answer at that IP — maybe it has a new one: look for it on the network.
             addr=$(mdns_find connect | head -n1)
             if [[ -n $addr ]]; then notify "Found the phone at $addr"; wifi_connect "$addr"
             else notify "No answer from the phone at $ip — is it on this Wi-Fi network, with Wireless debugging on?"; fi ;;
        *)   # The phone is there, on a new port: ask it, then the user.
             addr=$(mdns_find connect "$ip" | head -n1)
             if [[ -n $addr ]]; then notify "Found the new port: $addr"; wifi_connect "$addr"; return; fi
             addr=$(ask "New port" "The phone's Wireless debugging port has changed (it does after a restart). Type the IP:port on its Wireless debugging screen" "$ip:") || return
             wifi_connect "$addr" ;;
    esac
}

# Forget the phone on this side: disconnect it and drop the saved address. The
# pairing itself lives on the phone — adb keeps no pairing file here — so the
# phone has to forget the laptop too.
wifi_forget() {
    local last ip s
    last=$(head -n1 "$WIFI_LAST" 2>/dev/null); ip=${last%:*}
    [[ -z $ip ]] && is_wifi "${ANDROID_SERIAL:-}" && ip=${ANDROID_SERIAL%:*}
    confirm "Forget this phone${ip:+ ($ip)}? The laptop disconnects and drops the saved address. To unpair completely, the phone forgets the laptop too: Wireless debugging → Paired devices → this laptop → Forget." || return
    for s in $(adb devices 2>/dev/null | awk -v ip="$ip" 'NR > 1 && index($1, ip ":") == 1 { print $1 }'); do adb disconnect "$s" >/dev/null 2>&1; done
    rm -f "$WIFI_LAST"
    notify "Forgotten on the laptop. On the phone: Wireless debugging → Paired devices → this laptop → Forget."
}

wifi_conn_menu() {   # connected over Wi-Fi
    local i
    i=$(printf '%s\n' "󰖪  Disconnect · Reconnect over Wi-Fi brings it back" "󰆴  Forget this phone · disconnect and drop the saved address" |
        pick "Wi-Fi connection" "${ANDROID_SERIAL:-}") || return
    case $i in
        0) adb disconnect "$ANDROID_SERIAL" >/dev/null 2>&1; notify "Disconnected from the phone's Wi-Fi" ;;
        1) wifi_forget ;;
    esac
}

wifi_menu() {
    local last i addr rows=() acts=() found=()
    last=$(head -n1 "$WIFI_LAST" 2>/dev/null)
    if [[ -n $last ]]; then rows+=("󰖩  Connect to $last"); acts+=(last); fi
    rows+=("󰍉  Find phones on this network · with Wireless debugging on" "󰐕  Another address…" "󰌆  Pair a new phone · Android 11+, no cable needed")
    acts+=(find other pair)
    if [[ -n $last ]]; then rows+=("󰆴  Forget this phone · drop the saved address"); acts+=(forget); fi
    i=$(printf '%s\n' "${rows[@]}" | pick "Connect over Wi-Fi" "The phone has to be on this Wi-Fi network") || return
    case ${acts[i]:-} in
        last)  wifi_connect "$last" ;;
        other) addr=$(ask "Phone address" "IP[:port] — Android 11+: the address on the Wireless debugging screen; after a USB switch: port 5555" "${last%:*}") || return
               wifi_connect "$addr" ;;
        pair)  wifi_pair ;;
        find)  mapfile -t found < <(mdns_find connect)
               case ${#found[@]} in
                   0) notify "No phone announcing Wireless debugging here — is it switched on (Developer options)? Some networks block this; Another address… still works." ;;
                   1) wifi_connect "${found[0]}" ;;
                   *) i=$(printf '󰄜  %s\n' "${found[@]}" | pick "Phones found" "Pick one to connect") || return
                      wifi_connect "${found[i]}" ;;
               esac ;;
        forget) wifi_forget ;;
    esac
}

# ── the dropdown ────────────────────────────────────────────────────────────
rows=(); acts=(); plain=()
row() {   # ICON COLOUR NAME SUMMARY ACTION — shown as markup, searched as plain text
    rows+=("<span foreground='$2'>$1</span>   <b>$3</b>   <span foreground='#a6adc8'>$(printf '%s' "$4" | esc)</span>")
    # Typing searches the row's name, word starts only (like the shield's
    # dropdown), plus a hyphen-free copy ("WiFi"); escaped — rofi reads it as markup.
    plain+=("$(printf '%s' "$3 ${3//-/}" | esc)")
    acts+=("$5")
}

act() {
    local ip
    case $1 in
        mirror)      setsid -f "$S/mirror.sh" >/dev/null 2>&1 ;;
        mirror-off)  MIRROR_SCREEN_OFF=1 setsid -f "$S/mirror.sh" >/dev/null 2>&1 ;;
        # Not `mirror.sh stop`: that kills every scrcpy, the webcam one included.
        # Keep the layout it had — a Super+W toggle counts too.
        mirror-stop) case $(mirror_window | cut -d' ' -f2) in true) remember_layout float ;; false) remember_layout tile ;; esac
                     scan_procs; mirror_pids | xargs -r kill && notify "Mirroring stopped" ;;
        mirror-layout) toggle_layout ;;
        cam-front)   setsid -f "$S/phone-camera.sh" usb front >/dev/null 2>&1 ;;
        cam-back)    setsid -f "$S/phone-camera.sh" usb back >/dev/null 2>&1 ;;
        cam-stop)    "$S/phone-camera.sh" stop >/dev/null 2>&1 ;;
        cam-wifi)
            ip=$(SEC_MENU_POS=$(anchor_under_cursor "$MENU_W") ask "Phone IP[:port]" \
                     "Shown by the IP Webcam app on the phone, e.g. 192.168.1.42:8080") || return
            [[ -n ${ip//[[:space:]]/} ]] && setsid -f kitty --title "Phone camera" "$S/phone-camera.sh" start "$ip" >/dev/null 2>&1 ;;
        monitor)     setsid -f kitty --class sysmon-float --title "Phone monitor" "$S/phone-menu.sh" monitor >/dev/null 2>&1 ;;
        wifi-switch) wifi_switch ;;
        wifi)        SEC_MENU_POS=$(anchor_under_cursor "$MENU_W"); export SEC_MENU_POS; wifi_menu ;;
        wifi-again)  SEC_MENU_POS=$(anchor_under_cursor "$MENU_W"); export SEC_MENU_POS; wifi_reconnect ;;
        wifi-conn)   SEC_MENU_POS=$(anchor_under_cursor "$MENU_W"); export SEC_MENU_POS; wifi_conn_menu ;;
        info|apps|privacy|files|data|reboot)
            SEC_MENU_POS=$(anchor_under_cursor "$MENU_W"); export SEC_MENU_POS
            case $1 in
                info) device_info ;; apps) apps_menu ;; privacy) privacy_menu ;;
                files) files_menu ;; data) phone_data ;; reboot) reboot_menu ;;
            esac ;;
        help)        notify "Plug the phone in by USB. On the phone: Settings → About phone → tap Build number 7 times → Developer options → turn on USB debugging." ;;
        help-auth)   notify "Unlock the phone and accept \"Allow USB debugging?\" (tick \"Always allow from this computer\"), then open this menu again." ;;
        help-replug) notify "Unplug the cable and plug it back in, unlocked. If it stays unreachable: toggle USB debugging off and on in Developer options." ;;
    esac
    # Let the started process appear, then update the button.
    ( sleep 2; refresh ) >/dev/null 2>&1 &
}

dropdown() {
    local state="" model batt i serial
    scan_procs
    drop_stale
    if usb_debug_present || [[ -n $(wifi_serials) ]]; then
        adb start-server >/dev/null 2>&1
        pick_device
        state=$(adb get-state 2>/dev/null)
        serial=$(adb get-serialno 2>/dev/null)
        export ANDROID_SERIAL=${ANDROID_SERIAL:-$serial}
    fi
    case $state in
        device)
            model=$(model); batt=$(battery_info)
            if mirroring; then
                row "󰓛" "#f38ba8" "Stop mirroring" "closes the Phone window" mirror-stop
                if [[ $(mirror_window | cut -d' ' -f2) == false ]]; then
                    row "󰊓" "#b4befe" "Float the Phone window" "phone-sized, on top · remembered for next time" mirror-layout
                else
                    row "󰕰" "#b4befe" "Tile the Phone window" "into the layout · remembered for next time" mirror-layout
                fi
            else
                row "󰦉" "#b4befe" "Mirror screen" "over $(is_wifi "$serial" && echo Wi-Fi || echo USB) with sound · the phone stays usable" mirror
                row "󰶐" "#b4befe" "Mirror · phone screen off" "saves battery · Alt+Shift+O turns it back on" mirror-off
                is_wifi "$serial" || row "󰖩" "#b4befe" "Switch to Wi-Fi" "mirror without the cable · unplug it after" wifi-switch
            fi
            if webcam_on; then row "󰓛" "#f38ba8" "Stop webcam" "\"Phone Camera\" stops streaming" cam-stop
            else
                row "󰄂" "#b4befe" "Webcam · front camera" "into \"Phone Camera\" for any app · Android 12+" cam-front
                row "󰄆" "#b4befe" "Webcam · back camera"  "into \"Phone Camera\" for any app · Android 12+" cam-back
            fi
            row "󰗶" "#a6e3a1" "Device monitor" "${model:+$model · }${batt:-battery unknown}" monitor
            row "󰋽" "#cdd6f4" "Device info"  "Android, security patch, storage, serial" info
            row "󰀻" "#cdd6f4" "Apps"         "Google and third-party · disable, remove, restore" apps
            row "󰒃" "#cdd6f4" "Privacy"      "10 telemetry settings · reversible" privacy
            row "󰉋" "#cdd6f4" "Files"        "Download folder · get, send, scan" files
            row "󰇮" "#cdd6f4" "Phone data"   "accounts, contacts, calls, SMS" data
            row "󰜉" "#cdd6f4" "Reboot"       "restart, recovery, bootloader" reboot
            if is_wifi "$serial" && ! mirroring; then row "󰖩" "#cdd6f4" "Wi-Fi connection ›" "disconnect, or forget this phone" wifi-conn; fi
            ;;
        unauthorized)
            row "󰣮" "#f9e2af" "Allow USB debugging" "accept the prompt on the phone, then reopen" help-auth ;;
        "")
            if usb_debug_present; then   # plugged in, but adb got no answer
                row "󰥐" "#f9e2af" "Phone found, adb can't reach it" "unplug and replug, then reopen" help-replug
            else
                row "󰥐" "#7f849c" "No phone connected" "plug in with USB debugging on — tap for how" help
            fi
            if [[ -s $WIFI_LAST ]]; then
                row "󰖩" "#b4befe" "Reconnect over Wi-Fi" "$(head -n1 "$WIFI_LAST") · then mirror, webcam, apps…" wifi-again
                row "󰖩" "#b4befe" "Connect over Wi-Fi ›" "another address, or pair a new phone" wifi
            else
                row "󰖩" "#b4befe" "Connect over Wi-Fi ›" "a phone on this network · Android 11+ pairs with a code" wifi
            fi ;;
        *)  # offline, recovery, bootloader, …
            row "󰥐" "#f9e2af" "Phone is $state" "unplug and replug, or restart the phone" help-replug ;;
    esac
    # No cable needed for this one: the IP Webcam app, same Wi-Fi network.
    webcam_on || row "󰖩" "#b4befe" "Webcam over Wi-Fi" "IP Webcam app on the phone, same network" cam-wifi

    # One click picks a row; a click outside closes the dropdown; typing
    # filters the plain text, each row's "display" is what's shown.
    i=$(for j in "${!rows[@]}"; do printf '%s\0display\x1f%s\n' "${plain[j]}" "${rows[j]}"; done |
        rofi -dmenu -i -no-custom -markup-rows -matching prefix -format i -p "" \
             -theme "$theme" -theme-str "$(anchor_under_cursor "$PICKER_W") listview { lines: ${#rows[@]}; }" \
             -me-select-entry '' -me-accept-entry MousePrimary) || exit 0
    [[ $i =~ ^[0-9]+$ ]] && act "${acts[i]:-}"
}

# ── main ────────────────────────────────────────────────────────────────────
case ${1:-} in
    --status) status; exit 0 ;;
    monitor)  monitor; exit 0 ;;
esac

# A second click on the button closes the dropdown instead of stacking another.
if pgrep -u "$USER" -x rofi >/dev/null; then
    pkill -u "$USER" -x rofi
    exit 0
fi
dropdown
