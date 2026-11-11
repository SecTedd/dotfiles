-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
-- :ClaudePrompt / :ClaudeTarget, from the start so `nvim +ClaudePrompt` works
require("config.claude_prompt").setup()
