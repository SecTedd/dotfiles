-- Ctrl-hjkl between nvim windows and tmux panes, nvim's half (tmux.conf has the
-- other: a format test on the pane's program decides who gets the key). A key
-- at the editor's edge goes to tmux as select-pane, anywhere else it is wincmd.
-- Inspired by christoomey/vim-tmux-navigator (MIT). Our own because that plugin
-- asks "still the same window?" after wincmd, which misreads floating windows
-- (snacks' explorer sidebar): wincmd always leaves a float, so it never reaches tmux.

local M = {}

local PANE = { h = "-L", j = "-D", k = "-U", l = "-R" }

local function floating()
  return vim.api.nvim_win_get_config(0).relative ~= ""
end

-- The window touches the editor's edge on that side (a float's border counts)
local function at_edge(key)
  local row, col = unpack(vim.fn.win_screenpos(0))
  local config = vim.api.nvim_win_get_config(0)
  local border = (config.border and config.border ~= "none") and 1 or 0
  local top = vim.o.showtabline == 2 and 2 or 1
  local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  if key == "h" then return col - border <= 1 end
  if key == "l" then return col + vim.fn.winwidth(0) + border > vim.o.columns end
  if key == "k" then return row - border <= top end
  return row + vim.fn.winheight(0) + border > bottom
end

local function tmux_pane(key)
  if vim.env.TMUX then vim.system({ "tmux", "select-pane", PANE[key] }) end
end

function M.go(key)
  if floating() and at_edge(key) then return tmux_pane(key) end
  local before = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(key)
  if vim.api.nvim_get_current_win() == before then tmux_pane(key) end
end

return M
