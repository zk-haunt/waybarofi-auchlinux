#!/usr/bin/env bash

# Toggle: if rofi is already running for the user, kill it and exit

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

if pgrep -u "$USER" -x rofi >/dev/null; then
  pkill -u "$USER" -x rofi
  exit 0
fi

# Define Rofi theme
theme="$HOME/.config/rofi/websearch/style.rasi"

# If the custom theme doesn't exist yet, fallback to default or calc theme
if [[ ! -f "$theme" ]]; then
  theme="$HOME/.config/rofi/calc/style.rasi"
fi

# Step 1: Prompt the user for the search query
query=$(rofi -dmenu -p "🔍 Web" -theme "$theme" -theme-str 'entry { placeholder: "Type query (or use prefix: !g, !yt, !aw, !gh)..."; }')

[[ -z "$query" ]] && exit 0

# Check for prefix to bypass selector
prefix=$(echo "$query" | awk '{print $1}')
search_term=$(echo "$query" | cut -d' ' -f2-)

# If there is only one word and it starts with !, check if it is a prefix.
# If it is not a prefix or the word count is 1 and it does not start with !,
# treat the entire query as the search term.
word_count=$(echo "$query" | wc -w)
if [ "$word_count" -le 1 ]; then
  # Check if the single word is a prefix (e.g. they typed "!g" only)
  if [[ "$prefix" =~ ^![a-z]+$ ]]; then
    search_term=""
  else
    prefix=""
    search_term="$query"
  fi
fi

engine=""
case "$prefix" in
  "!g"|"!google")
    engine="google"
    ;;
  "!ddg"|"!d"|"!duckduckgo")
    engine="duckduckgo"
    ;;
  "!yt"|"!y"|"!youtube")
    engine="youtube"
    ;;
  "!gh"|"!github")
    engine="github"
    ;;
  "!aw"|"!a"|"!archwiki")
    engine="archwiki"
    ;;
  *)
    engine=""
    search_term="$query"
    ;;
esac

# Function to perform the search
do_search() {
  local eng="$1"
  local term="$2"
  
  # URL encode term using jq
  local encoded=$(echo -n "$term" | jq -s -R -r @uri)
  local url=""
  
  case "$eng" in
    "google")
      url="https://www.google.com/search?q=$encoded"
      ;;
    "duckduckgo")
      url="https://duckduckgo.com/?q=$encoded"
      ;;
    "youtube")
      url="https://www.youtube.com/results?search_query=$encoded"
      ;;
    "github")
      url="https://github.com/search?q=$encoded"
      ;;
    "archwiki")
      url="https://wiki.archlinux.org/index.php?search=$encoded"
      ;;
  esac
  
  if [[ -n "$url" ]]; then
    xdg-open "$url"
  fi
}

# If an engine was matched via prefix, search immediately and exit
if [[ -n "$engine" ]]; then
  # If they typed just the prefix, we can prompt them again or exit.
  # Let's prompt them for query with that specific engine context.
  if [[ -z "$search_term" ]]; then
    search_term=$(rofi -dmenu -p "🚀 $engine" -theme "$theme" -theme-str "entry { placeholder: \"Search on $engine...\"; }")
    [[ -z "$search_term" ]] && exit 0
  fi
  do_search "$engine" "$search_term"
  exit 0
fi

# Step 2: Prompt for engine selection
# Present options clearly
options=(
  "🔍 Google"
  "🦆 DuckDuckGo"
  "📺 YouTube"
  "🐙 GitHub"
  "󰣇 ArchWiki"
)

# Join array with newlines for rofi
choice=$(printf "%s\n" "${options[@]}" | rofi -dmenu -p "🚀 Search on" -theme "$theme" -theme-str "entry { placeholder: \"Searching for: $query\"; }")

[[ -z "$choice" ]] && exit 0

selected_engine=""
case "$choice" in
  *"Google"*)
    selected_engine="google"
    ;;
  *"DuckDuckGo"*)
    selected_engine="duckduckgo"
    ;;
  *"YouTube"*)
    selected_engine="youtube"
    ;;
  *"GitHub"*)
    selected_engine="github"
    ;;
  *"ArchWiki"*)
    selected_engine="archwiki"
    ;;
esac

if [[ -n "$selected_engine" ]]; then
  do_search "$selected_engine" "$query"
fi
