love.filesystem.setRequirePath("src/?.lua;?.lua")
local contracts = false
for _, value in ipairs(arg or {}) do if value == "--contracts" then contracts = true end end
-- Rounds mode runs inside the company app (`--rounds`, or its Rounds button).
require(contracts and "contract_app" or "company_app")
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
