# Homebrew packages the config in this repo needs, nothing else.
# Install: brew bundle --file ~/dotfiles/Brewfile
# (jq, used by the Claude Code scripts, ships with macOS)

# Shell
brew "fish"             # login shell
brew "stow"             # links this repo into ~
brew "nvm"              # Node versions (env.sh, fish functions/nvm.fish)
brew "pyenv"            # Python versions (env.sh, prompt)

# Terminal tools
brew "tmux"
brew "neovim"
brew "tree-sitter-cli"  # nvim-treesitter (main branch) builds parsers with it
brew "lazygit"
brew "git-delta"        # git/lazygit pager
brew "mergiraf"         # git merge driver (.config/git/attributes)

# CLI tools used by the fish config
brew "bat"              # cat with syntax highlighting, fzf previews
brew "eza"              # ls
brew "fd"               # fzf file finder
brew "fzf"              # Ctrl-R / Ctrl-T / Alt-C
brew "ripgrep"
brew "zoxide"           # z / zi

# yazi file manager + preview helpers (official list, minus jq/fonts)
brew "yazi"
brew "ffmpeg-full", link: :overwrite      # video thumbnails (keg-only: linked as in the yazi docs)
brew "imagemagick-full", link: :overwrite # HEIC, JPEG XL, font previews (keg-only: linked)
brew "poppler"          # PDF previews
brew "resvg"            # SVG previews
brew "sevenzip"         # archive previews

# Apps
cask "ghostty"
cask "hammerspoon"

# Font used by Ghostty, the fish prompt icons and Hammerspoon alerts
cask "font-roboto-mono-nerd-font"
