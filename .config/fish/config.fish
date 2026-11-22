# fish config
#   environment  ~/.config/shell/env.sh (shared with zsh, loaded via foreign-env)
#   Oh My Fish   conf.d/omf.fish (runs before this file), package: foreign-env
#   prompt       ~/.config/omf/themes/catppuccin-lean
#   functions    functions/ (gdf, y, ask, nvm, pyenv, claude, va abbreviation, key bindings)

# Shared environment: PATH, EDITOR, nvm's default Node, ... Loaded once per process
# tree: a child shell (tmux pane, nvim terminal) inherits it, until env.sh, nvm's
# default or the set of installed Node versions changes. A login child (every tmux
# pane) gets env.sh's PATH back: fish's macOS login startup moved /etc/paths in front
set -l env_stamp (path mtime ~/.config/shell/env.sh ~/.config/shell/env.local.sh \
    ~/.nvm/alias/default ~/.nvm/versions/node | string join -)
if test "$__env_sh_stamp" != "$env_stamp"; or not set -q __ENV_SH_PATH[1]
    fenv source ~/.config/shell/env.sh
    set -gx __env_sh_stamp $env_stamp
    set -gx __ENV_SH_PATH $PATH # a name ending in PATH arrives in the child as a list
else if status is-login
    set -gx PATH $__ENV_SH_PATH
end

# Colors: the Catppuccin Mocha theme is saved in fish_variables (setup.sh)
# pyenv: loaded on first use (functions/pyenv.fish), the shims are on PATH via env.sh

if status is-interactive
    set -g fish_greeting # no welcome message

    # Ghostty and tmux re-wrap the screen themselves when the window is resized;
    # fish repainting the prompt on top of that leaves a copy of its first line
    # behind at every step
    set -g fish_handle_reflow 0

    # zoxide: `z <part of a path>` jumps to a frequent dir, `zi` picks with fzf
    zoxide init fish | source

    # fzf: Ctrl-R history, Ctrl-T files, Alt-C cd into a dir
    #   fd as file finder (fast, respects .gitignore), bat/eza previews,
    #   Catppuccin Mocha colors, full screen (the screen is restored on exit)
    set -gx FZF_TMUX_HEIGHT 100%
    set -gx FZF_DEFAULT_COMMAND "fd --hidden --strip-cwd-prefix --exclude .git"
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    set -gx FZF_ALT_C_COMMAND "fd --type=d --hidden --strip-cwd-prefix --exclude .git"
    set -gx FZF_DEFAULT_OPTS "\
--color=bg+:#313244,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=selected-bg:#45475a,border:#6c7086"
    set -gx FZF_CTRL_T_OPTS "--preview 'if test -d {}; eza --tree --color=always --icons=always {} | head -200; else; bat -n --color=always --line-range :500 {}; end'"
    set -gx FZF_ALT_C_OPTS "--preview 'eza --tree --color=always --icons=always {} | head -200'"
    fzf --fish | source

    # eza instead of ls
    alias ls "eza --icons=always"
    alias ll "eza --icons=always --long --git --group-directories-first"
    alias lt "eza --icons=always --tree --level=2"

    # Other shortcuts
    alias lg lazygit
    alias fzfp "fzf --preview 'bat {-1} --color=always'"

    # Abbreviations: typed + Space they expand in place, so the command is visible before ⏎
    # (all listed in the shortcut panel, data/shortcuts.lua in the Hammerspoon config)
    abbr -a va --function __va_expand           # source the nearest .venv
    abbr -a gr 'git rup; git st; git stash list' # sync remotes, then status + stashes
    abbr -a cr 'claude --resume'
    abbr -a cu 'claude update'
    abbr -a nrd 'npm run dev'
    abbr -a rl 'exec fish'                       # reload the fish config (fresh shell in place)
end
