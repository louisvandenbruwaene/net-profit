-- Things open one at a time, and a new company starts gently.
package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
local Save=require('company_save')
local function check(v,m) T.check(v,m); print("  ok  "..m) end

local c=City.new({seed=24,obstacles=0})
check(not c:toolOpen("pump") and not c:toolOpen("gate") and not c:toolOpen("depot"),"a new company has only the well and the T split")
check(c:toolOpen("junction"),"the T split is always there")
local nxt=c:nextOpening()
check(nxt and nxt.name=="Pump" and nxt.need==4 and nxt.have==0,"the next thing to open is named with its target")
local d=c.districts[City.MAP.start]
for _=1,4 do assert(c:addClient("house",false)) end
check(c:toolOpen("pump") and not c:toolOpen("depot"),"four customers open the pump and nothing else")
check(c:nextOpening().name=="Tank","and the tank is next")
assert(c:addClient("house",false))
check(c:toolOpen("depot"),"the fifth opens the tank")
for _,n in ipairs(c:clientList()) do c:retireClient(n) end
check(c:toolOpen("pump") and c:toolOpen("depot"),"an opened tool stays open when customers are lost")
check(assert(Save.unpack(Save.pack(c))):toolOpen("depot"),"and after loading")

print("leaks ramp up over the first days")
local calm=City.new({seed=7,obstacles=0})
local early,late=0,0
for trial=1,200 do
  calm.day=1
  if calm:random()<calm:leakChance({commodity="water",alive=true})*math.min(1,calm.day/City.PROGRESSION.GENTLE_DAYS) then early=early+1 end
  calm.day=30
  if calm:random()<calm:leakChance({commodity="water",alive=true})*math.min(1,calm.day/City.PROGRESSION.GENTLE_DAYS) then late=late+1 end
end
check(early<late,"day one leaks less than day thirty ("..early.." against "..late..")")
print("the log counts a repeated line instead of repeating it")
local quiet=City.new({seed=24,obstacles=0})
quiet.log={}
quiet:note("Request declined. Reputation -%d.",1)
quiet:note("Request declined. Reputation -%d.",1)
quiet:note("Request declined. Reputation -%d.",1)
check(#quiet.log==1 and quiet.log[1].text=="Request declined. Reputation -1. x3","three declines in a row are one line, x3")
quiet.day=quiet.day+1
quiet:note("Request declined. Reputation -%d.",1)
check(#quiet.log==2 and quiet.log[1].text=="Request declined. Reputation -1.","a new day starts a new line")
print(T.checks.." progression checks passed")
