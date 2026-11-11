-- On-screen boxes in Catppuccin Mocha style, shared by all modules. Three
-- durations, so boxes feel consistent:
--   ui.flash(text)   1 s   short feedback ("Copied: gdf", "tmux.conf reloaded")
--   ui.alert(text)   4 s   something to notice (Claude finished / needs input)
--   ui.error(text)   8 s   a config problem, needs reading (module failed to load)
--   ui.box(text, seconds)  any other duration
--   ⌃⌥⌘X             close all boxes
--
-- Scripts show a flash via a URL event (text URL-encoded, at most 200 characters):
--   open -g "hammerspoon://flash?text=tmux.conf%20reloaded"      (tmux.conf)

local shortcuts = require("core.shortcuts")

local M = {}

M.seconds = { flash = 1, alert = 4, error = 8 }

M.style = {
  textFont = "RobotoMono Nerd Font",
  textSize = 20,
  textColor = { hex = "#cdd6f4" },
  fillColor = { hex = "#1e1e2e", alpha = 0.95 },
  strokeColor = { hex = "#cba6f7" },
  strokeWidth = 2,
  radius = 12,
}

function M.box(text, seconds)
  hs.alert.show(text, M.style, hs.screen.mainScreen(), seconds or M.seconds.alert)
end

function M.flash(text) M.box(text, M.seconds.flash) end
function M.alert(text) M.box(text, M.seconds.alert) end
function M.error(text) M.box(text, M.seconds.error) end

M.closeHotkey = shortcuts.bind({ "ctrl", "alt", "cmd" }, "x", "General", "Close all boxes", hs.alert.closeAll)

hs.urlevent.bind("flash", function(_, params)
  local text = params and params.text
  if text and text ~= "" then M.flash(text:sub(1, 200)) end
end)

return M
