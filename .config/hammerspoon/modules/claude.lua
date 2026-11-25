-- Claude Code alerts: on-screen box + menu bar icon that mutes the sounds.
-- Adapted from https://github.com/scorphus/tmux-claude-integration
-- Copyright (c) 2026, Pablo Aguiar. BSD 3-Clause License, full text in
-- LICENSES/tmux-claude-integration.txt of the dotfiles repo.
-- The menu bar bell is adapted from https://github.com/scorphus/scorphiles
-- (hammerspoon/Modules/tools_menu.lua) by Pablo Aguiar, Apache License 2.0, full text in
-- LICENSES/scorphiles-Apache-2.0.txt. Changes: drawn through core/icon, two states.
--
-- Triggered via fixed URL events (no code is passed in):
--   open -g "hammerspoon://claude-alert?text=<url-encoded text>"  (~/.claude/claude-announce.sh)
--   open -g "hammerspoon://claude-mute-toggle"                    (tmux prefix+M)
-- Muted = ~/.claude/announce-muted exists; claude-announce.sh then skips the sound.
-- The sound switch is a core/toggle (menu bar click silent, tmux flashes).

local icon = require("core.icon")
local ui = require("core.ui")
local toggle = require("core.toggle")

local M = {}

local muteFlag = os.getenv("HOME") .. "/.claude/announce-muted"

-- A bell with a clapper, and whatever is drawn over it
local function bell(...)
  return icon.image(14, {
    icon.shape(
      { x = 7, y = 1.3 },
      { x = 11.6, y = 6, c1x = 9.9, c1y = 1.3, c2x = 11.6, c2y = 3.5 },
      { x = 11.6, y = 9 },
      { x = 13.4, y = 11.9, c1x = 11.6, c1y = 10.6, c2x = 13.4, c2y = 10.8 },
      { x = 0.6, y = 11.9 },
      { x = 2.4, y = 9, c1x = 0.6, c1y = 10.8, c2x = 2.4, c2y = 10.6 },
      { x = 2.4, y = 6 },
      { x = 7, y = 1.3, c1x = 2.4, c1y = 3.5, c2x = 4.1, c2y = 1.3 }
    ),
    icon.dot(7, 14.2, 1.6),
    ...
  })
end

local ringing = bell()
local silenced = bell(icon.slash(1.5, 1.5, 12.5, 14.5))

local function muted()
  return hs.fs.attributes(muteFlag) ~= nil
end

M.sounds = toggle.new({
  name = "Claude sounds",
  group = "Claude",
  description = "Mute / unmute Claude sounds",
  isOn = function() return not muted() end,
  set = function(on)
    if on then
      os.remove(muteFlag)
    else
      local f = io.open(muteFlag, "w")
      if f then f:close() end
    end
  end,
  -- Nerd Font bell / bell-off (nf-md-bell, nf-md-bell_off), by codepoint
  flash = { on = utf8.char(0xF009A), off = utf8.char(0xF009B) },
  menubar = { on = ringing, off = silenced },
  url = "claude-mute-toggle",
  tmuxKey = "prefix M",
})

hs.urlevent.bind("claude-alert", function(_, params)
  local text = params and params.text
  if text and text ~= "" then
    ui.alert(text:sub(1, 200))
  end
end)

return M
