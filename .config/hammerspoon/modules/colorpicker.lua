-- ⌃⌥⌘ C: color picker. macOS's own color sampler opens (the loupe with the
-- pixel grid); a click puts that pixel on the clipboard as #rrggbb, Esc
-- cancels. Nothing else: no menu bar icon, no box.
--
-- Hammerspoon has no binding for the sampler, so a small helper does it:
-- colorpicker/sampler.swift, compiled by setup.sh into colorpicker/sampler
-- (git-ignored). It prints the hex in the color space named below.

local ui = require("core.ui")
local shortcuts = require("core.shortcuts")

local M = {}

-- sRGB is what CSS and design tools expect; the helper also knows
-- displayP3 (this screen's native values), adobeRGB and genericRGB
M.colorSpace = "sRGB"

M.sampler = hs.configdir .. "/modules/colorpicker/sampler"

local running = nil

function M.pick()
  if running and running:isRunning() then return end
  if not hs.fs.attributes(M.sampler) then
    return ui.error("Color picker: helper missing (modules/colorpicker/sampler)\nrun ~/dotfiles/setup.sh")
  end
  running = hs.task.new(M.sampler, function(code, out, err)
    running = nil
    local hex = out:match("#%x%x%x%x%x%x")
    if code == 0 and hex then
      hs.pasteboard.setContents(hex)
    elseif code ~= 1 then -- 1 = cancelled with Esc
      ui.error("Color picker: " .. (err ~= "" and err or ("helper exited with " .. code)))
    end
  end, { M.colorSpace })
  running:start()
end

M.hotkey = shortcuts.bind({ "ctrl", "alt", "cmd" }, "c", "General", "Pick a pixel's color: hex to the clipboard", M.pick)

return M
