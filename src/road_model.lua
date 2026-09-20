local Graph=require('graph')
return function(City)
 City.ROAD_TYPES={offroad={name='OFFROAD',factor=.5,colour={.65,.48,.30}},road={name='NORMAL ROAD',factor=1,colour={.65,.68,.72}},highway={name='HIGHWAY',factor=2,colour={.96,.80,.35}}}
 -- A corner is the cheap one: two ports, for bending a road round something
 -- rather than for meeting another road at it.
 local junctions={corner='ROAD CORNER',intersection='OFFROAD INTERSECTION',roundabout='ROUNDABOUT',interchange='HIGHWAY INTERCHANGE'}
 local ports={corner=2}
 local costs={corner=30,interchange=400}
 for key,name in pairs(junctions) do
  Graph.KINDS[key]={name=name,ports=ports[key] or 8,throughput=999,cost=costs[key] or 80,color={.8,.75,.5}}
  City.price[key]=Graph.KINDS[key].cost; City.BUILDABLE[key]=true; City.BUILD_UNLOCK[key]='roads'; City.TRANSIT_NODES[key]=true
 end
 for _,key in ipairs({'client','works','depot','source','exchange'}) do City.TRANSIT_NODES[key]=true end
 City.MODES.highway.name='CONTAINER TRUCKS'
 City.MODES.highway.blurb='Container trucks use connected normal roads and highways.'
 local household={house=true,home=true,estate=true,subscriber=true}
 function City:quantity(key,value) return key=='power' and string.format('%g kWh/day',value*5) or string.format('%g %s',value,require('symbols').get(key)) end
 function City:fullyServed(c)
  for key,want in pairs(c.demands or {}) do if (key==c.commodity and (self.served[c.id] or 0) or (((self.servedBy or {})[c.id] or {})[key] or 0))<want then return false end end
  return (self.served[c.id] or 0)>=c.demand
 end
 function City:contractValue(c)
  local total=0
  for key,want in pairs(c.demands or {[c.commodity]=c.demand}) do total=total+want*(key==c.commodity and c.rate or (c.utilityRates or {})[key] or c.rate) end
  return total
 end
 local income=City.clientIncome
 function City:clientIncome(c)
  local total=income(self,c)
  for key in pairs(c.demands or {}) do if key~=c.commodity then total=total+math.floor((((self.servedBy or {})[c.id] or {})[key] or 0)*(c.utilityRates[key] or c.rate)*self:eventRate(key)+.5) end end
  return total
 end
 -- Shortest physical path; freight and buses cannot use offroads.
 function City:roadPath(a,b,vehicle)
  local adj={}
  for _,l in ipairs(self.links or {}) do
   if l.alive and l.mode=='road' and (vehicle=='car' or l.roadType~='offroad') then
    local na,nb=self.g.nodes[l.a],self.g.nodes[l.b]
    if na and nb and na.alive and nb.alive then
     adj[l.a]=adj[l.a] or {}; adj[l.b]=adj[l.b] or {}; table.insert(adj[l.a],l); table.insert(adj[l.b],l)
    end
   end
  end
  local dist,prev,done={[a]=0},{},{}
  while true do
   local u,best
   for id,d in pairs(dist) do if not done[id] and (not best or d<best or d==best and id<u) then u,best=id,d end end
   if not u then return nil end
   if u==b then
    local path={}; while prev[u] do local l=prev[u]; table.insert(path,1,l); u=l.a==u and l.b or l.a end
    return path,best
   end
   done[u]=true
   for _,l in ipairs(adj[u] or {}) do
    local v=l.a==u and l.b or l.a; local d=best+self:nodeDistance(l.a,l.b)
    if not done[v] and (not dist[v] or d<dist[v]) then dist[v],prev[v]=d,l end
   end
  end
 end
 function City:roadConnected(a,b) return self:roadPath(a,b,'bus')~=nil end
 local unlocked=City.unlocked
 function City:unlocked(key)
  if key=='roads' and (#self.g:nodesOfKind('terminal')>0 or #self.g:nodesOfKind('dc')>0) then return true end
  return unlocked(self,key)
 end
 local linkError,quote,price=City.linkError,City.linkQuote,City.setLinkPrice
 function City:linkError(a,b,mode)
  local na,nb=self.g.nodes[a],self.g.nodes[b]
  if not (na and nb and na.alive and nb.alive) then return 'choose two live buildings' end
  if mode=='road' then
   local variant=self.buildRoadType or 'road'
   if not City.ROAD_TYPES[variant] then return 'choose a road variant' end
   for _,n in ipairs({na,nb}) do
    if n.kind=='stop' and variant~='road' then return 'bus stops attach to normal roads only' end
    if n.kind=='intersection' and variant~='offroad' then return 'offroad intersections take offroads only' end
    if n.kind=='roundabout' and variant=='highway' then return 'highways require a highway interchange' end
    if variant=='highway' and n.kind~='interchange' then return 'highways join highway interchanges; use normal roads for building access' end
   end
  elseif mode=='bus' then
   if na.kind~='stop' or nb.kind~='stop' then return 'buses board only at bus stops' end
  elseif na.kind=='stop' or nb.kind=='stop' then return 'bus stops work only for buses' end
  return linkError(self,a,b,mode)
 end
 function City:linkQuote(a,b,mode)
  local cost=quote(self,a,b,mode)
  return mode=='road' and math.ceil(cost*(City.ROAD_TYPES[self.buildRoadType or 'road'] or City.ROAD_TYPES.road).factor) or cost
 end
 function City:setLinkPrice(id,value)
  local l=(self.links or {})[id]
  if l and l.mode=='road' and l.roadType~='highway' then return nil,'only highways charge tolls' end
  return price(self,id,value)
 end
 local bulkError=City.bulkError
 function City:bulkError(a,b,mode)
  if mode~='highway' then return bulkError(self,a,b,mode) end
  local function freight(n) return n and n.alive and (n.kind=='terminal' or n.kind=='dc' or n.kind=='depot' or n.kind=='works' or n.kind=='source' or n.kind=='exchange' or n.kind=='client' and (n.clientType=='market' or n.clientType=='factory')) end
  if not freight(self.g.nodes[a]) or not freight(self.g.nodes[b]) then return 'container trucks serve depots, factories, food stores and freight sources' end
  if not self:roadPath(a,b,'truck') then return 'connect these buildings with normal roads or highways first' end
 end
 function City:setEdgeToll() return nil,'set tolls on physical highways, not truck services' end
 local length=City.pipeLength
 function City:pipeLength(e)
  if e.bulk=='highway' then local path,metres=self:roadPath(e.a,e.b,'truck'); if path then return metres end end
  return length(self,e)
 end
 local pipeError=City.pipeError
 function City:pipeError(a,b,commodity,rail,size)
  if rail~='highway' then return pipeError(self,a,b,commodity,rail,size) end
  if not self:licensed(commodity) then return 'no licence for that' end
  if Graph.formOf(commodity)=='energy' or Graph.formOf(commodity)=='data' then return 'electricity and data cannot travel in containers' end
  local why=self:bulkError(a,b,'highway'); if why then return why end
  if a==b then return 'a truck route needs two different buildings' end
  if self:pipeBetween(a,b,commodity) then return 'that freight service already exists' end
  if self.g:freePorts(a)<1 or self.g:freePorts(b)<1 then return 'no free freight ports' end
 end
 local railQuote=City.railQuote
 function City:railQuote(a,b,wagons,mode)
  if mode~='highway' then return railQuote(self,a,b,wagons,mode) end
  local _,metres=self:roadPath(a,b,'truck')
  local q={metres=metres or self:nodeDistance(a,b),ground=1,capacity=wagons or 1,rail=true,mode=mode,tiein=City.MODES.highway.tiein*2,trench=0,bore=math.max(1,wagons or 1)*City.MODES.highway.perWagon}
  q.total=q.tiein+q.bore; return q
 end
 local linkUpkeep=City.linkUpkeep
 function City:linkUpkeep(l) if l.goodsEdge then return 0 end; return linkUpkeep(self,l) end
 local refresh=City.refresh
 function City:refresh()
  self.links=self.links or {}
  if not self.roadModelVersion then
   for _,e in ipairs(self.g.edges) do
    if e.alive and e.bulk=='highway' and not self:linkBetween(e.a,e.b,'road') then
     local id=#self.links+1; self.links[id]={id=id,a=e.a,b=e.b,mode='road',roadType='road',alive=true,toll=0,paid=0}
    end
   end
   self.roadModelVersion=1
  end
  -- The existing local goods-road tool builds a normal road with containers.
  -- Keep it part of the same physical network as roads built in Transport.
  for _,e in ipairs(self.g.edges) do
   if e.alive and not e.rail and Graph.formOf(e.commodity)=='solid' and not e.goodsRoad then
    local l=self:linkBetween(e.a,e.b,'road')
    if not l then
     local id=#self.links+1
     l={id=id,a=e.a,b=e.b,mode='road',roadType='road',alive=true,toll=0,paid=0,goodsEdge=e.id}
     self.links[id]=l
    end
    e.goodsRoad=l.id
   end
  end
  for _,l in ipairs(self.links) do
   if l.goodsEdge and not self.g.edges[l.goodsEdge].alive then l.alive=false end
  end
  for _,l in ipairs(self.links) do if l.mode=='road'  then l.roadType=l.roadType or 'road'; if l.roadType~='highway' then l.toll=0 end end end
  for _,n in ipairs(self.g:aliveNodes()) do
   if n.kind=='client' and household[n.clientType] then
    n.utilityRates=n.utilityRates or {water=4,power=6}; n.demands=n.demands or {[n.commodity]=n.demand}; n.demands[n.commodity]=n.demand
    if self:licensed('water') then n.demands.water=n.demands.water or (n.clientType=='estate' and 6 or 3) end
    if self:licensed('power') and (n.prospect or n.powerAccepted or n.demands.power) then n.demands.power=n.demands.power or (n.clientType=='estate' and 4 or 2) end
   end
  end
  for _,n in ipairs(self.g:nodesOfKind('depot')) do
   n.freightStorage=true; n.intakeRequest=nil
   if (n.stored or 0)==0 then n.intakeRequest=math.min(City.depotFillRate,n.capacityStore or City.depotCapacity) end
  end
  for _,e in ipairs(self.g.edges) do
   if e.alive and (e.bulk=='highway' or e.goodsRoad) then
    e.transportBlocked=not self:roadPath(e.a,e.b,'truck')
    for _,id in ipairs({e.a,e.b}) do
     local n=self.g.nodes[id]
     if n.kind=='depot' then
      n.freightStorage=true
      if (n.stored or 0)==0 then n.intakeRequest=math.min(City.depotFillRate,n.capacityStore or City.depotCapacity) end
     end
    end
   end
  end
  return refresh(self)
 end
 -- Utility and freight access does not make a building a passenger destination.
 function City:dailyDestinationAllowed(n,vehicle)
  if not n or not n.alive or n.prospect then return false end
  if vehicle=='car' then return n.kind=='client' or n.kind=='works' or n.kind=='resort' or n.kind=='stop' end
  return n.kind=='works' or n.kind=='depot' or n.kind=='dc' or n.kind=='terminal'
    or n.kind=='client' and (n.clientType=='factory' or n.clientType=='market')
 end
 local routeTrips=City.routeTrips
 function City:routeTrips()
  local T=routeTrips(self); local places={}; local attached={}
  for _,l in ipairs(self.links or {}) do if l.alive and l.mode=='road' then attached[l.a]=true; attached[l.b]=true end end
  for _,n in ipairs(self.g:aliveNodes()) do if attached[n.id] and City.TRANSIT_NODES[n.kind] and not junctions[n.kind] and not n.prospect then places[#places+1]=n end end
  local tank={}
  for _,n in ipairs(self.g:nodesOfKind('station')) do tank[n.id]=self.served[n.id] or 0 end
  local function travel(path,count,vehicle)
   local distance,stations,seen=0,{},{}
   for _,l in ipairs(path) do
    distance=distance+self:nodeDistance(l.a,l.b)/1000
    for _,id in ipairs({l.a,l.b}) do if tank[id] and not seen[id] then stations[#stations+1]=id; seen[id]=true end end
    local rec=T.byLink[l.id] or {trips=0,income=0}; T.byLink[l.id]=rec
    rec.trips=rec.trips+count; rec[vehicle]=(rec[vehicle] or 0)+count
    local toll=l.roadType=='highway' and (l.toll or City.PEOPLE.tollDefault)*count or 0
    rec.income=rec.income+toll; T.tolls=T.tolls+toll
   end
   local want=distance*count*City.PEOPLE.fuelPerKm
   for _,id in ipairs(stations) do
    local take=math.min(tank[id],want); tank[id]=tank[id]-take; want=want-take
    T.fuel=T.fuel+take*(self.g.nodes[id].price or City.PEOPLE.pumpPrice)
    T.byNode[id]=T.byNode[id] or {}; T.byNode[id].sold=(T.byNode[id].sold or 0)+take
   end
  end
  for _,n in ipairs(places) do
   local vehicle=n.kind=='client' and household[n.clientType] and 'car' or (n.kind=='works' or n.kind=='depot' or n.kind=='dc' or n.kind=='client' and (n.clientType=='factory' or n.clientType=='market')) and 'truck'
   if vehicle and #places>1 then
    -- Stable for a day and save/load; refresh never advances the world's RNG.
    local seed=(((self.seed or 1)+n.id*104729+(self.day or 1)*13007)*48271)%2147483647
    local choices={}
    for _,d in ipairs(places) do
     if d.id~=n.id and self:dailyDestinationAllowed(d,vehicle) then choices[#choices+1]=d end
    end
    -- Retire saved choices that were made under the old utility-inclusive rule.
    if not self:dailyDestinationAllowed(self.g.nodes[n.dailyDestination],vehicle) then n.dailyDestination=nil end
    if #choices>0 and (n.destinationDay~=self.day or not n.dailyDestination) then
     n.dailyDestination=choices[seed%#choices+1].id; n.destinationDay=self.day
    end
    local target=self.g.nodes[n.dailyDestination]
    local path=target and target.alive and self:roadPath(n.id,target.id,vehicle)
    if n.dailyDestination then T.trips=T.trips+1 end
    if path then travel(path,1,vehicle); T.carried=T.carried+1 end
    T.byNode[n.id]=T.byNode[n.id] or {}; T.byNode[n.id].destination=n.dailyDestination
   end
  end
  for _,e in ipairs(self.g.edges) do
   if e.alive and (e.bulk=='highway' or e.goodsRoad) and not e.transportBlocked then
    local trucks=0; for key in pairs(e.wagons or {[e.commodity]=e.cap}) do trucks=trucks+math.ceil(math.abs((self.edgeFlowBy[key] or {})[e.id] or 0)/City.MODES.highway.wagonCap) end
    local path=self:roadPath(e.a,e.b,'truck'); if path and trucks>0 then travel(path,trucks,'truck') end
   end
  end
  for _,l in ipairs(self.links) do if l.alive and l.mode=='bus' then local path=self:roadPath(l.a,l.b,'bus'); if path then travel(path,l.vehicles or 1,'bus') end end end
  T.waiting=T.trips-T.carried; T.total=T.tolls+T.fares+T.fuel+T.resorts; return T
 end
end
