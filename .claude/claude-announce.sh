#!/bin/bash
# Claude Code hook: rings the bell in Claude's tmux pane (red tab, prefix A jumps
# there), shows a Hammerspoon box unless you are looking at that pane, and plays a
# sound unless muted (~/.claude/announce-muted: menu bar icon or prefix M).
# Adapted from https://github.com/scorphus/tmux-claude-integration
# Copyright (c) 2026, Pablo Aguiar. BSD 3-Clause License, full text in
# LICENSES/tmux-claude-integration.txt of the dotfiles repo.
#
# usage: claude-announce.sh done|waiting|failed   (hook JSON on stdin)
mode=${1:-done}
input=$(cat)

field() { jq -r "$1" <<<"$input"; }

# The session's display name from Claude's session registry
session_name() {
    local sid file=""
    sid=$(field '.session_id // ""')
    [ -n "$sid" ] && file=$(grep -lF -- "\"$sid\"" ~/.claude/sessions/*.json 2>/dev/null | head -1)
    if [ -n "$file" ]; then jq -r '.name // "claude"' "$file"; else echo claude; fi
}

message() {
    local name=$1
    case $mode in
        waiting)
            case $(field '.notification_type // ""') in
                permission_prompt) echo "✋ $name needs your permission" ;;
                idle_prompt)       echo "… $name is still waiting for you" ;;
                *)                 echo "✋ $name is waiting for you" ;;
            esac ;;
        failed) echo "✗ $name failed" ;;
        *)      echo "✓ $name is done" ;;
    esac
}

sound() {
    case $mode in
        waiting) echo Basso ;;
        failed)  echo Funk ;;
        *)       echo Hero ;;
    esac
}

in_tmux() { [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; }

# Ghostty in front, and Claude's pane is the active pane of the active window of an attached session
watching_claude() {
    local front
    front=$(lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null)
    [[ $front == *'"com.mitchellh.ghostty"'* ]] &&
        [ "$(tmux display-message -p -t "$TMUX_PANE" '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}' 2>/dev/null)" = 1 ]
}

remember_pane() { tmux set-option -w -t "$TMUX_PANE" @claude_alert_pane "$TMUX_PANE" 2>/dev/null; }

ring_bell() {
    local tty
    tty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
    [ -n "$tty" ] && [ -w "$tty" ] && printf '\a' > "$tty"
}

show_box() { open -g "hammerspoon://claude-alert?text=$(jq -rn --arg t "$1" '$t|@uri')" 2>/dev/null; }

play_sound() { [ -e ~/.claude/announce-muted ] || afplay "/System/Library/Sounds/$1.aiff" & }

main() {
    local msg watching=0
    msg=$(message "$(session_name)")
    if in_tmux; then
        if watching_claude; then watching=1; else remember_pane; fi
        ring_bell
    fi
    [ "$watching" = 1 ] || show_box "$msg"
    play_sound "$(sound)"
}
main
