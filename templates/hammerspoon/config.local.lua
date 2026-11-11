-- Hammerspoon settings for this Mac only (git-ignored). The file returns a table
-- with one section per module; a module reads its section via core/machine.lua.
return {
  -- apps: ⌃⌥⌘ + key -> app. Adds to the core apps in modules/apps.lua (Ghostty,
  -- Chrome, Spotify, Finder) or overrides them; `false` removes one on this Mac.
  apps = {
    --s = { id = "com.tinyspeck.slackmacgap", name = "Slack" },
    --m = false, -- no Spotify here
  },
}
