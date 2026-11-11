-- Settings for this Mac only, from config.local.lua next to init.lua (git-ignored;
-- start from templates/hammerspoon/config.local.lua in the dotfiles repo).
-- The file returns a table with one section per module:
--   return { apps = { s = { id = "com.tinyspeck.slackmacgap", name = "Slack" } } }
--   machine.get("apps")  -> that section, or an empty table if there is none

local ui = require("core.ui")

local M = { settings = {} }

local path = hs.configdir .. "/config.local.lua"
if hs.fs.attributes(path) then
  local chunk, err = loadfile(path)
  local ok, result = false, err
  if chunk then ok, result = pcall(chunk) end
  if ok and type(result) == "table" then
    M.settings = result
  else
    print("config.local.lua ignored: " .. tostring(result))
    ui.error("Hammerspoon: config.local.lua ignored\n" .. tostring(result))
  end
end

function M.get(section)
  return M.settings[section] or {}
end

return M
