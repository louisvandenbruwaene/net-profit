-- Temporary play assistant. Every move uses normal game prices and actions.
-- Failed construction plans are discarded as a whole; successful plans use
-- the same save representation as Undo and are reproducible from a seed.
local Save=require('company_save')
local A={}
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function connect(c,target)
 local candidates={}
 for _,n in ipairs(c.g:aliveNodes()) do
  if n.kind=='junction' or n.kind=='manifold' or n.kind=='pump' or n.kind=='filtration' then
   if c:connectionPorts(n.id)<n.ports then
    -- Only branch off a component actually fed by a well.
    local seen,q={[n.id]=true},{n.id}; local supply=0
    for _,id in ipairs(q) do
     local p=c.g.nodes[id]; if p.kind=='source' and p.commodity=='water' then supply=supply+math.max(0,(p.effectiveOutput or p.output or 0)-(c.produced[p.id] or 0)) end
     for _,e in ipairs(c.g:edgesAt(id)) do if e.commodity=='water' and e.cap>0 then local nextId=e.a==id and e.b or e.a; if not seen[nextId] then seen[nextId]=true; q[#q+1]=nextId end end end
    end
    if supply>=(target.demand or 0) then candidates[#candidates+1]=n end
   end
  end
 end
 table.sort(candidates,function(a,b) return distance(a,target)<distance(b,target) end)
 local from=candidates[1]
 if not from then return false end
 local reach=c:rangeBetween(from.id,target.id,nil,'water')
 local hops=math.ceil(distance(from,target)/math.min(220,reach))
 if hops>8 then return false end
 local start=from
 for i=1,hops-1 do
  local t=i/hops; local x,y=start.x+(target.x-start.x)*t,start.y+(target.y-start.y)*t
  local n=c:build(x,y,'junction'); if not n then return false end
  if not c:layPipe(from.id,n.id,'water','medium',nil,c.lining) then return false end
  from=n
 end
 if not c:layPipe(from.id,target.id,'water','small',nil,c.lining) then return false end
 return true
end
local function addWell(c)
 for _,d in ipairs(c.deposits) do
  local land=c:districtAt(d.x,d.y)
  if d.commodity=='water' and not d.taken and land and land.owned and not c:sourceError('water',d.x,d.y) then
   local trial=assert(Save.unpack(Save.pack(c)))
   local well=trial:buySource('water',d.x,d.y)
   if well then
    for _,offset in ipairs({{90,60},{90,-60},{-90,60},{-90,-60}}) do
     local hub=trial:build(well.x+offset[1],well.y+offset[2],'junction')
     if hub and trial:layPipe(well.id,hub.id,'water','large') then return trial end
     if hub then break end -- discard the whole plan rather than leave unused construction
    end
   end
  end
 end
end
function A.step(city)
 if city.bankrupt then return city,'Company has stopped trading',true end
 local c=assert(Save.unpack(Save.pack(city)))
 if #c.g:nodesOfKind('source')==0 then
  for _,d in ipairs(c.deposits) do
   local land=c:districtAt(d.x,d.y)
   if d.commodity=='water' and not d.taken and land and land.owned then
    local well=c:buySource('water',d.x,d.y)
    if well then
     local target=c:clientList(true)[1]
     local vx,vy=90,60
     if target then local len=distance(well,target); vx=(target.x-well.x)/len*90; vy=(target.y-well.y)/len*90 end
     local hub=c:build(well.x+vx,well.y+vy,'junction')
     if hub and c:layPipe(well.id,hub.id,'water','large') then return c,'Built a well and distribution split' end
     return city,'Saving for the opening network'
    end
   end
  end
 end
 local _,broken=c:repairAllCost()
 if broken>0 then local r=c:repairAll(); if r and r.fixed>0 then return c,'Repaired '..r.fixed..' lines' end end
 local requests={}
 for _,n in ipairs(c:clientList()) do if n.commodity=='water' and not c:fullyServed(n) then requests[#requests+1]=n end end
 for _,n in ipairs(c:clientList(true)) do if n.commodity=='water' then requests[#requests+1]=n end end
 table.sort(requests,function(a,b) return c:ratePremium(a)>c:ratePremium(b) end)
 for i=1,math.min(12,#requests) do
  local trial=assert(Save.unpack(Save.pack(c))); local n=trial.g.nodes[requests[i].id]
  if n.prospect then trial:acceptClient(n.id) end
  if trial:fullyServed(n) or connect(trial,n) and trial:fullyServed(n) then return trial,'Connected a water customer' end
 end
 if #requests>0 then
  for _,n in ipairs(c:clientList()) do
   if n.commodity=='water' and not c:fullyServed(n) then
    local why,id=c:constraintFor(n.id)
    local e=id and c.g.edges[id]
    local bigger=e and c:biggerSize(e)
    if why=='main' and bigger and c:replacePipe(id,bigger,e.grade) then return c,'Replaced a constrained main' end
   end
  end
  for _,n in ipairs(c.g:nodesOfKind('source')) do
   if n.commodity=='water' and (n.level or 1)<4 and (c.spare.water or 0)<10 and c.money>c:sourceUpgradeCost(n)+150 then
    if c:upgradeSource(n.id) then return c,'Upgraded a well' end
   end
  end
  if (c.spare.water or 0)<10 and c.money>c:sourceCost('water')+500 then
   local expanded=addWell(c)
   if expanded then return expanded,'Built another well and distribution split' end
  end
 end
 if c.money>2000 then
  for _,n in ipairs(c.g:nodesOfKind('junction')) do
   if c:connectionPorts(n.id)>=n.ports and c:convertNode(n.id,'manifold','water') then return c,'Expanded distribution connections' end
  end
 end
 if c.money>4000 and (#requests==0 or (c.spare.water or 0)<10) then
  local best,price
  for _,d in ipairs(c.districts) do
   local cost=c:districtCost(d)
   if not d.owned and c:districtAdjacent(d) and cost<c.money*.25 and not c:districtError(d.id) and (not price or cost<price) then best,price=d,cost end
  end
  if best then c:buyDistrict(best.id); return c,'Bought more land' end
 end
 if c.money>2000 and c.crews<1 then c:hireCrew(); return c,'Hired maintenance' end
 if #c:clientList()==0 then return city,'No affordable connection plan; autoplay paused',true end
 c:endDay()
 return c,'Day '..c.day..': $'..c.money,c.bankrupt
end
return A
