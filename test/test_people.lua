package.path='src/?.lua;'..package.path
local City=require('city')
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
 c.buildRoadType=kind or 'road'; return assert(c:layLink(a.id,b.id,'road'))
end
-- Physical topology, exact daily vehicle tolls and deterministic refreshes.
do
 local c=world(); local a=node(c,'client',1400,900); local b=node(c,'client',500,900)
 local x=node(c,'interchange',1200,900); local y=node(c,'interchange',700,900)
 road(c,a,x); road(c,b,y)
 check(c.transit.carried==0,'a destination in another component is unreachable')
 local h=road(c,x,y,'highway')
 check(c.transit.tolls==2,'both household cars pay once on the highway')
 check(c.transit.byLink[h.id].car==2,'only real trips are counted on a highway')
 local destination=c.transit.byNode[a.id].destination; local rng=c.rng
 c:refresh(); check(c.transit.tolls==2 and c.rng==rng,'refresh neither rerolls trips nor advances RNG')
 check(c.transit.byNode[a.id].destination==destination,'daily destination stays stable')
 assert(c:setLinkPrice(h.id,12)); check(c.transit.tolls==24,'connected vehicles pay even at the maximum toll')
 local clone=assert(Save.unpack(Save.pack(c)))
 check(clone.links[h.id].roadType=='highway' and clone.transit.tolls==24,'road variants and deterministic tolls survive saving')
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
 c.buildRoadType='road'; check(c:linkError(cross.id,round.id,'road')~=nil,'offroad intersections reject normal roads')
 c.buildRoadType='highway'; check(c:linkError(round.id,stop.id,'road')~=nil,'roundabouts and stops reject highways')
 c.buildRoadType='offroad'; check(c:linkError(stop.id,a.id,'road')~=nil,'bus stops reject offroads')
 check(c:linkError(a.id,b.id,'bus')~=nil,'houses and factories are not bus boarding points')
 check(Graph.KINDS.stop.name=='BUS STOP','stops are named bus stops')
end
-- Bus fares and service withdrawal when the physical route disappears.
do
 local c=world(); local a=node(c,'stop',1500,900); local b=node(c,'stop',500,900)
 check(not c:layLink(a.id,b.id,'bus'),'a bus requires a physical road first')
 local l=road(c,a,b); check(l.toll==0,'normal roads charge no toll')
 local bus=assert(c:layLink(a.id,b.id,'bus'))
 check(c.transit.fares>0 and c.transit.tolls==0,'passengers pay bus fares on a free road')
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
 check(c:quantity('power',7)=='35 kWh/day','electricity quantities use real daily energy units')
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
-- Passenger destinations exclude utility access, including saved old choices.
do
 local c=world(); local a=node(c,'client',1400,900); local b=node(c,'client',1600,900)
 local direct=road(c,a,b)
 check(#c.g:nodesOfKind('stop')==0 and c.transit.byLink[direct.id].car==2,'houses connect and drive directly without bus stops')
 local well=node(c,'source',1500,1000); well.commodity='water'; well.output=20
 road(c,a,well)
 local manifold=node(c,'manifold',1500,1100)
 local depot=node(c,'depot',1600,1100); depot.commodity='water'; depot.stored=0
 local hub=node(c,'gate',1700,1100)
 for _,n in ipairs({well,manifold,depot,hub}) do
  check(not c:dailyDestinationAllowed(n,'car'),'utility and freight-only buildings are not passenger destinations')
 end
 a.dailyDestination=well.id; a.destinationDay=c.day
 c:refresh(); check(a.dailyDestination==b.id,'a saved water-well destination is replaced immediately')
 for day=1,20 do
  c.day=day; c:refresh()
  check(a.dailyDestination==b.id and b.dailyDestination==a.id,'daily car destinations remain real homes on day '..day)
 end
 local shop=node(c,'client',1600,1200,'market'); local work=node(c,'works',1700,1200); local resort=node(c,'resort',1800,1200)
 for _,n in ipairs({shop,work,resort}) do check(c:dailyDestinationAllowed(n,'car'),'people can visit shops, workplaces and resorts') end
end
-- Buses and cars use exactly the same physical road segments.
do
 local c=world()
 local a=node(c,'client',1400,900); local b=node(c,'client',500,900)
 local bend=node(c,'roundabout',1000,1100)
 local sa=node(c,'stop',1500,800); local sb=node(c,'stop',400,800)
 local first=road(c,sa,a); local shared=road(c,a,bend); road(c,bend,b); road(c,b,sb)
 a.dailyDestination=b.id; a.destinationDay=c.day; b.dailyDestination=a.id; b.destinationDay=c.day
 local before=#c.links; local bus=assert(c:layLink(sa.id,sb.id,'bus'))
 check(#c.links==before+1 and c.links[#c.links].mode=='bus','opening a bus service does not build a physical road')
 local path,length=c:roadPath(sa.id,sb.id,'bus')
 check(#path==4 and length>c:nodeDistance(sa.id,sb.id),'buses follow the shared road detour, not a straight shortcut')
 check(c.transit.byLink[shared.id].car==2 and c.transit.byLink[shared.id].bus==1,'cars and the bus travel on the same road')
 check(c:dailyDestinationAllowed(sa,'car'),'bus stops count as passenger destinations')
 a.dailyDestination=sa.id; c:refresh()
 check(c.transit.byNode[a.id].destination==sa.id and (c.transit.byLink[first.id].car or 0)>0,'people can choose and drive to a bus stop')
 a.dailyDestination=b.id; c:refresh()
 assert(c:demolishLink(first.id))
 check(not c:roadPath(sa.id,sb.id,'bus') and c.transit.byLink[shared.id].car==2,'losing bus-stop access stops buses without stopping house-to-house cars')
end
-- A bus stop participates in the random draw even before a bus service opens.
do
 local c=world(); local home=node(c,'client',1400,900); local stop=node(c,'stop',1500,900)
 local shared=road(c,home,stop)
 check(home.dailyDestination==stop.id,'the random destination draw includes bus stops')
 check(c.transit.byLink[shared.id].car==1 and not c.transit.byLink[shared.id].bus,'driving to a bus stop does not create a bus service')
end
print(count..' transport and household checks passed')
