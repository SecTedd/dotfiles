# catppuccin-lean: two-line prompt in the style of Powerlevel10k "lean",
# Catppuccin Mocha colors, Nerd Font icons.
#   line 1:  ~/path  branch ↑ahead ↓behind +staged !changed ?untracked ~conflicts
#            ···········  ✘exit-code  duration (> 3 s)  background jobs
#            node (JS projects)  python (Python projects)  time
#   line 2: ❯ (red after an error)
# The right side sits on line 1, where fish's own fish_right_prompt cannot go (it
# draws on the ❯ line, without a filler), so line 1 is laid out by hand.
# A long path is shortened by fish's prompt_pwd (one letter per directory). Transient prompt: once
# a command runs, its prompt collapses to `❯ command` in the scrollback.
# Everything is computed without spawning slow tools: one `git status` call per
# prompt, Node/Python versions are read from nvm/pyenv paths and files.

# Redraw the prompt with --final-rendering before a command runs (fish >= 4.1)
set -g fish_transient_prompt 1
# The python segment shows the active venv; don't let activate.fish add "(.venv)" too
set -g VIRTUAL_ENV_DISABLE_PROMPT 1

# Catppuccin Mocha
set -g __lean_blue 89b4fa
set -g __lean_green a6e3a1
set -g __lean_yellow f9e2af
set -g __lean_red f38ba8
set -g __lean_peach fab387
set -g __lean_mauve cba6f7
set -g __lean_sky 89dceb
set -g __lean_text cdd6f4
set -g __lean_dim 7f849c
set -g __lean_dots 585b70

# Nerd Font icons
set -g __lean_icon_apple \uF179
set -g __lean_icon_folder \uF07C
set -g __lean_icon_branch \uF126
set -g __lean_icon_duration \uF252
set -g __lean_icon_jobs \uF013
set -g __lean_icon_node \uE718
set -g __lean_icon_python \uE73C
set -g __lean_icon_clock \uF017

# Colored text: __lean_color <hex> <text...>
function __lean_color
    printf '%s%s%s' (set_color $argv[1]) "$argv[2..-1]" (set_color normal)
end

# Nearest directory (from $PWD upwards) that contains one of the given files
function __lean_find_up
    set -l dir $PWD
    while true
        for name in $argv
            test -e "$dir/$name"; and echo $dir; and return 0
        end
        test "$dir" = /; and return 1
        set dir (path dirname $dir)
    end
end

# "feature/very-long-branch-name" -> "feature/ver…anch-name"
function __lean_shorten -a text max
    if test (string length -- $text) -le $max
        echo $text
    else
        set -l half (math "floor(($max - 1) / 2)")
        echo (string sub -l $half -- $text)…(string sub -s -$half -- $text)
    end
end

function __lean_git
    set -l lines (command git status --porcelain=v2 --branch 2>/dev/null); or return

    set -l branch
    set -l oid
    set -l ahead 0
    set -l behind 0
    set -l staged 0
    set -l changed 0
    set -l untracked 0
    set -l conflicts 0
    for line in $lines
        switch $line
            case '# branch.head *'
                set branch (string sub -s 15 -- $line)
            case '# branch.oid *'
                set oid (string sub -s 14 -l 7 -- $line)
            case '# branch.ab *'
                set -l ab (string split ' ' -- $line)
                set ahead (string sub -s 2 -- $ab[3])
                set behind (string sub -s 2 -- $ab[4])
            case '1 *' '2 *'
                set -l xy (string sub -s 3 -l 2 -- $line)
                test (string sub -l 1 -- $xy) != .; and set staged (math $staged + 1)
                test (string sub -s 2 -l 1 -- $xy) != .; and set changed (math $changed + 1)
            case 'u *'
                set conflicts (math $conflicts + 1)
            case '? *'
                set untracked (math $untracked + 1)
        end
    end
    test "$branch" = "(detached)"; and set branch "@$oid"

    set -l dirty (math $staged + $changed + $untracked + $conflicts)
    set -l branch_color $__lean_green
    test $dirty -gt 0; and set branch_color $__lean_yellow

    set -l out (__lean_color $branch_color $__lean_icon_branch (__lean_shorten $branch 32))
    test $ahead -gt 0; and set -a out (__lean_color $__lean_green ↑$ahead)
    test $behind -gt 0; and set -a out (__lean_color $__lean_green ↓$behind)
    test $staged -gt 0; and set -a out (__lean_color $__lean_green +$staged)
    test $changed -gt 0; and set -a out (__lean_color $__lean_yellow !$changed)
    test $untracked -gt 0; and set -a out (__lean_color $__lean_sky ?$untracked)
    test $conflicts -gt 0; and set -a out (__lean_color $__lean_red ~$conflicts)
    echo -n (string join ' ' -- $out)
end

# 12s, 1m5s, 1h2m
function __lean_duration -a ms
    set -l s (math "floor($ms / 1000)")
    if test $s -lt 60
        echo {$s}s
    else if test $s -lt 3600
        echo (math "floor($s / 60)")m(math "$s % 60")s
    else
        echo (math "floor($s / 3600)")h(math "floor($s % 3600 / 60)")m
    end
end

function __lean_node
    __lean_find_up package.json >/dev/null; or return
    set -l node (command -s node); or return
    # nvm path .../versions/node/v24.21.0/bin/node -> v24.21.0 (no `node --version` call)
    # (not `version`: that is fish's own read-only variable)
    set -l node_version (string match -r '/node/(v[0-9.]+)/bin/node$' -- $node)[2]
    test -n "$node_version"; or set node_version (node --version 2>/dev/null)
    __lean_color $__lean_green $__lean_icon_node $node_version
end

function __lean_python
    set -l name
    if set -q VIRTUAL_ENV
        set name (path basename $VIRTUAL_ENV)
    else
        __lean_find_up pyproject.toml requirements.txt setup.py Pipfile .python-version >/dev/null; or return
        # pyenv's version: $PYENV_VERSION, nearest .python-version, or the global default
        if set -q PYENV_VERSION
            set name $PYENV_VERSION
        else if set -l dir (__lean_find_up .python-version)
            read name <$dir/.python-version
        else if test -r $PYENV_ROOT/version
            read name <$PYENV_ROOT/version
        end
    end
    test -n "$name"; or return
    __lean_color $__lean_yellow $__lean_icon_python $name
end

function fish_prompt
    set -l last_status $status
    set -l duration $CMD_DURATION

    set -l char_color $__lean_green
    test $last_status -ne 0; and set char_color $__lean_red

    # Transient prompt: what stays in the scrollback is just `❯ command`
    if contains -- --final-rendering $argv
        echo -n ' '(__lean_color $char_color ❯)' '
        return
    end

    # Left side
    set -l path (prompt_pwd --dir-length=0)
    set -l left (__lean_color $__lean_text $__lean_icon_apple) (__lean_color $__lean_blue $__lean_icon_folder $path)
    set -l git (__lean_git)
    test -n "$git"; and set -a left $git

    # Right side
    set -l right
    test $last_status -ne 0; and set -a right (__lean_color $__lean_red ✘$last_status)
    test "$duration" -gt 3000 2>/dev/null; and set -a right (__lean_color $__lean_peach $__lean_icon_duration (__lean_duration $duration))
    set -l job_count (count (jobs -p))
    test $job_count -gt 0; and set -a right (__lean_color $__lean_mauve $__lean_icon_jobs $job_count)
    set -l node (__lean_node)
    test -n "$node"; and set -a right $node
    set -l python (__lean_python)
    test -n "$python"; and set -a right $python
    set -a right (__lean_color $__lean_dim $__lean_icon_clock (date +%H:%M:%S))

    # One space padding on the left, like the free last column on the right
    set -l left_text ' '(string join ' ' -- $left)
    set -l right_text (string join ' ' -- $right)
    set -l width (math $COLUMNS - 1)

    # Long path (> 80 chars) or line too long: shorten the path; still too long: drop the right side
    if test (string length -- $path) -gt 80; or test (math (string length --visible -- $left_text) + (string length --visible -- $right_text) + 2) -gt $width
        set left[2] (__lean_color $__lean_blue $__lean_icon_folder (prompt_pwd --dir-length=1))
        set left_text ' '(string join ' ' -- $left)
    end
    set -l gap (math $width - (string length --visible -- $left_text) - (string length --visible -- $right_text) - 2)
    if test $gap -lt 1
        set right_text ''
        set gap 0
    end

    echo -n $left_text
    if test -n "$right_text"
        echo -n ' '(set_color $__lean_dots)(string repeat -n $gap ·)(set_color normal)' '$right_text
    end
    echo

    # Line 2
    echo -n ' '(__lean_color $char_color ❯)' '
end
