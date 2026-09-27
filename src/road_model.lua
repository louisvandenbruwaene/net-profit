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
 for _,key in ipairs({'client','works','depot','source'}) do City.TRANSIT_NODES[key]=true end
 City.MODES.highway.name='CONTAINER TRUCKS'
 City.MODES.highway.blurb='Container trucks use connected normal roads and highways.'
 local household={house=true,home=true,estate=true,subscriber=true}
 City.HOUSEHOLD=household
 -- Electricity reads as a flow and a voltage: the number is how much, and
 -- one, two or three bolts say low, medium or high voltage. The same number
 -- is the same flow at any voltage.
 local RANK={low=1,medium=2,high=3}
 function City.bolts(voltage) return string.rep(require('symbols').get('power'),RANK[voltage or 'low'] or 1) end
 -- The voltage a building is supplied at: its own, or its cable's, or low.
 function City:voltageOf(n)
  if not n then return 'low' end
  if n.voltage then return n.voltage end
  for _,e in ipairs(self.g:edgesAt(n.id)) do if e.alive and e.commodity=='power' and e.voltage then return e.voltage end end
  return 'low'
 end
 function City:quantity(key,value,voltage)
  if key=='power' then return string.format('%g ',value)..City.bolts(voltage) end
  return string.format('%g %s',value,require('symbols').get(key))
 end
 -- Two figures in one unit, the unit written once.
 function City:quantityPair(key,a,b,voltage)
  if key=='power' then return string.format('%g / %g ',a,b)..City.bolts(voltage) end
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
 -- Which roads leave each place, for cars (offroads too) or for everything
 -- else. Every driver, truck line and bus asks for a path each day, so the
 -- table is built once per network: refresh forgets it, and nothing changes a
 -- road or a building without a refresh following.
 local roadAdjCache=setmetatable({},{__mode='k'})
 function City:forgetRoads() roadAdjCache[self]=nil end
 local function roadAdj(self,vehicle)
  local cache=roadAdjCache[self]
  if not cache or cache.rev~=self.revision then cache={rev=self.revision}; roadAdjCache[self]=cache end
  local key=vehicle=='car' and 'car' or 'road'
  if cache[key] then return cache[key] end
  local adj={}
  for _,l in ipairs(self.links or {}) do
   if l.alive and l.mode=='road' and (vehicle=='car' or l.roadType~='offroad') then
    local na,nb=self.g.nodes[l.a],self.g.nodes[l.b]
    if na and nb and na.alive and nb.alive then
     adj[l.a]=adj[l.a] or {}; adj[l.b]=adj[l.b] or {}; table.insert(adj[l.a],l); table.insert(adj[l.b],l)
    end
   end
  end
  cache[key]=adj
  return adj
 end
 function City:roadPath(a,b,vehicle)
  local adj=roadAdj(self,vehicle)
  -- Dijkstra: the nearest unsettled place first, the lower id on a tie. A
  -- place whose distance improved is pushed again and its older, longer
  -- entry skipped when it surfaces.
  local dist,prev,done={[a]=0},{},{}
  local heap=Graph.heap(); heap.push(0,a)
  while true do
   local best,u=heap.pop()
   if not best then return nil end
   if not done[u] and best==dist[u] then
    if u==b then
     local path={}; while prev[u] do local l=prev[u]; table.insert(path,1,l); u=l.a==u and l.b or l.a end
     return path,best
    end
    done[u]=true
    local list=adj[u]
    if list then
     for k=1,#list do
      local l=list[k]
      local v=l.a==u and l.b or l.a; local d=best+self:nodeDistance(l.a,l.b)
      if not done[v] and (not dist[v] or d<dist[v]) then dist[v],prev[v]=d,l; heap.push(d,v) end
     end
    end
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
