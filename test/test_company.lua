package.path = "src/?.lua;" .. package.path
local City = require("city")
local Save = require("company_save")
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
local function fresh(seed)
  return City.new({seed=seed or 12, obstacles=0})
end
local function supply(c)
  for _,n in ipairs(c:clientList()) do
    assert(c:layPipe(c.firstSource.id,n.id,"water",n.demand))
  end
end

print("company persistence and deterministic days")
do
  local c=fresh()
  supply(c)
  c:invest(50)
  local clone=assert(Save.unpack(Save.pack(c)))
  for _=1,12 do
    local a,b=c:endDay(),clone:endDay()
    check(c.money==clone.money and c.rng==clone.rng,"reload must preserve the next day's random outcomes")
    check(a.revenue==b.revenue and #a.leaks==#b.leaks,"reload preserves delivery and wear")
  end
  check(Save.unpack("return {version=1}")==nil,"reject incomplete save")
  check(Save.unpack("return os.execute('false')")==nil,"save has no access to OS APIs")
end

print("signed contracts, finite output, and endpoint isolation")
do
  local c=fresh()
  c.money=5000
  local a,b=c:clientList()[1],c:clientList()[2]
  a.demand,b.demand=10,10
  supply(c)
  check(c.flowBy.water==14,"one source cannot supply more than its finite output")
  local offer=assert(c:addClient("house",true))
  local grace=offer.grace
  c:endDay()
  check(offer.grace==grace and offer.alive,"unsigned customers do not lose patience")
  check(not c.served[offer.id],"unsigned customers consume no supply")
  assert(c:acceptClient(offer.id))
  check(not offer.prospect,"accept starts the customer contract")
  c:endDay()
  check(offer.grace==grace-1,"signed customers have a delivery deadline")

  c=fresh()
  for _,n in ipairs(c:clientList()) do c.g:killNode(n.id) end
  c.money=5000
  local first=c:addClient("house")
  local second=c:addClient("house")
  first.x,first.y=1100,700
  second.x,second.y=1200,700
  c:layPipe(c.firstSource.id,first.id,"water",10)
  c:layPipe(first.id,second.id,"water",10)
  check((c.served[second.id] or 0)==0,"houses cannot be used as free transit junctions")
end

print("maintenance, construction, and grants")
do
  local c=fresh()
  supply(c)
  local e=c.g.edges[1]
  e.leaking=true
  e.cap=1
  c:endDay()
  check(e.cap==0 and e.alive,"zero-capacity pipe remains repairable")
  c.money=5000
  c:repairPipe(e.id)
  check(e.cap==e.capMax and not e.leaking,"repair restores a fully blocked main")
  local original=c:leakChance(e)
  local a,b=c.g.nodes[e.a],c.g.nodes[e.b]
  local tower=assert(c:build((a.x+b.x)/2,(a.y+b.y)/2+60,"tower"))
  check(c:leakChance(e)<original/2,"local treatment protects mains in its radius")
  c:reinforcePipe(e.id)
  check(c:leakChance(e)<original/4,"lining stacks with local treatment")
  c:demolishNode(tower.id)
  check(c:leakChance(e)==original/2,"removing treatment removes its protection")
  local money=c.money
  check(not c:build(1500,700,"source") and c.money==money,"source cannot be created for free through build")
  check(not c:buyLicence("coffee") and c.money==money,"unknown trade rejected without charging")
  check(not c:invest(0/0),"NaN cannot corrupt the ledger")

  c=fresh(); supply(c)
  local expected=c.money+c:dailyRevenue()-c:dailyExpenses()+60
  local r=c:endDay()
  check(c.money==expected and r.bonus==60,"first grant pays after a successful day")
  local nextReport=c:endDay()
  check(nextReport.bonus==0,"grant cannot be farmed on successive days")
end

print("separate premium trade networks")
do
  local c=fresh()
  c.money=10000
  for _,n in ipairs(c:clientList()) do c.g:killNode(n.id) end
  for _,commodity in ipairs({"beer","oil"}) do
    assert(c:buyLicence(commodity))
    local source=assert(c:buySource(commodity,commodity=="beer" and 500 or 1500,700))
    local client=assert(c:addClient(commodity=="beer" and "pub" or "factory"))
    client.x,client.y=source.x,source.y+200
    assert(c:layPipe(source.id,client.id,commodity,client.demand))
    check(c.served[client.id]==client.demand,"premium demand supplied: "..commodity)
  end
  local clone=assert(Save.unpack(Save.pack(c)))
  check(clone.flowBy.beer>0 and clone.flowBy.oil>0 and clone.flowBy.water==0,"all trade flows survive save/load")
  check(clone:dailyRevenue()>150,"premium clients provide materially higher income")
end

print("early growth across 20 generated companies")
for seed=1,20 do
  local c=City.new({seed=seed})
  supply(c)
  local signed=2
  for _=1,40 do
    for _,e in ipairs(c.g.edges) do
      if e.alive and e.leaking and c.money>=c:repairCost(e) then c:repairPipe(e.id) end
    end
    for _,offer in ipairs(c:clientList(true)) do
      if signed<4 and c.flowBy.water+offer.demand<=14 then
        local source=c.firstSource
        if not c:pipeError(source.id,offer.id,"water") and c.money>=c:pipeCost(source.id,offer.id,offer.demand)+40 then
          assert(c:layPipe(source.id,offer.id,"water",offer.demand))
          assert(c:acceptClient(offer.id))
          signed=signed+1
        end
      end
    end
    check(not c.bankrupt,"careful company remains solvent")
    c:endDay()
  end
  check(c.money>300,"serving and repairing customers can accumulate growth capital")
  check(signed>=3,"a careful company can expand beyond its initial customers")
  check(c.lostClients==0,"maintenance avoids customer churn in a modest network")
end

print(checks.." company checks passed")
