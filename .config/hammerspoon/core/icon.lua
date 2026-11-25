-- Menu bar icons as vector drawings: 16 pt tall, drawn at 4x and scaled down (crisp on
-- Retina), black, so macOS tints them like its own template icons.
-- Adapted from https://github.com/scorphus/scorphiles (hammerspoon/Modules/menubar_icon.lua)
-- by Pablo Aguiar. Apache License 2.0, full text in LICENSES/scorphiles-Apache-2.0.txt of
-- the dotfiles repo. Changes: module layout and names, images set to their exact size.
--
--   icon.line(width, p1, p2, ...)  stroked path; a point is { x=, y= }, with c1x/c1y/c2x/c2y a curve
--   icon.shape(p1, p2, ...)        closed, filled path
--   icon.dot(x, y, radius)         filled circle
--   icon.cut(element)              the element erases what is under it instead of drawing
--   icon.slash(x1, y1, x2, y2)     a slash with a gap around it (two elements: the gap, the line)
--   icon.image(width, elements)    the hs.image, width plus a margin on each side

local HEIGHT = 16
local SCALE = 4
-- macos.sh sets the system's spacing between menu bar items to 0, so each icon carries its own
local MARGIN = 4.5
local BLACK = { white = 0 }

local M = {}

function M.line(width, ...)
  return {
    type = "segments", action = "stroke", strokeColor = BLACK, strokeWidth = width,
    strokeCapStyle = "round", strokeJoinStyle = "round", coordinates = { ... },
  }
end

function M.shape(...)
  return {
    type = "segments", action = "strokeAndFill", closed = true, fillColor = BLACK, strokeColor = BLACK,
    strokeWidth = 1, strokeJoinStyle = "round", coordinates = { ... },
  }
end

function M.dot(x, y, radius)
  return { type = "circle", action = "fill", fillColor = BLACK, center = { x = x, y = y }, radius = radius }
end

function M.cut(element)
  element.compositeRule = "destinationOut"
  return element
end

function M.slash(x1, y1, x2, y2)
  local gap = M.cut(M.line(2.8, { x = x1, y = y1 }, { x = x2, y = y2 }))
  local line = M.line(1.3, { x = x1, y = y1 }, { x = x2, y = y2 })
  return gap, line
end

function M.image(width, elements)
  local canvas = hs.canvas.new({ x = 0, y = 0, w = (width + 2 * MARGIN) * SCALE, h = HEIGHT * SCALE })
  local transformation = hs.canvas.matrix.scale(SCALE):translate(MARGIN, 0)
  for _, element in ipairs(elements) do
    element.transformation = transformation
    canvas:appendElements(element)
  end
  -- exact size: a canvas has whole pixels, and a proportional fit would shrink the height a bit
  local image = canvas:imageFromCanvas():setSize({ w = width + 2 * MARGIN, h = HEIGHT }, true)
  canvas:delete()
  return image
end

return M
