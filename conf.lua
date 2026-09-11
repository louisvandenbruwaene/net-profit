function love.conf(t)
  t.identity = "net-profit"
  t.window.title = "Net Profit"
  t.window.width = 1440
  t.window.height = 880
  t.window.minwidth = 1100
  t.window.minheight = 700
  t.window.resizable = true
  t.window.msaa = 4
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.joystick = false
end
