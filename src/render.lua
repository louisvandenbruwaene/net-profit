-- render.lua -- drawing the field. The visual language is deliberate:
--   link thickness  = capacity          (what it could carry)
--   moving dots     = flow              (what it does carry)
--   red pulse       = the minimum cut   (what is about to be taken)
--   node ring       = ports used        (degree against its limit)
-- If the player can read those four things, they can read a flow network.
local P = require("palette")

local R = {}
R.fx = {}
R.t = 0

local lg = love.graphics

function R.dimensions()
  if R.viewportOverride then return R.viewportOverride[1], R.viewportOverride[2] end
  return lg.getDimensions()
end

R.SIZES = { tiny = 11, small = 12, body = 14, mid = 18, big = 30, huge = 54 }

-- The interface can be drawn larger than a point per point (Settings > Text
-- size). Its letters are then rasterised at that size too, so a large panel
-- is as sharp as a small one rather than a stretched copy of it.
R.uiScale = 1

function R.init()
  local fontFile = "assets/DejaVuSans-Bold.ttf"
  local density = (lg.getDPIScale and lg.getDPIScale() or 1) * (R.uiScale or 1)
  local function loadFont(size)
    if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(fontFile) then
      return lg.newFont(fontFile, size, "normal", density)
    end
    return lg.newFont(size, "normal", density)
  end
  R.fonts = {}
  for key, size in pairs(R.SIZES) do R.fonts[key] = loadFont(size) end
  -- A font is rasterised for the density of the screen it was made on, so the
  -- density it was made at is worth remembering.
  R.density = lg.getDPIScale and lg.getDPIScale() or 1
  R.fontScale = R.uiScale or 1
  -- Teaches love.graphics.print to draw the commodity symbols that travel
  -- inside ordinary strings. The letters stay this typeface.
  require("symbol_font").install()
end

-- Dragging the window onto a screen of a different density leaves the letters
-- rasterised for the old one, so they are made again. On one screen this never
-- fires.
function R.retune()
  if math.abs((lg.getDPIScale and lg.getDPIScale() or 1)-(R.density or 1))>0.01
     or math.abs((R.uiScale or 1)-(R.fontScale or 1))>0.01 then R.init() end
end

--------------------------------------------------------------------------------
-- Zoom
--------------------------------------------------------------------------------

-- How large a symbol is drawn at a given camera scale.
--
-- A symbol must never grow as the camera pulls back, and clamping its size with
-- math.max(floor, k * scale) does precisely that: past the floor the world keeps
-- shrinking underneath a symbol that has stopped, so a city seen from far out
-- fills with blobs larger than the streets they stand on. The cure is to
-- compress the curve rather than clamp it. scale^0.55 is strictly increasing --
-- zooming out always makes a symbol smaller -- but it falls away slowly enough
-- that a node is still five pixels across at the furthest zoom instead of two.
local SYM = 0.55
function R.sym(base, scale)
  return base * scale ^ SYM
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

function R.burst(x, y, color, n)
  for _ = 1, (n or 14) do
    local a = math.random() * math.pi * 2
    local s = 40 + math.random() * 170
    R.fx[#R.fx + 1] = {
      kind = "spark", x = x, y = y,
      vx = math.cos(a) * s, vy = math.sin(a) * s,
      life = 0.5 + math.random() * 0.5, age = 0, color = color,
    }
  end
end

-- `delay` holds a text back before it rises, so a row of them can ripple
-- across the map rather than all appearing in the same frame.
function R.floatText(x, y, text, color, delay)
  delay = delay or 0
  R.fx[#R.fx + 1] = { kind = "text", x = x, y = y, text = text,
                      color = color, life = 1.6 + delay, age = 0, delay = delay }
end

-- A pulse running along a new main from one end to the other, leaving a
-- fading glow behind it: the pipe drawing itself into the ground.
function R.trace(ax, ay, bx, by, color, delay)
  delay = delay or 0
  R.fx[#R.fx + 1] = { kind = "trace", x = ax, y = ay, bx = bx, by = by, color = color,
                      life = 0.75 + delay, age = 0, delay = delay }
end

function R.ring(x, y, color)
  R.fx[#R.fx + 1] = { kind = "ring", x = x, y = y, color = color, life = 0.6, age = 0 }
end

function R.update(dt)
  R.t = R.t + dt
  for i = #R.fx, 1, -1 do
    local f = R.fx[i]
    f.age = f.age + dt
    if f.kind == "spark" then
      f.x = f.x + f.vx * dt
      f.y = f.y + f.vy * dt
      f.vx = f.vx * (1 - dt * 2.4)
      f.vy = f.vy * (1 - dt * 2.4)
    elseif f.kind == "text" and f.age >= (f.delay or 0) then
      f.y = f.y - dt * 26
    end
    if f.age >= f.life then table.remove(R.fx, i) end
  end
end

-- Floating numbers are screen-sized, so neighbours on the map collide at any
-- zoom. Each one that would overlap an earlier one is lifted clear above it.
local function stack(placed, sx, sy, w)
  local h = 24
  for _ = 1, #placed do
    local moved = false
    for _, p in ipairs(placed) do
      if math.abs(sx - p.x) < (w + p.w) / 2 + 4 and math.abs(sy - p.y) < h then
        sy, moved = p.y - h, true
      end
    end
    if not moved then break end
  end
  placed[#placed + 1] = { x = sx, y = sy, w = w }
  return sy
end

-- `layer` "shapes" draws sparks, rings and traces; "text" draws the floating
-- numbers, after the map labels so they can be placed clear of them.
function R.drawEffects(cam, layer)
  -- Placed in the order they appeared, so a late one never shoves one that is
  -- already on screen.
  -- Map labels already drawn (place names, flow readings) hold their
  -- ground: a floating number lifts clear of them as it would of another float.
  local texts, placed = {}, {}
  for _, box in ipairs(R.labelBoxes or {}) do placed[#placed + 1] = box end
  for i, f in ipairs(R.fx) do
    if f.kind == "text" and f.age >= (f.delay or 0) then texts[#texts + 1] = { f = f, i = i } end
  end
  table.sort(texts, function(a, b)
    if a.f.delay ~= b.f.delay then return (a.f.delay or 0) < (b.f.delay or 0) end
    return a.i < b.i
  end)
  for _, t in ipairs(texts) do
    local sx, sy = cam:toScreen(t.f.x, t.f.y)
    t.f.lift = stack(placed, sx, sy, R.fonts.body:getWidth(t.f.text) + 12) - sy
  end
  local shapes, words = layer ~= "text", layer ~= "shapes"
  for _, f in ipairs(R.fx) do
    local k = 1 - f.age / f.life
    local sx, sy = cam:toScreen(f.x, f.y)
    if (f.kind == "text" and not words) or (f.kind ~= "text" and not shapes) then
      -- drawn in the other layer
    elseif f.kind == "spark" then
      lg.setColor(f.color[1], f.color[2], f.color[3], k)
      lg.circle("fill", sx, sy, 2.2 * k * cam.scale + 0.6)
    elseif f.kind == "ring" then
      lg.setColor(f.color[1], f.color[2], f.color[3], k * 0.8)
      lg.setLineWidth(2.5 * k + 0.5)
      lg.circle("line", sx, sy, (1 - k) * 60 * cam.scale + 6)
    elseif f.kind == "trace" and f.age >= (f.delay or 0) then
      local d = f.delay or 0
      local t = math.min(1, (f.age - d) / 0.45)
      local fade = 1 - math.max(0, (f.age - d - 0.45) / 0.3)
      local ex, ey = cam:toScreen(f.bx, f.by)
      local hx, hy = sx + (ex - sx) * t, sy + (ey - sy) * t
      lg.setColor(f.color[1], f.color[2], f.color[3], 0.55 * fade)
      lg.setLineWidth(6 * math.max(0.4, cam.scale))
      lg.line(sx, sy, hx, hy)
      lg.setColor(1, 1, 1, 0.9 * fade)
      lg.circle("fill", hx, hy, 5 * math.max(0.5, cam.scale) + 1)
    elseif f.kind == "text" and f.age >= (f.delay or 0) then
      local d = f.delay or 0
      local kk = 1 - (f.age - d) / (f.life - d)
      local pop = math.min(1, (f.age - d) * 8)
      lg.setFont(R.fonts.body)
      local w = R.fonts.body:getWidth(f.text) + 12
      sy = sy + (f.lift or 0)
      lg.setColor(0.05, 0.08, 0.10, math.min(0.8, kk * 1.4))
      lg.rectangle("fill", sx - w / 2, sy - 10, w, 22, 6)
      lg.setColor(f.color[1], f.color[2], f.color[3], math.min(1, kk * 1.8))
      lg.push(); lg.translate(sx, sy); lg.scale(0.6 + 0.4 * pop)
      lg.printf(f.text, -70, -8, 140, "center")
      lg.pop()
    end
  end
end

--------------------------------------------------------------------------------
-- Field
--------------------------------------------------------------------------------

function R.drawGrid(cam, fieldW, fieldH)
  -- The city is large enough to be viewed from a long way out; a fixed grid
  -- step turns into a solid wash at that distance, so it coarsens with zoom.
  local step = cam.scale < 0.30 and 600 or cam.scale < 0.55 and 240 or 120
  local x0, y0 = cam:toWorld(cam.vx, cam.vy)
  local x1, y1 = cam:toWorld(cam.vx + cam.vw, cam.vy + cam.vh)
  lg.setLineWidth(1)
  for gx = math.floor(x0 / step) * step, x1, step do
    local major = (gx % (step * 5) == 0)
    lg.setColor(major and P.gridMajor or P.grid)
    local ax, ay = cam:toScreen(gx, y0)
    local bx, by = cam:toScreen(gx, y1)
    lg.line(ax, ay, bx, by)
  end
  for gy = math.floor(y0 / step) * step, y1, step do
    local major = (gy % (step * 5) == 0)
    lg.setColor(major and P.gridMajor or P.grid)
    local ax, ay = cam:toScreen(x0, gy)
    local bx, by = cam:toScreen(x1, gy)
    lg.line(ax, ay, bx, by)
  end

end

return R
