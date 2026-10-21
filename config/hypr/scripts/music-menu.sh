#!/usr/bin/env bash
# Music — a row in the hub dropdown (sec-picker.sh), after ppk's
# matrix-music-player: search YouTube, play the audio in mpv, control it here.
#
#   music-menu.sh            the menu
#   music-menu.sh --status   one JSON line for the hub row (now playing)
#
# mpv plays with --no-video and a control socket in $XDG_RUNTIME_DIR; the menu
# talks to that socket. Only this player is ever stopped — ppk's version ran
# `pkill -9 -f mpv`, which kills every mpv on the machine. Needs yt-dlp (mpv's
# YouTube support uses it); the row offers to install it when it's missing.
#
# Everything it keeps is in ~/Music as plain extended M3U — an
# "#EXTINF:-1,title" line before each YouTube link — so mpv or any player
# opens it, and a backup restored in place reads straight back:
#   ~/Music/playlists/NAME.m3u     playlists: made from search results, the
#                                  song playing, the queue (a similar-songs
#                                  mix, say) or a YouTube playlist link
#   ~/Music/recently-played.m3u    the last 30 played, newest first

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="Music"; MENU_ICON="󰎈"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

SOCK="${XDG_RUNTIME_DIR:-/tmp}/auch-music.sock"
MUSIC_DIR="${AUCH_MUSIC_DIR:-$HOME/Music}"
HIST="$MUSIC_DIR/recently-played.m3u"
SEP=$'\x1f'
PL_DIR="$MUSIC_DIR/playlists"
NOW="$AUCH_CACHE/music-playlist"     # name of the playlist playing, if one is

have_ytdlp() { command -v yt-dlp >/dev/null; }
our_pid()    { pgrep -a -x mpv | grep -F -- "--input-ipc-server=$SOCK" | cut -d' ' -f1 | head -n1; }
playing()    { [[ -n $(our_pid) && -S $SOCK ]]; }

# ipc JSON-ARRAY — send one command to our mpv, print its JSON reply.
ipc() {
    python3 - "$SOCK" "$1" <<'PY' 2>/dev/null
import json, socket, sys
s = socket.socket(socket.AF_UNIX)
s.settimeout(1.5)
s.connect(sys.argv[1])
s.sendall((json.dumps({"command": json.loads(sys.argv[2]), "request_id": 7}) + "\n").encode())
buf = b""
while True:
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
    *lines, buf = buf.split(b"\n")
    for line in lines:
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if m.get("request_id") == 7:          # events can arrive first; skip them
            print(json.dumps(m))
            sys.exit(0)
PY
}
prop() { ipc "[\"get_property\", \"$1\"]" | jq -r 'if .data == null then empty else .data end'; }
# props NAME… — several properties over one connection, one line each (empty
# when unset; true/false like prop). The status line wants six: one python
# start instead of six keeps the hub dropdown quick.
props() {
    python3 - "$SOCK" "$@" <<'PY' 2>/dev/null
import json, socket, sys
names = sys.argv[2:]
s = socket.socket(socket.AF_UNIX)
s.settimeout(1.5)
s.connect(sys.argv[1])
s.sendall("".join(json.dumps({"command": ["get_property", n], "request_id": i + 1}) + "\n"
                  for i, n in enumerate(names)).encode())
got, buf = {}, b""
while len(got) < len(names):
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
    *lines, buf = buf.split(b"\n")
    for line in lines:
        try:
            m = json.loads(line)
        except ValueError:
            continue
        rid = m.get("request_id")
        if isinstance(rid, int) and 1 <= rid <= len(names):
            d = m.get("data")
            got[rid] = "" if d is None else "true" if d is True else "false" if d is False else str(d)
for i in range(1, len(names) + 1):
    print(got.get(i, "").replace("\n", " "))
PY
}
clock() { local s=${1%.*}; [[ $s =~ ^[0-9]+$ ]] && printf '%d:%02d' $((s / 60)) $((s % 60)); }
vid_of() { sed -nE 's/.*[?&]v=([A-Za-z0-9_-]{11}).*/\1/p; s/.*youtu\.be\/([A-Za-z0-9_-]{11}).*/\1/p' <<<"$1" | head -n1; }

remember() {   # TITLE ID — to the top of recently-played.m3u, the last 30 kept
    local url="https://www.youtube.com/watch?v=$2"
    { printf '%s%s%s\n' "${1//$'\n'/ }" "$SEP" "$url"; pl_tracks "$HIST" | grep -v -F -- "$SEP$url"; } |
        head -n 30 | pl_write "$HIST"
}

stop() { local p; rm -f "$NOW"; p=$(our_pid); [[ -n $p ]] && { ipc '["quit"]' >/dev/null || kill "$p"; }; }

play() {   # URL TITLE [ID]
    stop
    sleep 0.3
    setsid -f mpv --no-video --no-terminal --idle=no --volume=70 --input-ipc-server="$SOCK" \
        --ytdl-format='bestaudio/best' --force-media-title="$2" -- "$1" >/dev/null 2>&1
    [[ -n ${3:-} ]] && remember "$2" "$3"
    notify "Playing: $2"
}

status() {
    local v=() t p pos dur k n pl npl where=""
    if ! have_ytdlp; then
        emit "󰎈" missing "<b>Music</b>
Needs yt-dlp — open this row to install it." "needs yt-dlp — tap to install"
        return
    fi
    if playing; then
        mapfile -t v < <(props media-title pause time-pos duration playlist-pos-1 playlist-count)
        t=${v[0]:-}; p=${v[1]:-}; pos=${v[2]:-}; dur=${v[3]:-}; k=${v[4]:-}; n=${v[5]:-1}
        pl=$(head -n1 "$NOW" 2>/dev/null)
        [[ $n =~ ^[0-9]+$ ]] && (( n > 1 )) && where=" · ${pl:+$pl }$k/$n"
        emit "󰎈" active "<b>Music · $( [[ $p == true ]] && echo paused || echo playing)</b>
$(printf '%s' "${t:-?}" | esc)
$(clock "$pos") / $(clock "$dur")$(printf '%s' "$where" | esc)" "$( [[ $p == true ]] && echo "⏸" || echo "▶") ${t:-playing}$where"
    else
        npl=$(pl_names | grep -c .)
        emit "󰎈" none "<b>Music</b>
Search YouTube and play the audio.$( ((npl)) && echo " Playlists: $npl")" \
            "search YouTube and play$( ((npl)) && echo " · $npl playlist$( ((npl == 1)) || echo s)")"
    fi
}

search() {   # [FILE] — no FILE: play the pick; a playlist FILE: add picks to it
    local into=${1:-} q rows=() ids=() titles=() added=() i j title chan dur id what
    what="YouTube search — plays the audio only"
    [[ -n $into ]] && what="YouTube search — the songs you pick go into \"$(basename "$into" .m3u)\""
    q=$(ask "Search" "$what" "") || return
    [[ -n ${q//[[:space:]]/} ]] || return
    notify "Searching YouTube for \"$q\"…"
    while IFS="$SEP" read -r title chan dur id; do
        [[ -n $id ]] || continue
        titles+=("$title"); ids+=("$id")
        rows+=("󰎈  $title · ${chan:-?} · ${dur:-live}")
    done < <(yt-dlp --flat-playlist --no-warnings --print "%(title)s${SEP}%(channel)s${SEP}%(duration_string)s${SEP}%(id)s" "ytsearch10:$q" 2>/dev/null)
    (( ${#rows[@]} )) || { notify "Nothing found (or YouTube didn't answer)"; return; }
    if [[ -z $into ]]; then
        i=$(printf '%s\n' "${rows[@]}" | pick "Results" "$q") || return
        play "https://www.youtube.com/watch?v=${ids[i]}" "${titles[i]}" "${ids[i]}"
        return
    fi
    # Adding: the results stay up so several can go in, ticked once added.
    while :; do
        i=$(for j in "${!rows[@]}"; do
                if [[ -n ${added[j]:-} ]]; then printf '󰄬  %s\n' "${rows[j]#*  }"; else printf '%s\n' "${rows[j]}"; fi
            done | pick "Add to $(basename "$into" .m3u)" "$q · pick songs to add · Esc when done") || return
        if pl_add "$into" "${titles[i]}" "https://www.youtube.com/watch?v=${ids[i]}"; then notify "Added: ${titles[i]}"
        else notify "Already in it: ${titles[i]}"; fi
        added[i]=1
    done
}

recent() {
    local rows=() titles=() urls=() i title url
    while IFS="$SEP" read -r title url; do
        titles+=("${title:-$url}"); urls+=("$url"); rows+=("󰋚  ${title:-$url}")
    done < <(pl_tracks "$HIST")
    (( ${#rows[@]} )) || { notify "Nothing played yet"; return; }
    i=$(printf '%s\n' "${rows[@]}" | pick "Recently played" "Pick one to play it again") || return
    play "${urls[i]}" "${titles[i]}" "$(vid_of "${urls[i]}")"
}

mix() {   # ID TITLE — YouTube's radio mix starting from that track
    play "https://www.youtube.com/watch?v=$1&list=RD$1" "Mix: $2"
}

# ── playlists ───────────────────────────────────────────────────────────────
pl_file()  { printf '%s/%s.m3u' "$PL_DIR" "$1"; }
pl_names() { find "$PL_DIR" -maxdepth 1 -name '*.m3u' -printf '%T@\t%f\n' 2>/dev/null | sort -rn | cut -f2- | sed 's/\.m3u$//'; }
# pl_tracks FILE -> "title<US>link" per song, in order.
pl_tracks() {
    awk -v sep="$SEP" '/^#EXTINF:/ { sub(/^#EXTINF:[^,]*,/, ""); t = $0; next }
                       /^#/ || /^[[:space:]]*$/ { next }
                       { print t sep $0; t = "" }' "$1" 2>/dev/null
}
pl_count() { pl_tracks "$1" | grep -c .; }
songs()    { printf '%d song%s' "$1" "$( (($1 == 1)) || echo s)"; }   # 1 song, 2 songs
# pl_write FILE — "title<US>link" lines on stdin become the whole playlist.
pl_write() {
    local t u tmp
    mkdir -p "${1%/*}"; tmp=$(mktemp "${1%/*}/.new.XXXXXX") || return 1   # beside it: mv stays atomic
    { echo "#EXTM3U"
      while IFS="$SEP" read -r t u; do [[ -n $u ]] && printf '#EXTINF:-1,%s\n%s\n' "${t:-$u}" "$u"; done
    } >"$tmp" && chmod 644 "$tmp" && mv "$tmp" "$1"   # mktemp makes it private; playlists aren't
}
# pl_add FILE TITLE LINK — fails when the link is in there already.
pl_add() {
    pl_tracks "$1" | cut -d"$SEP" -f2- | grep -qxF -- "$3" && return 1
    { pl_tracks "$1"; printf '%s%s%s\n' "${2//$'\n'/ }" "$SEP" "$3"; } | pl_write "$1"
}
# A name the file system takes: no slashes, no leading dots or spaces.
clean_name() {
    local n=${1//\//-}
    n=${n#"${n%%[![:space:].]*}"}; n=${n%"${n##*[![:space:]]}"}
    printf '%s' "$n"
}

new_playlist() {   # prints the new playlist's name
    local n
    n=$(ask "Name" "A name for the new playlist" "") || return 1
    n=$(clean_name "$n"); [[ -n $n ]] || return 1
    if [[ -e $(pl_file "$n") ]]; then notify "\"$n\" exists already — opening it"
    else printf '' | pl_write "$(pl_file "$n")"; fi
    printf '%s' "$n"
}

choose_playlist() {   # prints the file of the playlist picked (or just made)
    local names=() i n
    mapfile -t names < <(pl_names)
    i=$( { echo "󰐕  New playlist…"; if (( ${#names[@]} )); then printf '󰲸  %s\n' "${names[@]}"; fi; } |
         pick "Add to" "Pick a playlist") || return 1
    if (( i == 0 )); then n=$(new_playlist) || return 1; else n=${names[i-1]}; fi
    pl_file "$n"
}

# The song playing as "title<US>link"; YouTube links in their watch?v= form.
current_song() {
    local v=() id link
    mapfile -t v < <(props media-title path)
    link=${v[1]:-}; [[ -n $link ]] || return 1
    id=$(vid_of "$link"); [[ -n $id ]] && link="https://www.youtube.com/watch?v=$id"
    printf '%s%s%s\n' "${v[0]:-$link}" "$SEP" "$link"
}
add_current() {   # FILE
    local song t u
    song=$(current_song) || { notify "Nothing playing"; return; }
    IFS="$SEP" read -r t u <<<"$song"
    if pl_add "$1" "$t" "$u"; then notify "Added to $(basename "$1" .m3u): $t"
    else notify "Already in $(basename "$1" .m3u)"; fi
}

save_queue() {   # everything queued in the player — a similar-songs mix, say
    local n f
    n=$(ask "Name" "Save the $(prop playlist-count) songs queued now as a playlist" "$(head -n1 "$NOW" 2>/dev/null)") || return
    n=$(clean_name "$n"); [[ -n $n ]] || return
    f=$(pl_file "$n")
    [[ -e $f ]] && { confirm "\"$n\" exists — replace it?" || return; }
    # youtu.be/ID (how mpv expands a mix) in the watch?v= form the rest uses
    prop playlist | jq -r --arg sep "$SEP" '.[] | "\(.title // "" | gsub("[\n\u001f]"; " "))\($sep)\(.filename
        | sub("^https?://youtu\\.be/(?<id>[A-Za-z0-9_-]{11}).*"; "https://www.youtube.com/watch?v=\(.id)"))"' | pl_write "$f"
    notify "Saved \"$n\" · $(songs "$(pl_count "$f")")"
}

pl_import() {   # a YouTube playlist (or mix) link -> a playlist here
    local url clip lines=() first name f
    clip=$(wl-paste -n 2>/dev/null | head -c 300); [[ $clip == *youtu*list=* ]] || clip=""
    url=$(ask "Link" "A YouTube playlist link (it has list=…) — its songs become a playlist here" "$clip") || return
    [[ $url == *list=* ]] || { notify "That's not a playlist link — it needs list=…"; return; }
    notify "Reading the playlist…"
    mapfile -t lines < <(yt-dlp --flat-playlist --yes-playlist --no-warnings \
        --print "%(playlist_title)s${SEP}%(title)s${SEP}%(id)s" -- "$url" 2>/dev/null |
        awk -F"$SEP" '$3 != "" && $3 != "NA"')   # private or deleted videos have no id
    (( ${#lines[@]} )) || { notify "Couldn't read it — private, or YouTube didn't answer"; return; }
    first=${lines[0]%%"$SEP"*}; [[ $first == NA ]] && first=""
    name=$(ask "Name" "$(songs ${#lines[@]}) — a name for the playlist" "$first") || return
    name=$(clean_name "$name"); [[ -n $name ]] || return
    f=$(pl_file "$name")
    [[ -e $f ]] && { confirm "\"$name\" exists — replace it?" || return; }
    printf '%s\n' "${lines[@]}" | awk -F"$SEP" -v sep="$SEP" '{ print $2 sep "https://www.youtube.com/watch?v=" $3 }' | pl_write "$f"
    notify "Saved \"$name\" · $(songs "$(pl_count "$f")")"
    playlist_menu "$name"
}

play_list() {   # NAME [shuffle | START-INDEX]
    local f extra=()
    f=$(pl_file "$1")
    (( $(pl_count "$f") )) || { notify "\"$1\" is empty — add songs first"; return 1; }
    [[ ${2:-} == shuffle ]] && extra=(--shuffle)
    [[ ${2:-} =~ ^[0-9]+$ ]] && extra=(--playlist-start="$2")
    stop
    sleep 0.3
    # --playlist rather than the file as an argument: mpv reads it before
    # playing, so --shuffle and --playlist-start see every song. Only our own
    # files go in — mpv warns against --playlist with files from the internet.
    setsid -f mpv --no-video --no-terminal --idle=no --volume=70 --input-ipc-server="$SOCK" \
        --ytdl-format='bestaudio/best' "${extra[@]}" --playlist="$f" >/dev/null 2>&1
    printf '%s\n' "$1" >"$NOW"
    notify "Playing \"$1\"$( [[ ${2:-} == shuffle ]] && echo ", shuffled")"
}

songs_menu() {   # NAME — pick a song to play from it or take it out
    local name=$1 f i j t u titles=()
    f=$(pl_file "$name")
    while :; do
        titles=()
        while IFS="$SEP" read -r t u; do titles+=("${t:-$u}"); done < <(pl_tracks "$f")
        (( ${#titles[@]} )) || return
        i=$(for j in "${!titles[@]}"; do printf '󰎈  %d. %s\n' $((j + 1)) "${titles[j]}"; done |
            pick "$name" "$(songs ${#titles[@]}) · pick one to play from there or take it out") || return
        j=$(printf '%s\n' "󰐊  Play from here" "󰆴  Take it out of the playlist" "󰁍  Back" |
            pick "Song $((i + 1))" "$(printf '%s' "${titles[i]}" | esc)") || continue
        case $j in
            0) play_list "$name" "$i"; exit 0 ;;
            1) pl_tracks "$f" | awk -v n=$((i + 1)) 'NR != n' | pl_write "$f"; notify "Taken out: ${titles[i]}" ;;
        esac
    done
}

playlist_menu() {   # NAME
    local name=$1 f n i new rows=() acts=()
    while :; do
        f=$(pl_file "$name"); [[ -f $f ]] || return
        n=$(pl_count "$f"); rows=(); acts=()
        if (( n )); then rows+=("󰐊  Play" "󰒝  Shuffle"); acts+=(play shuffle); fi
        rows+=("󰍉  Add songs — search YouTube…"); acts+=(search)
        if playing; then rows+=("󰐒  Add the song playing now"); acts+=(addnow); fi
        if (( n )); then rows+=("󰲸  Songs · $n ›"); acts+=(songs); fi
        rows+=("󰑕  Rename…" "󰆴  Delete the playlist"); acts+=(rename delete)
        i=$(printf '%s\n' "${rows[@]}" | pick "$name" "$(songs "$n") · ${f/#$HOME/\~}") || return
        case ${acts[i]:-} in
            play)    play_list "$name" && exit 0 ;;
            shuffle) play_list "$name" shuffle && exit 0 ;;
            search)  search "$f" ;;
            addnow)  add_current "$f" ;;
            songs)   songs_menu "$name" ;;
            rename)  new=$(ask "Rename" "A new name for \"$name\"" "$name") || continue
                     new=$(clean_name "$new"); [[ -n $new && $new != "$name" ]] || continue
                     [[ -e $(pl_file "$new") ]] && { notify "\"$new\" exists already"; continue; }
                     mv "$f" "$(pl_file "$new")" || continue
                     [[ $(head -n1 "$NOW" 2>/dev/null) == "$name" ]] && printf '%s\n' "$new" >"$NOW"
                     name=$new ;;
            delete)  confirm "Delete the playlist \"$name\"? It goes to the trash." && gio trash "$f" &&
                         { notify "Deleted \"$name\""; return; } ;;
        esac
    done
}

playlists_menu() {
    local names=() rows=() i n
    while :; do
        mapfile -t names < <(pl_names)
        rows=("󰐕  New playlist…" "󰗃  Import a YouTube playlist link…")
        for n in "${names[@]}"; do rows+=("󰲸  $n · $(songs "$(pl_count "$(pl_file "$n")")")"); done
        i=$(printf '%s\n' "${rows[@]}" |
            pick "Playlists" "${#names[@]} in ${PL_DIR/#$HOME/\~} · plain .m3u files, any player opens them") || return
        case $i in
            0) n=$(new_playlist) && playlist_menu "$n" ;;
            1) pl_import ;;
            *) playlist_menu "${names[i-2]}" ;;
        esac
    done
}

menu() {
    local i v=() t p vol pos dur path id k n pl f last_t last_id rows=() acts=()
    if ! have_ytdlp; then
        i=$(printf '%s\n' "󰇚  Install yt-dlp · in a terminal" | pick "Music" "Playing from YouTube needs yt-dlp (mpv is already installed)") || return
        in_terminal "Install yt-dlp" "sudo pacman -S --needed yt-dlp"; return
    fi
    while :; do
        if playing; then
            mapfile -t v < <(props media-title pause volume time-pos duration path playlist-pos-1 playlist-count)
            t=${v[0]:-}; p=${v[1]:-}; vol=${v[2]:-}; pos=${v[3]:-}; dur=${v[4]:-}; path=${v[5]:-}; k=${v[6]:-}; n=${v[7]:-1}
            [[ $n =~ ^[0-9]+$ ]] || n=1
            id=$(vid_of "$path"); pl=$(head -n1 "$NOW" 2>/dev/null)
            rows=("$( [[ $p == true ]] && echo "󰐊  Resume" || echo "󰏤  Pause")" "󰒭  Next" "󰒮  Previous" "󰝝  Louder" "󰝞  Quieter"
                  "󰕾  Similar songs · a YouTube mix from this one" "󰐒  Add this song to a playlist ›")
            acts=(pause next prev up down mix addto)
            if (( n > 1 )); then rows+=("󰲸  Save the queue as a playlist · $n songs…"); acts+=(savequeue); fi
            rows+=("󰲸  Playlists ›" "󰍉  Search…" "󰋚  Recently played ›" "󰓛  Stop"); acts+=(playlists search recent stop)
            i=$(printf '%s\n' "${rows[@]}" |
                pick "Music" "$(printf '%s' "${t:-?}" | esc) · $(clock "$pos") / $(clock "$dur")$( ((n > 1)) && printf ' · %s' "${pl:+$pl }$k/$n" | esc) · volume ${vol%.*}%") || return
            case ${acts[i]:-} in
                pause)     ipc '["cycle", "pause"]' >/dev/null ;;
                next)      ipc '["playlist-next", "weak"]' >/dev/null ;;
                prev)      ipc '["playlist-prev", "weak"]' >/dev/null ;;
                up)        ipc '["add", "volume", 10]' >/dev/null ;;
                down)      ipc '["add", "volume", -10]' >/dev/null ;;
                mix)       if [[ -n $id ]]; then mix "$id" "$t"; return; else notify "This track has no YouTube id to build a mix from"; fi ;;
                addto)     f=$(choose_playlist) && add_current "$f" ;;
                savequeue) save_queue ;;
                playlists) playlists_menu ;;
                search)    search; return ;;
                recent)    recent; return ;;
                stop)      stop; notify "Stopped"; return ;;
            esac
        else
            last_t=""; last_id=""
            IFS="$SEP" read -r last_t last_id < <(pl_tracks "$HIST" | head -n1); last_id=$(vid_of "$last_id")
            rows=("󰍉  Search YouTube…" "󰲸  Playlists ›" "󰋚  Recently played ›"); acts=(search playlists recent)
            if [[ -n $last_id ]]; then rows+=("󰕾  Similar songs · a mix from \"$last_t\""); acts+=(mix); fi
            i=$(printf '%s\n' "${rows[@]}" | pick "Music" "Nothing playing") || return
            case ${acts[i]:-} in
                search)    search; return ;;
                playlists) playlists_menu ;;
                recent)    recent; return ;;
                mix)       mix "$last_id" "$last_t"; return ;;
            esac
        fi
    done
}

case ${1:-} in
    --status) status ;;
    *)        toggle_rofi; menu ;;
esac
