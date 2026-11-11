-- The panel's entries, collected from the three sources:
--   Hammerspoon  core/shortcuts.lua (every hotkey is bound through it)
--   tmux         live from the running server (modules/panel/tmux.lua) plus the
--                plugin-bound keys from data/shortcuts.lua
--   fish         data/shortcuts.lua
--
-- An entry: { source, group, key, description, index, words, run | copy, icon, iconTemplate }
--   group  shown as the row's tag: Hammerspoon groups plain ("Apps"), others "tmux · ours", "fish · built-in"
--   run    function: what ⏎ does (Hammerspoon action, tmux key press)
--   copy   string: what ⏎ puts on the clipboard instead (fish, copy-mode keys)
--   words  search words for the key (modules/panel/keys.lua)

local shortcuts = require("core.shortcuts")
local tmux = require("modules.panel.tmux")
local static = require("data.shortcuts")
local keys = require("modules.panel.keys")

local M = {}

local function hammerspoonEntries()
  local out = {}
  for _, e in ipairs(shortcuts.all()) do
    out[#out + 1] = {
      source = "Hammerspoon", group = e.group, key = e.key, description = e.description,
      run = e.run, icon = e.icon, iconTemplate = e.iconTemplate,
    }
  end
  return out
end

local function tmuxEntries()
  local out = tmux.entries()
  for _, e in ipairs(out) do
    if not e.run then e.copy = e.key end -- copy-mode keys: nothing to run outside copy mode
  end
  for _, e in ipairs(static.tmux) do
    local sequence = e.keys
    out[#out + 1] = {
      source = "tmux", group = "tmux · plugins", key = e.key, description = e.description,
      run = function() tmux.send(sequence) end,
    }
  end
  return out
end

local function fishEntries()
  local out = {}
  local function add(list, group)
    for _, e in ipairs(list) do
      out[#out + 1] = { source = "fish", group = group, key = e.key, description = e.description, copy = e.copy or e.key }
    end
  end
  add(static.fish.ours, "fish · ours")
  add(static.fish.builtin, "fish · built-in")
  return out
end

-- Every entry in display order: Hammerspoon, tmux (ours, plugins, built-in), fish
function M.all()
  local out = {}
  for _, list in ipairs({ hammerspoonEntries(), tmuxEntries(), fishEntries() }) do
    for _, e in ipairs(list) do
      e.index = #out + 1
      e.words = keys.searchWords(e.key)
      out[#out + 1] = e
    end
  end
  return out
end

return M
