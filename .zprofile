# Login shells: macOS's /etc/zprofile (path_helper) runs after ~/.zshenv and
# moves system paths in front of Homebrew; loading env.sh again restores the order.
. "$HOME/.config/shell/env.sh"
