-- Registry of every shortcut Hammerspoon provides, read by the panel
-- (modules/panel.lua). Modules bind their hotkeys through here instead of
-- hs.hotkey directly, so a shortcut can't exist without being listed.
--
--   shortcuts.bind(mods, key, group, description, pressed [, released [, repeatFn]])
--       binds and enables the hotkey; returns the hs.hotkey
--   shortcuts.new(...)        same, but not enabled (keys that only apply in one app)
--   shortcuts.add{ group=, key=<label>, description= [, run=fn] [, icon=hs.image, iconTemplate=bool] }
--       an entry without a hotkey, e.g. a menu bar click (icon: shown in the panel row)
--   shortcuts.all()           the entries in registration order: { group, key, description, run }
--   shortcuts.label(mods, key)  -> "⌃⌥⌘ T"

local M = { entries = {} }

local MOD_NAME = { ctrl = "ctrl", control = "ctrl", alt = "alt", option = "alt", shift = "shift", cmd = "cmd", command = "cmd" }
local MOD_SYMBOL = { ctrl = "⌃", alt = "⌥", shift = "⇧", cmd = "⌘" }
local MOD_ORDER = { "ctrl", "alt", "shift", "cmd" } -- macOS order
local KEY_NAME = {
  ["return"] = "⏎", space = "Space", escape = "Esc", tab = "⇥", delete = "⌫", forwarddelete = "⌦",
  left = "←", right = "→", up = "↑", down = "↓", home = "Home", ["end"] = "End", pageup = "PgUp", pagedown = "PgDn",
}

function M.label(mods, key)
  local set = {}
  for _, m in ipairs(mods) do set[MOD_NAME[m:lower()] or m] = true end
  local label = ""
  for _, m in ipairs(MOD_ORDER) do
    if set[m] then label = label .. MOD_SYMBOL[m] end
  end
  local k = KEY_NAME[key:lower()] or (#key == 1 and key:upper() or key)
  return label .. " " .. k
end

function M.add(entry)
  assert(type(entry.group) == "string" and type(entry.key) == "string" and type(entry.description) == "string",
    "shortcuts.add needs group, key and description")
  M.entries[#M.entries + 1] = entry
  return entry
end

local function register(enabled, mods, key, group, description, pressed, released, repeatFn)
  local hotkey = hs.hotkey.new(mods, key, pressed, released, repeatFn)
  if enabled then hotkey:enable() end
  M.add({
    group = group,
    key = M.label(mods, key),
    description = description,
    -- From the panel a hold-to-repeat key runs exactly one step
    run = function()
      pressed()
      if released then released() end
    end,
  })
  return hotkey
end

function M.bind(mods, key, group, description, pressed, released, repeatFn)
  return register(true, mods, key, group, description, pressed, released, repeatFn)
end

function M.new(mods, key, group, description, pressed, released, repeatFn)
  return register(false, mods, key, group, description, pressed, released, repeatFn)
end

function M.all()
  return M.entries
end

return M
