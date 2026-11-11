#!/bin/bash
# Claude Code status line: folder, model, context used, rate limits, and a red lock
# while Claude's tmux pane is read-only (prefix R). Catppuccin Mocha colors.
input=$(cat)

BLUE='137;180;250' YELLOW='249;226;175' GREEN='166;227;161' MAUVE='203;166;247' RED='243;139;168'
LOCK=$'\xf3\xb0\x8c\xbe' # nf-md-lock, U+F033E

colored() { printf '\033[38;2;%sm%s\033[0m' "$1" "$2"; }
percent() { printf '%.0f%%' "$1"; }

pane_is_readonly() {
    [ -n "${TMUX_PANE:-}" ] && [ "$(tmux show-options -pqv -t "$TMUX_PANE" @claude_readonly 2>/dev/null)" = 1 ]
}

{ read -r folder; read -r model; read -r used; read -r five_hour; read -r seven_day; } < <(jq -r '
    (.workspace.current_dir // .cwd // "?" | sub(".*/"; "")),
    (.model.display_name // "?"),
    (.context_window.used_percentage // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // "")' <<<"$input")

# One segment per line
segments() {
    colored "$BLUE" "$folder"; echo
    colored "$YELLOW" "$model"; echo
    [ -n "$used" ] && { printf 'ctx:'; colored "$GREEN" "$(percent "$used")"; echo; }
    [ -n "$five_hour" ] && { printf '5h:'; colored "$MAUVE" "$(percent "$five_hour")"; echo; }
    [ -n "$seven_day" ] && { printf '7d:'; colored "$MAUVE" "$(percent "$seven_day")"; echo; }
    pane_is_readonly && { colored "$RED" "$LOCK read-only"; echo; }
    return 0
}

join_with_two_spaces() {
    local sep="" part
    while IFS= read -r part; do
        printf '%s%s' "$sep" "$part"
        sep='  '
    done
}

segments | join_with_two_spaces
