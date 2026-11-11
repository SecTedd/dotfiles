-- Claude Code prompts written in nvim. `ask` (fish) opens nvim with `:ClaudePrompt %<pane>`
-- for the session picked in the tmux menu; `:ClaudePrompt` alone shows that menu from
-- nvim, and claude-menu.sh --pick reports the choice with
-- `nvim --server … --remote-expr "v:lua.ClaudePromptPicked(3)"` for pane %3.
-- @claude_peer on the two panes is read by tmux.conf's pane-focus hooks.

local M = {}

local MENU = vim.fn.expand("~/.claude/claude-menu.sh")
local TMUX_BUFFER = "claude-prompt"

local peered_buffer
local menu_callback

local function tmux(args)
  local result = vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
  if result.code ~= 0 then return nil, vim.trim(result.stderr or "") end
  return vim.trim(result.stdout or "")
end

local function pane_of(buf)
  return vim.b[buf].claude_pane
end

local function is_prompt(buf)
  return vim.b[buf].claude_prompt == true
end

-- Bracketed paste (-p): newlines stay in the prompt instead of submitting it
local function send_text(text, pane)
  local _, err = tmux({ "set-buffer", "-b", TMUX_BUFFER, "--", text })
  if not err then _, err = tmux({ "paste-buffer", "-p", "-d", "-b", TMUX_BUFFER, "-t", pane }) end
  if err then return vim.notify("Claude prompt: " .. err, vim.log.levels.ERROR) end
  tmux({ "select-pane", "-t", pane })
end

local function send_buffer(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  send_text(table.concat(lines, "\n"), pane_of(buf))
end

-- The Claude pane comes first: tmux stops at the first failing command, so a vanished
-- Claude pane leaves nothing behind and the error names it. The hooks fire on focus
-- changes only, so a pane that already has the focus lights the Claude pane here
local function connect(buf)
  local pane, mine = pane_of(buf), vim.env.TMUX_PANE
  if not mine then return end
  local _, err = tmux({
    "set", "-p", "-t", pane, "@claude_peer", mine, ";",
    "set", "-p", "-t", mine, "@claude_peer", pane, ";",
    "if", "-F", "-t", mine, "#{pane_active}", "set -pF -t " .. pane .. " window-style '#{window-active-style}'",
  })
  if err then return vim.notify("Claude prompt: " .. err, vim.log.levels.WARN) end
  peered_buffer = buf
end

-- One call per pane, because either pane may be gone by now
local function release(pane)
  tmux({ "set", "-pu", "-t", pane, "@claude_peer", ";", "set", "-pu", "-t", pane, "window-style" })
end

local function disconnect(buf)
  if peered_buffer ~= buf then return end
  peered_buffer = nil
  release(pane_of(buf))
  release(vim.env.TMUX_PANE)
end

-- BufWriteCmd leaves 'modified' to the handler
local function send_on_write(buf)
  send_buffer(buf)
  if is_prompt(buf) then vim.bo[buf].modified = false end
end

local function write_event(buf)
  if is_prompt(buf) then return "BufWriteCmd" end
  return "BufWritePost"
end

local function hooks(buf)
  local group = vim.api.nvim_create_augroup("claude_prompt_" .. buf, {})
  local function on(event, callback)
    vim.api.nvim_create_autocmd(event, { group = group, buffer = buf, callback = callback })
  end
  on(write_event(buf), function() send_on_write(buf) end)
  on("BufEnter", function() connect(buf) end)
  on("BufLeave", function() disconnect(buf) end)
end

local function aim(buf, pane)
  disconnect(buf)
  vim.b[buf].claude_pane = pane
  if not vim.b[buf].claude_prompt_hooked then
    vim.b[buf].claude_prompt_hooked = true
    hooks(buf)
  end
  if vim.api.nvim_get_current_buf() == buf then connect(buf) end
end

-- :enew reuses nvim's empty startup buffer, so `ask` opens with a single buffer.
-- No file and no filetype: nothing lints, formats or spell-checks a prompt
local function prompt_buffer(pane)
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, string.format("claude prompt %s #%d", pane, buf))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.b[buf].claude_prompt = true
  aim(buf, pane)
  vim.cmd.startinsert()
end

local function prompt_for(pane)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and is_prompt(buf) and pane_of(buf) == pane then return buf end
  end
end

local function show(buf)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then return vim.api.nvim_set_current_win(win) end
  vim.api.nvim_set_current_buf(buf)
end

local function open_for(pane)
  local buf = prompt_for(pane)
  if buf then return show(buf) end
  prompt_buffer(pane)
end

-- --remote-expr prints the expression's value; an empty string keeps the menu script quiet
function M.picked(number)
  local callback = menu_callback
  menu_callback = nil
  if callback then vim.schedule(function() callback("%" .. tostring(number)) end) end
  return ""
end

local function menu(callback)
  if not vim.env.TMUX_PANE then return vim.notify("Not inside tmux", vim.log.levels.WARN) end
  menu_callback = callback
  vim.system({ "bash", MENU, "--pick", vim.v.servername, vim.env.TMUX_PANE })
end

function M.open(pane)
  if pane then return open_for(pane) end
  menu(open_for)
end

function M.target()
  local buf = vim.api.nvim_get_current_buf()
  menu(function(pane) aim(buf, pane) end)
end

local function unpeer()
  if peered_buffer then disconnect(peered_buffer) end
end

local function open_command(opts)
  if opts.args == "" then return M.open() end
  M.open(opts.args)
end

function M.setup()
  _G.ClaudePromptPicked = M.picked
  vim.api.nvim_create_user_command("ClaudePrompt", open_command,
    { nargs = "?", desc = "Write a prompt for a Claude in this tmux window (menu, or the given pane)" })
  vim.api.nvim_create_user_command("ClaudeTarget", M.target, { desc = "Send this buffer to a Claude on every write" })
  vim.api.nvim_create_autocmd("VimLeavePre", { callback = unpeer })
end

return M
