local Graph=require('graph')
return function(City)
 City.ROAD_TYPES={offroad={name='OFFROAD',factor=.5,colour={.65,.48,.30}},road={name='NORMAL ROAD',factor=1,colour={.65,.68,.72}},highway={name='HIGHWAY',factor=2,colour={.96,.80,.35}}}
 -- A corner is the cheap one: two ports, for bending a road round something
 -- rather than for meeting another road at it.
 local junctions={corner='ROAD CORNER',intersection='OFFROAD INTERSECTION',roundabout='ROUNDABOUT',interchange='HIGHWAY INTERCHANGE'}
 City.ROAD_JUNCTIONS=junctions
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
 City.HOUSEHOLD=household
 function City:quantity(key,value) return key=='power' and string.format('%g kWh/day',value*5) or string.format('%g %s',value,require('symbols').get(key)) end
 -- Two figures in one unit. Spelling the unit out twice -- "0 kWh/day / 10
 -- kWh/day" -- is half again as wide as the column it is read in.
 function City:quantityPair(key,a,b)
  if key=='power' then return string.format('%g / %g kWh/day',a*5,b*5) end
  return string.format('%g / %g %s',a,b,require('symbols').get(key))
 end
 function City:fullyServed(c)
  for key,want in pairs(c.demands or {}) do if (key==c.commodity and (self.served[c.id] or 0) or (((self.servedBy or {})[c.id] or {})[key] or 0))<want then return false end end
  return (self.served[c.id] or 0)>=c.demand
 end
 function City:contractValue(c)
  local total=0
  for key,want in pairs(c.demands or {[c.commodity]=c.demand}) do total=total+want*(key==c.commodity and c.rate or (c.utilityRates or {})[key] or c.rate) end
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
 -- Utility and freight access does not make a building a passenger destination.
 function City:dailyDestinationAllowed(n,vehicle)
  if not n or not n.alive or n.prospect then return false end
  if vehicle=='car' then return n.kind=='client' or n.kind=='works' or n.kind=='resort' or n.kind=='stop' end
  return n.kind=='works' or n.kind=='depot' or n.kind=='dc' or n.kind=='terminal'
    or n.kind=='client' and (n.clientType=='factory' or n.clientType=='market')
 end
end
