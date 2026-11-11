-- ⌃⌥W: window mode, fine-tuning the focused window from the keyboard.
--   h j k l          move the window (hold: accelerates). Its leading edge stops
--                    at the next wall: a screen edge or middle, another window's
--                    edge; a green line flashes along the wall; press again to go on
--   ⇧H ⇧J ⇧K ⇧L      grab the left / bottom / top / right edge, then h l (a
--                    vertical edge) or j k (a horizontal edge) drag it like a
--                    mouse would, stopping at walls too; Space or the same ⇧key lets go
--   ⌃h ⌃j ⌃k ⌃l      precise: slow, no walls (moving, or dragging the grabbed edge)
--   Esc  q  ⌃⌥W      leave the mode
-- A window can't be pushed off screen; at a screen's edge, pressing the key
-- again carries it onto the neighbouring screen on that side.
--
-- A lavender border marks the window the keys act on, the one focused at that
-- moment. It follows focus changes and mouse moves instantly (accessibility
-- watchers on the front app and its focused window, alive only while the mode is
-- on). A grabbed edge is drawn in mauve with a small handle just outside it.
-- Windows that overlap each other are no walls for one another.
-- Snapping to halves, quarters and monitors in one go stays on the direct ⌃⌥
-- keys (modules/windows.lua). Frame arithmetic lives in windowmode/geometry.lua.

local shortcuts = require("core.shortcuts")
local hold = require("core.hold")
local geometry = require("modules.windowmode.geometry")

local M = { active = false, edge = nil }

local TICK = 1 / 60                           -- s between steps while a key is held
local STEP_START, STEP_MAX, ACCEL = 2, 24, 1  -- px per step: start, cap, gain per step
local PRECISE_STEP = 2                        -- px per step with ⌃, constant
local LAVENDER = { hex = "#b4befe", alpha = 0.95 }
local MAUVE = { hex = "#cba6f7", alpha = 0.95 }
local GREEN = { hex = "#a6e3a1", alpha = 0.9 }
local FLASH = { width = 2, fadeIn = 0.08, hold = 0.3, fadeOut = 0.25 } -- the snap line, seconds
local BORDER = 3                              -- px
local RADIUS = 26                             -- px, the corner radius of macOS windows
local HANDLE = { length = 40, thickness = 6, gap = 5 } -- px, the pill outside a grabbed edge
local PAD = 20                                -- px, canvas margin around the window (border + handle)

local held = hold.new()
M.held = held -- exposed for tests

---------------------------------------------------------------------------
-- Indicator: a border around the focused window; the grabbed edge in mauve with a handle

local function redraw()
  if not M.canvas then return end
  local win = hs.window.focusedWindow()
  if not win then return M.canvas:hide() end
  local f = win:frame()
  M.canvas:frame({ x = f.x - PAD, y = f.y - PAD, w = f.w + 2 * PAD, h = f.h + 2 * PAD })
  -- border centered on the window's outline
  M.canvas[1].frame = { x = PAD, y = PAD, w = f.w, h = f.h }
  if M.edge then
    -- the straight part of that side, between the corner arcs
    local x1, y1, x2, y2
    if M.edge == "left" then x1, y1, x2, y2 = PAD, PAD + RADIUS, PAD, PAD + f.h - RADIUS
    elseif M.edge == "right" then x1, y1, x2, y2 = PAD + f.w, PAD + RADIUS, PAD + f.w, PAD + f.h - RADIUS
    elseif M.edge == "top" then x1, y1, x2, y2 = PAD + RADIUS, PAD, PAD + f.w - RADIUS, PAD
    else x1, y1, x2, y2 = PAD + RADIUS, PAD + f.h, PAD + f.w - RADIUS, PAD + f.h end
    M.canvas[2].coordinates = { { x = x1, y = y1 }, { x = x2, y = y2 } }
    M.canvas[2].action = "stroke"
    -- the handle, centered on that side and hovering just outside the border
    local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    local out = BORDER / 2 + HANDLE.gap + HANDLE.thickness / 2
    if M.edge == "left" then cx = cx - out elseif M.edge == "right" then cx = cx + out
    elseif M.edge == "top" then cy = cy - out else cy = cy + out end
    local vertical = M.edge == "left" or M.edge == "right"
    local w, h = vertical and HANDLE.thickness or HANDLE.length, vertical and HANDLE.length or HANDLE.thickness
    M.canvas[3].frame = { x = cx - w / 2, y = cy - h / 2, w = w, h = h }
    M.canvas[3].action = "fill"
  else
    M.canvas[2].action = "skip"
    M.canvas[3].action = "skip"
  end
  M.canvas:show()
end

local function showIndicator()
  M.canvas = hs.canvas.new({ x = 0, y = 0, w = 10, h = 10 })
  M.canvas:level(hs.canvas.windowLevels.overlay)
  M.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  M.canvas:clickActivating(false)
  M.canvas[1] = { type = "rectangle", action = "stroke", strokeColor = LAVENDER, strokeWidth = BORDER,
    roundedRectRadii = { xRadius = RADIUS, yRadius = RADIUS } }
  M.canvas[2] = { type = "segments", action = "skip", strokeColor = MAUVE, strokeWidth = BORDER, strokeCapStyle = "round" }
  M.canvas[3] = { type = "rectangle", action = "skip", fillColor = MAUVE,
    roundedRectRadii = { xRadius = HANDLE.thickness / 2, yRadius = HANDLE.thickness / 2 } }
  redraw()
end

local function hideIndicator()
  if M.canvas then
    M.canvas:delete()
    M.canvas = nil
  end
end

-- A canvas straddling two displays is moved by macOS, so a line along a screen's
-- edge is kept just inside that screen
local function keepInside(rect, sf)
  rect.x = math.max(sf.x, math.min(rect.x, sf.x + sf.w - rect.w))
  rect.y = math.max(sf.y, math.min(rect.y, sf.y + sf.h - rect.h))
  return rect
end

-- A green line along the wall that stopped the window, across the screen the
-- wall is on, fading in and out
local function flashWall(stop, screen)
  if M.flash then M.flash:delete(); M.flash = nil end
  if M.flashTimer then M.flashTimer:stop(); M.flashTimer = nil end
  local sf = screen:frame()
  local line = stop.axis == "x"
    and { x = stop.p - FLASH.width / 2, y = sf.y, w = FLASH.width, h = sf.h }
    or { x = sf.x, y = stop.p - FLASH.width / 2, w = sf.w, h = FLASH.width }
  M.flash = hs.canvas.new(keepInside(line, sf))
  M.flash:level(hs.canvas.windowLevels.screenSaver) -- above the border
  M.flash:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  M.flash:clickActivating(false)
  M.flash[1] = { type = "rectangle", action = "fill", fillColor = GREEN }
  M.flash:show(FLASH.fadeIn)
  M.flashTimer = hs.timer.doAfter(FLASH.fadeIn + FLASH.hold, function()
    if M.flash then M.flash:hide(FLASH.fadeOut) end
    M.flashTimer = hs.timer.doAfter(FLASH.fadeOut, function()
      if M.flash then M.flash:delete(); M.flash = nil end
      M.flashTimer = nil
    end)
  end)
end

---------------------------------------------------------------------------
-- Actions (also callable directly, which is how they're tested)

-- The screens as Hammerspoon objects and as plain frames, in the same order
local function screens()
  local objects, frames = hs.screen.allScreens(), {}
  for i, s in ipairs(objects) do frames[i] = s:frame() end
  return objects, frames
end

-- Other visible standard windows; one that overlaps ours is no wall for it
local function otherFrames(win)
  local mine, frames = win:frame(), {}
  for _, w in ipairs(hs.window.visibleWindows()) do
    local other = w:frame()
    if w:id() ~= win:id() and w:isStandard() and not geometry.intersects(mine, other) then
      frames[#frames + 1] = other
    end
  end
  return frames
end

-- Step the window now and, while the key is held, every tick, until a wall
-- stops it. `step(frame, px, ctx)` returns the new frame and the stop, if any.
local function whileHeld(win, precise, step)
  local objects, frames = screens()
  local ctx = { screens = frames, walls = geometry.walls(frames, otherFrames(win)), precise = precise }
  local px = precise and PRECISE_STEP or STEP_START
  held:start(TICK, function()
    local frame = win:frame()
    if not frame then return held:stop() end -- the window went away mid-hold
    local f, stop = step(frame, math.floor(px), ctx)
    win:setFrame(f, 0)
    redraw()
    if stop then
      flashWall(stop, objects[stop.screen] or win:screen() or hs.screen.mainScreen())
      return held:stop()
    end
    if not precise then px = math.min(px + ACCEL, STEP_MAX) end
  end)
end

local DIRECTION = { h = { -1, 0 }, l = { 1, 0 }, k = { 0, -1 }, j = { 0, 1 } }

-- hjkl: move the window, or drag the grabbed edge when the key fits its direction
function M.press(key, precise)
  local win = hs.window.focusedWindow()
  if not win then return end
  local dx, dy = DIRECTION[key][1], DIRECTION[key][2]
  if not M.edge then
    return whileHeld(win, precise, function(f, px, ctx) return geometry.move(f, dx * px, dy * px, ctx) end)
  end
  local vertical = M.edge == "left" or M.edge == "right"
  if (vertical and dx ~= 0) or (not vertical and dy ~= 0) then
    local edge, delta = M.edge, (vertical and dx or dy)
    whileHeld(win, precise, function(f, px, ctx) return geometry.drag(f, edge, delta * px, ctx) end)
  end
end

function M.release()
  held:stop()
end

-- ⇧hjkl: grab an edge (again on the same edge, or Space: let go)
function M.grab(edge)
  held:stop()
  M.edge = (M.edge ~= edge) and edge or nil
  redraw()
end

function M.enter()
  if M.active then return end
  M.active, M.edge = true, nil
  M.modal:enter()
end

function M.exit()
  if not M.active then return end
  held:stop()
  if M.flashTimer then M.flashTimer:stop(); M.flashTimer = nil end
  if M.flash then M.flash:delete(); M.flash = nil end
  M.active, M.edge = false, nil
  M.modal:exit()
end

function M.toggle()
  if M.active then M.exit() else M.enter() end
end

---------------------------------------------------------------------------
-- Keys inside the mode

M.modal = hs.hotkey.modal.new()

-- The border follows the focus and the mouse: an app watcher notices app
-- switches, accessibility watchers notice the front app's focused-window changes
-- and the focused window's moves and resizes, all without delay
local function stopWatcher(name)
  if M[name] then M[name]:stop(); M[name] = nil end
end

local function watchWindow(win)
  stopWatcher("windowWatcher")
  if not win then return end
  M.windowWatcher = win:newWatcher(function() redraw() end)
  if M.windowWatcher then M.windowWatcher:start({ hs.uielement.watcher.windowMoved, hs.uielement.watcher.windowResized }) end
end

local function watchApp(app)
  stopWatcher("focusWatcher")
  if not app then return end
  M.focusWatcher = app:newWatcher(function()
    watchWindow(hs.window.focusedWindow())
    redraw()
  end)
  if M.focusWatcher then M.focusWatcher:start({ hs.uielement.watcher.focusedWindowChanged }) end
end

function M.modal:entered()
  M.appWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      watchApp(app)
      watchWindow(hs.window.focusedWindow())
      redraw()
    end
  end)
  M.appWatcher:start()
  watchApp(hs.application.frontmostApplication())
  watchWindow(hs.window.focusedWindow())
  showIndicator()
end

function M.modal:exited()
  stopWatcher("appWatcher")
  stopWatcher("focusWatcher")
  stopWatcher("windowWatcher")
  hideIndicator()
end

for _, key in ipairs({ "h", "j", "k", "l" }) do
  M.modal:bind({}, key, function() M.press(key) end, M.release)
  M.modal:bind({ "ctrl" }, key, function() M.press(key, true) end, M.release)
end
for key, edge in pairs({ h = "left", j = "bottom", k = "top", l = "right" }) do
  M.modal:bind({ "shift" }, key, function() M.grab(edge) end)
end
M.modal:bind({}, "space", function() M.grab(nil) end)
M.modal:bind({}, "escape", M.exit)
M.modal:bind({}, "q", M.exit)
-- ⌃⌥W itself stays the global toggle below (it leaves the mode when it's on)

---------------------------------------------------------------------------
-- Entry key and panel rows

M.hotkey = shortcuts.bind({ "ctrl", "alt" }, "w", "Window mode", "Window mode: hjkl move, ⇧hjkl grab an edge", M.toggle)
shortcuts.add({ group = "Window mode", key = "mode h  j  k  l", description = "Move; stops at walls, again at an edge: next screen" })
shortcuts.add({ group = "Window mode", key = "mode ⇧H  ⇧J  ⇧K  ⇧L", description = "Grab the left / bottom / top / right edge" })
shortcuts.add({ group = "Window mode", key = "mode h l  j k", description = "Drag the grabbed edge; stops at walls" })
shortcuts.add({ group = "Window mode", key = "mode ⌃h  ⌃j  ⌃k  ⌃l", description = "Precise: slow, ignores walls" })
shortcuts.add({ group = "Window mode", key = "mode Space", description = "Let go of the edge" })
shortcuts.add({ group = "Window mode", key = "mode Esc  q", description = "Leave window mode" })

return M
