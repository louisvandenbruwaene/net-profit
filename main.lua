love.filesystem.setRequirePath("src/?.lua;?.lua")
local contracts = false
for _, value in ipairs(arg or {}) do if value == "--contracts" then contracts = true end end
require(contracts and "contract_app" or "company_app")
