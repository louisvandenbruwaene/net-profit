-- camera.lua -- pan and zoom over the field.
local Camera = {}
Camera.__index = Camera

function Camera.new(fieldW, fieldH)
  return setmetatable({
    x = fieldW / 2, y = fieldH / 2,
    scale = 0.8, targetScale = 0.8,
    fieldW = fieldW, fieldH = fieldH,
    vw = 0, vh = 0, vx = 0,
    shake = 0,
  }, Camera)
end

-- The viewport is the window minus the sidebar.
function Camera:setViewport(x, y, w, h)
  self.vx, self.vy, self.vw, self.vh = x, y, w, h
end

-- The field is the surveyed extent of the city, and on an endless map it grows.
-- Handing the camera the bounds table itself rather than two numbers means the
-- clamp follows the company outward without anyone having to remember to tell
-- it.
function Camera:follow(bounds)
  self.field = bounds
end

function Camera:update(dt)
  self.scale = self.scale + (self.targetScale - self.scale) * math.min(1, dt * 12)
  -- A glide in progress eases toward its point and lets go once there, or as
  -- soon as the player pans: a hand on the map always wins.
  if self.glide then
    local k = math.min(1, dt * 7)
    self.x = self.x + (self.glide.x - self.x) * k
    self.y = self.y + (self.glide.y - self.y) * k
    if math.abs(self.glide.x - self.x) + math.abs(self.glide.y - self.y) < 0.5 then
      self.x, self.y, self.glide = self.glide.x, self.glide.y, nil
    end
  end
  if self.shake > 0 then self.shake = math.max(0, self.shake - dt * 2.6) end
  local m = 260 / self.scale
  local b = self.field
  local x0, y0 = b and b.x or 0, b and b.y or 0
  local x1 = b and (b.x + b.w) or self.fieldW
  local y1 = b and (b.y + b.h) or self.fieldH
  self.x = math.max(x0 - m, math.min(x1 + m, self.x))
  -- The sea is worth being able to look at, so the top clamp allows a screen of
  -- water above the coast.
  self.y = math.max(y0 - m - 700, math.min(y1 + m, self.y))
end

function Camera:shakeBy(amount)
  self.shake = math.min(1.4, self.shake + amount)
end

function Camera:offset()
  if self.shake <= 0 then return 0, 0 end
  local m = self.shake * 13
  return (math.random() * 2 - 1) * m, (math.random() * 2 - 1) * m
end

function Camera:toScreen(wx, wy)
  local ox, oy = self:offset()
  return self.vx + self.vw / 2 + (wx - self.x) * self.scale + ox,
         self.vy + self.vh / 2 + (wy - self.y) * self.scale + oy
end

-- Is this world point worth drawing? On an endless map the answer is usually
-- no: a company with a thousand customers has a handful of them on screen, and
-- everything else is work the frame cannot afford.
function Camera:sees(wx, wy, margin)
  margin = margin or 80
  local sx, sy = self:toScreen(wx, wy)
  return sx >= self.vx - margin and sx <= self.vx + self.vw + margin
     and sy >= self.vy - margin and sy <= self.vy + self.vh + margin
end

-- The same question for a box, used for districts and for pipes.
function Camera:seesBox(x0, y0, x1, y1, margin)
  margin = margin or 80
  local ax, ay = self:toScreen(x0, y0)
  local bx, by = self:toScreen(x1, y1)
  return bx >= self.vx - margin and ax <= self.vx + self.vw + margin
     and by >= self.vy - margin and ay <= self.vy + self.vh + margin
end

function Camera:toWorld(sx, sy)
  return (sx - self.vx - self.vw / 2) / self.scale + self.x,
         (sy - self.vy - self.vh / 2) / self.scale + self.y
end

-- Ease there over a few frames instead of cutting.
function Camera:glideTo(wx, wy)
  self.glide = { x = wx, y = wy }
end

function Camera:pan(dx, dy)
  self.glide = nil
  self.x = self.x - dx / self.scale
  self.y = self.y - dy / self.scale
end

-- Zoom about the cursor so the point under the mouse stays put.
function Camera:zoomAt(sx, sy, delta)
  self.glide = nil
  local wx, wy = self:toWorld(sx, sy)
  self.targetScale = math.max(0.11, math.min(2.2, self.targetScale * (1 + delta * 0.16)))
  self.scale = self.targetScale
  local nx, ny = self:toWorld(sx, sy)
  self.x = self.x + (wx - nx)
  self.y = self.y + (wy - ny)
end

function Camera:centerOn(wx, wy)
  self.glide = nil
  self.x, self.y = wx, wy
end

return Camera
