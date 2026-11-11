-- Centered window sizes to step through (⌃⌥+ larger, ⌃⌥- smaller): shares of the
-- screen's usable frame, so every monitor behaves the same. Pure functions on
-- plain { x, y, w, h } tables, no Hammerspoon calls, so they can be tested directly.

local M = {}

-- Largest first; width shrinks fast, height a little
M.STEPS = {
  { w = 1, h = 1 },
  { w = 0.8, h = 0.94 },
  { w = 0.65, h = 0.88 },
  { w = 0.5, h = 0.82 },
}

-- Apps like Ghostty resize in cell steps, so a window on a step is never exact
M.TOLERANCE = 0.02

local function widthShare(frame, screen)
  return frame.w / screen.w
end

-- The first step narrower than the frame, nil at the smallest
function M.smaller(frame, screen)
  local current = widthShare(frame, screen)
  for _, step in ipairs(M.STEPS) do
    if step.w < current - M.TOLERANCE then return step end
  end
end

-- The first step wider than the frame, nil at the largest
function M.larger(frame, screen)
  local current = widthShare(frame, screen)
  for i = #M.STEPS, 1, -1 do
    if M.STEPS[i].w > current + M.TOLERANCE then return M.STEPS[i] end
  end
end

local function round(v)
  return math.floor(v + 0.5)
end

-- The frame's size placed in the middle of the screen
function M.centered(frame, screen)
  return {
    x = round(screen.x + (screen.w - frame.w) / 2),
    y = round(screen.y + (screen.h - frame.h) / 2),
    w = frame.w,
    h = frame.h,
  }
end

-- The step's frame, centered on the screen
function M.frame(step, screen)
  return M.centered({ w = round(screen.w * step.w), h = round(screen.h * step.h) }, screen)
end

return M
