-- Test runs must not take over the desktop. The harness opens a real OpenGL
-- window because LOVE cannot render without one, so the next best thing is to
-- put it where nobody has to look at it and stop waiting for the display.
local function testRun()
  for _, a in ipairs(rawget(_G, "arg") or {}) do
    if a == "--smoke" or a == "--soak" or a == "--shot" or a == "--tut"
       or a == "--audio" or a == "--probe" then
      return true
    end
  end
  return false
end

function love.conf(t)
  t.identity = "net-profit"
  t.window.title = "Net Profit"
  t.window.width = 1440
  t.window.height = 880
  t.window.minwidth = 1100
  t.window.minheight = 700
  t.window.resizable = true
  -- Without this the window is drawn at one device pixel per point and the
  -- display stretches it, which on a Retina screen is what makes text look
  -- soft. With it, love.graphics keeps reporting 1440x880 and every coordinate
  -- in the game means what it always meant, while the buffer behind it holds
  -- 2880x1760 real pixels.
  t.window.highdpi = true
  t.window.msaa = 4
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.joystick = false
  if testRun() then
    t.window.x, t.window.y = -5000, -5000
    t.window.borderless = true
    t.window.vsync = 0
  end
end
