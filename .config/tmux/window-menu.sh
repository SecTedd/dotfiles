#!/bin/bash
# tmux menu of this session's windows; picking one jumps to it, 1-9 pick by number.
# Adapted from https://github.com/scorphus/scorphiles (bin/tmux-window-menu)
# by Pablo Aguiar. Apache License 2.0, full text in
# LICENSES/scorphiles-Apache-2.0.txt of the dotfiles repo.
# Changes: the client to show the menu in is an argument, 1-9 pick a window, the
# active window is bold, a # in a name is escaped, no Claude mark (the status bar
# has the fleet), tab-separated fields.
#
# usage (tmux.conf): bind -n C-BTab run-shell -b "bash ~/.config/tmux/window-menu.sh '#{client_name}'"
client=${1:-}
args=()
while IFS=$'\t' read -r index active name; do
    label="$index ${name//#/##}" # a # would be read as a tmux format
    [ "$active" = 1 ] && label="#[bold]$label"
    key=""
    [ "$index" -le 9 ] && key=$index
    args+=("$label" "$key" "select-window -t :$index")
done < <(tmux list-windows -F $'#{window_index}\t#{window_active}\t#{window_name}')
tmux display-menu ${client:+-c "$client"} -T "#[align=centre] Windows " -- "${args[@]}"
