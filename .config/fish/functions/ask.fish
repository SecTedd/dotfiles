# `ask [pane]`: write a Claude Code prompt in nvim. Without a pane the Claude
# session menu of this tmux window picks one (choosing an entry types `ask %<pane>`
# here, a single session needs no menu). In nvim, :w pastes the buffer into that
# Claude's prompt line and focuses its pane; you press Enter there.
# See nvim's lua/config/claude_prompt.lua.
function ask -d "Write a prompt for a Claude in this tmux window"
    set -l pane $argv[1]
    if test -z "$pane"
        set pane (bash ~/.claude/claude-menu.sh --choose $TMUX_PANE)
    end
    test -n "$pane"; or return 0
    nvim +"ClaudePrompt $pane"
end
