# Emergency fallback only: the everyday shell is fish (~/.config/fish).
# Environment (PATH, EDITOR, nvm, ...) comes from ~/.config/shell/env.sh via ~/.zshenv.

# Normal (emacs) line editing; zsh would pick vi mode because EDITOR=nvim
bindkey -e

autoload -Uz compinit && compinit -d "$HOME/.cache/zsh/zcompdump"

PROMPT='%F{blue}%~%f %(?.%F{green}.%F{red})❯%f '
