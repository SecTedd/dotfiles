#!/bin/bash
# tmux menu of every live Claude Code session; picking one jumps to its pane.
# Sessions started outside tmux are listed greyed out.
# Adapted from https://github.com/scorphus/tmux-claude-integration
# Copyright (c) 2026, Pablo Aguiar. BSD 3-Clause License, full text in
# LICENSES/tmux-claude-integration.txt of the dotfiles repo.
#
# usage (tmux.conf): bind BSpace run-shell -b "bash ~/.claude/claude-menu.sh '#{client_name}'"
#        (fish ask)  bash ~/.claude/claude-menu.sh --choose <pane id>
#                    only the sessions in that pane's tmux window: a single one is
#                    printed, several make the menu, where choosing one types
#                    `ask %<pane>` into that pane
#        (nvim)      bash ~/.claude/claude-menu.sh --pick <nvim server> <pane id>
#                    the same, choosing one hands the pane to nvim (lua/config/claude_prompt.lua)
SESSIONS=${CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}
mode=jump
client=${1:-}
title="#[align=centre] Claude sessions "

window_of() { tmux display-message -p -t "$1" '#{window_id}'; }

case ${1:-} in
    --choose) mode=choose; shell_pane=$2; here=$(window_of "$2") ;;
    --pick) mode=pick; nvim_server=$2; here=$(window_of "$3") ;;
esac
if [ "$mode" != jump ]; then
    client=""
    title="#[align=centre] Claude in this window "
fi
args=()
selectable=0
last_pane=""

status_dot() {
    case $1 in
        busy)  echo "#[fg=#a6e3a1,bold]●#[default]" ;;
        wait*) echo "#[fg=#f38ba8,bold]●#[default]" ;;
        *)     echo "#[fg=#6c7086]○#[default]" ;;
    esac
}

# "<session id> <window id> <pane index>" of a pane, looked up live so renamed
# sessions and moved windows still work; fails when the pane is gone
locate_pane() {
    [[ $1 =~ ^%[0-9]+$ ]] && tmux display-message -p -t "$1" '#{session_id} #{window_id} #{pane_index}' 2>/dev/null
}

# The pane goes over as a bare number (%3 -> 3): the menu's command is parsed
# twice by tmux, which would eat quotes around it
hand_to_nvim() { printf 'nvim --server %s --remote-expr %s >/dev/null' "$nvim_server" "'v:lua.ClaudePromptPicked(${1#%})'"; }

# What choosing the entry does: type `ask` for the pane, hand it to nvim, or jump to it
entry_command() {
    local pane=$1 session=$2 window=$3
    case $mode in
        choose) printf "send-keys -t '%s' 'ask %s' Enter" "$shell_pane" "$pane" ;;
        pick) printf 'run-shell -b "%s"' "$(hand_to_nvim "$pane")" ;;
        *) printf "switch-client -t '%s' ; select-window -t '%s' ; select-pane -t '%s'" "$session" "$window" "$pane" ;;
    esac
}

# add_entry <dot> <name> <registry location "session:@window.%pane">
add_entry() {
    local pane=${3##*.} location session window index label key=""
    if location=$(locate_pane "$pane"); then
        read -r session window index <<<"$location"
        [ "$mode" != jump ] && [ "$window" != "$here" ] && return
        selectable=$((selectable + 1))
        last_pane=$pane
        [ "$selectable" -le 9 ] && key=$selectable
        label="$1 $2"
        [ "$mode" != jump ] && label="$label  pane $index"
        args+=("$label" "$key" "$(entry_command "$pane" "$session" "$window")")
    elif [ "$mode" = jump ]; then
        args+=("-$1 $2 (not in tmux)" "" "") # a leading - disables the entry
    fi
}

for f in "$SESSIONS"/*.json; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r pid name status location \
        < <(jq -r '[.pid // 0, .name // "?", .status // "-", .tmux // ""] | @tsv' "$f")
    kill -0 "$pid" 2>/dev/null || continue
    add_entry "$(status_dot "$status")" "${name//#/}" "$location" # tmux formats would read a #
done

if [ "$selectable" -eq 1 ]; then
    case $mode in
        choose) echo "$last_pane"; exit 0 ;;
        pick) eval "$(hand_to_nvim "$last_pane")"; exit 0 ;;
    esac
fi
if [ "${#args[@]}" -eq 0 ]; then
    if [ "$mode" = jump ]; then
        tmux display-message ${client:+-c "$client"} "No live Claude sessions"
    else
        tmux display-message "No Claude in this window"
    fi
    exit 0
fi
tmux display-menu ${client:+-c "$client"} -T "$title" -- "${args[@]}"
