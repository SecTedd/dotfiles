-- ⌃⌥ + key: window management for the focused window
-- (⌃⌥ = windows layer; ⌃⌥⌘ = apps and general: apps, tabs, scroll, chrome, claude)
--   Enter   maximize (fill the screen, not macOS full screen); again = restore
--   → / ←   move to the next / previous monitor (keeps relative size + position)
--   H / L   left / right half of the screen
--   U I     top-left / top-right quarter      (the U I / J K block mirrors
--   J K     bottom-left / bottom-right quarter  the screen)
--   C       center on the screen (keeps size)
--   + / -   a step larger / smaller, centered (the sizes: windows/steps.lua)

local shortcuts = require("core.shortcuts")
local steps = require("modules.windows.steps")

local M = { hotkeys = {}, actions = {} }

local mods = { "ctrl", "alt" }

hs.window.animationDuration = 0 -- snap instantly, no resize animation
local STEP_SECONDS = 0.2 -- the size steps grow and shrink smoothly instead

-- Window id -> size/position before maximizing, relative to its screen, so
-- restoring works on whatever monitor the window is on now
local beforeMaximize = {}

-- Some apps (e.g. Ghostty) resize in steps, so "maximized" is never pixel-exact
local function nearlyEqual(a, b)
  local tolerance = 50
  return math.abs(a.x - b.x) < tolerance and math.abs(a.y - b.y) < tolerance
     and math.abs(a.w - b.w) < tolerance and math.abs(a.h - b.h) < tolerance
end

function M.actions.toggleMaximize(win)
  local id = win:id()
  local screenFrame = win:screen():frame()
  if beforeMaximize[id] and nearlyEqual(win:frame(), screenFrame) then
    win:moveToUnit(beforeMaximize[id])
    beforeMaximize[id] = nil
  else
    beforeMaximize[id] = win:frame():toUnitRect(screenFrame)
    win:maximize()
  end
end

function M.actions.nextScreen(win)
  win:moveToScreen(win:screen():next(), false, true)
end

function M.actions.previousScreen(win)
  win:moveToScreen(win:screen():previous(), false, true)
end

function M.actions.leftHalf(win)
  win:moveToUnit(hs.layout.left50)
end

function M.actions.rightHalf(win)
  win:moveToUnit(hs.layout.right50)
end

-- Quarters as unit rects: x, y, w, h as shares of the screen
local function quarter(x, y)
  return function(win) win:moveToUnit(hs.geometry.rect(x, y, 0.5, 0.5)) end
end
M.actions.topLeft = quarter(0, 0)
M.actions.topRight = quarter(0.5, 0)
M.actions.bottomLeft = quarter(0, 0.5)
M.actions.bottomRight = quarter(0.5, 0.5)

local function plain(rect)
  return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

-- The middle of the usable screen (below the menu bar, beside the dock), the same
-- middle the size steps use; a window bigger than that is shrunk to fit
function M.actions.center(win)
  local frame = steps.centered(plain(win:frame()), plain(win:screen():frame()))
  win:setFrameInScreenBounds(hs.geometry.rect(frame), 0)
end

local function stepTo(win, pick)
  local screen = plain(win:screen():frame())
  local step = pick(plain(win:frame()), screen)
  if step then win:setFrame(hs.geometry.rect(steps.frame(step, screen)), STEP_SECONDS) end
end

function M.actions.larger(win)
  stepTo(win, steps.larger)
end

function M.actions.smaller(win)
  stepTo(win, steps.smaller)
end

local bindings = {
  { "return", M.actions.toggleMaximize, "Maximize; again = restore" },
  { "right", M.actions.nextScreen, "Window to the next monitor" },
  { "left", M.actions.previousScreen, "Window to the previous monitor" },
  { "h", M.actions.leftHalf, "Window to the left half" },
  { "l", M.actions.rightHalf, "Window to the right half" },
  { "u", M.actions.topLeft, "Window to the top-left quarter" },
  { "i", M.actions.topRight, "Window to the top-right quarter" },
  { "j", M.actions.bottomLeft, "Window to the bottom-left quarter" },
  { "k", M.actions.bottomRight, "Window to the bottom-right quarter" },
  { "c", M.actions.center, "Center the window" },
  { "+", M.actions.larger, "Window a step larger, centered" },
  { "-", M.actions.smaller, "Window a step smaller, centered" },
}

for _, binding in ipairs(bindings) do
  local key, action, description = binding[1], binding[2], binding[3]
  M.hotkeys[key] = shortcuts.bind(mods, key, "Windows", description, function()
    local win = hs.window.focusedWindow()
    if win then action(win) end
  end)
end

return M
