-- Caffeine replacement: keep the display awake (toggle), like the Caffeine app.
--   menu bar icon  click toggles (silent, the icon changes)
--   tmux prefix C  open -g "hammerspoon://caffeine-toggle": toggles + flashes
-- Adapted from https://github.com/scorphus/scorphiles (hammerspoon/Modules/caffeine.lua),
-- the icons included, by Pablo Aguiar. Apache License 2.0, full text in
-- LICENSES/scorphiles-Apache-2.0.txt of the dotfiles repo.
-- Changes: self-contained module built on core/toggle, returns the module, both icons the
-- same width.

local icon = require("core.icon")
local toggle = require("core.toggle")

local M = {}

local RING, ARM, STROKE = 4.2, 2.2, 1.6
local WIDTH = 17.5 -- the same for both icons, so the item doesn't move on click

local function polar(center, radius, degrees)
  local angle = math.rad(degrees)
  return { x = center.x + radius * math.cos(angle), y = center.y + radius * math.sin(angle) }
end

local function ring(center, radius, start, corners)
  local points = {}
  for i = 0, corners do points[#points + 1] = polar(center, radius, start + 360 / corners * i) end
  return icon.line(STROKE, table.unpack(points))
end

local function arm(center, radius, degrees)
  return icon.line(STROKE, polar(center, radius, degrees), polar(center, radius + ARM, degrees))
end

-- Awake: caffeine's skeleton, a hexagon and a pentagon sharing one side, both with sides of length RING
local hexagon = { x = 6.4, y = 8 }
local pentagonRadius = RING / (2 * math.sin(math.rad(36)))
local pentagon = {
  x = hexagon.x + RING * math.cos(math.rad(30)) + RING / (2 * math.tan(math.rad(36))),
  y = 8,
}

local awake = icon.image(WIDTH, {
  ring(hexagon, RING, -90, 6),
  ring(pentagon, pentagonRadius, 144, 5),
  arm(hexagon, RING, -90),
  arm(hexagon, RING, 90),
  arm(hexagon, RING, 210),
  arm(hexagon, RING, 150),
  arm(pentagon, pentagonRadius, -72),
})

-- Asleep: a moon and two z's, 15.8 wide, centered
local function z(width, left, top, right, bottom)
  return icon.line(width,
    { x = left, y = top }, { x = right, y = top }, { x = left, y = bottom }, { x = right, y = bottom })
end

local dx = (WIDTH - 15.8) / 2
local asleep = icon.image(WIDTH, {
  icon.dot(6.3 + dx, 9.4, 6.2),
  icon.cut(icon.dot(9.6 + dx, 6.6, 5.4)),
  z(1.3, 8.4 + dx, 6, 10.8 + dx, 8.7),
  z(1.5, 11.4 + dx, 0.9, 15 + dx, 4.6),
})

M.awake = toggle.new({
  name = "Caffeine",
  group = "Caffeine",
  description = "Keep the display awake",
  -- Nerd Font coffee / coffee-off (nf-md-coffee, nf-md-coffee_off; by codepoint, so no editor can drop them)
  flash = { on = utf8.char(0xF0176), off = utf8.char(0xF0FAA) },
  isOn = function() return hs.caffeinate.get("displayIdle") end,
  set = function(on) hs.caffeinate.set("displayIdle", on, true) end,
  menubar = { on = awake, off = asleep },
  url = "caffeine-toggle",
  tmuxKey = "prefix C",
})

return M
