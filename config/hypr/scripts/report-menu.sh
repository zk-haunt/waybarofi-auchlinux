#!/usr/bin/env bash
# Report IP/URL — a row in the hub dropdown (sec-picker.sh), after ppk's
# sentinel-report: look up or report a suspicious IP address, domain or URL.
#
#   report-menu.sh            the menu
#   report-menu.sh --status   one JSON line for the hub row
#
# Web lookups need nothing: they open in the browser with the target filled in
# (or copied, for the sites that can't take it in the address). The API rows
# appear once a key file exists — one key per file, chmod 600:
#     ~/.config/auch/keys/abuseipdb     (abuseipdb.com → Account → API)
#     ~/.config/auch/keys/kaspersky     (opentip.kaspersky.com → API)
# Keys reach curl through a temporary header file, never its command line,
# where any process could read them.

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="Report"; MENU_ICON="󰀦"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

KEYS="${XDG_CONFIG_HOME:-$HOME/.config}/auch/keys"

is_ipv4() { [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_ipv6() { [[ $1 =~ ^[0-9a-fA-F:]+$ && $1 == *:*:* ]]; }
is_ip()   { is_ipv4 "$1" || is_ipv6 "$1"; }
is_url()  { [[ $1 =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]]+$ || $1 =~ ^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(/[^[:space:]]*)?$ ]]; }
enc()     { jq -rn --arg s "$1" '$s | @uri'; }

open_url() { xdg-open "$1" >/dev/null 2>&1 & }
# For sites with no way to pass the target in the address.
open_paste() { printf '%s' "$2" | wl-copy; open_url "$1"; notify "Copied $2 — paste it into the page"; }

# api_get URL KEYNAME HEADER — curl with the key header read from a 600 file.
api_call() {
    local url=$1 key=$2 header=$3 method=${4:-GET} hf out; shift 4 2>/dev/null || shift $#
    hf=$(umask 077; mktemp) || return 1
    printf '%s: %s\nAccept: application/json\n' "$header" "$(<"$KEYS/$key")" >"$hf"
    out=$(curl -sS --fail-with-body --max-time 15 -X "$method" -H @"$hf" "$url" "$@" 2>&1)
    rm -f "$hf"
    printf '%s' "$out"
}

status() {
    local keys=()
    [[ -s $KEYS/abuseipdb ]] && keys+=(AbuseIPDB)
    [[ -s $KEYS/kaspersky ]] && keys+=(OpenTIP)
    emit "󰀦" ok "<b>Report IP/URL</b>
Look up or report a suspicious IP address, domain or URL.
API keys: ${keys[*]:-none (web lookups only)}" "look up or report an IP or URL${keys:+ · keys: ${keys[*]}}"
}

abuse_check() {
    local r
    r=$(api_call "https://api.abuseipdb.com/api/v2/check?ipAddress=$(enc "$1")&maxAgeInDays=90" abuseipdb Key GET) || { notify "AbuseIPDB: $r"; return; }
    jq -r '.data | "Abuse confidence: \(.abuseConfidenceScore)%", "Reports (90 days): \(.totalReports) from \(.numDistinctUsers) users",
        "Country: \(.countryCode // "?") · ISP: \(.isp // "?")", "Domain: \(.domain // "?") · usage: \(.usageType // "?")",
        "Last reported: \(.lastReportedAt // "never")", "Whitelisted: \(.isWhitelisted)"' <<<"$r" 2>/dev/null |
        list_rows "AbuseIPDB" "$1"
}

abuse_report() {
    local cats=("14|Port scan" "18|Brute force" "22|SSH" "15|Hacking" "21|Web app attack" "19|Bad web bot" "4|DDoS")
    local i comment r
    i=$(printf '%s\n' "${cats[@]#*|}" | pick "Category" "What did $1 do? (AbuseIPDB category)") || return
    comment=$(ask "Comment" "What you saw — sent to AbuseIPDB with the report, so leave out anything private" "") || return
    confirm "Report $1 to AbuseIPDB as \"${cats[i]#*|}\"? The report is public." || return
    r=$(api_call "https://api.abuseipdb.com/api/v2/report" abuseipdb Key POST \
            --data-urlencode "ip=$1" --data-urlencode "categories=${cats[i]%%|*}" --data-urlencode "comment=$comment")
    if jq -e '.data.abuseConfidenceScore' <<<"$r" >/dev/null 2>&1; then
        notify "Reported. $1 now has abuse confidence $(jq -r '.data.abuseConfidenceScore' <<<"$r")%"
    else
        notify "AbuseIPDB didn't accept it: $(jq -r '.errors[0].detail // .' <<<"$r" 2>/dev/null | head -c 200)"
    fi
}

opentip() {
    local kind=$1 target=$2 r
    r=$(api_call "https://opentip.kaspersky.com/api/v1/search/$kind?request=$(enc "$target")" kaspersky x-api-key GET) || { notify "OpenTIP: $r"; return; }
    jq -r '"Zone: \(.Zone // "?")  (Red = dangerous · Orange = suspicious · Grey = unknown · Green = clean)",
        (.IpGeneralInfo // .DomainGeneralInfo // .UrlGeneralInfo // {} | to_entries[] | "\(.key): \(.value | tostring)")' <<<"$r" 2>/dev/null |
        list_rows "OpenTIP" "$target"
}

menu() {
    local clip target t kind i rows=() acts=()
    clip=$(wl-paste --no-newline 2>/dev/null | head -c 300)
    { is_ip "$clip" || is_url "$clip"; } || clip=""
    target=$(ask "IP or URL" "A suspicious IP address, domain or URL${clip:+ — filled in from the clipboard}" "$clip") || return
    target=${target//[[:space:]]/}
    t=$(enc "$target")
    if is_ip "$target"; then
        kind=ip
        rows+=("󰀦  AbuseIPDB · check" "󰒃  VirusTotal" "󰒃  Kaspersky OpenTIP" "󰈀  Spamhaus" "󰈀  Cisco Talos")
        acts+=("u|https://www.abuseipdb.com/check/$t" "u|https://www.virustotal.com/gui/ip-address/$t"
               "u|https://opentip.kaspersky.com/$t/" "u|https://check.spamhaus.org/results/?query=$t"
               "u|https://talosintelligence.com/reputation_center/lookup?search=$t")
        if [[ -s $KEYS/abuseipdb ]]; then
            rows+=("󰒃  AbuseIPDB API · look up here" "󰀦  AbuseIPDB API · report it"); acts+=("abuse-check" "abuse-report")
        fi
    elif is_url "$target"; then
        kind=url; [[ $target == *://* ]] || kind=domain
        rows+=("󰊭  Google Safe Browsing · report phishing" "󰖟  Microsoft · report unsafe site" "󰒃  Netcraft · report"
               "󰒃  VirusTotal" "󰒃  Kaspersky OpenTIP" "󰒃  McAfee · check" "󰒃  Symantec site review"
               "󰒃  Trend Micro site safety" "󰒃  Palo Alto URL filtering")
        acts+=("u|https://safebrowsing.google.com/safebrowsing/report_phish/?url=$t"
               "u|https://www.microsoft.com/en-us/wdsi/support/report-unsafe-site-guest?url=$t"
               "u|https://report.netcraft.com/report?url=$t" "u|https://www.virustotal.com/gui/search/$t"
               "u|https://opentip.kaspersky.com/$t/" "u|https://sitelookup.mcafee.com/en/feedback/url?action=checksingle&url=$t"
               "p|https://sitereview.symantec.com/" "p|https://global.sitesafety.trendmicro.com/"
               "p|https://urlfiltering.paloaltonetworks.com/")
    else
        notify "\"$target\" doesn't look like an IP address, domain or URL"
        return
    fi
    [[ -s $KEYS/kaspersky ]] && { rows+=("󰒃  OpenTIP API · look up here"); acts+=("opentip"); }
    [[ -s $KEYS/abuseipdb && -s $KEYS/kaspersky ]] || { rows+=("󰌆  Add API keys for lookups here ›"); acts+=("keys"); }

    while :; do
        i=$(printf '%s\n' "${rows[@]}" | pick "Report" "$target · web links open in your browser") || return
        case ${acts[i]} in
            u\|*) open_url "${acts[i]#u|}" ;;
            p\|*) open_paste "${acts[i]#p|}" "$target" ;;
            abuse-check)  abuse_check "$target" ;;
            abuse-report) abuse_report "$target" ;;
            opentip)      opentip "$kind" "$target" ;;
            keys) list_rows "API keys" "One key per file, readable only by you" <<EOF
mkdir -p ~/.config/auch/keys && chmod 700 ~/.config/auch/keys
AbuseIPDB (free): abuseipdb.com → Account → API → paste into ~/.config/auch/keys/abuseipdb
Kaspersky OpenTIP (free): opentip.kaspersky.com → My account → API → ~/.config/auch/keys/kaspersky
chmod 600 ~/.config/auch/keys/*
EOF
            ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    *)        toggle_rofi; menu ;;
esac
