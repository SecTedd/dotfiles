-- Run something repeatedly while a key is held (scrolling, moving a window).
--   local held = hold.new()        one per module; a module repeats one thing at a time
--   held:start(interval, tick)     runs tick now, then every `interval` seconds
--   held:stop()                    the hotkey's release callback
--   held:running()
-- Stops by itself after MAX_SECONDS in case the release never arrives (the key
-- was let go while another app or a modal swallowed the event).
-- Checking the held modifiers instead doesn't work: macOS reports the flags of
-- the last posted event, i.e. our own synthetic events.

local M = {}
M.__index = M

M.MAX_SECONDS = 15

function M.new()
  return setmetatable({}, M)
end

function M:start(interval, tick)
  self:stop()
  local started = hs.timer.secondsSinceEpoch()
  tick()
  self.timer = hs.timer.doEvery(interval, function()
    if hs.timer.secondsSinceEpoch() - started > M.MAX_SECONDS then return self:stop() end
    tick()
  end)
end

function M:stop()
  if self.timer then
    self.timer:stop()
    self.timer = nil
  end
end

function M:running()
  return self.timer ~= nil
end

return M
