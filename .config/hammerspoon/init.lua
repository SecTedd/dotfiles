-- Hammerspoon config (~/.config/hammerspoon, set via MJConfigFile; see the dotfiles README)
--
-- Layout
--   init.lua           this file: loads core, then every module, then starts the auto-reload
--   core/              shared infrastructure, no features of its own
--     ui.lua           on-screen boxes: flash 1 s / alert 4 s / error 8 s (+ ⌃⌥⌘X closes all)
--     shortcuts.lua    registry of all hotkeys; modules bind through it (shortcuts.bind)
--     toggle.lua       on/off switch with menu bar icon and/or URL event for tmux (claude, caffeine)
--     hold.lua         repeat an action while a key is held, with a safety cap (scroll, windowmode)
--     machine.lua      settings for this Mac from config.local.lua (git-ignored,
--                      template in templates/hammerspoon/ of the repo)
--   modules/           one feature per file; a module uses core, never another module.
--                      A bigger module keeps its parts in modules/<name>/ (see panel.lua)
--   data/              static tables, no code (shortcuts.lua: fish keys and plugin-bound tmux keys for the panel)
--   config.local.lua   this Mac only (optional)
--
-- Conventions
--   * A module is a file that returns a table holding everything that must stay
--     alive (hotkeys, menu bar items, watchers). No globals.
--   * Modules load independently: a broken one shows its error in a box and the
--     rest keeps working. The error is also in the Hammerspoon console.
--   * Every hotkey goes through core/shortcuts.lua, so the panel (⌃⌥⌘ Space) lists it.
--   * Saving any .lua file in this folder reloads the config.

-- `hs` command-line tool (IPC), linked next to Homebrew. Missing (false) or
-- half-installed ("broken", e.g. no man page link): remove what's there and
-- install it again.
require("hs.ipc")
local cliPrefix = "/opt/homebrew"
if hs.ipc.cliStatus(cliPrefix, true) ~= true then
  hs.ipc.cliUninstall(cliPrefix, true)
  if not hs.ipc.cliInstall(cliPrefix, true) then
    print("hs CLI could not be installed under " .. cliPrefix .. " (hs.ipc.cliInstall)")
  end
end

local ui = require("core.ui")

-- Loaded modules live in a global so Hammerspoon doesn't garbage-collect them
modules = {}
failedModules = {}
local function load(name)
  local ok, result = pcall(require, "modules." .. name)
  if ok then
    modules[name] = result
  else
    table.insert(failedModules, name)
    print("modules." .. name .. " failed: " .. tostring(result))
    ui.error("Hammerspoon: modules." .. name .. " failed\n" .. tostring(result))
  end
end

load("claude")   -- Claude Code alerts + menu bar sound toggle
load("apps")     -- ⌃⌥⌘ + letter: focus an app, cycle its windows, hide
load("tabs")     -- ⌃⌥⌘ H/L: previous/next tab in any app (hold to repeat)
load("scroll")   -- ⌃⌥⌘ J/K: smooth scroll down/up in any app (hold)
load("chrome")   -- ⌃⌥⌘ O/I: back/forward, only while Chrome is in front
load("windows")  -- ⌃⌥ + Enter/arrows/H/L/U/I/J/K/C: maximize, monitors, halves, quarters, center
load("windowmode") -- ⌃⌥W: window mode, hjkl move / ⇧hjkl grab an edge and drag it
load("caffeine") -- menu bar icon / tmux prefix C: keep the display awake
load("colorpicker") -- ⌃⌥⌘ C: macOS's color sampler, the pixel's hex to the clipboard
load("panel")    -- ⌃⌥⌘ Space: searchable panel of all shortcuts (Hammerspoon, tmux, fish)

-- Auto-reload: a saved .lua file in the config folder (symlink resolved, so file
-- events arrive) restarts the config
configWatcher = hs.pathwatcher.new(hs.fs.pathToAbsolute(hs.configdir), function(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end):start()

if #failedModules == 0 then
  ui.flash("Hammerspoon config loaded")
end
