-- An on/off switch with optional surfaces: a menu bar icon, a URL event for
-- tmux/scripts, and a row in the shortcut panel. Rule: the menu bar click is
-- silent (you see the icon change), everything else flashes the new state.
--
--   local sw = toggle.new({
--     name = "Caffeine",                  -- flash text: "Caffeine: ON"
--     group = "Caffeine",                 -- panel group
--     description = "Keep the display awake",   -- panel row text (keep it short)
--     isOn = function() ... end,          -- current state
--     set = function(on) ... end,         -- apply a state
--     menubar = { on = ..., off = ... },  -- optional: "ASCII:..." icons or short glyph strings
--     url = "caffeine-toggle",            -- optional: open -g "hammerspoon://caffeine-toggle" toggles + flashes
--     tmuxKey = "prefix C",               -- optional: appended to the panel row
--     flash = { on = "", off = "" },    -- optional glyphs before the flash text (default: the menu bar glyphs)
--   })
--   sw:toggle([quiet])   flip it; quiet = no flash (the menu bar click uses this)
--   sw:refresh()         redraw the menu bar icon after the state changed elsewhere
--
-- A switch may have only a menu bar icon, only a URL, or both.

local shortcuts = require("core.shortcuts")
local ui = require("core.ui")

local M = {}
M.__index = M

local function isAscii(icon) return type(icon) == "string" and icon:sub(1, 6) == "ASCII:" end

function M.new(spec)
  assert(spec.name and spec.isOn and spec.set, "toggle.new needs name, isOn and set")
  local self = setmetatable({ spec = spec }, M)

  if spec.menubar then
    self.menu = hs.menubar.new()
    self.menu:setClickCallback(function() self:toggle(true) end)
    self:refresh()
  end

  if spec.url then
    hs.urlevent.bind(spec.url, function() self:toggle() end)
  end

  -- Panel row: the menu bar click, or (without an icon) the URL-triggered toggle
  local glyph = spec.menubar and not isAscii(spec.menubar.on) and spec.menubar.on
  shortcuts.add({
    group = spec.group or spec.name,
    key = spec.menubar and (glyph and ("menu bar " .. glyph) or "menu bar") or (spec.tmuxKey or spec.name),
    description = spec.description .. (spec.tmuxKey and (" · " .. spec.tmuxKey) or ""),
    run = function() self:toggle() end,
    icon = (spec.menubar and isAscii(spec.menubar.on)) and hs.image.imageFromASCII(spec.menubar.on) or nil,
    iconTemplate = spec.menubar ~= nil and isAscii(spec.menubar.on),
  })
  return self
end

function M:refresh()
  if not self.menu then return end
  local icon = self.spec.isOn() and self.spec.menubar.on or self.spec.menubar.off
  if isAscii(icon) then self.menu:setIcon(icon) else self.menu:setTitle(icon) end
end

function M:toggle(quiet)
  local on = not self.spec.isOn()
  self.spec.set(on)
  self:refresh()
  if quiet then return end
  local glyphs = self.spec.flash or (self.spec.menubar and not isAscii(self.spec.menubar.on) and self.spec.menubar)
  local glyph = glyphs and ((on and glyphs.on or glyphs.off) .. " ") or ""
  ui.flash(glyph .. self.spec.name .. ": " .. (on and "ON" or "OFF"))
end

return M
