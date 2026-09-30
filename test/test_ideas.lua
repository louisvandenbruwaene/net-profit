package.path='src/?.lua;'..package.path
local City=require('city')
City.FLAT_USAGE = true -- these checks are about flow: customers draw their whole contract
local Save=require('company_save')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function fresh()
 local c=City.new({seed=24,obstacles=0}); c.money=1e7; c.obstacles={}; c.stock={steel=1000,concrete=1000}
 for _,d in ipairs(c.districts) do d.owned=true end
 c.permits={river=true,park=true,bedrock=true}; c.lining=4
 return c
end
local function node(c,kind,x,y,com,out)
 local n=c.g:addNode(x,y,kind); n.commodity=com; n.output=out; return n
end
local function edge(c,a,b,key)
 local e=c.g:addEdge(a.id,b.id,50); e.capMax=50; e.size='large'; e.grade=3; e.commodity=key; return e
end
-- Source upgrades, physical ports, storage and obsolete tool removal.
do
 local c=fresh(); local d
 for _,s in ipairs(c.deposits) do if s.opening then d=s end end
 local n=assert(c:buySource('water',d.x,d.y))
 check(n.ports==1 and n.output==20 and n.cap==50,'well starts at 20 with one outlet and a 50 ceiling')
 local previous=0
 for _,want in ipairs({30,40,50}) do
  local cost=c:sourceUpgradeCost(n); check(cost>previous,'successive upgrades cost more'); previous=cost
  assert(c:upgradeSource(n.id)); check(n.output==want,'well upgrade output is exact')
 end
 check(not c:upgradeSource(n.id),'fourth upgrade refused')
 check(not c:build(1500,1050,'tower'),'treatment tower removed')
 local depot=assert(c:build(1600,1050,'depot','water'))
 check((depot.capacityStore or City.depotCapacity)==100,'water depot stores 100')
end
-- Filter direction, bypasses, old mains, accumulated minerals and maintenance.
do
 local c=fresh(); local well=node(c,'source',1200,1100,'water',50)
 local filter=node(c,'filtration',1270,1100); local hub=node(c,'manifold',1340,1100)
 local incoming=edge(c,well,filter,'water'); local outgoing=edge(c,filter,hub,'water')
 c:refresh(); check(not incoming.filtered and outgoing.filtered,'filter protects only downstream')
 outgoing.calcification=105; c:refresh(); check(outgoing.calcification==105,'filter does not erase existing deposits')
 local bypass=edge(c,well,hub,'water'); c:refresh(); check(not outgoing.filtered,'raw-water bypass defeats clean downstream status')
 c.g:killEdge(bypass.id); c:refresh(); check(outgoing.filtered,'removing bypass restores protection')
 incoming.calcification=99; c.day=100
 local risk=c:leakChance(incoming); incoming.calcification=140
 check(c:leakChance(incoming)>risk,'mineral deposits increase leak probability after day 100')
 incoming.hydraulic=true
 local clogged=c:waterRating(incoming); incoming.calcification=0
 check(c:waterRating(incoming)>clogged,'mineral buildup reduces usable flow')
 incoming.calcification=120; incoming.leaking=true; incoming.cap=40
 assert(c:repairPipe(incoming.id)); check(incoming.calcification==0 and incoming.cap==50,'repair resets mineral age')
end
-- A real saltwater connection, both products, and interruption on lost feed.
do
 local c=fresh(); local sea=assert(c:buySource('saltwater',200,-40))
 local filter=assert(c:build(200,40,'filtration'))
 local purifier=assert(c:build(260,100,'works','purifier'))
 check(not c:layPipe(sea.id,filter.id,'saltwater','large',nil,2),'saltwater rejects unarmoured pipe')
 assert(c:layPipe(sea.id,filter.id,'saltwater','large',nil,3))
 local feed=assert(c:layPipe(filter.id,purifier.id,'saltwater','large',nil,3))
 local h=node(c,'client',310,100,'water'); h.demand=8; h.rate=4; h.clientType='house'; h.grace=100
 local salt=node(c,'works',310,170); salt.recipe='foodworks'
 edge(c,purifier,h,'water'); edge(c,purifier,salt,'salt')
 c:refresh()
 check(purifier.ready==16 and purifier.coproductReady==16,'purifier produces matching 16 clean water and salt')
 check((c.detail.works[salt.id].salt or 0)>0,'salt reaches an actual downstream factory')
 check((c.served[h.id] or 0)==8,'purified water reaches a customer')
 check(not c:replacePipe(feed.id,'large',1),'saltwater insulation cannot be downgraded below armoured')
 local copy=assert(Save.unpack(Save.pack(c)))
 check(copy.g.nodes[purifier.id].ready==16,'purification survives save round trip')
 c.g:killEdge(feed.id); c:refresh()
 check(purifier.ready==0 and purifier.coproductReady==0,'loss of saltwater stops both products')
end
-- Market mean, aging variance, per-worker tenure and payroll persistence.
do
 local c=fresh(); local mean,sd=c:investmentDistribution()
 check(mean==.1 and sd==0,'market starts at 10% mean and zero spread')
 assert(c:hireOrder('analysts')); c.day=8
 mean,sd=c:investmentDistribution()
 check(math.abs(mean-.21)<1e-9 and math.abs(sd-.07)<1e-9,'one analyst gains one point per completed week')
 assert(c:hireOrder('analysts')); mean=c:investmentDistribution()
 check(math.abs(mean-.31)<1e-9,'new analysts have their own tenure')
 check(c:orderWages()==51,'analyst wages grow one percent per completed week')
 local copy=assert(Save.unpack(Save.pack(c)))
 check(copy:investmentDistribution()==mean and copy:workerCount('analysts')==2,'analyst tenure survives save')
 assert(c:dismissOrder('analysts')); check(#c.analystHired==1,'dismissal removes one analyst')
end
-- The spread widens until it would start paying the player for the tail the
-- payout floor clips off, and then stops.
do
 local c=fresh(); c.day=400
 local mean,sd=c:investmentDistribution()
 check(mean==.1 and math.abs(sd-.275)<1e-9,'the spread stops widening')
 check(math.abs((1+mean)/sd-4)<1e-9,'where a total loss is four deviations out')
 assert(c:hireOrder('analysts'))
 local m2,sd2=c:investmentDistribution()
 check(m2>mean and sd2>sd,'an analyst buys mean, and a little more room to use it')
 check(m2/sd2>mean/sd,'and improves the return against the risk')
 check(math.abs((1+m2)/sd2-4)<1e-9,'with the total loss still that far out')
 c.day=12; local _,early=c:investmentDistribution()
 check(math.abs(early-.11)<1e-9,'an early company is still under the cap')
end
-- Stable discounts with the requested categorical frequencies and separate holdings.
do
 local c=fresh(); local totals={[0]=0,[10]=0,[20]=0,[30]=0,[40]=0,[50]=0}
 local d=c:surveyCell(8,8)
 for day=1,10000 do
  c.day=day; local rate=math.floor(c:landDiscount(d)*100+.5); totals[rate]=totals[rate]+1
  check(c:landDiscount(d)==c:landDiscount(d),'price inspection never rerolls discounts')
 end
 for _,percent in ipairs({10,20,30,40,50}) do
  local wanted=(60-percent)/1000
  check(math.abs(totals[percent]/10000-wanted)<.012,'land offer frequency matches design')
 end
 c.day=1; d.owned=false
 check(c:buyDistrict(d.id)~=nil,'nonadjacent holdings can be bought')
 for _,land in ipairs(c.districts) do land.owned=true end
end
-- Electricity requests do not silently change an existing signed contract.
do
 local c=fresh(); local h=c:clientList(true)[1]; c:acceptClient(h.id)
 c.unlocked=function() return true end
 -- Only the households that want a second utility are ever asked, and which
 -- ones those are comes from the company's seed. Both answers are pinned here.
 c.wantsSecondUtility=function() return false end
 assert(c:buyLicence('power'))
 check(not h.powerRequest and not (h.demands or {}).power,'a household that wants only water is never asked for more')
 c.licences.power=false; c.wantsSecondUtility=function() return true end
 assert(c:buyLicence('power'))
 check(h.powerRequest and not h.demands.power,'licence queues electricity for a household that wants it')
 local pole=node(c,'pole',h.x+60,h.y); assert(c:upgradeTower(pole.id,'transformer'))
 check(c:pipeError(pole.id,h.id,'power')==nil,'a cable can be run to them before the request is accepted')
 assert(c:layPipe(pole.id,h.id,'power','small'))
 assert(c:acceptClient(h.id)); check(h.demands.power==2,'acceptance activates a 10 kWh/day demand')
 -- Which households want a second utility comes from the company and the
 -- building, so it is the same share every time and the same answer after a
 -- reload. It is a possibility, not a rule: roughly a third.
 local d=fresh(); local want=0
 for id=1,3000 do if d:unit(id,29)<City.DUAL.share then want=want+1 end end
 check(math.abs(want/3000-City.DUAL.share)<0.04,'about a third of households ever ask for the second utility')
 local kept=Save.unpack(Save.pack(c))
 check(kept:wantsSecondUtility(kept.g.nodes[h.id])==c:wantsSecondUtility(h),
   'and the same households still want it after a reload')
 local transformer=assert(c:build(1400,1100,'transformer'))
 local set=c:voltagesAt(transformer)
 check(set.low and set.medium and set.high and transformer.ports==6,'standalone transformer changes any voltage')
end
-- Harvested resources can enter the commodity network, without duplication.
do
 local c=fresh(); c.stock.gems=5
 local depot=assert(c:build(1400,1100,'depot','gems'))
 assert(c:loadDepot(depot.id)); check(depot.stored==5 and c.stock.gems==0,'inventory transfers into physical storage')
 check(not c:loadDepot(depot.id),'inventory cannot be transferred twice')
end
-- Storage receives actual surplus and never diverts a customer's supply.
do
 local c=fresh(); local well=node(c,'source',1200,1100,'water',20)
 local hub=node(c,'manifold',1250,1100)
 local depot=assert(c:build(1300,1100,'depot','water'))
 local h=node(c,'client',1350,1100,'water'); h.demand=8; h.rate=4; h.clientType='house'; h.grace=100
 local feed=edge(c,well,hub,'water'); edge(c,hub,depot,'water'); edge(c,hub,h,'water')
 c:refresh()
 check(c.served[h.id]==8 and c.detail.depot[depot.id]==12,'storage fills only from surplus after customer delivery')
 c.leakChance=function() return 0 end; c:endDay()
 check(depot.stored==12,'only physically received water is stored')
 c.g:killEdge(feed.id); c:refresh()
 check(c.served[h.id]==8,'stored water sustains customers when the well is disconnected')
 c:endDay(); check(depot.stored==4,'delivered stored water is deducted once')
 local isolated=node(c,'depot',1850,1500,'water'); isolated.stored=0
 local dead=node(c,'junction',1650,1100); edge(c,isolated,dead,'water')
 c:refresh(); c:endDay(); check(isolated.stored==0,'unrelated well surplus cannot teleport into storage')
end
-- Clearing is finite, and jewelry sales are real deliveries in the ledger.
do
 local c=fresh(); c.obstacles={{x=1200,y=1100,r=100,kind='bedrock'}}
 local before=c.money; c.random=function() return 0 end
 assert(c:clearTerrain(1))
 check(#c.obstacles==0 and c.stock.rock==100 and c.stock.gems==1 and c.money==before-3500,'demolition removes terrain and yields finite stone and a gem')
 check(not c:clearTerrain(1),'cleared terrain cannot be harvested twice'); c.random=nil
 local gems=assert(c:build(1400,1100,'depot','gems')); c.stock.gems=4; c:loadDepot(gems.id)
 local works=assert(c:build(1470,1100,'works','jeweler'))
 local power=node(c,'source',1470,1170,'power',20)
 local yard=assert(c:build(1540,1100,'dc'))
 edge(c,gems,works,'gems'); edge(c,power,works,'power'); edge(c,works,yard,'jewelry')
 c:refresh(); check((c.detail.yard.jewelry or 0)==2,'jeweler consumes gems and power and delivers two jewelry')
 local revenue=c:dailyRevenue(); c.leakChance=function() return 0 end
 local report=c:endDay()
 check(report.jewelryIncome==1800 and report.revenue>=1800 and (c.stock.jewelry or 0)==0,'jewelry is sold once and recorded in revenue')
 check(revenue>=1800,'next-day estimate includes jewelry sales')
end
print(checks..' ideas checks passed')
