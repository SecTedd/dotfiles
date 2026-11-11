# Browse changed files with fzf; preview shows the diff.
# Pass any git diff args, e.g. `gdf HEAD~3`, `gdf --staged`.
#   ctrl-o : open selected file in $EDITOR
#   ctrl-s : git add selected file (and refresh the list)
function gdf --description "Browse changed files with fzf and a diff preview"
    set -l args (string escape -- $argv)
    git diff $argv --name-only \
        | fzf -m --ansi \
            --preview "git diff $args --color=always -- {}" \
            --bind "ctrl-o:execute($EDITOR {+})" \
            --bind "ctrl-s:execute-silent(git add {+})+reload(git diff $args --name-only)"
end
