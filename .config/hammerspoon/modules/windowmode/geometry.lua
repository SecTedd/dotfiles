-- Frame arithmetic for the window mode. Pure functions on plain { x, y, w, h }
-- tables, no Hammerspoon calls, so they can be tested directly.
--
-- Moves and drags stop at "walls": screen edges and middles, other windows'
-- edges. A wall only counts where the window would actually touch it: it
-- carries the span of its screen or window along the other axis. A step that
-- would carry the leading edge across a wall ends exactly on it and reports the
-- stop ({ axis = "x"|"y", p = <position>, screen = <index> }), so a held key
-- stops there and the next press moves on. Precise steps (ctx.precise) ignore
-- walls. Frames never leave the screens (that counts as a stop too); a move
-- pressed again at a screen's edge carries the window onto the screen on that
-- side, if there is one.

local M = {}

M.MIN_SIZE = 120 -- px, a window never gets smaller

---------------------------------------------------------------------------
-- Screens

local function inside(x, y, r)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- Two frames overlap (touching edges don't count)
function M.intersects(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Every corner of the frame lies on one of the screens
function M.visible(f, screens)
  for _, corner in ipairs({ { f.x, f.y }, { f.x + f.w, f.y }, { f.x, f.y + f.h }, { f.x + f.w, f.y + f.h } }) do
    local onScreen = false
    for _, s in ipairs(screens) do
      if inside(corner[1], corner[2], s) then onScreen = true; break end
    end
    if not onScreen then return false end
  end
  return true
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- The screen holding the frame's center (or the first one), and its index
local function screenOf(f, screens)
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  for i, s in ipairs(screens) do
    if inside(cx, cy, s) then return s, i end
  end
  return screens[1], 1
end

local function overlap(lo1, hi1, lo2, hi2)
  return math.max(0, math.min(hi1, hi2) - math.max(lo1, lo2))
end

-- The screen beyond screen s's edge in the direction (dx, dy): the one sharing
-- most of the frame's span along the other axis, then the nearest
local function neighbour(f, dx, dy, s, screens)
  local best, bestIndex, bestShare, bestDistance
  for i, n in ipairs(screens) do
    if n ~= s then
      local distance, share
      if dx > 0 then distance = n.x - (s.x + s.w)
      elseif dx < 0 then distance = s.x - (n.x + n.w)
      elseif dy > 0 then distance = n.y - (s.y + s.h)
      else distance = s.y - (n.y + n.h) end
      if dx ~= 0 then share = overlap(f.y, f.y + f.h, n.y, n.y + n.h)
      else share = overlap(f.x, f.x + f.w, n.x, n.x + n.w) end
      local better = not best or share > bestShare or (share == bestShare and distance < bestDistance)
      if distance >= 0 and better then
        best, bestIndex, bestShare, bestDistance = n, i, share, distance
      end
    end
  end
  return best, bestIndex
end

local function same(a, b)
  return math.abs(a - b) <= 1
end

-- A move whose leading edge already sits on its screen's edge: the frame lands
-- on the neighbouring screen, at the edge it enters through, keeping its
-- position along the other axis (clamped into that screen). nil when the frame
-- isn't at an edge or no screen lies on that side.
local function crossScreen(f, dx, dy, screens)
  if #screens == 0 then return nil end
  local s = screenOf(f, screens)
  local atEdge = (dx > 0 and same(f.x + f.w, s.x + s.w)) or (dx < 0 and same(f.x, s.x))
    or (dy > 0 and same(f.y + f.h, s.y + s.h)) or (dy < 0 and same(f.y, s.y))
  if not atEdge then return nil end
  local n, i = neighbour(f, dx, dy, s, screens)
  if not n then return nil end
  local stop
  if dx > 0 then f.x = n.x; stop = { axis = "x", p = n.x, screen = i }
  elseif dx < 0 then f.x = n.x + n.w - f.w; stop = { axis = "x", p = n.x + n.w, screen = i }
  elseif dy > 0 then f.y = n.y; stop = { axis = "y", p = n.y, screen = i }
  else f.y = n.y + n.h - f.h; stop = { axis = "y", p = n.y + n.h, screen = i } end
  f.x = clamp(f.x, n.x, math.max(n.x, n.x + n.w - f.w))
  f.y = clamp(f.y, n.y, math.max(n.y, n.y + n.h - f.h))
  return f, stop
end

---------------------------------------------------------------------------
-- Walls

-- Lines a move or drag stops at: the screens' edges and middles, other windows'
-- edges. Each carries its span along the other axis and the index of the
-- screen it is on.
function M.walls(screens, others)
  local w = { x = {}, y = {} }
  local function add(list, p, lo, hi, screen) list[#list + 1] = { p = p, lo = lo, hi = hi, screen = screen } end
  for i, s in ipairs(screens) do
    for _, p in ipairs({ s.x, s.x + s.w, s.x + s.w / 2 }) do add(w.x, p, s.y, s.y + s.h, i) end
    for _, p in ipairs({ s.y, s.y + s.h, s.y + s.h / 2 }) do add(w.y, p, s.x, s.x + s.w, i) end
  end
  for _, o in ipairs(others) do
    local _, i = screenOf(o, screens)
    add(w.x, o.x, o.y, o.y + o.h, i); add(w.x, o.x + o.w, o.y, o.y + o.h, i)
    add(w.y, o.y, o.x, o.x + o.w, i); add(w.y, o.y + o.h, o.x, o.x + o.w, i)
  end
  return w
end

-- The largest part of `delta` that moves position `p` without crossing a wall
-- whose span overlaps [lo, hi] (a position already on a wall may leave it), and
-- the wall if one was hit
local function stopAtWall(p, delta, walls, lo, hi)
  if delta == 0 then return 0, nil end
  local allowed, hit = delta, nil
  for _, wall in ipairs(walls) do
    if wall.hi > lo and wall.lo < hi then
      local d = wall.p - p
      -- landing exactly on the wall counts as hitting it (<=), leaving one doesn't (d ~= 0)
      if (delta > 0 and d > 0 and d <= allowed) or (delta < 0 and d < 0 and d >= allowed) then
        allowed, hit = d, wall
      end
    end
  end
  return allowed, hit
end

local function stopAt(axis, wall)
  return { axis = axis, p = wall.p, screen = wall.screen }
end

---------------------------------------------------------------------------
-- Steps: ctx = { screens = {frames}, walls = M.walls(...), precise = bool }

-- Move by (dx, dy): only the leading edge (the one facing the movement) stops
-- at walls. Returns the frame and the stop, if any.
function M.move(f, dx, dy, ctx)
  local stop = nil
  if not ctx.precise then
    local crossed, arrival = crossScreen(f, dx, dy, ctx.screens)
    if crossed then return crossed, arrival end
    local hitX, hitY
    dx, hitX = stopAtWall(dx > 0 and f.x + f.w or f.x, dx, ctx.walls.x, f.y, f.y + f.h)
    dy, hitY = stopAtWall(dy > 0 and f.y + f.h or f.y, dy, ctx.walls.y, f.x, f.x + f.w)
    if hitX then stop = stopAt("x", hitX) elseif hitY then stop = stopAt("y", hitY) end
  end
  f.x, f.y = f.x + dx, f.y + dy
  if #ctx.screens > 0 and not M.visible(f, ctx.screens) then
    local s, i = screenOf(f, ctx.screens)
    local x, y = clamp(f.x, s.x, math.max(s.x, s.x + s.w - f.w)), clamp(f.y, s.y, math.max(s.y, s.y + s.h - f.h))
    if x ~= f.x then stop = { axis = "x", p = dx > 0 and x + f.w or x, screen = i } end
    if y ~= f.y then stop = { axis = "y", p = dy > 0 and y + f.h or y, screen = i } end
    f.x, f.y = x, y
  end
  return f, stop
end

local function edgePosition(f, edge)
  if edge == "left" then return f.x end
  if edge == "right" then return f.x + f.w end
  if edge == "top" then return f.y end
  return f.y + f.h
end

local function withEdgeAt(f, edge, p)
  if edge == "left" then f.x, f.w = p, f.x + f.w - p
  elseif edge == "right" then f.w = p - f.x
  elseif edge == "top" then f.y, f.h = p, f.y + f.h - p
  else f.h = p - f.y end
  return f
end

-- Drag one edge by delta (negative = left/up). Returns the frame and the stop,
-- if any. Only the dragged edge moves, also when confined to the screen.
function M.drag(f, edge, delta, ctx)
  local vertical = edge == "left" or edge == "right"
  local axis = vertical and "x" or "y"
  local stop = nil
  if not ctx.precise then
    local hit
    if vertical then
      delta, hit = stopAtWall(edgePosition(f, edge), delta, ctx.walls.x, f.y, f.y + f.h)
    else
      delta, hit = stopAtWall(edgePosition(f, edge), delta, ctx.walls.y, f.x, f.x + f.w)
    end
    if hit then stop = stopAt(axis, hit) end
  end
  local _, screen = screenOf(f, ctx.screens)
  -- never smaller than MIN_SIZE: reaching it ends the drag like a wall would
  local size = vertical and f.w or f.h
  local grows = (edge == "right" or edge == "bottom") == (delta > 0)
  if not grows and size - math.abs(delta) < M.MIN_SIZE then
    delta = (delta < 0 and -1 or 1) * math.max(0, size - M.MIN_SIZE)
    stop = { axis = axis, p = edgePosition(f, edge) + delta, screen = screen }
  end
  local p = edgePosition(f, edge) + delta
  if #ctx.screens > 0 then
    local probe = withEdgeAt({ x = f.x, y = f.y, w = f.w, h = f.h }, edge, p)
    if not M.visible(probe, ctx.screens) then
      local s = ctx.screens[screen]
      p = vertical and clamp(p, s.x, s.x + s.w) or clamp(p, s.y, s.y + s.h)
      stop = { axis = axis, p = p, screen = screen }
    end
  end
  return withEdgeAt(f, edge, p), stop
end

return M
