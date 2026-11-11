# Copy commands to the clipboard:
#   Ctrl-X  current command line (fish's own fish_clipboard_copy)
#   Alt-X   last executed command
# Idea adapted from https://github.com/scorphus/scorphiles
# (fish/functions/fish_user_key_bindings.fish) by Pablo Aguiar.
# Apache License 2.0, full text in LICENSES/scorphiles-Apache-2.0.txt of the
# dotfiles repo. Changes: Ctrl-Up/Down (taken by macOS Mission Control) moved to
# Ctrl-X/Alt-X, fish 4 key syntax, no trailing newline.
function fish_user_key_bindings
    bind ctrl-x fish_clipboard_copy
    bind alt-x 'printf "%s" $history[1] | pbcopy'
end
