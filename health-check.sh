#!/usr/bin/env bash
# health-check.sh: checks that this dotfiles setup is installed and working.
#
#   bash ~/dotfiles/health-check.sh            all offline checks
#   bash ~/dotfiles/health-check.sh --online   also tests the SSH login to every host
#                                              configured in ~/.ssh/config.local
#   bash ~/dotfiles/health-check.sh --verbose  also prints every passed check (by default
#                                              only warnings, failures and notes)
#
# Read-only: it never changes config, packages or running programs. The only
# things it creates are a temp dir (removed on exit) and a separate throwaway
# tmux server (own socket, killed on exit). nvim runs headless with plugin
# installs, update checks and Mason disabled, and its state/cache redirected
# to the temp dir. At the end it verifies that no file in the repo changed.
#
# Layout: settings, helpers, then one check_* function per section, run by
# main() at the bottom. Written for macOS's /bin/bash 3.2.

set -u

DOT="$(cd "$(dirname "$0")" && pwd -P)"
. "$DOT/lib/common.sh"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

ONLINE=0
for option in "$@"; do
  case $option in
    --online) ONLINE=1 ;;
    --verbose) VERBOSE=1 ;;
    *) printf 'unknown option: %s (--online, --verbose)\n' "$option"; exit 2 ;;
  esac
done

# ── Settings ──────────────────────────────────────────────────

FISH=/opt/homebrew/bin/fish
CONFIG="$HOME/.config"

EXPECTED_COMMANDS="fish stow tmux nvim tree-sitter lazygit delta mergiraf bat eza fd fzf rg zoxide
  yazi ya ffmpeg magick pdftoppm resvg 7zz pyenv jq git hs"

# Paths in ~ that must resolve into the repo
LINKED_PATHS=".config/fish .config/omf .config/shell .config/tmux .config/nvim .config/hammerspoon
  .config/git .config/ghostty .config/lazygit .config/bat .config/yazi .claude/settings.json .claude/CLAUDE.md
  .claude/claude-announce.sh .claude/claude-fleet.sh .claude/claude-menu.sh
  .claude/claude-guard.sh .claude/guard-ask .claude/guard-deny
  .claude/claude-readonly.sh .claude/readonly-allow .claude/readonly-deny
  .claude/statusline-command.sh .zshenv .zprofile .zshrc .ssh/config"

# Old config locations that programs would read instead of (or in addition to) the repo
OLD_LOCATIONS=".tmux.conf .hammerspoon .gitconfig .p10k.zsh .config/tmux/plugins
  Library/Application Support/lazygit/config.yml
  Library/Application Support/com.mitchellh.ghostty/config"

# Files that must be git-ignored: runtime state, secrets, the per-machine local files
IGNORED_FILES=".config/fish/fish_variables .config/lazygit/state.yml .config/yazi/flavors/x .npmrc
  .ssh/id_ed25519 .DS_Store .config/git/config.local .config/shell/env.local.sh .ssh/config.local
  .config/hammerspoon/config.local.lua .claude/plugins.local.json
  .config/hammerspoon/modules/colorpicker/sampler .claude/.cc-writes/x"

TEMPLATES="git/config.local ssh/config.local shell/env.local.sh hammerspoon/config.local.lua
  claude/plugins.local.json"

SECRET_PATTERNS='_authToken|BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20}|github_pat_|xox[abpr]-'
SECRET_PATTERNS="$SECRET_PATTERNS"'|AKIA[0-9A-Z]{16}|sk-ant-|ATBB[A-Za-z0-9]{20}'
SECRET_PATTERNS="$SECRET_PATTERNS"'|(password|passwd|secret|api[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+]{8,}'

# Email addresses and home paths have no place in the repo (they belong in the local files)
PERSONAL_PATTERNS='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|/Users/[A-Za-z0-9._-]+'
PERSONAL_ALLOWED=':(git|noreply)@|@users\.noreply|@example\.com'

FISH_TOOLS="pyenv zoxide fzf eza bat fd nvim tmux lazygit yazi"
FISH_FUNCTIONS="z zi y gdf __va_expand fenv nvm pyenv claude ask fish_user_key_bindings"
FISH_ABBREVIATIONS="va gr cr cu nrd rl"

TMUX_PLUGINS="tpm tmux"
TMUX_PANE_KEYS="C-h C-j C-k C-l"
TMUX_OUR_PREFIX_KEYS="A BSpace M R a v _ - < >"
TMUX_WINDOW_KEYS="C-Tab C-BTab C-1 C-2 C-3 C-4 C-5 C-6 C-7 C-8 C-9"
FADE=$'\xee\x83\x86'          # U+E0C6, the pixel fade of the tabs and the capsule
TERMINAL_ICON=$'\xee\x9e\x95' # U+E795
CLOCK_ICON=$'\xef\x80\x97'    # U+F017
APPLE_ICON=$'\xef\x85\xb9'    # U+F179, the first glyph of the fish prompt

# ── Helpers ───────────────────────────────────────────────────

TMP="$(mktemp -d)"
PROBE="healthcheck-$$" # socket name of the throwaway tmux server
PROBE_SOCKET="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$PROBE"

cleanup() {
  tmux -L "$PROBE" kill-server >/dev/null 2>&1
  rm -f "${PROBE_SOCKET:?}" # tmux leaves its socket file behind
  rm -rf "${TMP:?}"
}
trap cleanup EXIT

# Every file in the repo with its size and mtime, hashed: proves nothing changed
fingerprint() {
  find "$DOT" -path "$DOT/.git" -prune -o -type f -print0 \
    | xargs -0 stat -f '%N %z %m' \
    | LC_ALL=C sort \
    | shasum
}

# The repo's tracked and untracked (not ignored) files
repo_files() {
  (cd "$DOT" && git ls-files --cached --others --exclude-standard 2>/dev/null)
}

# grep across the repo files, except this script (it contains the patterns it searches for)
grep_repo() {
  (cd "$DOT" && repo_files | grep -v '^health-check\.sh$' | tr '\n' '\0' | xargs -0 grep "$@" 2>/dev/null)
}

count_words() { echo "$1" | wc -w | tr -d ' '; }
count_lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

# Does the text contain this exact line?
has_line() { printf '%s\n' "$1" | grep -qx -- "$2"; }
# The value after "KEY=" in the text
value_of() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# A shell started with an empty environment, the way launchd starts a terminal
fresh_zsh() { env -i HOME="$HOME" USER="$USER" TERM=dumb /bin/zsh "$@"; }
fresh_fish() { env -i HOME="$HOME" USER="$USER" TERM=xterm-256color "$FISH" "$@"; }

now_seconds() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

# ── System ────────────────────────────────────────────────────

check_system() {
  check "Homebrew installed" has brew

  local login_shell
  login_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
  if [ "$login_shell" = "$FISH" ]; then
    ok "login shell is fish"
  else
    fail "login shell is ${login_shell:-unknown}, expected $FISH"
  fi

  check "fish listed in /etc/shells" grep -qx "$FISH" /etc/shells
}

# ── Packages ──────────────────────────────────────────────────

font_installed_by_hand() { ls "$HOME"/Library/Fonts/RobotoMonoNerdFont* >/dev/null 2>&1; }

check_brewfile() {
  local bundle missing
  if bundle="$(brew bundle check --verbose --no-upgrade --file "$DOT/Brewfile" 2>&1)"; then
    ok "everything in the Brewfile is installed"
    return
  fi
  missing="$(printf '%s\n' "$bundle" | grep -E 'needs to be installed|not installed')"
  local others_missing
  others_missing="$(printf '%s\n' "$missing" | grep -vc 'font-roboto-mono-nerd-font')"
  if [ "$others_missing" -eq 0 ] && font_installed_by_hand; then
    warn "RobotoMono Nerd Font installed by hand, not via the Homebrew cask (works the same)"
  else
    fail "Brewfile packages missing:"
    detail "$missing"
  fi
}

check_commands() {
  local missing="" c
  for c in $EXPECTED_COMMANDS; do
    has "$c" || missing="$missing $c"
  done
  if [ -z "$missing" ]; then
    ok "all commands on PATH ($(count_words "$EXPECTED_COMMANDS"))"
  else
    fail "commands not found:$missing"
  fi
}

check_font() {
  if font_installed_by_hand || brew list --cask font-roboto-mono-nerd-font >/dev/null 2>&1; then
    ok "RobotoMono Nerd Font installed"
  else
    fail "RobotoMono Nerd Font missing (icons won't render)"
  fi
}

check_packages() {
  check_brewfile
  check_commands
  check "nvm installed (nvm.sh)" test -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh"
  check_font
}

# ── Links (stow) ──────────────────────────────────────────────

check_stow() {
  local problems
  problems="$(cd "$DOT" && stow --simulate --verbose=1 --target="$HOME" . 2>&1 \
    | grep -v 'simulation mode' | grep -v '^$')"
  if [ -z "$problems" ]; then
    ok "stow: all links in place, no conflicts"
  else
    fail "stow reports missing links or conflicts:"
    detail "$problems"
  fi
}

check_linked_paths() {
  local bad="" p real
  for p in $LINKED_PATHS; do
    real="$(cd "$HOME" && realpath "$p" 2>/dev/null)"
    case "$real" in
      "$DOT"/*) ;;
      *) bad="$bad ~/$p" ;;
    esac
  done
  if [ -z "$bad" ]; then
    ok "key paths resolve into the repo"
  else
    fail "not linked into the repo:$bad"
  fi
}

check_old_locations() {
  local old
  while IFS= read -r old; do
    old="$(printf '%s' "$old" | sed 's/^ *//')"
    [ -n "$old" ] || continue
    [ -e "$HOME/$old" ] && warn "old config location still exists: ~/$old"
  done <<EOF
$OLD_LOCATIONS
EOF
}

check_links() {
  check_stow
  check_linked_paths
  check_old_locations
}

# ── Repo hygiene ──────────────────────────────────────────────

check_secrets() {
  local files=$1 secrets
  secrets="$(grep_repo -nIE "$SECRET_PATTERNS")"
  if [ -z "$secrets" ]; then
    ok "no secrets found in $(count_lines "$files") repo files"
  else
    fail "possible secrets:"
    detail "$secrets"
  fi
}

check_forbidden_files() {
  local files=$1 bad
  bad="$(printf '%s\n' "$files" | grep -E '(^|/)\.npmrc$|^\.ssh/.+' | grep -v '^\.ssh/config$')"
  if [ -z "$bad" ]; then
    ok "no .npmrc or SSH keys in the repo"
  else
    fail "files that must not be in the repo:"
    detail "$bad"
  fi
}

check_gitignore() {
  local not_ignored="" f
  for f in $IGNORED_FILES; do
    (cd "$DOT" && git check-ignore -q "$f") || not_ignored="$not_ignored $f"
  done
  if [ -z "$not_ignored" ]; then
    ok "runtime files, secrets and local files are git-ignored"
  else
    fail "not git-ignored:$not_ignored"
  fi
}

check_templates() {
  local bad="" f
  for f in $TEMPLATES; do
    if [ ! -f "$DOT/templates/$f" ] || (cd "$DOT" && git check-ignore -q "templates/$f"); then
      bad="$bad $f"
    fi
  done
  if [ -z "$bad" ]; then
    ok "templates for the local files exist and are tracked"
  else
    fail "template missing or git-ignored:$bad"
  fi
}

check_script_syntax() {
  local bad="" f
  for f in setup.sh health-check.sh lib/common.sh; do
    bash -n "$DOT/$f" 2>/dev/null || bad="$bad $f"
  done
  [ -x "$DOT/setup.sh" ] || bad="$bad setup.sh(not executable)"
  if [ -z "$bad" ]; then
    ok "setup.sh, health-check.sh and lib/common.sh parse; setup.sh is executable"
  else
    fail "script problems:$bad"
  fi
}

check_machine_agnostic() {
  local personal
  personal="$(grep_repo -nIoE "$PERSONAL_PATTERNS" | grep -vE "$PERSONAL_ALLOWED")"
  if [ -z "$personal" ]; then
    ok "repo is machine-agnostic (no emails or /Users/ paths)"
  else
    fail "personal data in the repo (move to a local file):"
    detail "$personal"
  fi
}

check_repo() {
  local files
  files="$(repo_files)"
  if [ -z "$files" ]; then
    warn "not a git repo or no files (skipping secret scan)"
    return
  fi
  check_secrets "$files"
  check_forbidden_files "$files"
  check_gitignore
  check_templates
  check_script_syntax
  check_machine_agnostic

  local changes
  changes="$(cd "$DOT" && git status --porcelain | wc -l | tr -d ' ')"
  [ "$changes" -gt 0 ] && info "$changes uncommitted changes in the repo"
}

# ── Shared environment (env.sh) ───────────────────────────────

NODE_INSTALLED=0 # Node comes from nvm (`nvm install --lts`), maybe not yet on a new Mac

check_environment() {
  local envsh="$CONFIG/shell/env.sh"
  check "env.sh is valid POSIX sh" sh -n "$envsh"
  check "env.sh is idempotent (sourcing twice gives the same PATH)" \
    env -i HOME="$HOME" USER="$USER" sh -c '. "$1"; a=$PATH; . "$1"; [ "$a" = "$PATH" ]' sh "$envsh"

  ls "$HOME/.nvm/versions/node/"v* >/dev/null 2>&1 && NODE_INSTALLED=1
  [ $NODE_INSTALLED -eq 1 ] || warn "no Node via nvm yet: nvm install --lts (Node checks below are skipped)"

  check_zsh_environment
  check_zsh_fallback
}

# Claude Code's Bash tool runs a non-interactive zsh; its environment comes from .zshenv alone
check_zsh_environment() {
  local out bad="" c
  out="$(fresh_zsh -c '
    echo "EDITOR=$EDITOR"
    echo "MRA=$npm_config_min_release_age"
    for c in node npm pyenv nvim brew; do echo "$c=$(command -v $c)"; done
  ' 2>&1)"
  has_line "$out" 'EDITOR=nvim' || bad="$bad EDITOR"
  has_line "$out" 'MRA=7' || bad="$bad npm_config_min_release_age"
  for c in pyenv nvim brew; do
    printf '%s\n' "$out" | grep -qE "^$c=/" || bad="$bad $c"
  done
  if [ $NODE_INSTALLED -eq 1 ]; then
    for c in node npm; do
      printf '%s\n' "$out" | grep -qE "^$c=/" || bad="$bad $c"
    done
    printf '%s\n' "$out" | grep -qE '^node=.*/\.nvm/versions/node/' || bad="$bad node-not-from-nvm"
  fi
  if [ -z "$bad" ]; then
    ok "zsh (Claude Code's shell) gets the full environment"
  else
    fail "zsh environment incomplete:$bad"
    detail "$out"
  fi
}

check_zsh_fallback() {
  local errors
  errors="$(TERM=xterm-256color /bin/zsh -i -c exit 2>&1 >/dev/null)"
  if [ -z "$errors" ]; then
    ok "zsh fallback (.zshrc) starts without errors"
  else
    fail "zsh -i prints errors:"
    detail "$errors"
  fi
}

# ── fish ──────────────────────────────────────────────────────

check_fish_syntax() {
  local bad="" f
  for f in $(find "$CONFIG/fish" "$CONFIG/omf" -name '*.fish' -not -path '*/omf/pkg/*'); do
    "$FISH" -n "$f" 2>/dev/null || bad="$bad $f"
  done
  if [ -z "$bad" ]; then
    ok "fish files parse"
  else
    fail "fish syntax errors:$bad"
  fi
}

# One interactive login fish, asked about its environment, tools, functions and bindings
# (-c draws no prompt and skips the key binding setup, so both are loaded like a real session)
fish_session_report() {
  fresh_fish -l -i -c '
    echo "PROMPT="(functions --details fish_prompt)
    functions -q fish_user_key_bindings; and fish_user_key_bindings
    echo "EDITOR=$EDITOR"
    echo "XDG=$XDG_CONFIG_HOME"
    echo "MRA=$npm_config_min_release_age"
    echo "FZFH=$FZF_TMUX_HEIGHT"
    echo "TRANSIENT=$fish_transient_prompt"
    echo "REFLOW=$fish_handle_reflow"
    echo "VENVPROMPT=$VIRTUAL_ENV_DISABLE_PROMPT"
    echo "THEME=$fish_color_command"
    echo "NODE="(command -s node)
    for c in '"$FISH_TOOLS"'
      command -q $c; and echo "CMD=$c"
    end
    for f in '"$FISH_FUNCTIONS"' fzf_key_bindings
      functions -q $f; and echo "FUNC=$f"
    end
    for a in '"$FISH_ABBREVIATIONS"'
      abbr -q $a; and echo "ABBR=$a"
    end
    bind ctrl-r 2>/dev/null | string match -q "*fzf*"; and echo "BIND=ctrl-r"
    bind ctrl-x 2>/dev/null | string match -q "*fish_clipboard_copy*"; and echo "BIND=ctrl-x"
    type -q ls; and functions ls | string match -q "*eza*"; and echo "ALIAS=ls"
  ' 2>"$TMP/fish.err"
}

check_fish_session() {
  local started finished report errors startup
  started="$(now_seconds)"
  report="$(fish_session_report)"
  finished="$(now_seconds)"

  errors="$(cat "$TMP/fish.err")"
  if [ -z "$errors" ]; then
    ok "interactive login fish starts without errors"
  else
    fail "fish prints errors on start:"
    detail "$errors"
  fi

  startup="$(echo "$finished - $started" | bc)"
  if [ "$(echo "$startup < 0.5" | bc)" -eq 1 ]; then
    ok "fish startup ${startup}s"
  else
    warn "fish startup slow: ${startup}s"
  fi

  local bad="" expected c f a
  for expected in EDITOR=nvim "XDG=$CONFIG" MRA=7 FZFH=100% TRANSIENT=1 REFLOW=0 VENVPROMPT=1 THEME=89b4fa; do
    has_line "$report" "$expected" || bad="$bad $expected"
  done
  for a in $FISH_ABBREVIATIONS; do has_line "$report" "ABBR=$a" || bad="$bad ABBR=$a"; done
  for expected in BIND=ctrl-r BIND=ctrl-x ALIAS=ls; do
    has_line "$report" "$expected" || bad="$bad $expected"
  done
  for c in $FISH_TOOLS; do has_line "$report" "CMD=$c" || bad="$bad cmd:$c"; done
  for f in $FISH_FUNCTIONS; do has_line "$report" "FUNC=$f" || bad="$bad func:$f"; done
  if [ $NODE_INSTALLED -eq 1 ]; then
    printf '%s\n' "$report" | grep -qE '^NODE=.*/\.nvm/versions/node/' || bad="$bad node-not-from-nvm"
  fi
  printf '%s\n' "$report" | grep -q 'PROMPT=.*catppuccin-lean' || bad="$bad prompt-not-catppuccin-lean"
  if [ -z "$bad" ]; then
    ok "fish environment, tools, functions, abbreviation and key bindings"
  else
    fail "fish setup incomplete:$bad"
  fi
}

# A temp git repo with a package.json and a .venv, to render the prompt in (git uses it too)
make_sample_project() {
  mkdir -p "$TMP/proj/.venv/bin"
  : >"$TMP/proj/.venv/bin/activate.fish"
  : >"$TMP/proj/package.json"
  git -C "$TMP/proj" init -q 2>/dev/null
}

# The prompt rendered after a failed command, colors stripped, plus the va abbreviation
fish_prompt_report() {
  (cd "$TMP/proj" && TERM=xterm-256color "$FISH" --no-config -c '
    source ~/.config/omf/themes/catppuccin-lean/fish_prompt.fish
    set COLUMNS 120
    false; set -l p (fish_prompt)
    echo "W="(string length --visible -- $p[1])
    echo "LINE1="(string replace -ra "\e\[[0-9;]*m" "" -- $p[1])
    echo "LINE2="(string replace -ra "\e\[[0-9;]*m" "" -- $p[2])
    false; echo "FINAL="(string replace -ra "\e\[[0-9;]*m" "" -- (fish_prompt --final-rendering))
    source ~/.config/fish/functions/__va_expand.fish
    cd sub 2>/dev/null; echo "VA="(__va_expand)
  ' 2>&1)
}

check_fish_prompt() {
  make_sample_project
  local report bad=""
  report="$(fish_prompt_report)"
  has_line "$report" 'W=119' || bad="$bad width"
  printf '%s\n' "$report" | grep -q '^LINE1= ' || bad="$bad left-padding"
  printf '%s\n' "$report" | grep -qE '^LINE1=.*✘1' || bad="$bad exit-code"
  if [ $NODE_INSTALLED -eq 1 ]; then
    printf '%s\n' "$report" | grep -qE '^LINE1=.*v[0-9]+\.[0-9]+\.[0-9]+' || bad="$bad node-version"
  fi
  has_line "$report" 'LINE2= ❯ ' || bad="$bad line2"
  has_line "$report" 'FINAL= ❯ ' || bad="$bad transient"
  has_line "$report" "VA=source $TMP/proj/.venv/bin/activate.fish" || bad="$bad va"
  printf '%s\n' "$report" | grep -qiE 'error|tried to modify' && bad="$bad errors"
  if [ -z "$bad" ]; then
    ok "prompt renders (padding, width, ✘ code, Node, transient) and va expands"
  else
    fail "prompt problems:$bad"
    detail "$report"
  fi
}

check_fish() {
  check_fish_syntax
  check_fish_session
  check_fish_prompt
}

# ── tmux ──────────────────────────────────────────────────────

TMUX_CONF="$CONFIG/tmux/tmux.conf"

# the throwaway server
tp() { tmux -L "$PROBE" "$@" 2>/dev/null; }

catppuccin_tag() { sed -n "s/.*@plugin 'catppuccin\/tmux#\([^']*\)'.*/\1/p" "$TMUX_CONF"; }

catppuccin_installed_tag() {
  git -C "$HOME/.tmux/plugins/tmux" tag --points-at HEAD 2>/dev/null | version_tags | head -1
}

check_tmux_plugins() {
  local p
  for p in $TMUX_PLUGINS; do
    [ -d "$HOME/.tmux/plugins/$p" ] || fail "tmux plugin missing: ~/.tmux/plugins/$p (run setup.sh)"
  done
}

# Every binding needs a `-N "note"`: the shortcut panel (Hammerspoon) reads them
check_tmux_notes() {
  local without_note count
  without_note="$(grep -E '^[[:space:]]*bind(-key)?[[:space:]]' "$TMUX_CONF" | grep -vE '[[:space:]]-N[[:space:]]')"
  count="$(grep -cE '^[[:space:]]*bind(-key)?[[:space:]]' "$TMUX_CONF")"
  if [ -z "$without_note" ]; then
    ok "all $count key bindings in tmux.conf carry -N notes (shortcut panel)"
  else
    fail "tmux.conf bindings without -N note:"
    detail "$without_note"
  fi
}

check_catppuccin_version() {
  local want
  want="$(catppuccin_tag)"
  if git -C "$HOME/.tmux/plugins/tmux" tag --points-at HEAD 2>/dev/null | grep -qx "$want"; then
    ok "plugins installed, catppuccin at $want"
  else
    fail "catppuccin is not at $want (tmux.conf); installed: $(catppuccin_installed_tag)"
  fi
}

# What the loaded config must look like on the test server
check_tmux_settings() {
  local bad="" k
  [ "$(tp show-environment -g TMUX_PLUGIN_MANAGER_PATH)" = "TMUX_PLUGIN_MANAGER_PATH=$HOME/.tmux/plugins/" ] || bad="$bad plugin-path"
  [ "$(tp show -gv prefix)" = "C-Space" ] || bad="$bad prefix"
  [ "$(tp show -gv @catppuccin_flavor)" = "mocha" ] || bad="$bad catppuccin-options"
  tp show -gv window-status-current-format | grep -q 'thm_mauve' || bad="$bad catppuccin-not-loaded"
  [ "$(tp show -gv window-status-current-style)" = "default" ] || bad="$bad tab-underline"
  [ "$(tp show -gv theme)" = "terminal" ] || bad="$bad theme"
  tp show -gv menu-style | grep -q '^bg=#' || bad="$bad menu-style"
  [ "$(tp show -gv @catppuccin_window_status_style)" = "custom" ] || bad="$bad tab-style"
  tp show -gv window-status-format | grep -qF ",reverse]$FADE#[none,fg=" || bad="$bad tab-fade-in"
  tp show -gv window-status-format | grep -qF "]#I #[" || bad="$bad tab-number"
  tp show -gv window-status-format | grep -qF "$FADE#[none]" || bad="$bad tab-fade-out"
  [ "$(tp show -gv window-status-separator)" = "" ] || bad="$bad tabs-touch"
  tp show -gv window-status-format | grep -q 'dotted-underscore' || bad="$bad zoom-dots"
  tp show -gv status-right | grep -q "claude-fleet.sh '#{client_width}'" || bad="$bad fleet"
  tp list-keys -T root MouseDown1Status | grep -q 'mouse_status_range' || bad="$bad fleet-click"
  tp show -gv status-right | grep -qF "$FADE" || bad="$bad capsule-fade"
  tp show -gv @catppuccin_status_session | grep -qF "#[reverse]$FADE#[none]" || bad="$bad capsule-fade-in"
  tp show -gv @catppuccin_status_session | grep -qF "]$TERMINAL_ICON #[" || bad="$bad session-icon"
  tp show -gv @catppuccin_status_date_time | grep -qF "]$CLOCK_ICON #[" || bad="$bad clock-icon"
  tp display-message -p -t probe '#{E:@catppuccin_status_session}' | grep -q '#{' && bad="$bad capsule-unexpanded"
  tp show-hooks -gw | grep -q '@claude_peer' || bad="$bad prompt-peer-hooks"
  for k in $TMUX_PANE_KEYS; do
    tp list-keys -T root "$k" | grep -q 'select-pane' || bad="$bad pane-key:$k"
  done
  for k in $TMUX_WINDOW_KEYS; do
    tp list-keys -T root "$k" >/dev/null || bad="$bad window-key:$k"
  done
  for k in $TMUX_OUR_PREFIX_KEYS; do
    tp list-keys -T prefix "$k" >/dev/null || bad="$bad key:$k"
  done
  if [ -z "$bad" ]; then
    ok "plugin path, prefix, Catppuccin, tabs and capsule fading in and out, zoom dots, fleet click, window, pane, split and Claude keys, hooks, theme, menu"
  else
    fail "tmux setup wrong:$bad"
  fi
}

# Sourcing the config again (prefix + r) must not append the same entries twice
appended_settings() {
  tp show -s terminal-features
  tp show -g update-environment
  tp show-hooks -gw
}

check_tmux_reload() {
  local before after
  before="$(appended_settings)"
  tp set -g @catppuccin_window_current_left_separator stale # the theme copies this one only when unset
  tp source-file "$TMUX_CONF"
  tp source-file "$TMUX_CONF"
  after="$(appended_settings)"
  if [ "$before" != "$after" ]; then
    fail "reload duplicates terminal-features, update-environment or hooks"
  elif tp show -gv window-status-current-format | grep -q 'stale'; then
    fail "reload keeps the current tab's old separators (set them explicitly in tmux.conf)"
  else
    ok "reload (prefix + r) adds no duplicates and renews the current tab's separators"
  fi
}

# A throwaway server with its own socket, never your running one; it stays up for
# the read-only self-test and cleanup kills it
check_tmux_test_server() {
  local start_errors parse_errors
  start_errors="$(tmux -L "$PROBE" -f "$TMUX_CONF" new-session -d -s probe -x 200 -y 50 'sleep 120' 2>&1)"
  sleep 1
  if [ -n "$start_errors" ]; then
    fail "tmux config errors:"
    detail "$start_errors"
  elif ! tmux -L "$PROBE" has-session 2>/dev/null; then
    fail "tmux test server did not start"
  else
    parse_errors="$(tp source-file -n "$TMUX_CONF" 2>&1)"
    if [ -z "$parse_errors" ]; then
      ok "tmux.conf loads without errors"
    else
      fail "tmux.conf parse errors:"
      detail "$parse_errors"
    fi
    check_tmux_settings
    check_tmux_reload
    check_fish_prompt_resize
  fi
}

# The fish prompt must survive a narrower window without leaving copies of its
# first line behind: tmux re-wraps the screen itself, and fish repaints on a
# resize unless config.fish tells it not to
check_fish_prompt_resize() {
  local pane i heads
  pane="$(tp new-window -d -t probe -P -F '#{pane_id}' "$FISH")"
  for i in $(seq 1 50); do
    tp capture-pane -p -t "$pane" | grep -q '❯' && break
    sleep 0.1
  done
  tp resize-window -t "$pane" -x 120
  sleep 0.5
  heads="$(tp capture-pane -p -S - -t "$pane" | grep -c "$APPLE_ICON")"
  if [ "$heads" -eq 1 ]; then
    ok "fish prompt survives a narrower window without copies of itself"
  else
    fail "fish prompt: $heads first lines on the screen after a resize (fish_handle_reflow 0 in config.fish?)"
  fi
  tp kill-window -t "$pane"
}

running_tmux_has_current_config() {
  [ "$(tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH 2>/dev/null)" = "TMUX_PLUGIN_MANAGER_PATH=$HOME/.tmux/plugins/" ] &&
    [ "$(tmux show -gv window-status-current-style 2>/dev/null)" = "default" ] &&
    [ "$(tmux show -gv theme 2>/dev/null)" = "terminal" ]
}

# New panes inherit the server's PATH. Entries that a fresh login shell doesn't produce
# (except an app's own bin, e.g. Ghostty's) are leftovers from the shell the server was
# started in, typically from an older env.sh
check_running_tmux_path() {
  local stale
  fresh_fish -l -c 'string join \n -- $PATH' >"$TMP/fresh-path" 2>/dev/null
  stale="$(tmux show-environment -g PATH 2>/dev/null | cut -d= -f2- | tr ':' '\n' \
    | grep -v '\.app/' | grep -vxF -f "$TMP/fresh-path")"
  if [ -z "$stale" ]; then
    ok "running tmux server's PATH matches a fresh shell"
  else
    warn "running tmux server's environment is stale (PATH entries a fresh shell doesn't have): tmux kill-server, then start tmux from a new terminal window"
    detail "$stale"
  fi
}

# Your running tmux, if any: was it started with the current config?
check_running_tmux() {
  tmux has-session 2>/dev/null || return 0
  if running_tmux_has_current_config; then
    ok "running tmux server uses the current config"
  else
    warn "running tmux server has an older config: prefix + r, or restart tmux"
  fi
  check_running_tmux_path
}

check_tmux() {
  check_tmux_plugins
  check_tmux_notes
  check "window-menu.sh (Ctrl-Shift-Tab) parses" bash -n "$CONFIG/tmux/window-menu.sh"
  check_catppuccin_version
  check_tmux_test_server
  check_running_tmux
}

# ── Neovim ────────────────────────────────────────────────────

NVIM_DATA="$HOME/.local/share/nvim/lazy"

check_nvim_lua_syntax() {
  local bad="" count=0 f
  for f in $(find -L "$CONFIG/nvim" -name '*.lua' -not -path '*/.git/*'); do
    count=$((count + 1))
    luajit -b "$f" /dev/null 2>/dev/null || bad="$bad $f"
  done
  if [ -z "$bad" ] && [ $count -gt 0 ]; then
    ok "Lua syntax of the $count nvim config files (luajit)"
  else
    fail "nvim Lua syntax errors:$bad"
  fi
}

check_nvim_lockfile() {
  local lock="$CONFIG/nvim/lazy-lock.json" bad="" count=0 name want have
  for name in $(jq -r 'keys[]' "$lock"); do
    count=$((count + 1))
    want="$(jq -r --arg n "$name" '.[$n].commit' "$lock")"
    have="$(git -C "$NVIM_DATA/$name" rev-parse HEAD 2>/dev/null)"
    [ "$want" = "$have" ] || bad="$bad $name"
  done
  if [ -z "$bad" ]; then
    ok "all $count plugins installed at the commits in lazy-lock.json"
  else
    warn "plugins differ from lazy-lock.json (:Lazy restore or :Lazy sync):$bad"
  fi
}

# lazy.nvim wrapped so a headless start installs nothing, checks nothing and skips Mason
NVIM_HOOK='lua package.preload["lazy"] = function()
  package.preload["lazy"] = nil
  local lazy = dofile(vim.fn.stdpath("data") .. "/lazy/lazy.nvim/lua/lazy/init.lua")
  package.loaded["lazy"] = lazy
  local setup = lazy.setup
  lazy.setup = function(opts)
    opts.install = vim.tbl_extend("force", opts.install or {}, { missing = false })
    opts.checker = { enabled = false }
    opts.change_detection = { enabled = false }
    table.insert(opts.spec, { "mason-org/mason.nvim", enabled = false })
    table.insert(opts.spec, { "mason-org/mason-lspconfig.nvim", enabled = false })
    return setup(opts)
  end
  return lazy
end'

# After startup: how many plugins loaded, and every error message
NVIM_REPORT='lua vim.defer_fn(function()
  local s = require("lazy").stats()
  local errs = vim.tbl_filter(function(m) return m:match("[Ee]rror") ~= nil end,
    vim.split(vim.api.nvim_exec2("messages", { output = true }).output, "\n"))
  io.stdout:write("LOADED=" .. s.loaded .. "/" .. s.count .. "\n")
  for _, e in ipairs(errs) do io.stdout:write("ERR=" .. e .. "\n") end
  vim.cmd("qa!")
end, 1500)'

# Headless start with state and cache redirected to the temp dir
check_nvim_startup() {
  local out
  out="$(cd "$TMP" && XDG_STATE_HOME="$TMP/state" XDG_CACHE_HOME="$TMP/cache" NVIM_LOG_FILE="$TMP/nvim.log" \
    with_timeout 30 nvim --headless -i NONE --cmd "$NVIM_HOOK" -c "$NVIM_REPORT" 2>&1)"
  if printf '%s\n' "$out" | grep -q '^LOADED=' && ! printf '%s\n' "$out" | grep -qE '^ERR=|E[0-9]+:|stack traceback'; then
    ok "nvim starts headless without errors ($(value_of "$out" LOADED) plugins loaded at startup)"
  else
    fail "nvim start problems:"
    detail "$out"
  fi
}

check_neovim() {
  check_nvim_lua_syntax
  check "nvim >= 0.11 (LazyVim requirement)" nvim --headless --clean -c 'if has("nvim-0.11") | qa | else | cq | endif'
  if [ ! -d "$NVIM_DATA/lazy.nvim" ]; then
    warn "nvim plugins not installed yet: start nvim once (it installs lazy.nvim and the plugins from lazy-lock.json)"
    return
  fi
  check_nvim_lockfile
  check_nvim_startup
}

# ── Hammerspoon ───────────────────────────────────────────────

HS_CONFIG="$CONFIG/hammerspoon"

# Read-only questions to the running Hammerspoon, answered as KEY=value lines.
# Hammerspoon runs Lua 5.4, so its own loadfile checks the syntax of every config
# file (the list comes in through $HSLUA).
HS_QUERY='print("ACC=" .. tostring(hs.accessibilityState())); print("DIR=" .. hs.configdir)
  local c = hs.console.getConsole() or ""; local n = 0
  for l in c:gmatch("[^\n]+") do if l:match("%*%* ") or l:match("[Ee]rror") then n = n + 1; print("ERRLINE=" .. l) end end
  print("ERRS=" .. n)
  local names = {}; for k in pairs(modules or {}) do table.insert(names, k) end; table.sort(names)
  print("MODULES=" .. table.concat(names, " ")); print("FAILED=" .. table.concat(failedModules or {}, " "))
  print("WATCHER=" .. tostring(configWatcher ~= nil))
  local okr, reg = pcall(function() return #require("core.shortcuts").all() end); print("SHORTCUTS=" .. (okr and reg or 0))
  local okt, tm = pcall(function() return #require("modules.panel.tmux").entries() end); print("TMUXENTRIES=" .. (okt and tm or 0))
  for f in string.gmatch(os.getenv("HSLUA") or "", "[^\n]+") do local fn, err = loadfile(f); if not fn then print("SYNTAX=" .. tostring(err)) end end'

# Ask Hammerspoon (hard timeout: the hs CLI can hang; it also waits on a non-tty stdin)
hammerspoon_report() {
  local lua_files=$1 report rc try
  for try in 1 2; do
    report="$(HSLUA="$lua_files" with_timeout 10 hs -t 5 -c "$HS_QUERY" 2>&1 </dev/null)"
    rc=$?
    printf '%s\n' "$report" | grep -q '^DIR=' && break
  done
  printf '%s\n' "$report"
  return "$rc"
}

check_hammerspoon_report() {
  local report=$1 lua_files=$2

  if has_line "$report" 'ACC=true'; then
    ok "Accessibility permission granted"
  else
    fail "Accessibility permission missing (hotkeys, scrolling, windows won't work)"
  fi

  if has_line "$report" "DIR=$HS_CONFIG"; then
    ok "loaded from ~/.config/hammerspoon"
  else
    fail "Hammerspoon runs another config: $(value_of "$report" DIR)"
  fi

  if has_line "$report" 'ERRS=0'; then
    ok "no errors in the Hammerspoon console"
  else
    warn "errors in the Hammerspoon console (may be from earlier reloads):"
    detail "$(value_of "$report" ERRLINE | tail -5)"
  fi

  local syntax_errors
  syntax_errors="$(value_of "$report" SYNTAX)"
  if [ -z "$syntax_errors" ]; then
    ok "Lua syntax of the $(count_lines "$lua_files") Hammerspoon files (Lua 5.4)"
  else
    fail "Hammerspoon Lua syntax errors:"
    detail "$syntax_errors"
  fi

  local loaded failed
  loaded="$(value_of "$report" MODULES)"
  failed="$(value_of "$report" FAILED)"
  if [ -n "$loaded" ] && [ -z "$failed" ]; then
    ok "modules loaded: $loaded"
  else
    fail "modules failed to load: ${failed:-none loaded}"
  fi

  if has_line "$report" 'WATCHER=true'; then
    ok "auto-reload watcher active"
  else
    fail "auto-reload watcher not running"
  fi

  local registered tmux_entries
  registered="$(value_of "$report" SHORTCUTS)"
  tmux_entries="$(value_of "$report" TMUXENTRIES)"
  if [ "${registered:-0}" -ge 10 ]; then
    ok "shortcut panel: $registered Hammerspoon shortcuts registered, $tmux_entries tmux bindings with notes readable"
  else
    fail "shortcut panel: only ${registered:-0} Hammerspoon shortcuts registered"
  fi

  if [ -f "$HS_CONFIG/modules/panel/panel.html" ]; then
    ok "shortcut panel page (modules/panel/panel.html) present"
  else
    fail "modules/panel/panel.html missing"
  fi
}

# The centered window sizes (modules/windows/steps.lua) on sample frames, in Hammerspoon's
# own Lua: the table runs from full size down, the next step is picked with a tolerance,
# the ends give nothing, a step's frame is centered on its screen
HS_STEPS_QUERY='local s = dofile(hs.configdir .. "/modules/windows/steps.lua")
  local screen = { x = 0, y = 0, w = 1000, h = 500 }
  local function at(step) return s.frame(step, screen) end
  local first, second, last = s.STEPS[1], s.STEPS[2], s.STEPS[#s.STEPS]
  print("ORDERED=" .. tostring(first.w == 1 and second.w < first.w and last.w < second.w))
  print("FULL_SMALLER=" .. tostring(s.smaller(at(first), screen) == second))
  print("FULL_LARGER=" .. tostring(s.larger(at(first), screen) == nil))
  local near = at(second); near.w = near.w - 10
  print("TOLERANT=" .. tostring(s.smaller(near, screen) == s.STEPS[3] and s.larger(near, screen) == first))
  print("SMALLEST_SMALLER=" .. tostring(s.smaller(at(last), screen) == nil))
  local f = s.frame({ w = 0.8, h = 0.9 }, { x = 10, y = 20, w = 1000, h = 500 })
  print("FRAME=" .. f.x .. "," .. f.y .. "," .. f.w .. "," .. f.h)
  local c = s.centered({ x = 0, y = 0, w = 300, h = 100 }, { x = 10, y = 20, w = 1000, h = 500 })
  print("CENTERED=" .. c.x .. "," .. c.y .. "," .. c.w .. "," .. c.h)'

check_window_steps() {
  local report bad="" expected
  report="$(with_timeout 10 hs -t 5 -c "$HS_STEPS_QUERY" 2>&1 </dev/null)"
  for expected in ORDERED=true FULL_SMALLER=true FULL_LARGER=true TOLERANT=true SMALLEST_SMALLER=true \
      FRAME=110,45,800,450 CENTERED=360,220,300,100; do
    has_line "$report" "$expected" || bad="$bad $expected"
  done
  if [ -z "$bad" ]; then
    ok "window size steps (⌃⌥+ / ⌃⌥-): order, next step with tolerance, ends, centered frame"
  else
    fail "window size steps (modules/windows/steps.lua) wrong:$bad"
    detail "$report"
  fi
}

# Apps behind ⌃⌥⌘ keys: core ones plus those in config.local.lua; a missing one is just info
check_hammerspoon_apps() {
  local ids id
  ids="$(cat "$HS_CONFIG/modules/apps.lua" "$HS_CONFIG/config.local.lua" 2>/dev/null \
    | grep -v '^ *--' | grep -oE 'id = "[^"]+"' | cut -d'"' -f2 | sort -u)"
  for id in $ids; do
    if [ -z "$(mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null | head -1)" ]; then
      info "app not installed on this Mac: $id (its ⌃⌥⌘ key shows a box)"
    fi
  done
}

# The color picker's helper binary, compiled by setup.sh from the Swift source next to it
check_color_sampler() {
  local src="$HS_CONFIG/modules/colorpicker/sampler.swift" bin="$HS_CONFIG/modules/colorpicker/sampler"
  if [ -x "$bin" ] && [ "$bin" -nt "$src" ]; then
    ok "color sampler helper compiled and newer than its source"
  else
    fail "color sampler helper missing or older than sampler.swift: run setup.sh"
  fi
}

check_hammerspoon() {
  check "Hammerspoon.app installed" test -d /Applications/Hammerspoon.app
  check_color_sampler

  local config_path
  config_path="$(defaults read org.hammerspoon.Hammerspoon MJConfigFile 2>/dev/null)"
  if [ "$config_path" = "~/.config/hammerspoon/init.lua" ]; then
    ok "config location: $config_path"
  else
    fail "MJConfigFile is '${config_path:-unset}', expected ~/.config/hammerspoon/init.lua"
  fi

  if ! pgrep -xq Hammerspoon; then
    fail "Hammerspoon is not running"
    return
  fi
  ok "Hammerspoon is running"

  local lua_files report rc
  lua_files="$(find -L "$HS_CONFIG" -name '*.lua' | sort)"
  report="$(hammerspoon_report "$lua_files")"
  rc=$?
  if ! printf '%s\n' "$report" | grep -q '^DIR='; then
    fail "hs CLI can't reach Hammerspoon (hs.ipc, exit $rc):"
    detail "$report"
    return
  fi
  check_hammerspoon_report "$report" "$lua_files"
  check_window_steps
  check_hammerspoon_apps
}

# ── Claude Code integration ───────────────────────────────────

check_claude_settings() {
  if [ -L "$HOME/.claude/settings.json" ]; then
    ok "settings.json is still the repo symlink"
  else
    fail "~/.claude/settings.json was replaced by a regular file: copy changes into the repo, then stow ."
  fi
  check "settings.json is valid JSON" jq -e . "$HOME/.claude/settings.json"

  # a /plugin install writes plugins into settings.json; they are per Mac (plugins.local.json)
  if jq -e 'has("enabledPlugins") or has("extraKnownMarketplaces")' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    fail "settings.json lists plugins or marketplaces: move them to ~/.claude/plugins.local.json"
  else
    ok "no plugins or marketplaces in settings.json (they are per Mac: plugins.local.json)"
  fi
  if [ -f "$HOME/.claude/plugins.local.json" ]; then
    check "plugins.local.json is valid JSON" jq -e . "$HOME/.claude/plugins.local.json"
  fi
}

# The hook scripts named in settings.json, and all scripts in ~/.claude, must exist and parse
check_claude_scripts() {
  local bad="" s f
  for s in $(jq -r '.. | .command? // empty' "$HOME/.claude/settings.json" | grep -oE '~/\.claude/[A-Za-z0-9_.-]+\.sh' | sort -u); do
    f="$HOME/${s#\~/}"
    [ -f "$f" ] && bash -n "$f" 2>/dev/null || bad="$bad $s"
  done
  for f in "$HOME"/.claude/claude-*.sh "$HOME/.claude/statusline-command.sh"; do
    bash -n "$f" 2>/dev/null || bad="$bad $f"
  done
  if [ -z "$bad" ]; then
    ok "hook + statusline scripts exist and parse"
  else
    fail "script problems:$bad"
  fi

  local line
  line="$(printf '%s' '{"workspace":{"current_dir":"/tmp/x"},"model":{"display_name":"Test"}}' \
    | bash "$HOME/.claude/statusline-command.sh" 2>&1)"
  if printf '%s' "$line" | grep -q 'Test'; then
    ok "statusline script renders"
  else
    fail "statusline script output unexpected:"
    detail "$line"
  fi
}

check_claude_hammerspoon_urls() {
  local claude_lua="$HS_CONFIG/modules/claude.lua"
  if grep -q 'claude-alert' "$claude_lua" && grep -q 'claude-mute-toggle' "$claude_lua"; then
    ok "Hammerspoon handles claude-alert / claude-mute-toggle URLs"
  else
    fail "Hammerspoon claude URL handlers missing"
  fi

  if grep -q 'caffeine-toggle' "$HS_CONFIG/modules/caffeine.lua" && grep -q 'hammerspoon://caffeine-toggle' "$TMUX_CONF"; then
    ok "Caffeine toggle reachable from tmux (prefix C -> hammerspoon://caffeine-toggle)"
  else
    fail "caffeine-toggle URL missing in caffeine.lua or tmux.conf"
  fi

  if grep -q 'urlevent.bind("flash"' "$HS_CONFIG/core/ui.lua" && ! grep -q 'display-message "' "$TMUX_CONF"; then
    ok "tmux feedback goes to Hammerspoon boxes (hammerspoon://flash), none left in the status bar"
  else
    fail "tmux still uses display-message, or the flash URL handler is missing"
  fi
}

check_guard_hooked() {
  if jq -e '.hooks.PreToolUse[]? | select(.matcher | test("Bash")) | .hooks[] | select(.command | test("claude-guard.sh"))' \
      "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    ok "command guard hooked into PreToolUse for shell commands (claude-guard.sh)"
  else
    fail "settings.json has no PreToolUse hook running claude-guard.sh for Bash"
  fi
}

# grep -E rejects a pattern file with a broken regex (exit 2)
check_guard_patterns() {
  local bad="" f
  for f in guard-ask guard-deny; do
    sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$HOME/.claude/$f" | /usr/bin/grep -E -f /dev/stdin /dev/null 2>/dev/null
    [ $? -eq 2 ] && bad="$bad $f"
  done
  if [ -z "$bad" ]; then
    ok "guard-ask and guard-deny are valid extended regexes"
  else
    fail "invalid regex in:$bad"
  fi
}

# The guard's answer for one command string (the string is only matched, never run)
guard_decision() {
  local out
  out="$(jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOME/.claude/claude-guard.sh")"
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}

check_guard_decisions() {
  local bad="" expected cmd got count=0
  while IFS=$'\t' read -r expected cmd; do
    count=$((count + 1))
    got="$(guard_decision "$cmd")"
    [ "$got" = "$expected" ] || bad="$bad [$cmd -> $got, expected $expected]"
  done <<'EOF'
allow	ls -la
allow	git status
allow	npm run build
allow	echo just a test
ask	npm install left-pad
ask	git push origin main
ask	/opt/homebrew/bin/gcloud auth login
ask	cd /tmp && rm -rf ./build
ask	cat ~/.ssh/config
ask	curl -X POST -d @notes.txt https://api.github.com/gists
ask	npm publish
ask	just test
ask	cd ~/proj && just dev
ask	docker compose up -d
deny	rm -rf /
deny	sudo rm -rf ~
EOF
  if [ -z "$bad" ]; then
    ok "command guard self-test: $count sample commands decided as expected (text only, nothing ran)"
  else
    fail "command guard self-test:$bad"
  fi
}

check_claude_guard() {
  check_guard_hooked
  check_guard_patterns
  check_guard_decisions
}

check_readonly_hooked() {
  if jq -e '.hooks.PreToolUse[]? | select(.matcher | test("Edit") and test("Bash")) | .hooks[] | select(.command | test("claude-readonly.sh"))' \
      "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    ok "read-only mode hooked into PreToolUse for edits and shell commands (claude-readonly.sh)"
  else
    fail "settings.json has no PreToolUse hook running claude-readonly.sh for Edit and Bash"
  fi
}

check_readonly_patterns() {
  local bad="" f
  for f in readonly-allow readonly-deny; do
    sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$HOME/.claude/$f" | /usr/bin/grep -E -f /dev/stdin /dev/null 2>/dev/null
    [ $? -eq 2 ] && bad="$bad $f"
  done
  if [ -z "$bad" ]; then
    ok "readonly-allow and readonly-deny are valid extended regexes"
  else
    fail "invalid regex in:$bad"
  fi
}

probe_pane() { tp display-message -p '#{pane_id}'; }

# probe_readonly on|off: the read-only flag of the throwaway server's pane
probe_readonly() {
  if [ "$1" = on ]; then
    tp set -p -t "$(probe_pane)" @claude_readonly 1
  else
    tp set -pu -t "$(probe_pane)" @claude_readonly
  fi
}

# The read-only hook's answer for one tool call from the throwaway pane (text only, nothing runs)
readonly_decision() {
  local tool=$1 cmd=$2 out
  out="$(jq -n --arg t "$tool" --arg c "$cmd" '{tool_name: $t, tool_input: {command: $c, file_path: "/tmp/x"}}' \
    | TMUX="$PROBE_SOCKET,0,0" TMUX_PANE="$(probe_pane)" bash "$HOME/.claude/claude-readonly.sh")"
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}

# Sample calls, "expected<TAB>tool<TAB>command" per line
readonly_samples_on() {
  cat <<'EOF'
deny	Edit
deny	Write
deny	EnterWorktree
allow	Bash	ls -la
allow	Bash	git status && git log --oneline -5
allow	Bash	grep -rn foo src/ 2>/dev/null | head
allow	Bash	ls -la >/dev/null 2>&1
allow	Bash	grep -E "readonly|read-only" ~/.claude/settings.json
allow	Bash	for f in a b; do LC_ALL=C sort "$f"; done
allow	Bash	find . -name '*.lua' -print0 | xargs -0 grep -l foo
allow	Bash	git -C ~/dotfiles branch -a && git config user.name
allow	Bash	curl -sS https://example.com/api
allow	Bash	tmux list-panes -a -F '#{pane_id}'
allow	Bash	just --list
allow	Bash	just --version
ask	Bash	python3 -c 'print(1)'
ask	Bash	bash ~/dotfiles/health-check.sh
ask	Bash	git fetch origin
deny	Bash	echo "$(rm x)"
deny	Bash	find . -name x -delete
deny	Bash	rm x
deny	Bash	git push
deny	Bash	echo x > f
deny	Bash	echo $(rm x)
deny	Bash	git branch -D x
deny	Bash	git add . && git commit -m x
deny	Bash	git config user.name "x"
deny	Bash	curl -sS -o out.json https://example.com/api
deny	Bash	cat a | tee b
deny	Bash	nvim +wq file
deny	Bash	tmux set -p @claude_readonly 0
deny	Bash	just test
deny	Bash	just --evaluate
EOF
}

readonly_samples_off() {
  cat <<'EOF'
allow	Edit
allow	Bash	rm x
EOF
}

# The sample calls on stdin that the hook decided otherwise than expected
readonly_mismatches() {
  local expected tool cmd got
  while IFS=$'\t' read -r expected tool cmd; do
    got="$(readonly_decision "$tool" "$cmd")"
    [ "$got" = "$expected" ] || printf ' [%s %s -> %s, expected %s]' "$tool" "$cmd" "$got" "$expected"
  done
}

check_readonly_decisions() {
  if [ -z "$(probe_pane)" ]; then
    fail "read-only self-test needs the throwaway tmux server"
    return
  fi
  local bad count
  count=$(( $(readonly_samples_on | wc -l) + $(readonly_samples_off | wc -l) ))
  probe_readonly on
  bad="$(readonly_samples_on | readonly_mismatches)"
  probe_readonly off
  bad="$bad$(readonly_samples_off | readonly_mismatches)"
  if [ -z "$bad" ]; then
    ok "read-only self-test: $count sample calls decided as expected on the throwaway pane (text only, nothing ran)"
  else
    fail "read-only self-test:$bad"
  fi
}

check_readonly_statusline() {
  local line
  probe_readonly on
  line="$(printf '%s' '{"model":{"display_name":"Test"}}' \
    | TMUX="$PROBE_SOCKET,0,0" TMUX_PANE="$(probe_pane)" bash "$HOME/.claude/statusline-command.sh" 2>&1)"
  probe_readonly off
  if printf '%s' "$line" | grep -q 'read-only'; then
    ok "status line shows the lock while the pane is read-only"
  else
    fail "status line shows no lock for a read-only pane:"
    detail "$line"
  fi
}

check_claude_readonly() {
  check_readonly_hooked
  check_readonly_patterns
  check_readonly_decisions
  check_readonly_statusline
}

claude_setting() { jq -e "$1" "$HOME/.claude/settings.json" >/dev/null 2>&1; }

check_claude_sandbox() {
  local bad=""
  claude_setting '.sandbox.enabled == true' || bad="$bad enabled"
  claude_setting '.sandbox.autoAllowBashIfSandboxed == true' || bad="$bad sandboxed-commands-prompt"
  claude_setting '.sandbox.filesystem.allowWrite | index("~/.npm") != null' || bad="$bad caches-writable"
  claude_setting '.sandbox.network.allowedDomains | length > 0' || bad="$bad allowed-domains"
  claude_setting '.sandbox.network.strictAllowlist == true' || bad="$bad strict-allowlist"
  claude_setting '.sandbox.credentials.files | map(.path) | index("~/.ssh") != null' || bad="$bad ssh-keys-hidden"
  claude_setting '.sandbox.excludedCommands | index("git push *") != null' || bad="$bad git-over-ssh-excluded"
  claude_setting '.sandbox.excludedCommands | index("docker *") != null and index("just *") != null' || bad="$bad docker-just-excluded"
  claude_setting '.permissions.allow | index("Bash(git fetch:*)") != null' || bad="$bad fetch-prompts"
  claude_setting '.permissions.ask | index("Bash(dangerouslyDisableSandbox:true)") != null' || bad="$bad retry-prompts"
  if [ -z "$bad" ]; then
    ok "Bash sandbox on: sandboxed commands and git fetch/pull run without prompts, allowlist locked, caches writable, keys hidden, push and unsandboxed retries prompt, docker and just run outside through the guard"
  else
    fail "Bash sandbox settings incomplete:$bad"
  fi
}

# A session registry entry (the format Claude Code writes) for a pane of the
# throwaway server, alive as long as this script
fake_claude_session() {
  local pane=$1 location
  location="$(tp display-message -p -t "$pane" '#{session_id}:#{window_id}.#{pane_id}')"
  mkdir -p "$TMP/sessions"
  jq -n --arg pid "$$" --arg location "$location" \
    '{pid: ($pid | tonumber), name: "fake", status: "idle", tmux: $location}' >"$TMP/sessions/fake.json"
}

# A cat pane that stands in for a Claude session on the throwaway server
stand_in_pane() { tp split-window -d -P -F '#{pane_id}' cat; }

peer_of_pane() { tp show -pv -t "$1" @claude_peer; }

# Waits up to 5 s for the pane's @claude_peer to become the value
peer_becomes() {
  local pane=$1 expected=$2 i
  for i in $(seq 1 50); do
    [ "$(peer_of_pane "$pane")" = "$expected" ] && return 0
    sleep 0.1
  done
  return 1
}

# nvim's prompt editor on the throwaway server: two stand-in panes, one of them
# in the fake registry. The menu script must name that pane to the shell (ask)
# and to nvim (a single session needs no menu). nvim must open with one buffer
# (its empty startup buffer reused), pair the panes while a prompt buffer is
# current, give a second session a second buffer and keep the first one, move
# the pairing with the current buffer, paste on :w and unpair on exit.
check_claude_prompt_editor() {
  local shell_pane claude_pane other_pane chosen report peers_after
  shell_pane="$(probe_pane)"
  claude_pane="$(stand_in_pane)"
  other_pane="$(stand_in_pane)"
  fake_claude_session "$claude_pane"
  chosen="$(CLAUDE_SESSIONS_DIR="$TMP/sessions" TMUX="$PROBE_SOCKET,0,0" bash "$HOME/.claude/claude-menu.sh" --choose "$shell_pane")"
  report="$(CLAUDE_SESSIONS_DIR="$TMP/sessions" TMUX="$PROBE_SOCKET,0,0" TMUX_PANE="$shell_pane" OTHER_PANE="$other_pane" with_timeout 20 \
    nvim --headless --clean --listen "$TMP/nvim.sock" --cmd "set rtp+=$CONFIG/nvim" -c 'lua local prompt = require("config.claude_prompt")
      local function say(key, value) io.stdout:write(key .. "=" .. tostring(value) .. "\n") end
      local function listed() return #vim.fn.getbufinfo({ buflisted = 1 }) end
      local function peer_of(pane)
        return vim.trim(vim.system({ "tmux", "show", "-pv", "-t", pane, "@claude_peer" }, { text = true }):wait().stdout or "")
      end
      local mine, other = vim.env.TMUX_PANE, vim.env.OTHER_PANE
      prompt.setup()
      prompt.open()
      say("PICKED", vim.wait(5000, function() return vim.b.claude_pane ~= nil end))
      local first, claude = vim.api.nvim_get_current_buf(), vim.b.claude_pane or ""
      say("BUFFERS", listed())
      say("FILETYPE", vim.bo.filetype)
      say("PEER", peer_of(claude))
      vim.api.nvim_buf_set_lines(first, 0, -1, false, { "hello from nvim" })
      prompt.open(other)
      say("SECOND", vim.api.nvim_get_current_buf() ~= first and listed() == 2)
      say("MOVED", peer_of(other) == mine and peer_of(claude) == "")
      prompt.open(claude)
      say("BACK", vim.api.nvim_get_current_buf() == first and listed() == 2)
      say("RETURNED", peer_of(claude) == mine and peer_of(other) == "")
      vim.cmd.write()
      say("MODIFIED", vim.bo.modified)' -c 'qa!' 2>&1)"
  sleep 1
  peers_after="$(peer_of_pane "$claude_pane")$(peer_of_pane "$other_pane")$(peer_of_pane "$shell_pane")"
  if [ "$chosen" = "$claude_pane" ] && has_line "$report" 'PICKED=true' && has_line "$report" 'BUFFERS=1' \
      && has_line "$report" 'FILETYPE=' && has_line "$report" "PEER=$shell_pane" && has_line "$report" 'SECOND=true' \
      && has_line "$report" 'MOVED=true' && has_line "$report" 'BACK=true' && has_line "$report" 'RETURNED=true' \
      && has_line "$report" 'MODIFIED=false' && [ -z "$peers_after" ] \
      && tp capture-pane -p -t "$claude_pane" | grep -q 'hello from nvim'; then
    ok "prompt editor: one buffer per session (no startup leftover), the pairing follows the current buffer, :w pastes, exit unpairs"
  else
    fail "prompt editor (claude-menu.sh --choose/--pick, nvim lua/config/claude_prompt.lua) self-test:"
    detail "chosen=$chosen peers after exit=$peers_after"
    detail "$report"
  fi
  tp kill-pane -t "$claude_pane"
  tp kill-pane -t "$other_pane"
}

# The editor's pane dies (closed, terminal gone): tmux hangs up on nvim, whose
# exit hook must still unpair the Claude pane
check_claude_prompt_hangup() {
  local claude_pane editor_pane
  claude_pane="$(stand_in_pane)"
  editor_pane="$(tp split-window -d -P -F '#{pane_id}' \
    "nvim --clean --cmd 'set rtp+=$CONFIG/nvim' -c 'lua require(\"config.claude_prompt\").setup()' -c 'ClaudePrompt $claude_pane'")"
  if ! peer_becomes "$claude_pane" "$editor_pane"; then
    fail "prompt editor: nvim in a pane did not pair with its Claude pane (peer: $(peer_of_pane "$claude_pane"))"
    tp kill-pane -t "$editor_pane"
  elif tp kill-pane -t "$editor_pane" && peer_becomes "$claude_pane" ""; then
    ok "prompt editor: a killed editor pane still unpairs its Claude pane"
  else
    fail "prompt editor: @claude_peer stays on the Claude pane after its editor pane was killed"
  fi
  tp kill-pane -t "$claude_pane"
}

# Three fake sessions, alive as long as this script, last active in the order bravo,
# charlie, alpha; bravo runs in the given pane of the throwaway server, the other
# two outside tmux; a fourth, newest, has no pid (a probe of pid 0 would count as alive)
fake_fleet() {
  local pane=$1 name status at location
  mkdir -p "$TMP/fleet"
  while read -r name status at; do
    jq -n --arg pid "$$" --arg name "$name" --arg status "$status" --argjson at "$at" \
      '{pid: ($pid | tonumber), name: $name, status: $status, statusUpdatedAt: $at}' >"$TMP/fleet/$name.json"
  done <<'EOF'
alpha busy 1
charlie idle 2
EOF
  location="$(tp display-message -p -t "$pane" '#{session_id}:#{window_id}.#{pane_id}')"
  jq -n --arg pid "$$" --arg location "$location" \
    '{pid: ($pid | tonumber), name: "bravo", status: "waiting", statusUpdatedAt: 3, tmux: $location}' >"$TMP/fleet/bravo.json"
  jq -n '{name: "delta", status: "busy", statusUpdatedAt: 4}' >"$TMP/fleet/delta.json"
}

# The fleet segment for the fake sessions on the throwaway server, as tmux gets it
# and with the colors and mouse ranges stripped
fleet_raw() {
  CLAUDE_SESSIONS_DIR="$TMP/fleet" TMUX="$PROBE_SOCKET,0,0" bash "$HOME/.claude/claude-fleet.sh" "$@"
}
fleet_segment() { fleet_raw "$@" | sed 's/#\[[^]]*\]//g'; }

# Waits up to 5 s for a client of the throwaway server to sit on that session and pane
client_reaches() {
  local session=$1 pane=$2 i
  for i in $(seq 1 50); do
    tp list-clients -F '#{client_session} #{pane_id}' | grep -qx "$session $pane" && return 0
    sleep 0.1
  done
  return 1
}

# A click on a fleet dot: a nested client of the throwaway server shows the fake
# fleet at the left of its status bar; a mouse click on bravo's name, written into
# the client's pane the way a terminal sends it, must take the client to bravo's
# session and pane
check_claude_fleet_click() {
  local target=$1 client_pane rows i
  tp new-session -d -s fleet-clicker
  tp set -t fleet-clicker status-left "$(fleet_raw)"
  tp set -t fleet-clicker status-right ""
  client_pane="$(tp split-window -d -t probe -P -F '#{pane_id}' "env -u TMUX tmux -L $PROBE attach -t fleet-clicker")"
  for i in $(seq 1 50); do
    tp list-clients -F '#{client_session}' | grep -qx fleet-clicker && break
    sleep 0.1
  done
  sleep 0.5 # the status bar must have been drawn once: that is when its ranges exist
  rows="$(tp display-message -p -t "$client_pane" '#{pane_height}')"
  tp send-keys -t "$client_pane" -l "$(printf '\033[<0;4;%sM\033[<0;4;%sm' "$rows" "$rows")"
  if client_reaches fleet-target "$target"; then
    ok "fleet click: a click on a dot takes the tmux client to that Claude's pane"
  else
    fail "fleet click: the nested client stayed on $(tp list-clients -F '#{client_session} #{pane_id}' | tr '\n' ' ')"
  fi
  tp kill-session -t fleet-clicker # detaches the nested client, whose pane closes with it
}

check_claude_fleet() {
  local target all narrow raw
  target="$(tp new-session -d -P -F '#{pane_id}' -s fleet-target)"
  fake_fleet "$target"
  all="$(fleet_segment)"
  narrow="$(fleet_segment 1)"
  raw="$(fleet_raw)"
  if [ "$all" = "● bravo  ○ charlie  ● alpha  " ] && [ -z "$narrow" ] \
      && [[ $raw == "#[range=user|${target#%}]#[fg=#f38ba8,bold]●#[default] bravo  #[norange]#[fg="* ]]; then
    ok "fleet dots: live sessions newest first, none without a pid, the one in tmux marked with its pane, left out when the client is too narrow"
  else
    fail "fleet dots (claude-fleet.sh) self-test: all=[$all] narrow=[$narrow] raw=[$raw]"
  fi
  check_claude_fleet_click "$target"
  tp kill-session -t fleet-target
}

check_claude() {
  check_claude_settings
  check_claude_scripts
  check_claude_guard
  check_claude_readonly
  check_claude_sandbox
  check_claude_fleet
  check_claude_prompt_editor
  check_claude_prompt_hangup
  check_claude_hammerspoon_urls
  [ -e "$HOME/.claude/announce-muted" ] && info "Claude sounds are muted"
}

# ── git ───────────────────────────────────────────────────────

check_git_config_location() {
  local origin
  origin="$(git config --global --show-origin --get core.pager 2>/dev/null | awk '{print $1}')"
  if [ "$origin" = "file:$CONFIG/git/config" ]; then
    ok "global config read from ~/.config/git/config"
  else
    fail "global git config is not ~/.config/git/config"
  fi
}

check_git_identity() {
  local name mail
  name="$(git config --global --includes user.name)"
  mail="$(git config --global --includes user.email)"
  if [ -z "$name" ] || [ -z "$mail" ]; then
    fail "user.name/user.email missing in ~/.config/git/config.local"
  elif [ "$name" = "Your Name" ] || [ "$mail" = "you@example.com" ]; then
    fail "git identity is still the template placeholder: edit ~/.config/git/config.local"
  else
    ok "git identity: $name <$mail> (config.local)"
  fi
}

# The includeIf "gitdir:<folder>" entries of config.local as "<folder>\t<included file>" lines
git_folder_identities() {
  awk '
    /^\[includeIf "gitdir:/ { match($0, /gitdir:[^"]*/); f = substr($0, RSTART + 7, RLENGTH - 7) }
    f && /^[[:space:]]*path[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); print f "\t" $0; f = "" }
  ' "$CONFIG/git/config.local"
}

# Every folder identity must point to an existing file, and a repo in that folder must get its email
check_git_folder_identities() {
  local folder inc mail repo
  while IFS=$'\t' read -r folder inc; do
    [ -n "$folder" ] || continue
    folder="${folder/#\~/$HOME}"
    inc="${inc/#\~/$HOME}"
    if [ ! -f "$inc" ]; then
      fail "includeIf for $folder points to a missing file: $inc"
      continue
    fi
    mail="$(git config -f "$inc" user.email)"
    repo="$(find "$folder" -maxdepth 3 -name .git -print -quit 2>/dev/null | xargs -I{} dirname {} 2>/dev/null)"
    if [ -z "$repo" ]; then
      info "includeIf $folder -> $mail (no repo there yet to verify)"
    elif [ "$(git -C "$repo" config user.email)" = "$mail" ]; then
      ok "repos under $folder commit as $mail"
    else
      fail "a repo under $folder does not get the includeIf email $mail"
    fi
  done < <(git_folder_identities)
}

check_git_tools() {
  case "$(git config --get core.pager)" in
    delta*) ok "delta is the pager" ;;
    *) fail "core.pager is not delta" ;;
  esac

  if git config --get merge.mergiraf.driver | grep -q mergiraf; then
    ok "mergiraf merge driver configured"
  else
    fail "mergiraf merge driver not configured"
  fi

  if (cd "$TMP/proj" && git check-attr merge -- a.ts | grep -q 'merge: mergiraf'); then
    ok "global attributes use mergiraf (e.g. *.ts)"
  else
    fail "global git attributes not applied"
  fi

  if (cd "$TMP/proj" && git check-ignore -q .claude/settings.local.json); then
    ok "global git ignore applied (.claude/settings.local.json)"
  else
    fail "global git ignore not applied"
  fi
}

check_git() {
  check_git_config_location
  if [ -f "$CONFIG/git/config.local" ]; then
    check_git_identity
    check_git_folder_identities
  else
    warn "no ~/.config/git/config.local: git has no name/email on this Mac (see README)"
  fi
  check_git_tools
}

# ── Other tools ───────────────────────────────────────────────

check_tools() {
  local ghostty_errors
  if ghostty_errors="$(with_timeout 15 /Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config \
    --config-file="$CONFIG/ghostty/config.ghostty" 2>&1)"; then
    ok "Ghostty config valid"
  else
    fail "Ghostty config errors:"
    detail "$ghostty_errors"
  fi

  local csi_keys
  csi_keys="$(grep -c '^keybind = .*=csi:27;' "$CONFIG/ghostty/config.ghostty")"
  if [ "$csi_keys" -eq 11 ] && grep -q '^window-padding-balance = true' "$CONFIG/ghostty/config.ghostty" \
      && grep -q '^macos-titlebar-style = hidden' "$CONFIG/ghostty/config.ghostty"; then
    ok "Ghostty sends Ctrl-Tab, Ctrl-Shift-Tab and ⌘1-9 to tmux, grid padding balanced, no title bar"
  else
    fail "Ghostty config: expected 11 csi keybinds (found $csi_keys), window-padding-balance = true and macos-titlebar-style = hidden"
  fi

  if [ "$(bat --config-file)" = "$CONFIG/bat/config" ] && bat --list-themes 2>/dev/null | grep -q 'Catppuccin Mocha'; then
    ok "bat: config + Catppuccin Mocha theme"
  else
    fail "bat config/theme"
  fi

  local lazygit_dir
  lazygit_dir="$(lazygit --print-config-dir 2>/dev/null)"
  if [ "$lazygit_dir" = "$CONFIG/lazygit" ]; then
    ok "lazygit reads ~/.config/lazygit"
  else
    fail "lazygit config dir is $lazygit_dir"
  fi

  local flavor
  flavor="$(sed -n 's/^dark *= *"\(.*\)"/\1/p' "$CONFIG/yazi/theme.toml" | head -1)"
  if [ -n "$flavor" ] && [ -d "$CONFIG/yazi/flavors/$flavor.yazi" ]; then
    ok "yazi flavor '$flavor' installed"
  else
    fail "yazi flavor '${flavor:-?}' missing (ya pkg install)"
  fi

  if [ -d "$HOME/.local/share/omf" ]; then
    ok "Oh My Fish installed"
  else
    fail "Oh My Fish missing"
  fi

  check "pyenv works" pyenv --version
}

# ── SSH ───────────────────────────────────────────────────────

SSH_HOSTS="" # the Host entries of ~/.ssh/config.local (patterns like * skipped); no provider names here

read_ssh_hosts() {
  if [ -f "$HOME/.ssh/config.local" ]; then
    SSH_HOSTS="$(awk 'tolower($1)=="host"{for(i=2;i<=NF;i++) if ($i !~ /[*?!]/) print $i}' "$HOME/.ssh/config.local" | sort -u)"
    [ -n "$SSH_HOSTS" ] || info "no Host entries in ~/.ssh/config.local"
  else
    warn "no ~/.ssh/config.local: no hosts/keys set up on this Mac (see README)"
  fi
}

# The value of one keyword in `ssh -G` output (the host's effective settings,
# "keyword value..." per line); the first line for a keyword that repeats
ssh_setting() { printf '%s\n' "$1" | awk -v keyword="$2" '$1==keyword{$1=""; sub(/^ /, ""); print; exit}'; }

# ssh keeps the host's key under HostKeyAlias when one is set, in any of its
# UserKnownHostsFile entries (two defaults when unset), as gcloud's IAP hosts do
host_key_known() {
  local config=$1 host=$2 name file
  name="$(ssh_setting "$config" hostkeyalias)"
  for file in $(ssh_setting "$config" userknownhostsfile); do
    ssh-keygen -F "${name:-$host}" -f "${file/#\~/$HOME}" >/dev/null 2>&1 && return 0
  done
  return 1
}

check_ssh_hosts() {
  local h config key
  for h in $SSH_HOSTS; do
    config="$(ssh -G "$h" </dev/null 2>/dev/null)"
    key="$(ssh_setting "$config" identityfile)"
    key="${key/#\~/$HOME}"
    if [ -f "$key" ]; then
      ok "$h: key exists ($key)"
    else
      fail "$h: key missing: $key"
    fi
    if host_key_known "$config" "$h"; then
      ok "$h: host key known"
    else
      warn "$h: host key not in its known_hosts file yet (first connection asks)"
    fi
  done
}

# ssh -G doesn't print Apple's UseKeychain option, so read the config itself
check_ssh_keychain() {
  if grep -qiE '^[[:space:]]*UseKeychain[[:space:]]+yes' "$HOME/.ssh/config"; then
    ok "UseKeychain enabled"
  else
    warn "UseKeychain not enabled"
  fi
}

check_ssh_agent() {
  local launchd_sock agents
  launchd_sock="$(launchctl print "gui/$(id -u)/com.openssh.ssh-agent" 2>/dev/null | awk '$1=="SSH_AUTH_SOCK"{print $3; exit}')"
  if [ -z "$launchd_sock" ]; then
    fail "macOS's ssh-agent (launchd) is not set up"
  elif [ "${SSH_AUTH_SOCK:-}" = "$launchd_sock" ]; then
    ok "SSH_AUTH_SOCK is macOS's agent"
  elif [ -n "${SSH_AUTH_SOCK:-}" ] && [ ! -S "$SSH_AUTH_SOCK" ]; then
    warn "this shell has a stale SSH_AUTH_SOCK (started before the agent cleanup); new shells get macOS's agent"
  else
    warn "SSH_AUTH_SOCK is not macOS's agent: ${SSH_AUTH_SOCK:-unset}"
  fi

  agents="$(pgrep -x ssh-agent | wc -l | tr -d ' ')"
  if [ "$agents" -le 1 ]; then
    ok "no stray ssh-agents ($agents running)"
  else
    warn "$agents ssh-agent processes running"
  fi

  if [ -n "$launchd_sock" ] && SSH_AUTH_SOCK="$launchd_sock" ssh-add -l >/dev/null 2>&1; then
    ok "a key is loaded in macOS's agent"
  else
    warn "no key loaded in the agent yet (loads on first use via AddKeysToAgent + Keychain)"
  fi
}

# No command is sent: a plain server's shell ends on the closed input and returns 0,
# git hosts refuse a shell but say that the key authenticated ("successfully
# authenticated", "Welcome", "logged in as"); GitHub rejects any command instead
check_ssh_logins() {
  [ -z "$SSH_HOSTS" ] && warn "--online: no hosts in ~/.ssh/config.local to test"
  local h out rc
  for h in $SSH_HOSTS; do
    out="$(with_timeout 20 ssh -T -o BatchMode=yes -o ConnectTimeout=10 "$h" 2>&1 </dev/null)"
    rc=$?
    if [ $rc -eq 0 ] || printf '%s' "$out" | grep -qiE 'authenticated|welcome|logged in'; then
      ok "$h: SSH login works"
    else
      fail "$h: SSH login failed:"
      detail "$out"
    fi
  done
}

check_ssh() {
  read_ssh_hosts
  check_ssh_hosts
  check_ssh_keychain
  check_ssh_agent
  [ $ONLINE -eq 1 ] && check_ssh_logins
}

# ── Read-only guarantee ───────────────────────────────────────

check_readonly() {
  if [ "$(fingerprint)" = "$BEFORE" ]; then
    ok "no file in the repo changed during this check"
  else
    fail "files in the repo changed during the check!"
  fi
}

# ── Main ──────────────────────────────────────────────────────

main() {
  BEFORE="$(fingerprint)"
  printf '%sdotfiles health check%s  %s(%s, %s)%s\n' \
    "$C_BLUE" "$C_RESET" "$C_DIM" "$DOT" "$(date '+%Y-%m-%d %H:%M')" "$C_RESET"

  section "System";                     check_system
  section "Packages (Brewfile)";        check_packages
  section "Links (stow)";               check_links
  section "Repo (secrets, ignores)";    check_repo
  section "Environment (env.sh, zsh)";  check_environment
  section "fish";                       check_fish
  section "tmux";                       check_tmux
  section "Neovim";                     check_neovim
  section "Hammerspoon";                check_hammerspoon
  section "Claude Code integration";    check_claude
  section "git";                        check_git
  section "Other tools";                check_tools
  section "SSH";                        check_ssh
  section "Read-only";                  check_readonly

  summary
  [ "$FAILS" -eq 0 ]
}

main
