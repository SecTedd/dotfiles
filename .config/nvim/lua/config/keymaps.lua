-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Exit insert mode with jk
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Ctrl-hjkl: nvim windows and tmux panes alike (lua/config/tmux_navigate.lua)
for key, side in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  map("n", "<C-" .. key .. ">", function() require("config.tmux_navigate").go(key) end, { desc = "Window / tmux pane " .. side })
end

-- Keyboard scrolling (Hammerspoon ⌃⌥⌘ J/K, see ~/.config/hammerspoon/modules/scroll.lua) sends
-- Alt+wheel: scroll the current window by 3 lines, not the one under the mouse.
-- The real mouse wheel is unchanged.
map({ "n", "v", "i" }, "<M-ScrollWheelUp>", "<Cmd>normal! 3<C-y><CR>", { desc = "Scroll current window up" })
map({ "n", "v", "i" }, "<M-ScrollWheelDown>", "<Cmd>normal! 3<C-e><CR>", { desc = "Scroll current window down" })
