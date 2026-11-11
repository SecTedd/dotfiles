#!/usr/bin/env bash
# setup.sh: turns a Mac with Homebrew and this repo into the working setup.
#
#   git clone <repo> ~/dotfiles && ~/dotfiles/setup.sh
#
#   --dry-run       only print what would be done
#   --yes           don't ask before moving conflicting files aside
#   --skip a,b,...  skip steps: packages shell links omf tmux yazi node hammerspoon local check
#   --pins          report only: pinned vs installed vs latest upstream version of each piece
#   --verbose       also print what was already fine (by default: changes, warnings, errors)
#
# Safe to re-run: every step checks first and only does what's missing, so a
# re-run is also the update path after pulling changes (new packages, plugins,
# links). Nothing is ever upgraded, only installed; `brew upgrade` stays your call.
#
# Pins are the source of truth. Everything downloaded here is pinned to a commit
# or tag and comes from its official repo (MIT licensed, all of them). An
# installed copy that is at a different commit is moved to the pin. To update
# deliberately: read the upstream changes, change the pin below (or the tag in
# tmux.conf, or the rev in .config/yazi/package.toml), pull on each Mac, run setup.sh.
#   Oh My Fish          github.com/oh-my-fish/oh-my-fish                  OMF_COMMIT
#   foreign-env         github.com/oh-my-fish/plugin-foreign-env          FENV_COMMIT
#   tpm                 github.com/tmux-plugins/tpm                       TPM_COMMIT
#   catppuccin/tmux     github.com/catppuccin/tmux (installed by tpm)     tag in .config/tmux/tmux.conf
#   yazi flavor         github.com/yazi-rs/flavors (installed by ya)      rev + hash in .config/yazi/package.toml
# Homebrew packages come from the Brewfile (homebrew/core and homebrew/cask only);
# Homebrew has no version pins, it installs the current version.
#
# Layout: pins and settings, options, helpers, the pin report, then one step_*
# function per step, run by main() at the bottom. macOS /bin/bash 3.2 compatible.

set -u

DOT="$(cd "$(dirname "$0")" && pwd -P)"
. "$DOT/lib/common.sh"

# ── Pins and settings ─────────────────────────────────────────

OMF_REPO="https://github.com/oh-my-fish/oh-my-fish"
OMF_COMMIT="53b5a1bf8526007824964d610211259bf2ad92dd" # v8
FENV_REPO="https://github.com/oh-my-fish/plugin-foreign-env"
FENV_COMMIT="b693237c3027b81ac3760d60d159d2be4925ed1c"
TPM_REPO="https://github.com/tmux-plugins/tpm"
TPM_COMMIT="e261deb1b47614eed3400089ce7197dc68acc4eb" # master, 2026-05-17
CATPPUCCIN_REPO="https://github.com/catppuccin/tmux"
YAZI_FLAVORS_REPO="https://github.com/yazi-rs/flavors"

FISH="/opt/homebrew/bin/fish"
FISH_THEME="catppuccin-mocha"   # one of fish's built-in themes (fish_config theme list)
FISH_THEME_COMMAND_COLOR="89b4fa" # its command color: tells a saved theme from the default
OMF_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/omf"
OMF_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omf"
TMUX_PLUGINS="$HOME/.tmux/plugins"
TMUX_CONF="$DOT/.config/tmux/tmux.conf"
YAZI_PKG="$DOT/.config/yazi/package.toml"
HAMMERSPOON_CONFIG='~/.config/hammerspoon/init.lua'
SAMPLER_SRC="$DOT/.config/hammerspoon/modules/colorpicker/sampler.swift"
SAMPLER_BIN="$DOT/.config/hammerspoon/modules/colorpicker/sampler"
# The official install command from https://brew.sh
BREW_INSTALL='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

# ── Options ───────────────────────────────────────────────────

DRY=0
YES=0
PINS=0
SKIP=","

parse_options() {
  while [ $# -gt 0 ]; do
    case $1 in
      --dry-run) DRY=1 ;;
      --yes) YES=1 ;;
      --pins) PINS=1 ;;
      --verbose) VERBOSE=1 ;;
      --skip) [ $# -ge 2 ] || die "--skip needs a list of steps (try --help)"; SKIP=",$2,"; shift ;;
      -h | --help) print_help; exit 0 ;;
      *) printf 'unknown option: %s (try --help)\n' "$1"; exit 2 ;;
    esac
    shift
  done
}

# The comment block at the top of this file
print_help() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

# ── Helpers ───────────────────────────────────────────────────

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

# run <cmd...>: run it, or only print it with --dry-run
run() {
  if [ $DRY -eq 1 ]; then
    text "$C_DIM\$ $*$C_RESET"
    return 0
  fi
  "$@"
}

# quiet <cmd...>: like run, but the output is shown only if the command fails
quiet() {
  if [ $DRY -eq 1 ]; then
    run "$@"
    return 0
  fi
  "$@" >"$TMP/quiet.log" 2>&1 || { flush_section; cat "$TMP/quiet.log"; return 1; }
}

die() {
  flush_section
  printf '\n%s✘ %s%s\n' "$C_RED" "$1" "$C_RESET"
  exit 1
}

short() { printf '%s' "${1:0:7}"; }

# nocred <cmd...>: run it with git's credential helpers switched off. Every clone
# here is a public https repo, and Apple's git sets the osxkeychain helper
# system-wide: without this, tpm's clones (user "git" in the URL) would store
# an entry in the Keychain, or pop up "Keychain not found" where there is none.
nocred() { GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= "$@"; }

# clone_pinned <repo> <commit> <dir>: a clone checked out at exactly that commit
clone_pinned() {
  local repo=$1 commit=$2 dir=$3
  nocred git clone -q "$repo" "$dir" || return 1
  git -C "$dir" checkout -q "$commit" || { text "commit $commit not found in $repo"; return 1; }
}

# ensure_pinned <label> <repo> <commit> <dir>: clone if missing, otherwise move
# an installed copy to the pinned commit (fetch + checkout) if it's elsewhere
ensure_pinned() {
  local label=$1 repo=$2 commit=$3 dir=$4 have
  if [ ! -d "$dir/.git" ]; then
    if [ $DRY -eq 1 ]; then
      run git clone "$repo" "$dir" "@$(short "$commit")"
      return 0
    fi
    clone_pinned "$repo" "$commit" "$dir" || die "cloning $label failed"
    did "$label installed (pinned to $(short "$commit"))"
    return 0
  fi

  have="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  if [ "$have" = "$commit" ]; then
    ok "$label at $(short "$commit")"
    return 0
  fi
  if [ $DRY -eq 1 ]; then
    run git -C "$dir" fetch origin
    run git -C "$dir" checkout "$(short "$commit")"
    return 0
  fi
  nocred git -C "$dir" fetch -q origin 2>/dev/null
  git -C "$dir" checkout -q "$commit" 2>/dev/null \
    || die "$label: commit $(short "$commit") not found in $repo (wrong pin, or no network to fetch it)"
  did "$label moved to the pin $(short "$commit") (was $(short "$have"))"
}

# ensure_tag <label> <dir> <tag>: an installed clone must sit on this tag
ensure_tag() {
  local label=$1 dir=$2 tag=$3
  [ -d "$dir/.git" ] || die "$label is missing in $dir"
  if git -C "$dir" tag --points-at HEAD 2>/dev/null | grep -qx "$tag"; then
    ok "$label at $tag"
    return 0
  fi
  if [ $DRY -eq 1 ]; then
    run git -C "$dir" fetch origin "refs/tags/$tag:refs/tags/$tag"
    run git -C "$dir" checkout "$tag"
    return 0
  fi
  nocred git -C "$dir" fetch -q origin "refs/tags/$tag:refs/tags/$tag" 2>/dev/null
  git -C "$dir" checkout -q "$tag" 2>/dev/null || die "$label: tag $tag not found (wrong tag in tmux.conf, or no network to fetch it)"
  did "$label moved to $tag"
}

catppuccin_tag() { sed -n "s/.*@plugin 'catppuccin\/tmux#\([^']*\)'.*/\1/p" "$TMUX_CONF"; }
yazi_flavor() { sed -n 's/^use *= *"[^:]*:\(.*\)"/\1/p' "$YAZI_PKG" | head -1; }
yazi_rev() { sed -n 's/^rev *= *"\(.*\)"/\1/p' "$YAZI_PKG" | head -1; }

# ── --pins: report only ───────────────────────────────────────

# upstream_head <repo>: latest commit upstream (git ls-remote reads refs only, downloads nothing)
upstream_head() { nocred git ls-remote "$1" HEAD 2>/dev/null | cut -c1-40; }
installed_head() { git -C "$1" rev-parse HEAD 2>/dev/null; }

installed_tag() {
  git -C "$TMUX_PLUGINS/tmux" tag --points-at HEAD 2>/dev/null | version_tags | head -1
}

latest_catppuccin_tag() {
  nocred git ls-remote --tags --refs "$CATPPUCCIN_REPO" 2>/dev/null \
    | sed 's#.*refs/tags/##' | version_tags | sort -V | tail -1
}

installed_yazi_rev() {
  ya pkg list 2>/dev/null | sed -n "s/.*$(yazi_flavor) (\([0-9a-f]*\)).*/\1/p" | head -1
}

# pin_row <label> <pinned> <installed> <upstream>
pin_row() {
  local label=$1 pinned=$2 installed=$3 upstream=$4 state
  if [ -z "$installed" ]; then
    state="not installed"
  elif [ "$installed" != "$pinned" ]; then
    state="installed differs from the pin: run setup.sh"
  elif [ -n "$upstream" ] && [ "$upstream" != "$pinned" ]; then
    state="newer upstream available"
  elif [ -n "$upstream" ]; then
    state="up to date with upstream"
  else
    state="upstream not reachable"
  fi
  text "$(printf '%-20s %-10s %-10s %-10s %s' "$label" "${pinned:-?}" "${installed:--}" "${upstream:--}" "$state")"
}

# pin_commit_row <label> <repo> <pinned commit> <dir>
pin_commit_row() {
  local label=$1 repo=$2 commit=$3 dir=$4
  pin_row "$label" "$(short "$commit")" "$(short "$(installed_head "$dir")")" "$(short "$(upstream_head "$repo")")"
}

report_pins() {
  section "Pins (pinned / installed / latest upstream)"
  text "$(printf '%-20s %-10s %-10s %-10s' piece pinned installed upstream)"
  pin_commit_row "Oh My Fish" "$OMF_REPO" "$OMF_COMMIT" "$OMF_PATH"
  pin_commit_row "foreign-env" "$FENV_REPO" "$FENV_COMMIT" "$OMF_PATH/pkg/foreign-env"
  pin_commit_row "tpm" "$TPM_REPO" "$TPM_COMMIT" "$TMUX_PLUGINS/tpm"
  pin_row "catppuccin/tmux" "$(catppuccin_tag)" "$(installed_tag)" "$(latest_catppuccin_tag)"
  pin_row "yazi flavor" "$(yazi_rev)" "$(installed_yazi_rev)" "$(short "$(upstream_head "$YAZI_FLAVORS_REPO")")"
  info "nvim plugins: pinned in lazy-lock.json; :Lazy check shows updates, :Lazy update applies and rewrites the lock file"
  if has brew; then
    info "Homebrew: no pins; $(brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ') outdated (brew outdated / brew upgrade)"
  fi
}

# ── Steps ─────────────────────────────────────────────────────

step_prerequisites() {
  [ "$(uname)" = Darwin ] || die "this setup is for macOS"
  if has brew; then
    ok "Homebrew"
  else
    text "Homebrew is missing. Install it with the official command from https://brew.sh,"
    text "then run this script again:"
    text "  $BREW_INSTALL"
    exit 1
  fi
  if has git; then
    ok "git"
  else
    die "git is missing (xcode-select --install)"
  fi
}

step_packages() {
  if brew bundle check --no-upgrade --file "$DOT/Brewfile" >/dev/null 2>&1; then
    ok "everything installed"
    return
  fi
  run brew bundle install --no-upgrade --file "$DOT/Brewfile" || die "brew bundle failed: fix the error above and re-run"
  did "installed"
}

step_shell() {
  [ -x "$FISH" ] || die "$FISH is missing (the packages step installs it)"
  if grep -qx "$FISH" /etc/shells; then
    ok "fish is in /etc/shells"
  else
    run sudo sh -c "echo '$FISH' >> /etc/shells" || die "could not add fish to /etc/shells"
    did "fish added to /etc/shells"
  fi

  local login_shell
  login_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
  if [ "$login_shell" = "$FISH" ]; then
    ok "login shell is fish"
  else
    run chsh -s "$FISH" || die "chsh failed"
    did "login shell set to fish (new terminal windows use it)"
  fi
  save_fish_theme
}

# The colors are universal variables (fish_variables, per Mac), saved once here
# instead of chosen on every shell start. fish asks before replacing colors saved
# earlier and needs the dark/light choice spelled out, because only a terminal
# can tell it (the terminals here are dark)
save_fish_theme() {
  if "$FISH" -c "test \"\$fish_color_command\" = $FISH_THEME_COMMAND_COLOR" 2>/dev/null; then
    ok "fish theme $FISH_THEME saved"
    return
  fi
  printf 'y\n' | run "$FISH" -c "fish_config theme save --color-theme dark $FISH_THEME" \
    || die "saving the fish theme failed"
  did "fish theme $FISH_THEME saved (fish_variables)"
}

# Files in ~ that would block a link, as stow reports them in a simulation
stow_conflicts() {
  (cd "$DOT" && stow --simulate --restow --target="$HOME" . 2>&1) \
    | sed -n 's/.*existing target \(.*\) since neither a link nor a directory.*/\1/p;
              s/.*existing target is neither a link nor a directory: \(.*\)/\1/p;
              s/.*existing target is not owned by stow: \(.*\)/\1/p' \
    | sort -u
}

# Move the conflicting files into a dated backup folder, after asking (unless --yes)
move_conflicts_aside() {
  local conflicts=$1 backup answer f
  backup="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
  text "These files are in the way and would be moved to $backup:"
  detail "$conflicts"
  if [ $YES -eq 0 ] && [ $DRY -eq 0 ]; then
    printf '  Move them and continue? [y/N] '
    read -r answer </dev/tty
    case $answer in
      y | Y) ;;
      *) die "aborted: move the files yourself, or re-run with --yes" ;;
    esac
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    run mkdir -p "$backup/$(dirname "$f")"
    run mv "$HOME/$f" "$backup/$f"
  done <<EOF
$conflicts
EOF
  did "moved aside to $backup"
}

step_links() {
  has stow || die "stow is missing (the packages step installs it)"
  # These must be real directories, so stow links their contents, not the directories themselves
  run mkdir -p "$HOME/.config" "$HOME/.claude" "$HOME/.ssh"
  run chmod 700 "$HOME/.ssh"

  local conflicts planned
  conflicts="$(stow_conflicts)"
  [ -n "$conflicts" ] && move_conflicts_aside "$conflicts"

  planned="$(cd "$DOT" && stow --simulate --verbose=1 --target="$HOME" . 2>&1 | grep -v 'simulation mode' | grep -v '^$')"
  (cd "$DOT" && run stow --restow --target="$HOME" .) || die "stow failed"
  if [ -n "$planned" ]; then
    did "linked into ~ (stow --restow)"
  else
    ok "linked into ~ (stow --restow)"
  fi
}

# Offline install from a pinned clone: it only copies files. The bootstrap
# (conf.d/omf.fish) and .config/omf/* are already there from the links step.
install_omf() {
  if [ $DRY -eq 1 ]; then
    run git clone "$OMF_REPO" "@$(short "$OMF_COMMIT")"
    run "$FISH" bin/install --offline --noninteractive --yes --path="$OMF_PATH" --config="$OMF_CONFIG"
    return
  fi
  clone_pinned "$OMF_REPO" "$OMF_COMMIT" "$TMP/omf" || die "cloning Oh My Fish failed"
  quiet "$FISH" "$TMP/omf/bin/install" --offline="$TMP/omf" --noninteractive --yes \
    --path="$OMF_PATH" --config="$OMF_CONFIG" || die "Oh My Fish install failed"
  did "Oh My Fish installed to $OMF_PATH (pinned to $(short "$OMF_COMMIT"))"
}

step_omf() {
  [ -x "$FISH" ] || die "$FISH is missing (the packages step installs it)"
  if [ -f "$OMF_PATH/init.fish" ]; then
    ensure_pinned "Oh My Fish" "$OMF_REPO" "$OMF_COMMIT" "$OMF_PATH"
  else
    install_omf
  fi
  # Packages: pinned clones in omf's pkg/ folder (`omf install` would take the
  # latest commit). omf treats a folder there as installed. .config/omf/bundle
  # lists the same names, so `omf` itself agrees with what's installed.
  grep -qx "package foreign-env" "$DOT/.config/omf/bundle" || die "foreign-env is not in .config/omf/bundle"
  ensure_pinned "foreign-env" "$FENV_REPO" "$FENV_COMMIT" "$OMF_PATH/pkg/foreign-env"
}

step_tmux() {
  run mkdir -p "$TMUX_PLUGINS"
  ensure_pinned "tpm" "$TPM_REPO" "$TPM_COMMIT" "$TMUX_PLUGINS/tpm"
  # tpm reads the @plugin lines in tmux.conf and clones what's missing (catppuccin
  # at its tag); then the tag is enforced
  if [ $DRY -eq 1 ] || [ -x "$TMUX_PLUGINS/tpm/bin/install_plugins" ]; then
    quiet nocred "$TMUX_PLUGINS/tpm/bin/install_plugins" || die "tmux plugin install failed"
  fi
  if [ $DRY -eq 1 ] && [ ! -d "$TMUX_PLUGINS/tmux" ]; then
    info "catppuccin $(catppuccin_tag) would be installed"
    return
  fi
  ensure_tag "catppuccin/tmux" "$TMUX_PLUGINS/tmux" "$(catppuccin_tag)"
}

step_yazi() {
  has ya || die "ya is missing (the packages step installs yazi)"
  local before
  before="$(installed_yazi_rev)"
  quiet nocred ya pkg install || die "ya pkg install failed" # flavor pinned (rev + hash) in package.toml
  if [ "$before" = "$(yazi_rev)" ]; then
    ok "flavor installed (rev $(yazi_rev))"
  else
    did "flavor installed (rev $(yazi_rev))"
  fi
}

step_node() {
  run mkdir -p "$HOME/.nvm" # nvm's working directory (Homebrew's nvm doesn't create it)
  if ls "$HOME/.nvm/versions/node/"v* >/dev/null 2>&1; then
    ok "Node installed via nvm"
  else
    info "no Node yet: run \`nvm install --lts\` in a new shell (env.sh then puts it on PATH)"
  fi
}

step_hammerspoon() {
  if [ "$(defaults read org.hammerspoon.Hammerspoon MJConfigFile 2>/dev/null)" = "$HAMMERSPOON_CONFIG" ]; then
    ok "config path is $HAMMERSPOON_CONFIG"
  else
    run defaults write org.hammerspoon.Hammerspoon MJConfigFile "$HAMMERSPOON_CONFIG" || die "defaults write failed"
    did "config path set to $HAMMERSPOON_CONFIG"
  fi
  if pgrep -xq Hammerspoon; then
    ok "running"
  else
    run open -a Hammerspoon || die "could not start Hammerspoon (is the cask installed?)"
    did "started"
  fi
  build_color_sampler
}

# The color picker's helper: macOS's color sampler has no Hammerspoon binding
build_color_sampler() {
  if [ -x "$SAMPLER_BIN" ] && [ "$SAMPLER_BIN" -nt "$SAMPLER_SRC" ]; then
    ok "color sampler helper is up to date"
    return
  fi
  has swiftc || die "swiftc is missing (xcode-select --install)"
  quiet swiftc -O -o "$SAMPLER_BIN" "$SAMPLER_SRC" || die "compiling the color sampler helper failed"
  did "color sampler helper compiled (modules/colorpicker/sampler)"
}

NEW_LOCAL="" # local files created in this run, for the summary

# copy_template <template> <target>: create the local file from its template if missing
copy_template() {
  local template=$1 target=$2
  if [ -e "$target" ]; then
    ok "$target exists"
    return
  fi
  run mkdir -p "$(dirname "$target")"
  (umask 077 && run cp "$DOT/templates/$template" "$target") || die "could not create $target"
  NEW_LOCAL="$NEW_LOCAL $target"
  did "$target created from the template"
}

step_local() {
  copy_template git/config.local "$HOME/.config/git/config.local"
  copy_template ssh/config.local "$HOME/.ssh/config.local"
  copy_template shell/env.local.sh "$HOME/.config/shell/env.local.sh"
  copy_template hammerspoon/config.local.lua "$HOME/.config/hammerspoon/config.local.lua"
  copy_template claude/plugins.local.json "$HOME/.claude/plugins.local.json"
}

step_left_for_you() {
  info "Hammerspoon: allow it under System Settings → Privacy & Security → Accessibility"
  [ -n "$NEW_LOCAL" ] && info "fill in the new local files:$NEW_LOCAL"
  info "SSH keys (~/.ssh/config.local), Node (nvm install --lts), Python (pyenv install <version>)"
  info "open a new terminal window: it starts fish with this config"
}

# ── Main ──────────────────────────────────────────────────────

# step <name> <title> <function>: a titled step, skipped when named in --skip
step() {
  local name=$1 title=$2 fn=$3
  section "$title"
  case "$SKIP" in
    *",$name,"*) info "skipped" ;;
    *) "$fn" ;;
  esac
}

run_health_check() {
  printf '\n'
  if [ $VERBOSE -eq 1 ]; then
    bash "$DOT/health-check.sh" --verbose
  else
    bash "$DOT/health-check.sh"
  fi
}

main() {
  parse_options "$@"

  if [ $PINS -eq 1 ]; then
    printf '%sdotfiles pins%s  %s(%s)%s\n' "$C_BLUE" "$C_RESET" "$C_DIM" "$DOT" "$C_RESET"
    report_pins
    exit 0
  fi

  printf '%sdotfiles setup%s  %s(%s)%s\n' "$C_BLUE" "$C_RESET" "$C_DIM" "$DOT" "$C_RESET"
  [ $DRY -eq 1 ] && info "dry run: nothing is changed"

  section "Prerequisites"; step_prerequisites
  step packages    "Packages (Brewfile)"                step_packages
  step shell       "Login shell"                        step_shell
  step links       "Links (stow)"                       step_links
  step omf         "Oh My Fish"                         step_omf
  step tmux        "tmux plugins"                       step_tmux
  step yazi        "yazi"                               step_yazi
  step node        "Node (nvm)"                         step_node
  step hammerspoon "Hammerspoon"                        step_hammerspoon
  step local       "Machine-specific files (templates/)" step_local

  if [ $VERBOSE -eq 1 ] || [ $CHANGES -gt 0 ]; then
    section "Left for you"; step_left_for_you
  elif [ $DRY -eq 0 ]; then
    section "Nothing to do"; info "everything is already in place"
  fi

  case "$SKIP" in
    *",check,"*) ;;
    *) if [ $DRY -eq 0 ]; then run_health_check; fi ;;
  esac
}

main "$@"
