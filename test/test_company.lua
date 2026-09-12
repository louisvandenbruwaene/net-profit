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
-- A well only goes where the survey marked water, so a test that wants one at
-- a particular spot marks that spot first. Yield and discount are left at 1 so
-- the well is priced and sized exactly like the plain well these tests were
-- written against.
local function well(c,x,y,commodity)
  c.deposits[#c.deposits+1]=
    {x=x,y=y,commodity=commodity or "water",taken=false,yield=1,discount=1}
  return c:buySource(commodity or "water",x,y)
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

print("signed contracts, finite output, and household service valves")
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
  local home=c.firstSource
  first.x,first.y=home.x-150,home.y+120
  second.x,second.y=home.x-50,home.y+120
  first.demand,second.demand=3,4
  local main=assert(c:layPipe(c.firstSource.id,first.id,"water",7))
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
  local tower=assert(c:build((a.x+b.x)/2,(a.y+b.y)/2+60,"tower"))
  check(c:leakChance(e)<original/2,"local treatment protects mains in its radius")
  local bareRepair=c:repairCost(e)
  c:reinforcePipe(e.id)
  check(c:leakChance(e)<original/4,"lining stacks with local treatment")
  check(c:repairCost(e)<bareRepair,"lining makes the repair it cannot prevent cheaper")
  c:demolishNode(tower.id)
  check(c:leakChance(e)==original*City.GRADES[2].risk,"removing treatment removes its protection")
  check(c:reinforcePipe(e.id) and e.grade==3,"a lined main can be armoured")
  check(c:leakChance(e)==original*City.GRADES[3].risk,"armour is the last grade")
  check(not c:reinforcePipe(e.id),"there is nothing beyond armour")
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
  assert(c:layPipe(rig.id,works.id,"oil",works.demand))
  check(c.served[works.id]==works.demand,"a rig on the deposit supplies the works")

  -- Beer is landed, hauled inland by track, and only then piped.
  local edge=c.districts[5]
  edge.owned=true
  local haven=assert(c:build(edge.x+90,edge.y+edge.h/2,"terminal"))
  check(haven.haven=="port","the west edge opens onto the estuary")
  check(haven.commodity==nil and haven.output==nil,"a haven carries every trade, without a ceiling")
  local yard=assert(c:build(edge.x+620,edge.y+edge.h/2,"junction"))
  check(select(2,c:layPipe(haven.id,yard.id,"beer",6))=="a haven ships by track only",
    "nothing is piped straight out of a haven")
  assert(c:layPipe(haven.id,yard.id,"beer",6,true))
  local pub=assert(c:addClient("pub"))
  pub.x,pub.y=yard.x,yard.y+200
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
  local water=c:pipeCost(src.id,far.id,"water",4)
  local power=c:pipeCost(src.id,far.id,"power",4)
  local beer=c:pipeCost(src.id,far.id,"beer",4)
  local oil=c:pipeCost(src.id,far.id,"oil",4)
  check(water<power and power<beer and beer<oil,
    "each trade has its own price: water < power < beer < oil")
  check(c:pipeCost(src.id,far.id,"water",8)>c:pipeCost(src.id,far.id,"water",2),
    "a wider bore costs more")
  -- Bore is charged per metre, so widening a long run costs more than a short one.
  local e1=assert(c:layPipe(src.id,near.id,"water",2))
  local e2=assert(c:layPipe(src.id,far.id,"water",2))
  check(c:boreCost(e2,1)>c:boreCost(e1,1),"widening a long main costs more than widening a stub")
  check(c:repairCost(e2)>c:repairCost(e1),"repairing a long main costs more")
  check(c:pipeUpkeep(e2)>c:pipeUpkeep(e1),"and it costs more to run every day")
end

print("lining is optional, and pays for itself")
do
  local c=fresh()
  c.money=99999
  local src=c.firstSource
  local far=assert(c:build(src.x+280,src.y,"junction"))
  local e=assert(c:layPipe(src.id,far.id,"water",6))
  local bareRisk,bareRepair=c:leakChance(e),c:repairCost(e)
  local perDay,days=c:liningPayback(e)
  check(perDay>0 and days>0,"the inspector can state what lining is worth")
  local cost=c:liningCost(e)
  assert(c:reinforcePipe(e.id))
  check(c:leakChance(e)<bareRisk and c:repairCost(e)<bareRepair,
    "lining cuts both the risk and the bill")
  check(math.abs(cost/perDay-days)<2,"the stated payback matches the price and the saving")
  -- Armour is the luxury grade: slower to pay back, but it halves the bleed.
  assert(c:reinforcePipe(e.id))
  check(City.GRADES[e.grade].decay==2,"an armoured main loses capacity at half speed")
  e.leaking=true
  local cap=e.cap
  c:endDay()
  check(e.cap==cap,"armour holds its capacity through the first day of a leak")
  c:endDay()
  check(e.cap==cap-1,"and gives way on the second")
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
  check(c:sourceIncome(src)>0,"wholesale income scales with what the well produces")
  for _=1,10 do c:upgradeSource(src.id) end
  check(src.level==City.sourceMaxLevel,"a well tops out")
  check(not c:upgradeSource(src.id),"and refuses to go further")
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
  check(c:districtError(far)=="not next to your ground","the company grows outward, not by leaping")
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

  -- A haven stands on the edge of the map and nowhere else.
  c.obstacles={}
  local spot={x=home.x+90,y=home.y+610}
  check(c:placementError(spot.x,spot.y)==nil,"there is clear ground in the home district")
  check(select(2,c:build(spot.x,spot.y,"terminal"))
    =="a haven stands on the edge: the estuary, the highway or the apron",
    "a haven cannot stand inland")
  -- And on the edge it works, with track to move what it lands.
  local hd=c.districts[5]
  hd.owned=true
  local t=assert(c:build(hd.x+130,hd.y+hd.h/2,"terminal"))
  check(t.haven=="port","the haven opens onto the gateway it was built beside")
  check(select(2,c:build(hd.x+130,hd.y+hd.h/2-300,"terminal"))
    =="naval port already has its haven","one haven to each gateway")
  local j=assert(c:build(hd.x+hd.w-130,hd.y+hd.h/2,"junction"))
  check(c:pipeError(t.id,j.id,"water")=="a haven ships by track only","no main comes off a haven")
  local rail=assert(c:layPipe(t.id,j.id,"water",8,true))
  check(rail.rail and c:leakChance(rail)==0,"track carries it, and never corrodes")
  check(c:liningCost(rail)==nil,"there is nothing to line on a railway")
  local spur=c:build(hd.x+hd.w-130,hd.y+hd.h/2-260,"junction")
  check(select(2,c:layPipe(j.id,spur.id,"water",4,true))=="track must start or end at a haven",
    "track has to come from somewhere")
  c:refresh()
  check(c:expenseBreakdown().imports==0,"a haven idle at its berths costs nothing per unit")
  -- It only bills for what it actually moves, so a haven is a margin decision
  -- rather than a standing bill.
  local buyer=assert(c:addClient("house"))
  buyer.x,buyer.y=j.x,j.y+120
  buyer.demand=6
  assert(c:layPipe(j.id,buyer.id,"water",6))
  check(c.served[buyer.id]==6,"freight reaches a customer over the track")
  local bill=c:expenseBreakdown()
  check(bill.imports>0,"and now the haven bills for every unit it landed")
  check(math.abs(bill.imports-6*City.trade.water.importCost*City.HAVENS.port.import)<0.01,
    "the import charge is exactly the units moved times the rate")
  check(bill.haulage>0,"and the haulage is charged on what the track moved")
  check(c:sourceIncome(t)==0,"a haven pays no wholesale, because it produces nothing")
end

print("the game tells a customer why they are short, and the fix works")
do
  local c=fresh()
  c.money=9999
  local src=c.firstSource
  local a,b=c:clientList()[1],c:clientList()[2]
  a.demand,b.demand=3,4
  a.x,a.y=src.x+200,src.y
  b.x,b.y=src.x+400,src.y
  -- Chain the second house through the first on a main only wide enough for one.
  local narrow=assert(c:layPipe(src.id,a.id,"water",3))
  assert(c:layPipe(a.id,b.id,"water",4))
  check((c.served[b.id] or 0)==0,"a downstream customer starves behind a narrow main")
  local why,eid=c:constraintFor(b.id)
  check(why=="main" and eid==narrow.id,"the game names the main that is holding them back")
  for _=1,4 do c:upgradePipe(eid) end
  check(c.served[b.id]==b.demand,"widening the named main supplies them")
  check(c:constraintFor(b.id)==nil,"and there is nothing left to explain")
  -- The other shapes of the same question.
  assert(c:toggleSupply(a.id))
  check(c:constraintFor(a.id)=="valve","a shut valve is reported as a shut valve")
  assert(c:toggleSupply(a.id))
  local stranded=assert(c:addClient("house")); stranded.demand=3; c:refresh()
  check(c:constraintFor(stranded.id)=="unconnected","an unconnected customer is told so")
  c.g:killNode(stranded.id)
  -- With the wells flat out, a wider pipe is not the answer and the game says so.
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
  local c=City.new({seed=seed})
  for _,n in ipairs(c:clientList()) do
    assert(c:layPipe(c.firstSource.id,n.id,"water",n.demand))
  end
  for _=1,120 do
    for _,e in ipairs(c.g.edges) do
      if e.alive and e.leaking and c.money>=c:repairCost(e)+60 then c:repairPipe(e.id) end
    end
    for _,short in ipairs(c:shortCustomers()) do
      local why,eid=c:constraintFor(short.id)
      if why=="main" and c.money>c:boreCost(c.g.edges[eid],1)+60 then
        c:upgradePipe(eid)
      elseif why=="output" then
        for _,w in ipairs(c.g:nodesOfKind("source")) do
          if w.commodity==short.commodity and (w.level or 1)<City.sourceMaxLevel
             and c.money>c:sourceUpgradeCost(w)+200 then c:upgradeSource(w.id); break end
        end
      end
    end
    for _,o in ipairs(c:clientList(true)) do
      local best,cost
      for _,n in ipairs(c.g:aliveNodes()) do
        if not (n.kind=="client" and n.prospect) and not c:pipeError(n.id,o.id,o.commodity) then
          local q=c:pipeCost(n.id,o.id,o.commodity,o.demand)
          if not best or q<cost then best,cost=n,q end
        end
      end
      if best and c.money>=cost+150 and (c.spare[o.commodity] or 0)>=o.demand then
        assert(c:layPipe(best.id,o.id,o.commodity,o.demand))
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

print("a tender is a contract with a bond, not free money")
do
  local c=fresh()
  c.money=9999
  c.licences.water=true
  c.flowBy={water=6}
  local t=assert(c:rollTender())
  c.nextTender=2
  c.tenders[1]=t
  check(t.status=="offered","a tender arrives as an offer")
  check(t.bond>0 and t.bond<t.reward,"with a bond smaller than the reward")
  check(t.units>6,"asking for more than the company currently delivers")

  -- Ignoring one costs nothing.
  local money=c.money
  c.day=t.offerExpires
  c:tenderProgress()
  check(#c.tenders==0 and c.money==money,"an unanswered offer is withdrawn for free")

  -- Declining costs nothing either.
  c.tenders[1]=assert(c:rollTender()); c.tenders[1].id=7
  money=c.money
  assert(c:declineTender(7))
  check(#c.tenders==0 and c.money==money,"declining costs nothing")

  -- Accepting stakes the bond.
  local t2=assert(c:rollTender()); t2.id=9; t2.units=4; t2.days=2
  c.tenders[1]=t2
  money=c.money
  assert(c:acceptTender(9))
  check(c.money==money-t2.bond,"accepting posts the bond out of the till")
  check(t2.status=="accepted" and t2.expires>c.day,"and starts the delivery clock")
  check(not c:acceptTender(9),"a signed tender cannot be signed twice")
  check(not c:declineTender(9),"nor declined after signing")

  -- Delivering returns the bond with the reward.
  c.flowBy={water=t2.units}
  c.day=c.day+1
  local paid=c:tenderProgress()
  check(paid==0 and t2.met==1,"one close met is not yet delivery")
  c.day=c.day+1
  paid=c:tenderProgress()
  check(paid==t2.reward+t2.bond,"delivering pays the reward and returns the bond")
  check(#c.tenders==0 and c.tendersDone==1,"and closes the contract")

  -- Failing forfeits it.
  local t3=assert(c:rollTender()); t3.id=11; t3.units=99; t3.days=2
  c.tenders[1]=t3
  assert(c:acceptTender(11))
  local rep=c.reputation
  c.flowBy={water=0}
  c.day=t3.expires
  local _,lost=c:tenderProgress()
  check(lost==t3.bond,"missing the deadline forfeits the bond")
  check(c.reputation<rep,"and costs reputation")
  check(#c.tenders==0,"and closes the contract")

  check(c:tenderShortfall({commodity="water",units=10})==10,"shortfall is what is still missing")
  c.flowBy={water=7}
  check(c:tenderShortfall({commodity="water",units=10})==3,"and shrinks as supply grows")
end

print("a well can be closed without taking the network with it")
do
  local c=fresh()
  c.money=9999
  local src=c.firstSource
  local a,b=c:clientList()[1],c:clientList()[2]
  assert(c:layPipe(src.id,a.id,"water",a.demand))
  assert(c:layPipe(src.id,b.id,"water",b.demand))
  local far=assert(c:build(src.x,src.y+200,"junction"))
  assert(c:layPipe(src.id,far.id,"water",4))
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
  assert(c:layPipe(src.id,c:clientList()[1].id,"water",3))
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

print("replacing a structure keeps its mains")
do
  local c=fresh()
  c.money=9999
  local src=c.firstSource
  local j=assert(c:build(src.x,src.y+200,"junction"))
  assert(c:layPipe(src.id,j.id,"water",4))
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
  check(not c:convertNode(j.id,"tower"),"and it has to be paid for")
end

print(checks.." company checks passed")
