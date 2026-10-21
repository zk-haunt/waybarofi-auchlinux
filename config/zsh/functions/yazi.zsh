# y — open Yazi; on quit, the shell lands in the directory you left it in.
# (Yazi's own recommended wrapper: it writes its last cwd to a temp file.)
# `Q` quits without changing directory.
function y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")" || return
    yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [[ -n "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}
