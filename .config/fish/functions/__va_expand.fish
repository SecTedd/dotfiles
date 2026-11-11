# Expansion for the `va` abbreviation (config.fish): the activate command of the
# nearest Python venv (.venv in $PWD or a parent dir), so it can be reviewed before Enter.
function __va_expand
    set -l dir $PWD
    while true
        if test -f "$dir/.venv/bin/activate.fish"
            echo source (string escape -- "$dir/.venv/bin/activate.fish")
            return
        end
        test "$dir" = /; and break
        set dir (path dirname $dir)
    end
    # Nothing found: a harmless comment instead of a command
    echo "# no .venv found in $PWD or above"
end
