-- Chrome-only shortcuts, active only while Chrome is in front
-- (in other apps these keys pass through untouched):
--   ⌃⌥⌘ O / I   back / forward in history (like Ctrl-O / Ctrl-I in vim)
-- Uses Chrome's own menu commands, so it also works while typing in a text field.

local shortcuts = require("core.shortcuts")

local M = { hotkeys = {} }

local CHROME = "com.google.Chrome"

local mods = { "ctrl", "alt", "cmd" }

local function menu(path)
  return function()
    local app = hs.application.get(CHROME)
    if app then app:selectMenuItem(path) end
  end
end

-- shortcuts.new: registered for the panel, enabled only while Chrome is in front
M.hotkeys.o = shortcuts.new(mods, "o", "Chrome", "Chrome: back in history", menu({ "History", "Back" }))
M.hotkeys.i = shortcuts.new(mods, "i", "Chrome", "Chrome: forward in history", menu({ "History", "Forward" }))

local function setEnabled(on)
  for _, hotkey in pairs(M.hotkeys) do
    if on then hotkey:enable() else hotkey:disable() end
  end
end

local function isChrome(app)
  return app ~= nil and app:bundleID() == CHROME
end

M.watcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated then
    setEnabled(isChrome(app))
  end
end)
M.watcher:start()

setEnabled(isChrome(hs.application.frontmostApplication()))

return M
