-- Claude Code alerts: on-screen box + menu bar icon that mutes the sounds.
-- Adapted from https://github.com/scorphus/tmux-claude-integration
-- Copyright (c) 2026, Pablo Aguiar. BSD 3-Clause License, full text in
-- LICENSES/tmux-claude-integration.txt of the dotfiles repo.
--
-- Triggered via fixed URL events (no code is passed in):
--   open -g "hammerspoon://claude-alert?text=<url-encoded text>"  (~/.claude/claude-announce.sh)
--   open -g "hammerspoon://claude-mute-toggle"                    (tmux prefix+M)
-- Muted = ~/.claude/announce-muted exists; claude-announce.sh then skips the sound.
-- The sound switch is a core/toggle (menu bar click silent, tmux flashes).

local ui = require("core.ui")
local toggle = require("core.toggle")

local M = {}

local muteFlag = os.getenv("HOME") .. "/.claude/announce-muted"

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
  menubar = { on = utf8.char(0xF009A), off = utf8.char(0xF009B) },
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
