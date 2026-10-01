package.path='src/?.lua;'..package.path
local City=require('city')
City.FLAT_USAGE = true -- these checks are about flow: customers draw their whole contract
local Graph=require('graph')
local Save=require('company_save')
local count=0
local function check(v,m) assert(v,m); count=count+1 end
local function world()
 local c=City.new({seed=31,obstacles=0}); c.money=1e6; c.obstacles={}; c.permits={park=true,bedrock=true,river=true}
 for _,d in ipairs(c.districts) do d.owned=true; d.population=0 end
 c.districts[5].population=600; c.districts[6].population=600
 for _,n in ipairs(c.g:aliveNodes()) do c.g:killNode(n.id) end
 return c
end
local function node(c,kind,x,y,typ)
 local n=c.g:addNode(x,y,kind)
 if kind=='client' then n.clientType=typ or 'house'; n.commodity='water'; n.demand=3; n.rate=4; n.grace=3 end
 return n
end
local function road(c,a,b,kind)
 -- Over water only a bridge will do.
 c.buildRoadType=c:waterAlong(a.x,a.y,b.x,b.y)>0 and 'bridge' or kind or 'road'
 return assert(c:layLink(a.id,b.id,'road'))
end
-- Physical topology, exact daily vehicle tolls and deterministic refreshes.
do
 local c=world(); local a=node(c,'client',1400,900); local b=node(c,'client',500,900)
 local x=node(c,'interchange',1200,900); local y=node(c,'interchange',700,900)
 road(c,a,x); road(c,b,y)
 check(c.transit.carried==0,'a destination in another component is unreachable')
 local h=road(c,x,y,'highway')
 local cars=c.transit.byLink[h.id].car or 0
 check(cars>0 and cars<=6,'residents with a car drive to the other house: three live in each')
 check(c.transit.tolls==cars,'every car on the highway pays its toll once')
 check(c.transit.trips==6,'every resident picks somewhere to go')
 local destination=c.transit.byNode[a.id].destination; local rng=c.rng
 c:refresh(); check(c.transit.tolls==cars and c.rng==rng,'refresh neither rerolls trips nor advances RNG')
 check(c.transit.byNode[a.id].destination==destination,'daily destination stays stable')
 assert(c:setLinkPrice(h.id,3)); check(c.transit.tolls==3*cars,'a dearer toll is paid by the same drivers while the trip is worth it')
 assert(c:setLinkPrice(h.id,12)); check(c.transit.tolls<12*cars,'a toll dearer than the trip is worth keeps drivers at home')
 assert(c:setLinkPrice(h.id,3))
 local clone=assert(Save.unpack(Save.pack(c)))
 check(clone.links[h.id].roadType=='highway' and clone.transit.tolls==3*cars,'road variants and deterministic tolls survive saving')
 assert(c:demolishLink(h.id)); check(c.transit.tolls==0,'cutting the highway removes its traffic and income')
end
-- Road variants and appropriate junctions.
do
 local c=world(); local a=node(c,'client',1400,900); local b=node(c,'works',1500,900)
 local l=road(c,a,b,'offroad')
 check(c:roadPath(a.id,b.id,'car') and not c:roadPath(a.id,b.id,'truck'),'only cars use offroads')
 check(not c:roadConnected(a.id,b.id),'buses cannot route over offroads')
 check(l.toll==0 and not c:setLinkPrice(l.id,1),'offroads are free')
 local cross=node(c,'intersection',1600,900); local round=node(c,'roundabout',1700,900); local stop=node(c,'stop',1800,900)
 c.buildRoadType='road'; check(c:linkError(cross.id,round.id,'road')==nil,'a road node takes any road and becomes the junction it needs')
 c.buildRoadType='highway'; check(c:linkError(round.id,stop.id,'road')~=nil,'stops reject highways')
 c.buildRoadType='offroad'; check(c:linkError(stop.id,a.id,'road')~=nil,'bus stops reject offroads')
 check(c:linkError(a.id,b.id,'bus')~=nil,'houses and factories are not bus boarding points')
 check(Graph.KINDS.stop.name=='BUS STOP','stops are named bus stops')
end
-- Bus fares and service withdrawal when the physical route disappears.
do
 local c=world(); local a=node(c,'stop',1500,900); local b=node(c,'stop',500,900)
 -- A house a short walk from each stop, with no road of its own.
 local ha=node(c,'client',1500,1100); local hb=node(c,'client',500,1100)
 check(not c:layLink(a.id,b.id,'bus'),'a bus requires a physical road first')
 local l=road(c,a,b); check(l.toll==0,'normal roads charge no toll')
 local bus=assert(c:layLink(a.id,b.id,'bus'))
 check(c.transit.fares>0 and c.transit.tolls==0,'passengers pay bus fares on a free road')
 check(c.transit.fares==3*(c.transit.byLink[bus.id].trips or 0) and c.transit.byLink[bus.id].trips==6,
   'everyone in both houses walks to a stop, rides and pays the fare')
 check((c.transit.byNode[a.id].boarded or 0)+(c.transit.byNode[b.id].boarded or 0)==6,'boardings are counted at the stops')
 check(c.transit.byLink[l.id].bus==1,'the bus itself traverses the road once')
 assert(c:addVehicle(bus.id)); check(bus.vehicles==2,'bus fleet controls still work')
 assert(c:demolishLink(l.id)); check(c.transit.fares==0,'a broken bus road stops passenger fares')
end
-- Container trucks deliver several commodities over shared normal roads.
do
 local c=world(); c.licences.food=true
 local a=node(c,'terminal',1400,900); a.haven='highway'
 local b=node(c,'client',1500,900,'market'); b.commodity='food'; b.demand=4
 check(not c:layPipe(a.id,b.id,'food',1,'highway'),'trucks require a connected road')
 local l=road(c,a,b)
 local e=assert(c:layPipe(a.id,b.id,'food',1,'highway'))
 check(c.served[b.id]==4,'container trucks serve a food store directly')
 check((c.transit.byLink[l.id].truck or 0)>0,'loaded containers are counted on the physical road')
 assert(c:addWagon(e.id,'water')); check(e.wagons.food and e.wagons.water,'one truck service handles separate commodity containers')
 assert(c:demolishLink(l.id)); check((c.served[b.id] or 0)==0 and e.transportBlocked,'cut roads stop actual freight flow')
 road(c,a,b,'offroad'); check((c.served[b.id] or 0)==0,'an offroad does not restore truck delivery')
end
-- Dual utility households: independent flow and payment, joint satisfaction.
do
 local c=world(); c.licences.power=true
 local h=node(c,'client',1500,900); h.powerAccepted=true
 local water=node(c,'source',1450,900); water.commodity='water'; water.output=20
 local power=node(c,'source',1450,950); power.commodity='power'; power.output=20
 local function edge(a,b,key)
  local e=c.g:addEdge(a.id,b.id,20); e.commodity=key; e.capMax=20; return e
 end
 local w=edge(water,h,'water'); c:refresh()
 check(h.demands.water==3 and h.demands.power==2,'the same house requests water and 10 kWh/day')
 check(c.servedBy[h.id].water==3 and not c:fullyServed(h),'water alone does not satisfy both utilities')
 local p=edge(power,h,'power'); c:refresh()
 check(c.servedBy[h.id].power==2 and c:fullyServed(h),'one house receives both commodities concurrently')
 check(c:clientIncome(h)==24,'both deliveries contribute to household income')
 check(c:tradeCosts('power').revenue==2*h.utilityRates.power,'unit costs price a second utility at its own rate')
 p.alive=false; c:refresh(); check(c:clientIncome(h)==12 and not c:fullyServed(h),'electricity failure preserves water billing but reduces satisfaction')
 local bolt=require('symbols').get('power')
 check(c:quantity('power',7)=='7 '..bolt and c:quantity('power',7,'high')=='7 '..bolt..bolt..bolt,
   'electricity reads as a flow and one to three bolts for its voltage')
 p.alive=true; local copy=assert(Save.unpack(Save.pack(c)))
 check(copy.g.nodes[h.id].demands.power==2 and copy:fullyServed(copy.g.nodes[h.id]),'dual contracts survive saving')
end
-- Migration adds access roads once, never resurrecting demolished roads.
do
 local c=world(); local a=node(c,'dc',1400,900); local b=node(c,'dc',1500,900)
 local e=c.g:addEdge(a.id,b.id,18); e.commodity='water'; e.bulk='highway'; e.rail=true; e.wagons={water=18}; e.capMax=18
 c.roadModelVersion=nil; c:refresh()
 local l=c:linkBetween(a.id,b.id,'road'); check(l and l.roadType=='road','legacy freight highways retain a usable normal road')
 assert(c:demolishLink(l.id)); c:refresh(); check(not c:roadPath(a.id,b.id,'truck'),'migration never rebuilds demolished access')
end
-- Depot-to-depot cargo is conserved and credited only at the daily close.
do
 local c=world(); local a=node(c,'depot',1400,900); local b=node(c,'depot',1500,900)
 a.commodity='water'; a.stored=8; a.capacityStore=18
 b.commodity='water'; b.stored=0; b.capacityStore=18
 road(c,a,b); local e=assert(c:layPipe(a.id,b.id,'water',1,'highway'))
 check(c.detail.depot[b.id]==8 and c.produced[a.id]==8,'an empty depot receives cargo from another depot')
 check(b.stored==0,'previewing deliveries does not create stored cargo')
 c:endDay(); check(a.stored==0 and b.stored==8,'daily close conserves cargo across depot transfers')
 local l=c:linkBetween(a.id,b.id,'road'); assert(c:demolishLink(l.id)); c:endDay()
 check(a.stored==0 and b.stored==8,'a disconnected depot cannot teleport stored cargo')
end
-- A tank's level sets how much it takes in when it refills.
do
 local c=world(); local t=node(c,'depot',1400,900); t.commodity='water'; t.stored=0
 City.setLevel(c,t,4,true); c:refresh()
 check(t.intakeRequest==t.fillRate and t.fillRate>City.depotFillRate,'an upgraded tank refills at its own rate')
end
-- Freight follows road detours even when the endpoints are far apart.
do
 local c=world(); local a=node(c,'dc',1400,900); local b=node(c,'dc',3800,900)
 local x=node(c,'roundabout',2600,1000)
 road(c,a,x); road(c,x,b)
 local e=assert(c:layPipe(a.id,b.id,'water',1,'highway'))
 check(c:pipeLength(e)>2400,'truck haulage uses the physical detour length')
 check(c:railQuote(a.id,b.id,1,'highway').trench==0,'opening a truck service does not charge for building another road')
 check(not c:layPipe(a.id,b.id,'power',1,'highway'),'containers cannot carry electricity')
end
-- Filling stations still receive and sell real delivered gasoline.
do
 local c=world(); local a=node(c,'client',1400,900); local b=node(c,'client',1600,900)
 local station=node(c,'station',1500,900); station.fuelWanted=30; station.price=3
 local source=node(c,'source',1500,950); source.commodity='gasoline'; source.output=30
 local e=c.g:addEdge(source.id,station.id,30); e.commodity='gasoline'; e.capMax=30
 road(c,a,station); road(c,station,b)
 check(c.served[station.id]>0,'a station receives gasoline through its service drain')
 check(c.transit.fuel>0 and c.transit.byNode[station.id].sold<=c.served[station.id],'daily traffic buys no more fuel than was delivered')
 -- Every dollar over the going rate turns away its share of the drivers.
 local P=City.PEOPLE
 local fair=c.transit.byNode[station.id].sold
 assert(c:setStationPrice(station.id,P.pumpPrice+2))
 local dear=c.transit.byNode[station.id].sold or 0
 check(math.abs(dear-fair*(1-2*P.priceSensitivity))<1e-9,'two dollars over sells '..math.floor(200*P.priceSensitivity)..'% less')
 assert(c:setStationPrice(station.id,P.tollMax))
 check((c.transit.byNode[station.id].sold or 0)<=fair*math.max(0,1-(P.tollMax-P.pumpPrice)*P.priceSensitivity)+1e-9,'and at the top price hardly anyone stops')
end
-- Drivers turned away by a dear pump fill up at the next station on the way.
do
 local c=world(); local a=node(c,'client',1400,900); local b=node(c,'client',1700,900)
 local s1=node(c,'station',1500,900); local s2=node(c,'station',1600,900)
 for i,st in ipairs({s1,s2}) do
  st.fuelWanted=30; st.price=City.PEOPLE.pumpPrice
  local src=node(c,'source',st.x,950); src.commodity='gasoline'; src.output=30
  local e=c.g:addEdge(src.id,st.id,30); e.commodity='gasoline'; e.capMax=30
 end
 road(c,a,s1); road(c,s1,s2); road(c,s2,b); c:refresh()
 local function sold() local t=0; for _,st in ipairs({s1,s2}) do t=t+((c.transit.byNode[st.id] or {}).sold or 0) end; return t end
 local fair=sold()
 assert(c:setStationPrice(s1.id,City.PEOPLE.pumpPrice+2))
 check(fair>0 and math.abs(sold()-fair)<1e-9,'a dear pump sends its drivers on to the next station')
end
-- Residents visit homes, shops, workplaces and resorts, never utility plant.
do
 local c=world(); local a=node(c,'client',1400,900); local b=node(c,'client',1600,900)
 local direct=road(c,a,b)
 check(#c.g:nodesOfKind('stop')==0 and (c.transit.byLink[direct.id].car or 0)>0,'houses connect and drive directly without bus stops')
 local well=node(c,'source',1500,1000); well.commodity='water'; well.output=20
 road(c,a,well)
 local manifold=node(c,'manifold',1500,1100)
 local depot=node(c,'depot',1600,1100); depot.commodity='water'; depot.stored=0
 local hub=node(c,'gate',1700,1100)
 for day=1,20 do
  c.day=day; c:refresh()
  check(c.transit.byNode[a.id].destination==b.id and c.transit.byNode[b.id].destination==a.id,'with only homes to visit, they visit each other on day '..day)
 end
 local shop=node(c,'client',1600,1200,'market'); local work=node(c,'works',1700,1200); local resort=node(c,'resort',1800,1200)
 local seen={}
 for day=1,40 do
  c.day=day; c:refresh()
  local d=c.g.nodes[c.transit.byNode[a.id].destination]
  check(d.kind=='client' or d.kind=='works' or d.kind=='resort','day '..day..': a destination is a building people go to')
  seen[d.id]=true
 end
 check(not seen[well.id] and not seen[manifold.id] and not seen[depot.id] and not seen[hub.id],'utility buildings are never visited')
 check(seen[shop.id] or seen[work.id] or seen[resort.id],'shops, workplaces and resorts draw visitors')
end
-- Buses and cars use exactly the same physical road segments.
do
 local c=world()
 local a=node(c,'client',1400,900); local b=node(c,'client',500,900)
 local bend=node(c,'roundabout',1000,1100)
 local sa=node(c,'stop',1500,800); local sb=node(c,'stop',400,800)
 local first=road(c,sa,a); local shared=road(c,a,bend); road(c,bend,b); road(c,b,sb)
 local before=#c.links; local bus=assert(c:layLink(sa.id,sb.id,'bus'))
 check(#c.links==before+1 and c.links[#c.links].mode=='bus','opening a bus service does not build a physical road')
 local path,length=c:roadPath(sa.id,sb.id,'bus')
 check(#path==4 and length>c:nodeDistance(sa.id,sb.id),'buses follow the shared road detour, not a straight shortcut')
 check((c.transit.byLink[shared.id].car or 0)>0 and c.transit.byLink[shared.id].bus==1,'cars and the bus travel on the same road')
 assert(c:demolishLink(first.id))
 check(not c:roadPath(sa.id,sb.id,'bus') and (c.transit.byLink[shared.id].car or 0)>0,'losing bus-stop access stops buses without stopping house-to-house cars')
end
-- Nobody to visit, nobody travels; and a stop is not somewhere people go.
do
 local c=world(); local home=node(c,'client',1400,900); local stop=node(c,'stop',1500,900)
 local shared=road(c,home,stop)
 check(c.transit.trips==0 and not (c.transit.byLink[shared.id] or {}).car,'a lone house has nowhere to go: a bus stop is not a destination')
end
-- Mixed trips: drive to the stop, park, ride the bus, walk the rest.
do
 local c=world()
 local home=node(c,'client',1500,1300); local sa=node(c,'stop',1500,900); local sb=node(c,'stop',400,900)
 local far=node(c,'client',400,1100)
 local drive=road(c,home,sa); road(c,sa,sb); local bus=assert(c:layLink(sa.id,sb.id,'bus'))
 check((c.transit.byLink[bus.id].trips or 0)>0,'people from a house with no stop in walking reach ride the bus')
 check((c.transit.byLink[drive.id].car or 0)>0 or (c.transit.byLink[bus.id].trips or 0)>=3,'some drive to the stop and park')
 check(c.transit.carried<=c.transit.trips and c.transit.waiting==c.transit.trips-c.transit.carried,'every trip is either made or waits')
end

-- Bridges: the one road over water, built by the company, with a toll.
do
 local c=world()
 local wet
 for x=200,3800,100 do if c:riverAt(x,900) then wet=x; break end end
 if wet then
  local a=node(c,'client',wet-300,900); local b=node(c,'client',wet+300,900)
  c.buildRoadType='road'
  check(select(2,c:layLink(a.id,b.id,'road'))=='water in the way: build a bridge','an ordinary road stops at the water')
  local dryA=node(c,'client',wet-700,1500); local dryB=node(c,'client',wet-500,1500)
  c.buildRoadType='bridge'
  check(c:waterAlong(dryA.x,dryA.y,dryB.x,dryB.y)>0 or select(2,c:layLink(dryA.id,dryB.id,'road'))=='a bridge has to cross water','a bridge has to cross water')
  local road_=c:linkQuote(a.id,b.id,'road')
  c.buildRoadType='road'
  local plain=math.ceil(City.PEOPLE.roadTiein*2+c:nodeDistance(a.id,b.id)*City.PEOPLE.roadPerM)
  c.buildRoadType='bridge'
  check(road_>plain,'a bridge costs more than the road it carries')
  local l=assert(c:layLink(a.id,b.id,'road'))
  check(l.roadType=='bridge' and l.toll==City.BRIDGE.toll and City.tolled(l),'a bridge charges a toll')
  assert(c:setLinkPrice(l.id,5)); check(l.toll==5,'and the toll can be set')
 end
end
print(count..' transport and household checks passed')
