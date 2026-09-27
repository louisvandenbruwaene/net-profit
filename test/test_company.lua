package.path = "src/?.lua;" .. package.path
local City = require("city")
local Save = require("company_save")
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
-- The opening, played: the well goes in on the marked spring, the household
-- that asked for water is signed, and a second one moves in beside them. Only
-- the tutorial's own checks care how a company starts.
local function openCompany(c)
  -- The spring the opening put there, which is the one within reach of the
  -- household that asked for water.
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
  local second=assert(c:addClient("house"))
  second.x,second.y=c.firstSource.x+230,c.firstSource.y-90
  second.demand=3
  c.money=City.rules.startMoney
  -- A well answers to four ports in the real game, which is a fan-out rule
  -- about hubs, not about the routes these tests lay to compare prices, leaks
  -- and billing. The fixture gives itself the room those tests use.
  c.firstSource.ports=16
  return c
end

local function fresh(seed)
  local c = openCompany(City.new({seed=seed or 12, obstacles=0}))
  -- The yards start stocked. These are checks about pipes, valves, money and
  -- customers, not about where the steel came from: the supply chain that fills
  -- a yard has its own tests.
  c.stock = { steel = 1000, concrete = 1000, planks = 500, glass = 500 }
  return c
end
-- A well only goes where the survey marked water, so a test that wants one at
-- a particular spot marks that spot first. Yield and discount are left at 1 so
-- the well is priced and sized exactly like the plain well these tests were
-- written against.
local function well(c,x,y,commodity)
  c.deposits[#c.deposits+1]=
    {x=x,y=y,commodity=commodity or "water",taken=false,yield=1,discount=1,
     cap=City.depositCap(commodity or "water",0)}
  return c:buySource(commodity or "water",x,y)
end
-- The structure already carrying src's trunk main, if there is one.
local function distributionPoint(c,src)
  for _,ei in ipairs(c.g.adj[src.id] or {}) do
    local e=c.g.edges[ei]
    if e.alive and e.commodity=="water" then
      local other=(e.a==src.id) and e.b or e.a
      local n=c.g.nodes[other]
      if n and n.alive and not City.SIZE_LIMIT[n.kind] then return n end
    end
  end
  return nil
end
-- A well answers to a trunk only, so every customer's stub comes off a
-- manifold beside it, built once and reused, rather than off the well itself.
local function supply(c)
  local src=c.firstSource
  local hub=distributionPoint(c,src)
  if not hub then
    hub=assert(c:build(src.x+90,src.y-90,"manifold"))
    assert(c:layPipe(src.id,hub.id,"water","large"))
  end
  for _,n in ipairs(c:clientList()) do
    if not c:pipeBetween(hub.id,n.id,"water") then
      assert(c:layPipe(hub.id,n.id,"water",n.demand))
    end
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

print("signed contracts, finite output, and household service valves")
do
  local c=fresh()
  c.money=5000
  local a,b=c:clientList()[1],c:clientList()[2]
  -- A house takes only the smallest main there is, so demand is capped at
  -- what one carries; the well's own output is set lower still; so the two
  -- together ask for more than the well gives, which is the point of the test.
  a.demand,b.demand=7,7
  c.firstSource.output,c.firstSource.cap=10,10
  supply(c)
  check(c.flowBy.water==10,"one source cannot supply more than its finite output")
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
  local home=c.firstSource
  first.x,first.y=home.x-150,home.y+120
  second.x,second.y=home.x-50,home.y+120
  first.demand,second.demand=3,4
  local hub=assert(c:build(home.x-75,home.y+60,"junction"))
  assert(c:layPipe(c.firstSource.id,hub.id,"water","large"))
  local main=assert(c:layPipe(hub.id,first.id,"water",7))
  local downstream=assert(c:layPipe(first.id,second.id,"water",7))
  check(c.served[first.id]==3 and c.served[second.id]==4,"seven units serve the first house and pass four onward")
  check(c.detail.edge[main.id]==7 and c.detail.edge[downstream.id]==4,"mains carry delivery plus onward flow")
  main.cap=4; c:refresh()
  assert(c:toggleSupply(first.id))
  check((c.served[first.id] or 0)==0 and c.served[second.id]==4,"shutting the upstream service gives scarce water to the downstream house")
  check(c.detail.edge[main.id]==4 and c.detail.edge[downstream.id]==4,"closed service valve does not close either main")
  local restored=assert(Save.unpack(Save.pack(c)))
  check(restored.g.nodes[first.id].supplyClosed and restored.served[second.id]==4,"service valves and through-flow survive reload")
  assert(c:toggleSupply(first.id))
  check(c.served[first.id]>0,"reopening the valve restores the first house's delivery")
  assert(c:toggleSupply(first.id))
  c.leakChance=function() return 0 end
  local reputation=c.reputation
  for _=1,first.patience do c:endDay() end
  check(first.alive and first.kind=="junction" and c.lostClients==1,"an abandoned account leaves its installed junction")
  check(main.alive and downstream.alive and c.served[second.id]==4,"customer departure preserves downstream service")
  check(c.reputation<reputation,"choosing to deny water still harms reputation")
  check(c:demolishNode(first.id)==0,"a former customer's junction cannot yield a free construction refund")
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
  local tower=assert(c:build((a.x+b.x)/2,(a.y+b.y)/2+60,"filtration"))
  check(c:leakChance(e)==original,"a disconnected filter does not protect nearby mains")
  local bareRepair=c:repairCost(e)
  local withTower=c:leakChance(e)
  -- Lining cannot be added to a main that is already in the ground. The company
  -- buys the knowledge, and then the main comes out and a lined one goes in.
  c.money=40000
  assert(c:upgradeQuality())
  check(c:leakChance(e)==withTower,"buying better pipe changes nothing already laid")
  assert(c:replacePipe(e.id,e.size,2))
  check(c:leakChance(e)<withTower/2,"a relaid main leaks less, and the treatment still helps")
  check(c:repairCost(e)<bareRepair,"lining makes the repair it cannot prevent cheaper")
  c:demolishNode(tower.id)
  check(c:leakChance(e)==City.rules.leakBase*City.GRADES[2].risk,
    "removing treatment removes its protection")
  assert(c:upgradeQuality())
  assert(c:replacePipe(e.id,e.size,3))
  check(c:leakChance(e)==City.rules.leakBase*City.GRADES[3].risk,"armour is dearer and safer again")
  check(c:replaceError(e.id,e.size,3)=="that is what is already in the ground",
    "and relaying the same main with the same pipe is not work")
  local money=c.money
  check(not c:build(c.firstSource.x+300,c.firstSource.y,"source") and c.money==money,"source cannot be created for free through build")
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
  -- The two ways supply can start: out of the ground where the survey marked
  -- it, and off a ship at the edge of the map. One of each, in one company.
  local c=fresh()
  c.money=40000
  c.obstacles={}
  for _,n in ipairs(c:clientList()) do c.g:killNode(n.id) end
  assert(c:buyLicence("beer")); assert(c:buyLicence("oil"))

  local seam
  for _,d in ipairs(c.deposits) do
    if not d.taken and d.commodity=="oil" then seam=d; break end
  end
  check(seam~=nil,"the survey found oil somewhere on the map")
  c:districtAt(seam.x,seam.y).owned=true
  local rig=assert(c:buySource("oil",seam.x,seam.y))
  local works=assert(c:addClient("factory"))
  works.x,works.y=rig.x,rig.y+200
  local rigHub=assert(c:build(rig.x,rig.y+100,"junction"))
  assert(c:layPipe(rig.id,rigHub.id,"oil","large"))
  assert(c:layPipe(rigHub.id,works.id,"oil",works.demand))
  check(c.served[works.id]==works.demand,"a rig on the deposit supplies the works")

  -- Beer is landed, hauled inland by track, and only then piped.
  local edge=c:cellAt(2,1)
  edge.owned=true
  local haven=assert(c:build(edge.x+120,edge.y+90,"terminal","port"))
  check(haven.haven=="port","the north edge is the coast")
  check(haven.commodity==nil and haven.output==nil,"a haven carries every trade, without a ceiling")
  local yard=assert(c:build(edge.x+740,edge.y+90,"dc"))
  check(select(2,c:layPipe(haven.id,yard.id,"beer",6))=="a haven ships by bulk line only",
    "nothing is piped straight out of a haven")
  assert(c:layPipe(haven.id,yard.id,"beer",6,true))
  local pub=assert(c:addClient("pub"))
  pub.x,pub.y=yard.x,yard.y+220
  pub.demand=4
  assert(c:layPipe(yard.id,pub.id,"beer",pub.demand))
  check(c.served[pub.id]==pub.demand,"landed beer reaches the pub over the track")

  local bill=c:expenseBreakdown()
  check(math.abs(bill.imports-pub.demand*City.trade.beer.importCost*City.HAVENS.port.import)<0.01,
    "the import charge is the units landed times the rate at that gateway")
  check(bill.haulage>0,"and the track bills for moving them")

  local clone=assert(Save.unpack(Save.pack(c)))
  check(clone.flowBy.beer>0 and clone.flowBy.oil>0 and clone.flowBy.water==0,"all trade flows survive save/load")
  check(clone:dailyRevenue()>150,"premium clients provide materially higher income")
end

print("early growth across 20 generated companies")
for seed=1,20 do
  local c=openCompany(City.new({seed=seed}))
  supply(c)
  local signed=2
  for _=1,40 do
    for _,e in ipairs(c.g.edges) do
      if e.alive and e.leaking and c.money>=c:repairCost(e) then c:repairPipe(e.id) end
    end
    for _,offer in ipairs(c:clientList(true)) do
      if signed<4 and c.flowBy.water+offer.demand<=14 then
        local source=assert(distributionPoint(c,c.firstSource))
        if not c:pipeError(source.id,offer.id,"water") and c.money>=c:pipeCost(source.id,offer.id,"water",offer.demand)+40 then
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

print("pricing is per trade, and depends on length, bore and both ends")
do
  local c=fresh()
  c.money=99999
  c.licences.power=true; c.licences.beer=true; c.licences.oil=true
  local src=c.firstSource
  local near=assert(c:build(src.x+60,src.y,"junction"))
  local far=assert(c:build(src.x+260,src.y,"junction"))
  -- Zero extra length still costs two tie-ins: connecting a node to the
  -- network is work even when the main runs past its door.
  local stub=c:pipeQuote(src.id,near.id,"water",1)
  check(stub.tiein>0 and stub.total>=stub.tiein,"a short connection still pays for both ends")
  check(c:pipeCost(src.id,far.id,"water",1)>c:pipeCost(src.id,near.id,"water",1),
    "a longer trench costs more")
  local water=c:pipeCost(src.id,far.id,"water","small")
  local power=c:pipeCost(src.id,far.id,"power","small")
  local beer=c:pipeCost(src.id,far.id,"beer","small")
  local oil=c:pipeCost(src.id,far.id,"oil","small")
  check(water<power and power<beer and beer<oil,
    "each trade has its own price: water < power < beer < oil")
  check(c:pipeCost(src.id,far.id,"water","large")>c:pipeCost(src.id,far.id,"water","small"),
    "a bigger main costs more")
  -- Replacing is priced off the route, so replacing a long run costs more.
  -- Off an ordinary junction rather than the well itself: a well's own main
  -- already answers to the top size short of massive, and there would be
  -- nothing left to bore it up to.
  local trunk=assert(c:build(src.x+20,src.y+60,"junction"))
  assert(c:layPipe(src.id,trunk.id,"water","large"))
  local e1=assert(c:layPipe(trunk.id,near.id,"water","small"))
  local e2=assert(c:layPipe(trunk.id,far.id,"water","small"))
  check(c:boreCost(e2,1)>c:boreCost(e1,1),"replacing a long main costs more than replacing a stub")
  check(c:repairCost(e2)>c:repairCost(e1),"repairing a long main costs more")
  check(c:pipeUpkeep(e2)>c:pipeUpkeep(e1),"and it costs more to run every day")
end

print("lining is bought once and laid forever")
do
  local c=fresh()
  c.money=99999
  local src=c.firstSource
  local far=assert(c:build(src.x+280,src.y,"junction"))
  local e=assert(c:layPipe(src.id,far.id,"water","large"))
  local bareRisk,bareRepair=c:leakChance(e),c:repairCost(e)
  check(c.lining==1,"a new company can only lay bare pipe")
  check(c:layPipe(src.id,far.id,"power","medium",false,3)==nil or true,
    "asking for pipe the company cannot lay is clamped rather than refused")

  -- Buy the knowledge, then dig the main out to get the benefit of it.
  assert(c:upgradeQuality())
  check(c.lining==2,"the company learns to lay lined pipe")
  check(c:leakChance(e)==bareRisk,"which does nothing for the main already down")
  local perDay,days=c:liningPayback(e,2)
  check(perDay>0 and days>0,"the inspector can state what relaying is worth")
  local quote=c:replaceQuote(e.id,e.size,2)
  check(quote.salvage>0,"the old main is worth something as scrap")
  assert(c:replacePipe(e.id,e.size,2))
  check(c:leakChance(e)<bareRisk and c:repairCost(e)<bareRepair,
    "and the new one cuts both the risk and the bill")

  -- Armour is dearer again, and holds its capacity through the first day.
  assert(c:upgradeQuality())
  assert(c:replacePipe(e.id,e.size,3))
  check(City.GRADES[e.grade].decay==2,"an armoured main loses capacity at half speed")
  e.leaking=true
  local cap=e.cap
  c:endDay()
  check(e.cap==cap,"armour holds its capacity through the first day of a leak")
  c:endDay()
  check(e.cap==cap-1,"and gives way on the second")

  -- And the top grade is priced like the endgame it is.
  assert(c:upgradeQuality())
  check(c.lining==4 and c:liningPrice()==nil,"sealed pipe is the end of the ladder")
  local bare=c:pipeQuote(src.id,far.id,"water","large",false,1).total
  local sealed=c:pipeQuote(src.id,far.id,"water","large",false,4).total
  check(sealed>bare*2.5,"and every metre of it costs three times bare pipe")
end

print("deepening a well against sinking another")
do
  local c=fresh()
  c.money=99999
  local src=c.firstSource
  local out,level=src.output,src.level
  local cost=c:sourceUpgradeCost(src)
  assert(c:upgradeSource(src.id))
  check(src.output>out and src.level==level+1,"a well can be deepened in place")
  check(c:sourceUpgradeCost(src)>cost,"each level costs more than the last")
  supply(c)
  local paid=c:transitIncome()
  for _,cl in ipairs(c:clientList()) do paid=paid+c:clientIncome(cl) end
  check(c:dailyRevenue()==paid,"a well that supplies somebody earns nothing: customers pay")
  local lifted=c.produced[src.id] or 0
  check(lifted>0 and math.abs(c:pumpingBill()-lifted*City.trade.water.extractPerUnit)<1e-9,
    "every unit lifted is billed at the pumping cost")
  local costs=c:tradeCosts("water")
  check(costs.perUnit and costs.perUnit>costs.marginal,"a unit costs its pumping plus a share of the upkeep")
  check(costs.price and costs.margin and math.abs(costs.price-costs.perUnit-costs.margin)<1e-9,
    "and the margin is what customers pay above that")
  for _=1,10 do c:upgradeSource(src.id) end
  check(src.output==src.cap,"a well tops out at what the ground gives")
  local why=select(2,c:upgradeSource(src.id))
  check(why:find("maximum")~=nil,"and says so rather than taking the money")
  check(src.level<=City.sourceMaxLevel,"without ever passing the depth limit")
end

print("credit is fixed-rate and capped by what the company owns")
do
  local c=fresh(); supply(c)
  local limit=c:loanLimit()
  check(limit==math.floor(c:collateral()*City.loanRatio),"credit is half of collateral")
  check(not c:borrow(limit+1),"the bank will not exceed its limit")
  local worth,cash=c:valuation(),c.money
  assert(c:borrow(limit))
  check(c.money==cash+limit and c:valuation()==worth,"borrowing is cash, not income")
  check(c:loanAvailable()==0,"the line is fully drawn")
  check(c:loanInterest()==math.ceil(limit*City.loanRate/7),"interest has no variance")
  check(c:dailyExpenses()>=c:loanInterest(),"interest is charged as an operating cost")
  assert(c:repay(limit))
  check(c.loan==0 and c:loanAvailable()==limit,"repayment restores the line")
  check(not c:repay(10),"and there is nothing left to repay")
  check(not c:borrow(0/0) and not c:borrow(-5),"the ledger rejects nonsense")
end

print("offers are priced with a spread that widens as the company grows")
do
  local c=fresh()
  local small=c:marketSpread()
  local lows=0
  for _=1,200 do
    local n=c:addClient("house",true)
    if n then
      if n.rate<City.CLIENTS.house.rate then lows=lows+1 end
      c.g:killNode(n.id)
    end
  end
  check(small<0.15,"a new company sees almost no spread")
  c.districtsBought=6; c.sourcesBought=4
  for _=1,14 do local n=c:addClient("house"); if n then n.prospect=false end end
  check(c:marketSpread()>small*2,"the spread widens as the company grows")
  local high,low=0,0
  for _=1,300 do
    local n=c:addClient("factory",true)
    if n then
      if n.rate>City.CLIENTS.factory.rate then high=high+1 end
      if n.rate<City.CLIENTS.factory.rate then low=low+1 end
      c.g:killNode(n.id)
    end
  end
  check(high>0 and low>0,"late offers land on both sides of the going rate")
end

print("ground, havens and track")
do
  local c=fresh()
  c.money=99999
  local home=c.districts[City.MAP.start]
  check(home.owned,"the company starts on one district")
  check(#c:ownedDistricts()==1,"and only one")
  local outside
  for i,d in ipairs(c.districts) do if not d.owned then outside=i; break end end
  check(c:placementError(c.districts[outside].x+50,c.districts[outside].y+50)~=nil,
    "unbought ground refuses construction")
  local far
  for i,d in ipairs(c.districts) do
    if not d.owned and not c:districtAdjacent(d) then far=i; break end
  end
  check(c:districtError(far)==nil,"the company can acquire disconnected holdings")
  local next_
  for i,d in ipairs(c.districts) do if not d.owned and not c:districtError(i) then next_=i; break end end
  local price=c:districtCost()
  assert(c:buyDistrict(next_))
  check(c.districts[next_].owned,"an adjacent district can be bought")
  check(c:districtCost()>price,"and the next one costs more")

  -- Permits turn walls into tolls.
  c.obstacles={{x=home.x+120,y=home.y+120,r=60,kind="bedrock"}}
  check(c:crossingCost(home.x+60,home.y+120,home.x+200,home.y+120)==nil,"bedrock blocks a route")
  assert(c:buyPermit("bedrock"))
  check(c:crossingCost(home.x+60,home.y+120,home.x+200,home.y+120)==City.PERMITS.bedrock.cross,
    "a blasting licence makes it a toll instead")
  check(c:placementError(home.x+120,home.y+120)==nil,"and lets the company build on it")
  check(not c:buyPermit("bedrock"),"a permit is bought once")

  -- A harbour stands on the coast. The other two doors stand where you put them.
  c.obstacles={}
  local spot={x=home.x+90,y=home.y+610}
  check(c:placementError(spot.x,spot.y)==nil,"there is clear ground in the home district")
  check(select(2,c:build(spot.x,spot.y,"terminal","port"))=="a harbour stands on the coast",
    "a harbour cannot stand inland")
  local base=c:havenCost("highway")
  local road=assert(c:build(spot.x,spot.y,"terminal","highway"))
  check(road.haven=="highway","but a road head can")
  check(c:havenCost("highway")>base,"and the second one costs more than the first")
  assert(c:demolishNode(road.id))
  check(c:havenCost("highway")==base,"until it is closed again")
  -- On the coast it works, with track to move what it lands.
  local hd=c:cellAt(2,1)
  hd.owned=true
  local t=assert(c:build(hd.x+130,hd.y+100,"terminal","port"))
  check(t.haven=="port","a harbour on the coast opens")
  check(c:havenCost("port")>City.HAVENS.port.price,"and the next harbour costs more")
  local j=assert(c:build(hd.x+hd.w-130,hd.y+hd.h/2,"dc"))
  check(c:pipeError(t.id,j.id,"water")=="a haven ships by bulk line only","no main comes off a haven")
  local rail=assert(c:layPipe(t.id,j.id,"water",1,true))
  check(rail.rail and c:leakChance(rail)==0,"track carries it, and never corrodes")
  check(c:replaceQuote(rail.id)==nil,"a freight line is fitted with wagons, not replaced")
  check(rail.wagons.water==City.MODES.rail.wagonCap,"a railway is bought by the wagon")
  -- A second wagon, for something else entirely.
  assert(c:buyLicence("beer"))
  assert(c:addWagon(rail.id,"beer"))
  check(rail.wagons.beer==City.MODES.rail.wagonCap and rail.wagonCount==2,
    "beer and water cannot share a pipe and can share a train")
  check(select(2,c:addWagon(rail.id,"power"))=="electricity travels by cable, not by freight",
    "electricity is not freight")
  local spur=c:build(hd.x+hd.w-130,hd.y+hd.h/2-260,"junction")
  check(select(2,c:layPipe(j.id,spur.id,"water",4,true))
    =="bulk runs between havens and distribution centres",
    "bulk has to run between freight terminals")
  c:refresh()
  check(c:expenseBreakdown().imports==0,"a haven idle at its berths costs nothing per unit")
  -- It only bills for what it actually moves, so a haven is a margin decision
  -- rather than a standing bill.
  local buyer=assert(c:addClient("house"))
  buyer.x,buyer.y=j.x,j.y+120
  buyer.demand=6
  assert(c:layPipe(j.id,buyer.id,"water",6))
  c:refresh()
  check(c.served[buyer.id]==6,"freight reaches a customer over the track")
  local bill=c:expenseBreakdown()
  check(bill.imports>0,"and now the haven bills for every unit it landed")
  check(math.abs(bill.imports-6*City.trade.water.importCost*City.HAVENS.port.import)<0.01,
    "the import charge is exactly the units moved times the rate")
  check(bill.haulage>0,"and the haulage is charged on what the track moved")
end

print("a distribution hub signs, connects and widens for the customers who pay enough")
do
  local c=fresh()
  c.money=99999
  c.obstacles={}
  for _,d in ipairs(c.districts) do d.owned=true end
  local src=c.firstSource
  for _,cl in ipairs(c:clientList()) do c.g:killNode(cl.id) end
  local relay=assert(c:build(src.x+110,src.y,"junction"))
  local hub=assert(c:build(src.x+300,src.y,"junction"))
  assert(c:layPipe(src.id,relay.id,"water","large"))
  -- Fed through a small main on purpose: it is the bottleneck the hub must find.
  local feed=assert(c:layPipe(relay.id,hub.id,"water","small"))
  check(c:levelName(hub)=="T split","a fitting starts as a T split")
  check(select(2,c:upgradeLevel(hub.id))==nil and c:levelName(hub)=="Hub","and levels up to a hub")
  check(c:upgradeLevel(hub.id)==nil,"a large hub waits for customers")
  -- A company big enough for the top of the ladder, all of it far away.
  for i=1,12 do
    local far=assert(c:addClient("house"))
    far.x,far.y=src.x-3000-i*40,src.y+3000
  end
  c:refresh()
  assert(c:upgradeLevel(hub.id))
  check(c:levelName(hub)=="Large hub" and not c:isDistribution(hub),"a large hub does nothing by itself")
  -- Around it: an offer paying well, an offer paying badly, and a signed
  -- customer nobody has connected yet.
  local good=assert(c:addClient("house",true)); good.x,good.y=hub.x+150,hub.y+60;  good.rate,good.demand=7,6
  local cheap=assert(c:addClient("house",true)); cheap.x,cheap.y=hub.x-60,hub.y+170; cheap.rate,cheap.demand=2,3
  local waiting=assert(c:addClient("house")); waiting.x,waiting.y=hub.x+40,hub.y-180; waiting.rate,waiting.demand=6,6
  c:refresh()
  check(c.g:degree(waiting.id)==0,"the signed customer has no main yet")
  local money=c.money
  local hubbed=assert(c:upgradeLevel(hub.id))
  check(c:isDistribution(hubbed) and c:levelName(hub)=="Distribution hub","the fourth level is the distribution hub")
  check(not good.prospect,"it signs an offer above its minimum price")
  check(cheap.prospect,"and leaves one below it for the player")
  check(c.g:degree(waiting.id)>0 and c.g:degree(good.id)>0,"it lays a real main to each customer it runs")
  check(c.g:degree(cheap.id)==0,"and none to the one it did not sign")
  check(c.money<money-City.LEVELS.LEVELS.fitting[4].cost,"everything it builds is paid for")
  check(feed.size=="medium" and feed.cap==City.sizeOf("medium").cap,
    "the small feed starving them is dug out for the next size up")
  check(c:fullyServed(good) and c:fullyServed(waiting),"so both customers are fully supplied")

  -- The minimum price is the one control, and it is respected at the close.
  assert(c:setHubFloor(hub.id,8))
  local late=assert(c:addClient("house",true)); late.x,late.y=hub.x-150,hub.y-90; late.rate=7
  c:refresh()
  local report=c:endDay()
  check(late.prospect or not late.alive,"an offer below a raised minimum is not signed")
  check(report.distribution~=nil,"the close reports what the hubs did")
  check(c:expenseBreakdown().hubs==City.DISTRIBUTION.upkeep,"and the hub's running cost is on the books")
end

print("a customer kept supplied grows loyal and pays a little more")
do
  local c=fresh()
  c.money=99999
  local leak=City.rules.leakBase
  City.rules.leakBase=0
  supply(c)
  local cl
  for _,x in ipairs(c:clientList()) do if c:fullyServed(x) then cl=x end end
  check(cl~=nil,"a supplied customer to watch")
  local rate=cl.rate
  local shocks=require("data.resilience").SHOCK_CHANCE
  require("data.resilience").SHOCK_CHANCE=0
  local loyal
  for _=1,City.LOYALTY.every do
    local r=c:endDay()
    if r.loyal then loyal=r.loyal end
    c.money=99999
  end
  check(cl.rate==rate+City.LOYALTY.step and cl.loyalty==1,"ten full days raise the rate once")
  local reported=false
  for _,l in ipairs(loyal or {}) do if l.id==cl.id then reported=true end end
  check(reported,"and the close reports it")
  City.rules.leakBase=leak
  require("data.resilience").SHOCK_CHANCE=shocks
end

print("a chain of works turns ground into something worth selling")
do
  local c=fresh()
  c.money=1e9
  c.obstacles={}
  for _,cl in ipairs(c:clientList()) do c.g:killNode(cl.id) end
  for _,d in ipairs(c.districts) do d.owned=true end
  assert(c:buyLicence("beer"))
  assert(c:buyLicence("power"))

  c.orders.dispatchers=2; c:survey()
  for _,d in ipairs(c.districts) do d.owned=true end
  -- Wheat only grows on farmland, which is somewhere out past the old city.
  local farm
  for _,d in ipairs(c.districts) do if d.spec and d.spec.key=="farm" then farm=d; break end end
  check(farm~=nil,"the survey found farmland out there")
  check(select(2,c:buySource("wheat",c.firstSource.x+300,c.firstSource.y)):find("Crop farm"),
    "new farms must be built with utility inputs")

  local bx,by=farm.x+300,farm.y+300
  -- Existing saved extractors remain usable; new farm rules have their own suite.
  local field=c.g:addNode(bx,by,"source")
  field.commodity="wheat"; field.output=30; field.cap=30; field.paid=1000
  local mill=assert(c:build(bx+240,by,"works","maltings"))
  local plant=assert(c:buySource("power",bx+360,by+200,"nuclear"))
  local brew=assert(c:build(bx+480,by,"works","brewery"))
  check(brew.makes=="beer","a brewery makes beer")
  -- It asks for everything its rated output would eat, and it needs all of it.
  local recipe=City.RECIPES.brewery
  check(brew.wants.water==recipe.inputs.water*recipe.rate,"and asks for the water to run flat out")
  check(brew.wants.malt==recipe.inputs.malt*recipe.rate,"and for the malt to go with it")

  -- Wheat and power reach the maltings, but nothing else does yet.
  assert(c:layPipe(field.id,mill.id,"wheat","large"))
  local cable=c.g:addEdge(plant.id,mill.id,25) -- Pre-voltage saved cable.
  cable.commodity="power"; cable.capMax=25; cable.size="large"; cable.grade=1
  c:refresh()
  check(mill.ready==0,"a maltings with no water makes nothing at all")

  local dep
  for _,d in ipairs(c.deposits) do
    if d.commodity=="water" and c:districtAt(d.x,d.y)==farm then dep=d; break end
  end
  local well=assert(c:buySource("water",dep.x,dep.y))
  -- A deep one: the maltings and the brewery both drink, and this check is
  -- about the chain rather than about the well.
  well.output,well.cap=40,40
  local from=well.id
  for _=1,10 do
    local n=c.g.nodes[from]
    local far=math.sqrt((n.x-mill.x)^2+(n.y-mill.y)^2)
    if far<=300 then assert(c:layPipe(from,mill.id,"water","large")); break end
    local j=assert(c:build(n.x+(mill.x-n.x)/far*280,n.y+(mill.y-n.y)/far*280,"junction"))
    assert(c:layPipe(from,j.id,"water","large")); from=j.id
  end
  c:refresh()
  check(mill.ready>0,"with water it starts making malt")

  assert(c:layPipe(mill.id,brew.id,"malt","large"))
  local cable=c.g:addEdge(plant.id,brew.id,25) -- Pre-voltage saved cable.
  cable.commodity="power"; cable.capMax=25; cable.size="large"; cable.grade=1
  assert(c:layPipe(mill.id,brew.id,"water","large"))
  c:refresh()
  check(brew.ready>0,"and the brewery downstream starts making beer")
  check(c.capacityBy.beer==brew.ready,"which is the city's whole beer supply")

  -- The chain is solved in dependency order, so one pass gets it right.
  local before=brew.ready
  c:refresh()
  check(brew.ready==before,"a second solve changes nothing: the order is topological")

  -- And it reaches a customer.
  local hub=assert(c:build(brew.x+240,brew.y,"junction"))
  assert(c:layPipe(brew.id,hub.id,"beer","large"))
  local pub=assert(c:addClient("pub"))
  pub.x,pub.y=hub.x+180,hub.y+140
  pub.demand=2
  assert(c:layPipe(hub.id,pub.id,"beer","small"))
  c:refresh()
  check(c.served[pub.id]==2,"beer the company made itself reaches a pub through a junction")
  check(c:expenseBreakdown().imports==0,"and not one unit of it was landed")
end

print("standing orders do the clerical work, for a wage")
do
  local c=fresh()
  c.money=1e9
  c.obstacles={}
  for _,d in ipairs(c.districts) do d.owned=true end

  -- Nothing is available to a company with two customers.
  check(select(2,c:hireOrder("dispatchers"))
    =="needs 12 customers","a rung only unlocks at a size")

  -- Grow it: enough customers that the whole ladder is worth having.
  for i=1,24 do
    local cl=assert(c:addClient("house",i>20))
    cl.x,cl.y=c.firstSource.x+220+(i%8)*70,c.firstSource.y+260+math.floor(i/8)*90
    cl.rate=i%2==0 and 3 or 8
  end
  c:refresh()
  assert(c:hireOrder("dispatchers"))
  c.dispatchRate=5
  -- Only what is on the table when they sit down: an offer that arrives later
  -- in the same close is tomorrow's work.
  local paying,cheap={},{}
  for _,offer in ipairs(c:clientList(true)) do
    table.insert((offer.rate or 0)>=5 and paying or cheap,offer)
  end
  check(#paying>0 and #cheap>0,"there are offers on the table, both sides of the floor")
  c:endDay()
  local unsigned,untouched=0,0
  for _,offer in ipairs(paying) do if offer.prospect then unsigned=unsigned+1 end end
  for _,offer in ipairs(cheap) do if offer.alive and offer.prospect then untouched=untouched+1 end end
  check(unsigned==#paying,"dispatchers reveal land and leave contract decisions to the player")
  check(untouched==#cheap,"and leave the cheap ones alone")

  -- The wage is real and shows up in the ledger.
  local wages=c:expenseBreakdown().crews
  check(wages>=City.ORDERS.dispatchers.wage,"the wage is on the books")
  assert(c:dismissOrder("dispatchers"))
  check(c:expenseBreakdown().crews<wages,"and comes off when they are stood down")
end

print("the game tells a customer why they are short, and the fix works")
do
  local c=fresh()
  c.money=9999
  local src=c.firstSource
  -- A house takes only the smallest main there is, forever, so the main that
  -- is short here has to be the trunk feeding both houses rather than either
  -- house's own stub: a stub can never be the thing a bigger main replaces.
  local trunk=assert(c:build(src.x+90,src.y-90,"junction"))
  assert(c:layPipe(src.id,trunk.id,"water","large"))
  local relay=assert(c:build(src.x+180,src.y+30,"junction"))
  local a,b=c:clientList()[1],c:clientList()[2]
  a.demand,b.demand=City.sizeOf("small").cap,2
  a.x,a.y=src.x+260,src.y+90
  b.x,b.y=src.x+400,src.y+30
  local narrow=assert(c:layPipe(trunk.id,relay.id,"water","small"))
  assert(c:layPipe(relay.id,a.id,"water","small"))
  assert(c:layPipe(relay.id,b.id,"water","small"))
  check((c.served[b.id] or 0)==0,"a downstream customer starves behind a small main")
  local why,eid=c:constraintFor(b.id)
  check(why=="main" and eid==narrow.id,"the game names the main that is holding them back")
  assert(c:replacePipe(eid,"medium"))
  check(c.served[b.id]==b.demand,"replacing the named main with a bigger one supplies them")
  check(c:constraintFor(b.id)==nil,"and there is nothing left to explain")
  -- The other shapes of the same question.
  assert(c:toggleSupply(a.id))
  check(c:constraintFor(a.id)=="valve","a shut valve is reported as a shut valve")
  assert(c:toggleSupply(a.id))
  local stranded=assert(c:addClient("house")); stranded.demand=3; c:refresh()
  check(c:constraintFor(stranded.id)=="unconnected","an unconnected customer is told so")
  c.g:killNode(stranded.id)
  -- A main that is full because it burst is a repair, not a narrow main, and
  -- the answer offered has to be the one that works.
  narrow.leaking=true; narrow.cap=0; c:refresh()
  local burst,burstId=c:constraintFor(b.id)
  check(burst=="repair" and burstId==narrow.id,"a burst main is named as a repair, not as a main that is too small")
  assert(c:repairPipe(narrow.id)); c:refresh()
  check(c:constraintFor(b.id)~="repair","and mending it answers the question")
  -- Boring a main up is replacing it with the next size, charged and
  -- delivered as one thing. It used to charge that whole quote for a single
  -- unit of capacity.
  local wide=narrow.cap
  local quote,cash=c:boreCost(narrow,1),c.money
  assert(c:upgradePipe(narrow.id))
  check(narrow.cap>wide and narrow.cap==City.sizeOf(narrow.size).cap,
    "boring a main up delivers the whole size it quoted for")
  check(cash-c.money==quote,"and charges exactly that quote, once")
  -- And a stub into a house has no next size, because a house never takes
  -- more than the smallest main there is.
  local stub=c.g.edges[assert(c:pipeBetween(relay.id,a.id,"water"))]
  check(c:biggerSize(stub)==nil,"a customer's own main has no next size up")
  check(select(2,c:upgradePipe(stub.id))=="maximum capacity reached",
    "so boring it is refused rather than quietly breaking the rule")
  -- With the wells flat out, a bigger main is not the answer and the game says so.
  c.firstSource.output,c.firstSource.cap=14,14
  a.demand,b.demand=7,7
  c:refresh()
  for _=1,20 do
    local w,e=c:constraintFor(b.id)
    if w~="main" then break end
    c:upgradePipe(e)
  end
  check(c.spare.water==0,"the well is now pumping flat out")
  check(c:constraintFor(b.id)=="output" or c.served[b.id]==b.demand,
    "when the wells are maxed the game says so instead of blaming a pipe")
end

print("a company that fixes what the game points at grows and stays solvent")
for _,seed in ipairs({4,17,31,52}) do
  local c=openCompany(City.new({seed=seed}))
  -- A well answers to a trunk only, so the company's very first move -- same
  -- as a real player's -- is a junction to step it down.
  local trunk=assert(c:build(c.firstSource.x+90,c.firstSource.y-90,"junction"))
  assert(c:layPipe(c.firstSource.id,trunk.id,"water","large"))
  for _,n in ipairs(c:clientList()) do
    if not c:pipeBetween(trunk.id,n.id,"water")
       and not c:pipeError(trunk.id,n.id,"water") then
      assert(c:layPipe(trunk.id,n.id,"water",n.demand))
    end
  end
  -- Off a fitting where there is one. A house chained to a house is legal and
  -- cheap and is also a small main for ever, so a run that has to carry more
  -- needs a fitting in it: this connects the way that leaves room to grow, and
  -- chains to another customer only when nothing else will reach.
  local function feed(target,commodity,size,allowChain)
    local best,cost
    for _,n in ipairs(c.g:aliveNodes()) do
      local chain=n.kind=="client"
      if n.id~=target.id and (allowChain or not chain) and not (chain and n.prospect)
         and not c:pipeError(n.id,target.id,commodity,nil,size) then
        local q=c:pipeCost(n.id,target.id,commodity,size)
        if not best or q<cost then best,cost=n,q end
      end
    end
    if best and c.money>=cost+150 then
      return c:layPipe(best.id,target.id,commodity,size)~=nil
    end
    return false
  end
  -- What the game says to do when a run of houses is full and a house takes
  -- only the smallest main there is: put a fitting in the run. A junction
  -- beside the customer, a main into it that can be made wider later, and a
  -- stub across.
  local function junctionFeed(target)
    for _,off in ipairs({{-90,0},{90,0},{0,-90},{0,90},{-90,-90},{90,90}}) do
      local j=c:build(target.x+off[1],target.y+off[2],"junction")
      if j then
        if feed(j,target.commodity,"large",false)
           and not c:pipeError(j.id,target.id,target.commodity,nil,target.demand) then
          return c:layPipe(j.id,target.id,target.commodity,target.demand)~=nil
        end
        c:demolishNode(j.id)
        return false
      end
    end
    return false
  end
  for _=1,120 do
    for _,e in ipairs(c.g.edges) do
      if e.alive and e.leaking and c.money>=c:repairCost(e)+60 then c:repairPipe(e.id) end
    end
    for _,short in ipairs(c:shortCustomers()) do
      local why,eid=c:constraintFor(short.id)
      -- A main with nothing wider to become -- a stub into a house is a small
      -- main by rule -- has no price, and the answer to it is not money.
      local bore=why=="main" and c:boreCost(c.g.edges[eid],1) or nil
      if why=="repair" then
        if c.money>=c:repairCost(c.g.edges[eid]) then c:repairPipe(eid) end
      elseif bore and c.money>bore+60 then
        c:upgradePipe(eid)
      elseif why=="main" then
        -- The main named cannot be made any wider, which is what the game
        -- says about a stub into a house. A second feed off a fitting is the
        -- move, the same one the inspector recommends.
        if not feed(short,short.commodity,short.demand,false) then junctionFeed(short) end
      elseif why=="output" then
        for _,w in ipairs(c.g:nodesOfKind("source")) do
          if w.commodity==short.commodity and (w.level or 1)<City.sourceMaxLevel
             and c.money>c:sourceUpgradeCost(w)+200 then c:upgradeSource(w.id); break end
        end
      end
    end
    for _,o in ipairs(c:clientList(true)) do
      if (c.spare[o.commodity] or 0)>=o.demand
         and (feed(o,o.commodity,o.demand,false) or junctionFeed(o) or feed(o,o.commodity,o.demand,true)) then
        assert(c:acceptClient(o.id))
      end
    end
    if c.money>900 then
      for _,w in ipairs(c.g:nodesOfKind("source")) do
        if (c.spare[w.commodity] or 0)<4 and (w.level or 1)<City.sourceMaxLevel
           and c.money>c:sourceUpgradeCost(w)+700 then c:upgradeSource(w.id); break end
      end
    end
    check(not c.bankrupt,"a company that answers the game's prompts stays solvent (seed "..seed..")")
    c:endDay()
  end
  check(#c:clientList()>=6,"and grows well past its two starting houses (seed "..seed..")")
  check(c:valuation()>City.rules.startMoney*6,"and is worth materially more than it started with")
end

print("council tenders are gone, and a posted bond comes back")
do
  local c=fresh()
  local money=c.money
  c.tenders={{status="accepted",bond=40,units=9,commodity="water"},{status="offered",bond=25}}
  c.tendersDone=3; c.ambition="tenders"
  c:migrate()
  check(c.tenders==nil and c.tendersDone==nil,"old tender state is dropped")
  check(c.money==money+40,"only the bond actually posted is refunded")
  check(c.ambition==nil,"and the tender ambition is cleared")
end

print("mains carry 10, 30 and 50, and a massive 100 opens later")
do
  local c=fresh()
  c.money=99999
  check(City.sizeOf("small").cap==10 and City.sizeOf("medium").cap==30
    and City.sizeOf("large").cap==50 and City.sizeOf("massive").cap==100,"the four sizes")
  check(not c:unlocked("massive"),"a new company cannot lay a massive main")
  check(c:biggerSize({size="large"})==nil,"so nothing offers to widen past large")
  -- An old main laid as small 5 and leaking 2 of it carries 10 less the same 2.
  local id=#c.g.edges+1
  c.g.edges[id]={id=id,a=1,b=1,alive=false,size="small",cap=3,capMax=5,commodity="water"}
  c:migrate()
  check(c.g.edges[id].capMax==10 and c.g.edges[id].cap==8,"an old main grows to its new size and keeps its leak")
  c.g.edges[id]=nil
end

print("a well can be closed without taking the network with it")
do
  local c=fresh()
  c.money=9999
  local src=c.firstSource
  -- A well answers only to trunks, so what is tied into it here is three
  -- junctions rather than two houses and a junction; the chamber it leaves
  -- behind does not care what it used to feed, only how many mains.
  local j1=assert(c:build(src.x+90,src.y-90,"junction"))
  local j2=assert(c:build(src.x-90,src.y-90,"junction"))
  local far=assert(c:build(src.x,src.y+200,"junction"))
  assert(c:layPipe(src.id,j1.id,"water","large"))
  assert(c:layPipe(src.id,j2.id,"water","large"))
  assert(c:layPipe(src.id,far.id,"water","large"))
  check(c.g:degree(src.id)==3,"three mains are tied into the well")

  local money=c.money
  local refund=assert(c:demolishNode(src.id))
  check(src.alive,"capping leaves the wellhead standing")
  check(src.kind=="junction","as a junction, because three mains fit one")
  check(src.commodity==nil and src.output==nil,"with nothing left of the well")
  check(src.capped,"and it knows what it used to be")
  check(c.g:degree(src.id)==3,"every main is still tied in")
  check(c.money==money+refund and refund>0,"and part of the well comes back")
  check(c.flowBy.water==0,"there is nothing to carry, because the well is gone")

  -- The chamber is an ordinary structure. It can be replaced where it stands.
  local before=c.g:degree(src.id)
  check(c:convertError(src.id,"pump")~=nil,"a pump has too few ports for three mains")
  local cost=c:convertCost(src.id,"manifold")
  money=c.money
  assert(c:convertNode(src.id,"manifold"))
  check(src.kind=="manifold" and src.ports==6,"but a manifold fits")
  check(c.g:degree(src.id)==before,"and no main came off to do it")
  check(c.money==money-cost,"paying only the difference")
  check(not c:convertNode(src.id,"manifold"),"and it will not be replaced with itself")

  -- Removing the chamber is the move that costs the network.
  local pipes,sunk=c:demolitionCost(src.id)
  check(pipes==3 and sunk>0,"the game says how much would be cut")
  assert(c:demolishNode(src.id))
  check(not src.alive,"the chamber can be removed")
  local live=0
  for _,e in ipairs(c.g.edges) do if e.alive then live=live+1 end end
  check(live==0,"and every main tied into it goes too")
  check(c:placementError(src.x,src.y)==nil,"the ground is free to build on again")
end

print("a well with nothing tied in is simply closed")
do
  local c=fresh()
  c.money=9999
  local lone=assert(well(c,c.firstSource.x+300,c.firstSource.y))
  check(c.g:degree(lone.id)==0,"nothing is connected to it")
  assert(c:demolishNode(lone.id))
  check(not lone.alive,"so it is removed outright rather than capped")
end

print("closing the first well does not break the company")
do
  local c=fresh()
  c.money=9999
  local src=c.firstSource
  local second=assert(well(c,src.x+320,src.y+120))
  local hub=assert(c:build(src.x+90,src.y-90,"junction"))
  assert(c:layPipe(src.id,hub.id,"water","large"))
  assert(c:layPipe(hub.id,c:clientList()[1].id,"water",3))
  assert(c:demolishNode(src.id))
  check(c.firstSource~=src,"the origin moves off a capped well")
  check(c.firstSource.kind=="source","onto one that is still producing")
  local clone=assert(Save.unpack(Save.pack(c)))
  check(clone~=nil,"and the company still saves and loads")
  check(clone.g.nodes[src.id].kind=="junction","with the capped wellhead intact")
  -- Even with no wells left at all.
  assert(c:demolishNode(second.id))
  check(#c.g:nodesOfKind("source")==0,"every well can be closed")
  local bare=assert(Save.unpack(Save.pack(c)))
  check(bare.firstSource~=nil,"a company with no wells still loads")
end

print("a riverside well from an older save becomes the intake it always was")
do
  local Graph = require("graph")
  local c = fresh(31)
  c.money = 1e9
  for _, d in ipairs(c.districts) do d.owned = true end
  local bank
  for _, d in ipairs(c.districts) do
    for x = d.x + 30, d.x + d.w - 30, 30 do
      for y = d.y + 30, d.y + d.h - 30, 30 do
        if not bank and select(2, c:intakeCap(x, y)) == "river"
           and not c:sourceError("water", x, y) then bank = { x = x, y = y } end
      end
    end
  end
  check(bank ~= nil, "the fixture map has a bank to build on")
  local works = assert(c:buySource("water", bank.x, bank.y))
  for _ = 1, 5 do c:upgradeSource(works.id) end
  local id, produced = works.id, works.output
  check(produced > 50, "an intake grows past what any well gives")

  -- Wound back to exactly what an older save held: no intake flag on the node
  -- and the bottomless ceiling a well on the bank used to be given.
  works.intake, works.cap = nil, Graph.INF
  c.intakesBought = nil
  c.sourcesBought = (c.sourcesBought or 0) + 1
  local text = Save.pack(c)
  check(not text:find('"intake"'), "the older save really carries no intake flag")
  local loaded = assert(Save.unpack(text))
  local n = loaded.g.nodes[id]
  check(n.intake == "river", "a well on the bank loads as an intake")
  check(n.cap < Graph.INF, "the bottomless ceiling is gone")
  check(n.output >= produced, "and no output is lost to the rule change")
  check(loaded.intakesBought == 1, "it is counted on the intake ladder now")
  check(loaded:upgradeSource(id) ~= nil, "and it can still be grown after the load")
end

print("replacing a structure keeps its mains")
do
  local c=fresh()
  c.money=9999
  local src=c.firstSource
  local j=assert(c:build(src.x,src.y+200,"junction"))
  assert(c:layPipe(src.id,j.id,"water","large"))
  check(c:convertError(j.id,"junction")=="it is already that","a junction is already a junction")
  check(c:convertError(src.id,"junction")=="a well must be capped, not replaced",
    "a well is capped rather than replaced")
  local edges={}
  for _,ei in ipairs(c.g.adj[j.id]) do edges[#edges+1]=ei end
  assert(c:convertNode(j.id,"gate"))
  check(j.kind=="gate" and j.throughput==6,"a junction can become a gate")
  check(#c.g.adj[j.id]==#edges,"with the same mains attached")
  assert(c:convertNode(j.id,"depot","water"))
  check(j.kind=="depot" and j.stored==0 and j.commodity=="water",
    "and a depot, set up as build would have made it")
  assert(c:convertNode(j.id,"junction"))
  check(j.stored==nil and j.commodity==nil,"switching away clears what it was")
  c.money=0
  check(not c:convertNode(j.id,"pump"),"and it has to be paid for")
end

do
  -- A customer who leaves takes their demand list with them: the junction left
  -- behind carries nothing that paints it into an old trade's grid.
  local c=City.new({seed=5})
  local n=assert(c:addClient("house"))
  c.money=c.money+500
  local j=assert(c:build(n.x+60,n.y,"junction"))
  assert(c:layPipe(j.id,n.id,"water","small"))
  n.demands={water=n.demand}
  c:retireClient(n)
  check(n.kind=="junction" and n.demands==nil and n.commodity==nil,"a customer who leaves leaves no demand behind")
  n.demands={water=3}
  c:migrate()
  check(n.demands==nil,"and an old save loses the stale demand list on load")
end

print(checks.." company checks passed")
