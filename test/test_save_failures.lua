-- Exercise real application actions with failed persistence, without graphics or real saves.
package.path = "src/?.lua;" .. package.path
local City = require("city")
local Save = require("company_save")
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
local readSlot = Save.readSlot
Save.readSlot = function(slot)
  if slot == 1 then return nil, "damaged company save" end
  return nil
end
check(Save.summarize(1).error and not Save.summarize(1).empty, "damaged slots are occupied")
check(Save.firstEmptySlot() == 2, "new companies skip damaged slots")
Save.readSlot = readSlot

package.loaded.render = { init=function() end, dimensions=function() return 1440,880 end }
package.loaded.audio = { init=function() end }
package.loaded.company_render = {}
package.loaded.company_ui = { width=340 }
_G.love = {}
local current = City.new({seed=24,obstacles=0})
local other = City.new({seed=25,obstacles=0})
current.slot,other.slot = 1,2
local writes, reads = 0,0
Save.read = function() return current end
Save.write = function() writes=writes+1; return nil,"disk full" end
Save.writeSlot = function() writes=writes+1; return nil,"disk full" end
Save.writeCurrent = function() return true end
Save.readCurrent = function() return 1 end
Save.summaries = function() return {} end
local app = require("company_app")
love.load({})
Save.read = function() reads=reads+1; return other end
app.action("loadSlot",2)
check(app.city()==current and reads==0, "failed save prevents switching companies")
app.action("newSlot",3)
check(app.city()==current, "failed save prevents replacing the active company")
check(love.quit()==true, "failed save keeps the window open")
Save.write = function() return true end
Save.summarize = function() return {empty=true} end
app.action("newSlot",3)
check(app.city()==current, "failed new-slot write preserves the current company")
app.action("restart")
check(app.city()==current, "failed restart write preserves the current company")
app.action("loadSlot",2)
check(app.city()==other, "successful save allows switching")

-- A bad startup save must never be replaced by the temporary opening map.
package.loaded.company_app = nil
Save.read = function() return nil,"damaged company save" end
app = require("company_app")
love.load({})
local before = writes
check(app.state.modal=="slots", "damaged startup opens the company picker")
app.action("openSlots")
love.quit()
check(writes==before, "damaged startup is not overwritten by autosave or quit")
Save.read = function() return other end
app.action("loadSlot",2)
check(app.city()==other, "a healthy company can be opened after a damaged startup")
check(love.quit()==nil, "healthy companies can save and quit normally")
print(checks.." save failure checks passed")
