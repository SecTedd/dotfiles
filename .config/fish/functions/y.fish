# `y`: open yazi; when you quit, the shell changes to the directory you were in.
# Shell wrapper from the Yazi docs (https://yazi-rs.github.io/docs/quick-start).
function y --description "yazi file manager, cd to its last directory on quit"
    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and test -n "$cwd"; and test "$cwd" != "$PWD"
        builtin cd -- "$cwd"
    end
    command rm -f -- "$tmp"
end
