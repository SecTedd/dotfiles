#!/usr/bin/env bash
# macos.sh: sets the macOS preferences this setup expects. The last step of setup.sh;
# safe to run twice (a value already set is left alone, nothing restarts for it).
#
#   ./macos.sh            apply; exit status 1 when a value could not be written
#   ./macos.sh --check    report only, change nothing; exit status 1 when a value differs
#                         (health-check.sh and setup.sh run this)
#   ./macos.sh --save     read the nested values off this Mac into macos/, change nothing else
#   ./macos.sh --dry-run  print the commands instead of running them
#   ./macos.sh --verbose  also print what was already fine
#
# Single values are one `defaults` line each. Nested ones (the system keyboard shortcuts,
# the keyboard layouts) are kept whole, one file per key in macos/: change them in System
# Settings, run --save, commit. The health check warns while the Mac and the files differ.
#
# Most values apply at the next login, the menu bar spacing included; nothing here logs
# you out. Dock and Finder are restarted when one of their values changed (Finder windows
# close), so theirs apply at once. The screen zoom lines write com.apple.universalaccess,
# which macOS allows only from a terminal with Full Disk Access (System Settings → Privacy
# & Security): without it they are reported and the rest still runs.
#
# Adapted from https://github.com/scorphus/scorphiles (macos.sh) by Pablo Aguiar.
# Apache License 2.0, full text in LICENSES/scorphiles-Apache-2.0.txt.
# Changes: the preferences chosen for this setup, every value is read before it is
# written, --check and --dry-run, lib/common.sh output, no sudo. macOS /bin/bash 3.2.

set -u

DOT="$(cd "$(dirname "$0")" && pwd -P)"
. "$DOT/lib/common.sh"
NESTED_DIR="$DOT/macos"

# Nested values kept whole: <domain> <key>, one macos/<key>.plist each
NESTED="com.apple.symbolichotkeys AppleSymbolicHotKeys
com.apple.HIToolbox AppleEnabledInputSources"

MODE=apply
for option in "$@"; do
  case $option in
    --check) MODE=check ;;
    --save) MODE=save ;;
    --dry-run) MODE=dry ;;
    --verbose) VERBOSE=1 ;;
    -h | --help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown option: %s (try --help)\n' "$option"; exit 2 ;;
  esac
done

RESTART="" # programs whose values changed, restarted at the end

# ── Single values ─────────────────────────────────────────────

# What `defaults read` prints for a value written with this type
stored() {
  case "$1 $2" in
    "-bool true") echo 1 ;;
    "-bool false") echo 0 ;;
    *) echo "$2" ;;
  esac
}

restart_for() {
  case $1 in
    com.apple.dock) RESTART="$RESTART Dock" ;;
    com.apple.finder) RESTART="$RESTART Finder" ;;
  esac
}

# set_value <scope> <domain> <key> <type> <value> <what>: write one value unless it is
# already set; scope is "" or -currentHost (a value kept per Mac)
set_value() {
  local scope=$1 domain=$2 key=$3 type=$4 value=$5 what=$6 current
  current="$(defaults $scope read "$domain" "$key" 2>/dev/null)"
  if [ "$current" = "$(stored "$type" "$value")" ]; then
    ok "$what"
    return
  fi
  case $MODE in
    check) fail "$what: is ${current:-unset}" ;;
    dry) text "$C_DIM\$ defaults ${scope:+$scope }write $domain $key $type $value$C_RESET" ;;
    apply)
      if defaults $scope write "$domain" "$key" "$type" "$value" 2>/dev/null; then
        did "$what"
        restart_for "$domain"
      else
        warn "$what: could not write $domain (Full Disk Access for this terminal?)"
      fi ;;
  esac
}

pref() { set_value "" "$@"; }
hostpref() { set_value -currentHost "$@"; }

set_values() {
  pref -g KeyRepeat -int 2 "keyboard: fastest key repeat"
  pref -g InitialKeyRepeat -int 15 "keyboard: shortest delay before the repeat"
  pref -g AppleKeyboardUIMode -int 2 "keyboard: Tab moves through all controls, not only text boxes and lists"

  pref com.apple.AppleMultitouchTrackpad Clicking -bool true "trackpad: tap to click"
  hostpref -g com.apple.mouse.tapBehavior -int 1 "trackpad: tap to click (per Mac)"

  pref com.apple.universalaccess closeViewScrollWheelToggle -bool true "screen zoom: scrolling with a modifier key zooms"
  pref com.apple.AppleMultitouchTrackpad HIDScrollZoomModifierMask -int 262144 "screen zoom: the modifier is Ctrl"

  pref -g AppleInterfaceStyle -string Dark "appearance: dark mode"
  pref -g AppleIconAppearanceTheme -string RegularDark "appearance: dark app icons"

  pref com.apple.dock autohide -bool true "Dock: hidden until the pointer reaches it"
  pref com.apple.dock appswitcher-all-displays -bool true "Dock: ⌘Tab on every display"
  local corner
  for corner in tl tr bl br; do
    pref com.apple.dock "wvous-$corner-corner" -int 1 "Dock: hot corner $corner off"
    pref com.apple.dock "wvous-$corner-modifier" -int 0 "Dock: hot corner $corner needs no modifier"
  done
  pref com.apple.WindowManager EnableTiledWindowMargins -bool false "windows: tiled windows touch each other and the edges"

  hostpref -g NSStatusItemSpacing -int 0 "menu bar: items packed tight (per Mac)"
  hostpref -g NSStatusItemSelectionPadding -int 0 "menu bar: no padding around a selected item (per Mac)"

  pref com.apple.finder ShowPathbar -bool true "Finder: path bar"
  pref com.apple.finder ShowStatusBar -bool true "Finder: status bar"
}

# ── Nested values ─────────────────────────────────────────────

# The live value of a nested key as plist XML, the form --save stores
live_plist() { defaults export "$1" - | plutil -extract "$2" xml1 -o - -; }

save_nested() {
  local domain=$1 key=$2 file="$NESTED_DIR/$2.plist"
  mkdir -p "$NESTED_DIR"
  if live_plist "$domain" "$key" >"$file"; then
    did "$key saved to macos/$key.plist"
  else
    rm -f "$file"
    fail "$key could not be read from $domain"
  fi
}

set_nested() {
  local domain=$1 key=$2 file="$NESTED_DIR/$2.plist"
  if [ ! -f "$file" ]; then
    warn "macos/$key.plist missing (./macos.sh --save writes it)"
    return
  fi
  if live_plist "$domain" "$key" | cmp -s - "$file"; then
    ok "$key as in macos/$key.plist"
    return
  fi
  case $MODE in
    check) warn "$key differs from macos/$key.plist (changed in System Settings? ./macos.sh --save; or ./macos.sh applies the file)" ;;
    dry) text "$C_DIM\$ defaults write $domain $key <macos/$key.plist$C_RESET" ;;
    apply)
      if defaults write "$domain" "$key" "$(cat "$file")" 2>/dev/null; then
        did "$key applied from macos/$key.plist"
      else
        warn "$key: could not write $domain"
      fi ;;
  esac
}

for_each_nested() {
  local domain key
  while read -r domain key; do "$1" "$domain" "$key"; done <<<"$NESTED"
}

# ── Main ──────────────────────────────────────────────────────

restart_changed() {
  local program
  for program in $(printf '%s\n' $RESTART | sort -u); do
    killall "$program" 2>/dev/null && did "$program restarted"
  done
}

set_all() {
  [ $MODE = dry ] && info "dry run: nothing is changed"
  set_values
  for_each_nested set_nested
  [ $MODE = apply ] || return 0
  restart_changed
  if [ "$CHANGES" -gt 0 ]; then info "most of these apply at the next login (nothing here logs you out)"; fi
}

main() {
  if [ $MODE = save ]; then for_each_nested save_nested; else set_all; fi
  [ "$FAILS" -eq 0 ] && [ "$WARNS" -eq 0 ]
}

main
