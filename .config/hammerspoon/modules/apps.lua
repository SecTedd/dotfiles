-- ⌃⌥⌘ + letter: bring an app to the front (launching it if needed). Pressing
-- again while it's in front cycles through its windows, and once every window
-- has been shown, hides the app. An app with one window: focus, then hide.
-- The cycle always runs in the same order: top to bottom, then left to right.
-- An app that isn't installed shows a box.
--
-- The core apps below are the same on every Mac. config.local.lua adds or
-- removes apps for one Mac (section "apps", see core/machine.lua):
--   apps = { s = { id = "com.tinyspeck.slackmacgap", name = "Slack" }, m = false }
--
-- Everything happens on the key press (no watchers, no timers): the windows
-- are listed when you press, and the cycle state is one small table.

local ui = require("core.ui")
local machine = require("core.machine")
local shortcuts = require("core.shortcuts")

local M = { hotkeys = {}, apps = {} }

local mods = { "ctrl", "alt", "cmd" }

local core = {
  t = { id = "com.mitchellh.ghostty", name = "Ghostty" },
  b = { id = "com.google.Chrome", name = "Chrome" },
  m = { id = "com.spotify.client", name = "Spotify" },
  f = { id = "com.apple.finder", name = "Finder" },
}

for key, app in pairs(core) do M.apps[key] = app end
for key, app in pairs(machine.get("apps")) do
  if app == false then
    M.apps[key] = nil
  elseif type(app) == "table" and app.id and app.name then
    M.apps[key] = app
  else
    print("config.local.lua: apps." .. tostring(key) .. " needs { id = ..., name = ... } or false")
  end
end

---------------------------------------------------------------------------
-- Window cycle

-- The cycle in progress: which app, which of its windows were shown, which one
-- we focused last (so a window you picked yourself restarts the cycle)
local cycle = nil

-- The app's windows worth cycling: standard, not minimized, sorted top to
-- bottom then left to right, so the order is predictable across monitors.
-- While an app is hidden, macOS reports its windows as dialogs instead of
-- standard windows, so then every real window (role AXWindow) counts.
local function cycleWindows(app)
  local hidden = app:isHidden()
  local windows = {}
  for _, w in ipairs(app:allWindows()) do
    if w:role() == "AXWindow" and not w:isMinimized() and (hidden or w:isStandard()) then
      windows[#windows + 1] = w
    end
  end
  table.sort(windows, function(a, b)
    local fa, fb = a:frame(), b:frame()
    if fa.y ~= fb.y then return fa.y < fb.y end
    if fa.x ~= fb.x then return fa.x < fb.x end
    return a:id() < b:id()
  end)
  return windows
end

-- The next window after `current` (wrapping) that hasn't been shown in this cycle
local function nextUnshown(windows, current, shown)
  local n = #windows
  local start = 1
  for i, w in ipairs(windows) do
    if current and w:id() == current:id() then start = i; break end
  end
  for step = 1, n do
    local w = windows[(start - 1 + step) % n + 1]
    if not shown[w:id()] then return w end
  end
  return nil
end

local function press(app)
  local running = hs.application.get(app.id)
  if not running or not running:isFrontmost() then
    cycle = nil
    local windows = running and cycleWindows(running) or {}
    if #windows > 1 then
      -- Start the cycle at the first window (top/left), not at the one macOS
      -- would pick (the last used), so the order is the same every time
      if running:isHidden() then running:unhide() end
      windows[1]:focus()
      cycle = { app = app.id, shown = { [windows[1]:id()] = true }, last = windows[1]:id() }
    elseif not hs.application.launchOrFocusByBundleID(app.id) then
      ui.flash(app.name .. " is not installed")
    end
    return
  end

  local windows = cycleWindows(running)
  if #windows <= 1 then
    cycle = nil
    running:hide()
    return
  end

  local focused = hs.window.focusedWindow()
  local focusedId = focused and focused:id()
  -- A fresh cycle: another app, or you focused a window yourself since the last press
  if not cycle or cycle.app ~= app.id or cycle.last ~= focusedId then
    cycle = { app = app.id, shown = { [focusedId or -1] = true }, last = focusedId }
  end

  local nextWindow = nextUnshown(windows, focused, cycle.shown)
  if nextWindow then
    nextWindow:focus()
    cycle.shown[nextWindow:id()] = true
    cycle.last = nextWindow:id()
  else
    cycle = nil
    running:hide()
  end
end

---------------------------------------------------------------------------
-- Hotkeys (sorted, so the panel lists the apps in a stable order)

local keys = {}
for key in pairs(M.apps) do keys[#keys + 1] = key end
table.sort(keys)
for _, key in ipairs(keys) do
  local app = M.apps[key]
  M.hotkeys[key] = shortcuts.bind(mods, key, "Apps", app.name .. ": focus, cycle windows, then hide",
    function() press(app) end)
end

return M
