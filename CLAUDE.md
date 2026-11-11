# dotfiles: rules for this repo

- The folder mirrors `~`, GNU Stow links it. Scripts, `lib/`, `templates/`, `README.md`,
  `LICENSE`, `LICENSES/`, `Brewfile` and this file stay unlinked (`.stow-local-ignore`).
- Nothing in the repo is tied to one Mac or one job: identity, hosts, work paths and Claude
  plugins live in git-ignored local files with templates in `templates/`. The scripts know no
  git provider.
- `bash ~/dotfiles/health-check.sh` is the verification. Every feature gets its checks there,
  and the check stays read-only (throwaway tmux server, temp dir, nothing in the repo changes).
- Pins are the source of truth: every download is pinned to a commit or tag from the official
  repo. A bump means reading the upstream changes first.
- Hammerspoon: saving a `.lua` file reloads the config. Ask it something only with a hard
  timeout: `perl -e 'alarm 10; exec @ARGV' hs -t 3 -c '...' </dev/null`. Never move, resize or
  focus my windows in a test; geometry is tested as pure functions.
- tmux: test servers only with their own socket (`tmux -L name`), never the running one, never
  `tmux kill-server`.
- Nothing polls: no timers, no watchers while a mode is off. Event-driven only.
- Every hotkey goes through `core/shortcuts.lua` with a group and a description; every tmux
  binding carries `-N "note"`. The panel lists both.
- The config should be as efficient as possible to not slow down the machine. Also the config
  must not leak anything, s.t. it does NOT get slower while using it.
- Boxes: `<icon> <text>: ON/OFF` for toggles, descriptions up to 45 characters. Colors only
  from the Catppuccin Mocha palette, Nerd Font glyphs by codepoint.
- Shortcuts are proposed for a German ISO keyboard.
- Claude Code: `settings.json` is shared, plugins are per Mac. The guard (`guard-ask`,
  `guard-deny`), read-only mode (`readonly-allow`, `readonly-deny`) and the sandbox are the
  safety net; a change to one is mirrored in the health check and the README.
