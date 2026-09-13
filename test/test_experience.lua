package.path="src/?.lua;"..package.path
local City=require("city")
local Save=require("company_save")
local E=require("experience")
local checks=0
local function check(ok,message) assert(ok,message); checks=checks+1 end
-- A company that has been through its opening: well in, first household on
-- supply, so these checks are about previews rather than about day one.
local function fresh()
  local c=City.new({seed=23,obstacles=0})
  local house=c:clientList(true)[1]
  local spring,best
  for _,d in ipairs(c.deposits) do
    local ground=c:districtAt(d.x,d.y)
    if not d.taken and d.commodity=="water" and ground and ground.owned then
      local far=d.opening and -1 or (d.x-house.x)^2+(d.y-house.y)^2
      if not best or far<best then spring,best=d,far end
    end
  end
  c.money=c.money+900
  assert(c:buySource("water",spring.x,spring.y))
  for _,offer in ipairs(c:clientList(true)) do c:acceptClient(offer.id) end
  c:rebaseOrigin()
  c.money=City.rules.startMoney
  return c
end

do
  local c=fresh()
  local n=c:clientList()[1]
  local before=Save.pack(c)
  local net=c:dailyRevenue()-c:dailyExpenses()
  local p=E.pipePreview(c,c.firstSource.id,n.id,"water",n.demand,false)
  check(Save.pack(c)==before,"a quote must not mutate cash, randomness, logs or graph")
  check(p.delivery==n.demand and p.demand==n.demand,"quote solves actual delivery")
  assert(c:layPipe(c.firstSource.id,n.id,"water",n.demand))
  check(p.cash==c.money,"remaining cash matches the committed action")
  check(p.net==c:dailyRevenue()-c:dailyExpenses()-net,"net preview includes upkeep")
  check(E.pipePreview(c,c.firstSource.id,n.id,"water",n.demand,false).error~=nil,"cached quote invalidates after construction")
  local route=E.route(c,n.id)
  check(route[c.g.edges[1].id],"selected route reaches its source")
  c:demolishPipe(c.g.edges[1].id)
  check(next(E.route(c,n.id))==nil,"removed lines are excluded from route")
end
do
  local c=fresh()
  local n=c:clientList()[1]
  c.money=0
  local before=Save.pack(c)
  local p=E.pipePreview(c,c.firstSource.id,n.id,"water",n.demand,false)
  check(p.cash<0 and p.delivery==n.demand,"unaffordable plans still explain their potential")
  check(Save.pack(c)==before,"unaffordable preview leaves company untouched")
  n.prospect=true; c:refresh()
  local saved=Save.pack(c)
  local offer=E.offerPreview(c,n.id)
  check(offer.cost and offer.delivery==n.demand,"offer estimates a feasible direct full-supply connection")
  check(Save.pack(c)==saved and n.prospect,"offer simulation neither signs nor spends")
  c.money=1000
  assert(c:layPipe(c.firstSource.id,n.id,"water",n.demand))
  check(E.offerPreview(c,n.id).cost==0,"existing routes are recognized before signing")
end
do
  local c=fresh()
  check(c:chooseAmbition("service"),"a player can select an ambition")
  check(not c:chooseAmbition("missing"),"unknown ambitions are rejected")
  assert(c:setCompanyName("  Brightwater Co.  "))
  check(c.companyName=="Brightwater Co.","company names are trimmed")
  check(not c:setCompanyName("  "),"empty names are rejected")
  assert(c:dismissGuide())
  for _,n in ipairs(c:clientList()) do assert(c:layPipe(c.firstSource.id,n.id,"water",n.demand)) end
  for _=1,6 do E.close(c,{unhappy=0,bonus=0}) end
  local clone=assert(Save.unpack(Save.pack(c)))
  check(clone.serviceStreak==6 and clone.ambition=="service","ambition progress survives reload")
  check(clone.companyName==c.companyName and clone.guideDismissed,"name and guide preference survive reload")
  local cash=clone.money
  local r={unhappy=0,bonus=0}
  E.close(clone,r)
  check(clone.ambitionsDone.service and clone.money==cash+350 and r.achievement,"seventh successful close awards the grant")
  E.close(clone,{unhappy=0,bonus=0})
  check(clone.money==cash+350,"achievement grants cannot be collected twice")
  E.close(clone,{unhappy=1,bonus=0})
  check(clone.serviceStreak==0,"a service shortfall breaks the streak")
  assert(clone:chooseAmbition("districts"))
  check(clone.ambitionsDone.service,"switching ambitions preserves achievements")
  local old=fresh()
  check(E.companyName(old) and E.progress(old,E.ambitions[2])==0,"older saves need no new fields")
end
print(checks.." experience checks passed")
