## My Neovim config

A personal Neovim setup, based on the LazyVim starter template and customized for daily use across Rust, Python, JavaScript/TypeScript, C/C++/CMake, SQL, TOML, JSON, and Markdown.

### Stack

- **Distribution:** LazyVim (Apache 2.0) — provides the base plugin set, sensible defaults, and language extras.
- **Plugin manager:** lazy.nvim.
- **Terminal:** Tested with Ghostty.
- **Theme:** Catppuccin Mocha.
- **Languages enabled:** Clangd/CMake, JSON, Markdown, Python, Rust, SQL, Tailwind, TOML, TypeScript (vtsls), plus prettier, ESLint, and the test/dap extras.

### Custom changes on top of the starter

- `jk` exits insert mode.
- Legacy provider warnings silenced (`perl`, `ruby`, `node`, `python3` providers disabled).
- `lazy.nvim` luarocks subsystem disabled (no plugins require it).
- `:ClaudePrompt` / `:ClaudeTarget` (`lua/config/claude_prompt.lua`): write a Claude Code prompt
  here, one file-less buffer per Claude session of the current tmux window; `:w` pastes it
  into that Claude's pane.
- `Ctrl-hjkl` across windows and tmux panes (`lua/config/tmux_navigate.lua`, inspired by
  vim-tmux-navigator; also right from floating windows such as the explorer sidebar).

### Install

Part of the dotfiles repo: `setup.sh` links `~/.config/nvim` to this folder and the Brewfile
brings Neovim ≥ 0.11. Launch `nvim` once; lazy.nvim bootstraps itself and installs the plugins
at the commits in `lazy-lock.json`.

### Credits

Built on the LazyVim starter template, Apache License 2.0. The original `LICENSE` file is
preserved in this folder per the terms of that license.
