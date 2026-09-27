love.filesystem.setRequirePath("src/?.lua;?.lua")
require("company_app")
-- Automated runs must return a failing exit code, not wait on an offscreen error dialog.
for _,value in ipairs(arg or {}) do
  if value=="--smoke" or value=="--soak" or value=="--shot" or value=="--tut" or value=="--audio" then
    function love.errorhandler(message)
      io.stderr:write(debug.traceback(tostring(message),2).."\n")
      return function() return 1 end
    end
    break
  end
end
