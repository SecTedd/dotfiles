# lib/common.sh: helpers shared by setup.sh and health-check.sh.
# Source it, don't run it. macOS /bin/bash 3.2 compatible.

# Colors only on a terminal
if [ -t 1 ]; then
  C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_BLUE=$'\033[1;34m' C_DIM=$'\033[2m' C_RESET=$'\033[0m'
else
  C_GREEN='' C_YELLOW='' C_RED='' C_BLUE='' C_DIM='' C_RESET=''
fi

nerd_font_installed() {
  local f
  for f in "$HOME"/Library/Fonts/*NerdFont* /Library/Fonts/*NerdFont*; do
    [ -e "$f" ] && return 0
  done
  return 1
}
if nerd_font_installed; then INFO_GLYPH=$'\xf3\xb0\x8b\xbd'; else INFO_GLYPH=i; fi # nf-md-information_outline

VERBOSE=0
PASS=0
WARNS=0
FAILS=0
CHANGES=0
SECTION_PENDING=""

section() {
  if [ "$VERBOSE" -eq 1 ]; then
    printf '\n%s%s%s\n' "$C_BLUE" "$1" "$C_RESET"
  else
    SECTION_PENDING=$1
  fi
}

flush_section() {
  [ -n "$SECTION_PENDING" ] || return 0
  printf '\n%s%s%s\n' "$C_BLUE" "$SECTION_PENDING" "$C_RESET"
  SECTION_PENDING=""
}

text() { flush_section; printf '  %s\n' "$1"; }
line() { text "$1$2$C_RESET $3"; }

ok()      { PASS=$((PASS + 1)); if [ "$VERBOSE" -eq 1 ]; then line "$C_GREEN" "✓" "$1"; fi; }
did()     { CHANGES=$((CHANGES + 1)); line "$C_GREEN" "✓" "$1"; }
warn()    { WARNS=$((WARNS + 1)); line "$C_YELLOW" "!" "$1"; }
fail()    { FAILS=$((FAILS + 1)); line "$C_RED" "✘" "$1"; }
info()    { text "$C_DIM$INFO_GLYPH $1$C_RESET"; }
detail()  { flush_section; printf '%s' "$1" | sed "s/^/      ${C_DIM}/;s/\$/${C_RESET}/"; printf '\n'; }
summary() { printf '\n%s%d passed%s, %s%d warnings%s, %s%d failed%s\n' "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARNS" "$C_RESET" "$C_RED" "$FAILS" "$C_RESET"; }

has() { command -v "$1" >/dev/null 2>&1; }

# check <description> <command...>: ok if the command succeeds, fail otherwise
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi; }

# Run a command with a hard timeout in seconds (macOS has no `timeout`)
with_timeout() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

# Keeps vX.Y.Z tags, drops floating ones like v2 or latest
version_tags() { grep -E '^v[0-9]+(\.[0-9]+){2}$'; }
