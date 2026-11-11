-- ⌃⌥⌘ H / L: previous / next tab in the frontmost app (Chrome, Finder, ...)
-- by sending the standard ⌃⇧Tab / ⌃Tab. Hold to keep switching.

local shortcuts = require("core.shortcuts")

local M = { hotkeys = {} }

local mods = { "ctrl", "alt", "cmd" }

local function switchTab(shortcut)
  return function()
    hs.eventtap.keyStroke(shortcut, "tab", 10000) -- 10 ms key press
  end
end

local previousTab = switchTab({ "ctrl", "shift" })
local nextTab = switchTab({ "ctrl" })

-- bind(mods, key, group, description, pressed, released, repeat)
M.hotkeys.h = shortcuts.bind(mods, "h", "Tabs", "Previous tab (hold to repeat)", previousTab, nil, previousTab)
M.hotkeys.l = shortcuts.bind(mods, "l", "Tabs", "Next tab (hold to repeat)", nextTab, nil, nextTab)

return M
