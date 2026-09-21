love.filesystem.setRequirePath("src/?.lua;?.lua")

-- Three games share this window: the company (the default), Rounds mode, and
-- the archived contract puzzles. The company app installs its own love.*
-- callbacks when it is required; Rounds returns a table of them and they are
-- installed here. Switching clears whatever is installed and loads the other
-- one fresh, and the one being left saves itself first.
local CALLBACKS = { "load", "update", "draw", "mousepressed", "mousemoved", "mousereleased",
  "wheelmoved", "keypressed", "textinput", "resize", "quit" }

local flags = {}
for _, value in ipairs(arg or {}) do flags[value] = true end
local testRun = flags["--smoke"] or flags["--soak"] or flags["--shot"] or flags["--tut"]
  or flags["--audio"] or flags["--probe"]

local function install(name)
  for _, key in ipairs(CALLBACKS) do love[key] = nil end
  package.loaded[name] = nil
  local mod = require(name)
  if type(mod) == "table" and mod.load and mod.draw then
    for _, key in ipairs(CALLBACKS) do
      if mod[key] then love[key] = function(...) return mod[key](...) end end
    end
  end
  if type(mod) == "table" then mod.switchTo = _G.switchMode end
  return mod
end

-- Called from inside a running game: the next frame belongs to the other one.
function _G.switchMode(name)
  if love.quit then love.quit() end
  install(name)
  if love.load then love.load({}) end
end

local first = "company_app"
if flags["--contracts"] then
  first = "contract_app"
elseif flags["--rounds"] then
  first = "rounds_app"
elseif not testRun and love.filesystem.getInfo("mode.txt")
       and (love.filesystem.read("mode.txt") or ""):match("^rounds") then
  -- Reopen whichever game was open when the window closed.
  first = "rounds_app"
end
install(first)

-- Automated runs must return a failing exit code, not wait on an offscreen error dialog.
if testRun then
  function love.errorhandler(message)
    io.stderr:write(debug.traceback(tostring(message), 2) .. "\n")
    return function() return 1 end
  end
end
