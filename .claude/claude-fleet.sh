#!/bin/bash
# tmux status-right segment: one dot per live Claude Code session (green = busy,
# red = waiting for you, grey = idle) with its name, the most recently active
# first. A click on a dot jumps to its pane: the dot is marked with the pane as a
# mouse range, tmux.conf binds the click. Sessions that don't fit beside the
# window tabs and the session/clock capsule are left out: tmux.conf passes the
# client width ('#{client_width}'), no width shows all.
# Adapted from https://github.com/scorphus/tmux-claude-integration
# Copyright (c) 2026, Pablo Aguiar. BSD 3-Clause License, full text in
# LICENSES/tmux-claude-integration.txt of the dotfiles repo.
sessions=${CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}
width=${1:-0}

# What the tabs and the capsule take, following the formats in tmux.conf: a tab
# is its number, a space and its name between two caps, tabs touch; the capsule
# is two caps, a gap between its modules, two icons each with a space, the clock
# and the session name
taken_width() {
    local session_name tab_sizes tab tabs=0
    read -r session_name tab_sizes \
        < <(tmux display-message -p '#{n:session_name} #{W:#{e|+:#{n:window_index},#{n:window_name}} }')
    for tab in $tab_sizes; do tabs=$((tabs + tab + 3)); done
    echo $((tabs + session_name + 12))
}

# "<last status change> <pid> <status> <name> <tmux location>" per registered
# session, newest first
registered_sessions() {
    local f
    for f in "$sessions"/*.json; do
        [ -e "$f" ] || continue
        jq -r 'select((.pid // 0) > 0) | [.statusUpdatedAt // 0, .pid, .status // "-", .name // "?", .tmux // ""] | @tsv' "$f"
    done | sort -rn
}

# The entry as a mouse range named after its pane (the number alone: tmux runs
# status text through strftime, which eats a %), for the click in tmux.conf; a
# session started outside tmux has no pane and stays plain
clickable() {
    local pane=$1 entry=$2
    if [[ $pane =~ ^%[0-9]+$ ]]; then
        printf '#[range=user|%s]%s#[norange]' "${pane#%}" "$entry"
    else
        printf '%s' "$entry"
    fi
}

dot_for() {
    case $1 in
        busy)  echo "#[fg=#a6e3a1,bold]●#[default]" ;;
        wait*) echo "#[fg=#f38ba8,bold]●#[default]" ;;
        *)     echo "#[fg=#6c7086]○#[default]" ;;
    esac
}

if [ "$width" -gt 0 ] 2>/dev/null; then
    room=$((width - $(taken_width)))
else
    room=1000
fi
out=""
while IFS=$'\t' read -r _ pid status name location; do
    kill -0 "$pid" 2>/dev/null || continue
    name=${name//#/}   # a # would be read as a tmux format
    name=${name:0:12}
    room=$((room - ${#name} - 4))
    [ "$room" -ge 0 ] || break
    out+="$(clickable "${location##*.}" "$(dot_for "$status") $name  ")"
done < <(registered_sessions)
printf '%s' "$out"
