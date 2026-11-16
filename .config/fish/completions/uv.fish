# uv's own completions, generated the first time Tab follows `uv` (fish loads
# this file only then). The standalone installer ships none; Homebrew's did.
command -q uv; and uv generate-shell-completion fish | source
