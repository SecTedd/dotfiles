# Shared environment for every shell:
#   zsh  -> ~/.zshenv (all zsh, incl. Claude Code's Bash tool) and ~/.zprofile
#   fish -> ~/.config/fish/config.fish (via foreign-env)
# POSIX sh only. Safe to load repeatedly: PATH entries are moved, never duplicated.

# Put a directory at the front (or back) of PATH, removing an earlier copy.
# A directory that doesn't exist on this Mac is skipped.
_path_remove() { PATH=$(printf '%s' ":$PATH:" | sed "s#:$1:#:#g; s#^:##; s#:\$##"); }
path_prepend() { [ -d "$1" ] || return 0; _path_remove "$1"; PATH="$1${PATH:+:$PATH}"; }
path_append() { [ -d "$1" ] || return 0; _path_remove "$1"; PATH="${PATH:+$PATH:}$1"; }

export XDG_CONFIG_HOME="$HOME/.config"
export EDITOR="nvim"

# Homebrew (static equivalent of `brew shellenv`, without spawning brew)
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
case ":${MANPATH:-}:" in *":/opt/homebrew/share/man:"*) ;; *) export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:" ;; esac
case ":${INFOPATH:-}:" in *":/opt/homebrew/share/info:"*) ;; *) export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}" ;; esac
path_prepend "/opt/homebrew/sbin"
path_prepend "/opt/homebrew/bin"

# pyenv: shims on PATH (fish additionally loads `pyenv init` for `pyenv shell`).
# The shims folder appears with the first `pyenv install`; until then it's skipped.
export PYENV_ROOT="$HOME/.pyenv"
path_prepend "$PYENV_ROOT/bin"
path_prepend "$PYENV_ROOT/shims"

# nvm: put the default Node version on PATH without loading the slow nvm.sh.
# Follows nvm's aliases, e.g. default -> lts/* -> lts/krypton -> v24.21.0.
# (`nvm use` etc. load the real nvm: fish via functions/nvm.fish)
export NVM_DIR="$HOME/.nvm"
if [ -r "$NVM_DIR/alias/default" ]; then
  _nvm_version=$(cat "$NVM_DIR/alias/default")
  _nvm_hops=0
  while [ "$_nvm_hops" -lt 5 ]; do
    case $_nvm_version in
      lts/*) _nvm_version=$(cat "$NVM_DIR/alias/lts/${_nvm_version#lts/}" 2>/dev/null) ;;
      *) break ;;
    esac
    _nvm_hops=$((_nvm_hops + 1))
  done
  case $_nvm_version in
    node | stable | "") _nvm_version="v" ;;  # newest installed
    v*) ;;
    *) _nvm_version="v$_nvm_version" ;;     # e.g. "24" -> newest v24.x
  esac
  _nvm_dir=$(ls -d "$NVM_DIR/versions/node/$_nvm_version"* 2>/dev/null | sort -V | tail -1)
  [ -n "$_nvm_dir" ] && path_prepend "$_nvm_dir/bin"
  unset _nvm_version _nvm_hops _nvm_dir
fi

path_prepend "$HOME/.local/bin"

# Docker Desktop's CLI folder in its "User" install mode (its "System" mode links
# the tools into /usr/local/bin and leaves this folder empty)
path_append "$HOME/.docker/bin"

# npm: only install package versions that are at least 7 days old (supply-chain
# safety). The npm login token stays local in ~/.npmrc, never in the dotfiles.
export npm_config_min_release_age=7

# Machine-specific additions (work tools, ...): env.local.sh next to this file,
# git-ignored (template: templates/shell/env.local.sh). It can use path_prepend / path_append.
[ -r "$HOME/.config/shell/env.local.sh" ] && . "$HOME/.config/shell/env.local.sh"

export PATH
unset -f _path_remove path_prepend path_append
