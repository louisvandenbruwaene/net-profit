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

function Camera:update(dt)
  self.scale = self.scale + (self.targetScale - self.scale) * math.min(1, dt * 12)
  if self.shake > 0 then self.shake = math.max(0, self.shake - dt * 2.6) end
  local m = 260 / self.scale
  self.x = math.max(-m, math.min(self.fieldW + m, self.x))
  self.y = math.max(-m, math.min(self.fieldH + m, self.y))
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

function Camera:toWorld(sx, sy)
  return (sx - self.vx - self.vw / 2) / self.scale + self.x,
         (sy - self.vy - self.vh / 2) / self.scale + self.y
end

function Camera:pan(dx, dy)
  self.x = self.x - dx / self.scale
  self.y = self.y - dy / self.scale
end

-- Zoom about the cursor so the point under the mouse stays put.
function Camera:zoomAt(sx, sy, delta)
  local wx, wy = self:toWorld(sx, sy)
  self.targetScale = math.max(0.28, math.min(2.2, self.targetScale * (1 + delta * 0.16)))
  self.scale = self.targetScale
  local nx, ny = self:toWorld(sx, sy)
  self.x = self.x + (wx - nx)
  self.y = self.y + (wy - ny)
end

function Camera:centerOn(wx, wy)
  self.x, self.y = wx, wy
end

return Camera
