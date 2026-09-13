-- Presentation helpers and planning simulations. Previews never mutate a company.
local E = {}
local Save = require("company_save")
E.ambitions = {
  {id="districts", name="A city connected", target=12, description="Hold twelve districts at once.", reward=1200},
  {id="service", name="A company people trust", target=7, description="Supply every signed customer for seven consecutive closes.", reward=350},
  {id="customers", name="The next metropolis", target=50, description="Fully supply fifty customers at a close.", reward=1500},
}
-- The authored twelve have a story each. Generated ground tells its own, out of
-- the character the survey found there, so every district has something to say
-- however far out it is.
function E.districtStory(city, id)
  local d = city.districts[id]
  if not d then return "" end
  if E.districtStories[id] and (d.ring or 0) == 0 then return E.districtStories[id] end
  local spec = d.spec or {}
  local ring = d.ring or 0
  return (spec.story or "Open ground.")
    .. (ring > 0 and ("  Ring " .. ring .. " out: deeper ground, dearer to buy.") or "")
end

E.districtStories = {
  "Porches, repair shops and the highway gate. A dependable place to start a wider service.",
  "Garden estates climb the hill. Their thirsty households reward generous water capacity.",
  "Wet ground and buried riches. Plan the permits before promising the next connection.",
  "Foundries and workshops share these streets. Power and oil keep the district working.",
  "Terraced homes surround the old market. The pubs are part of neighbourhood life.",
  "Your first neighbourhood: cottages, small businesses, and room for a company to grow.",
  "A street of taprooms and cellar doors. Every festival is an opportunity for the beer trade.",
  "Cranes overlook the factories. The port can bring a whole new scale of supply inland.",
  "Courtyards and broad avenues. Large estates need a strong water network.",
  "Waterside homes and lively pubs. The crossings take planning; the customers make it worthwhile.",
  "Low roofs beneath the flight path. The airfield is another door into the city's freight network.",
  "Heavy industry above difficult ground. Valuable seams wait beneath the rock.",
}
function E.companyName(c) return c.companyName or "Millbrook Utilities" end
function E.clientName(c,n)
  if n.businessName then return n.businessName end
  local names={house={"Willow House","Rose Cottage","Maple House","Elm Cottage"},
    estate={"Garden Court","Riverside Flats","Orchard Court"},
    pub={"The Copper Tap","The Fox & Fir","The Little Barrel"},
    workshop={"Finch & Sons","Atlas Repairs","Cooper Works"},
    factory={"Northstar Mills","Union Foundry","Beacon Works"}}
  local list=names[n.clientType] or names.house
  return list[(n.id-1)%#list+1].." "..n.id
end
function E.progress(c,a)
  if a.id=="districts" then return #c:ownedDistricts() end
  if a.id=="service" then return c.serviceStreak or 0 end
  return #c:clientList()-c.unserved
end
function E.close(c,report)
  c.serviceStreak=report.unhappy==0 and #c:clientList()>0 and ((c.serviceStreak or 0)+1) or 0
  c.ambitionsDone=c.ambitionsDone or {}
  for _,a in ipairs(E.ambitions) do
    if c.ambition==a.id and not c.ambitionsDone[a.id] and E.progress(c,a)>=a.target then
      c.ambitionsDone[a.id]=true
      c.money=c.money+a.reward
      report.bonus=(report.bonus or 0)+a.reward
      report.achievement=a.name.."  +$"..a.reward
      c:note("Ambition achieved: %s (+$%d)",a.name,a.reward)
    end
  end
end
-- Where the opening guide should point right now: a sidebar button by id, a
-- spot on the map, or the drag from the well to the house. It walks the player
-- back first when they have wandered off to another tab or selection.
function E.tutorialTarget(c,state)
  local step=c:tutorialStep()
  if not step then return nil end
  local house,well
  for _,n in ipairs(c.g:aliveNodes()) do
    if n.kind=="client" and not house then house=n end
    if n.kind=="source" and not well then well=n end
  end
  if step.key=="close" then return {button="end-day"} end
  if state.tab~="network" then return {button="tab-network"} end
  if step.key=="well" then
    if state.node or state.edge then return {button="back-to-build"} end
    if state.commodity~="water" then return {button="water"} end
    if state.tool~="source" then return {button="source"} end
    for _,d in ipairs(c.deposits or {}) do
      if d.opening and not d.taken then return {x=d.x,y=d.y} end
    end
    return nil
  end
  if step.key=="junction" then
    if state.node or state.edge then return {button="back-to-build"} end
    if state.tool~="junction" then return {button="tool-junction"} end
    if well and house then return {x=(well.x+house.x)/2,y=(well.y+house.y)/2} end
    return nil
  end
  if step.key=="main" and well and house then
    local junction
    for _,n in ipairs(c.g:aliveNodes()) do
      if n.kind=="junction" then junction=n end
    end
    if not junction then return nil end
    if state.commodity~="water" and not (state.node or state.edge) then return {button="water"} end
    if not c:pipeBetween(well.id,junction.id,"water") then return {from=well,to=junction} end
    return {from=junction,to=house}
  end
  if step.key=="sign" and house then
    if state.node==house.id then return {button="accept"} end
    return {x=house.x,y=house.y}
  end
  return nil
end

local cache=setmetatable({}, {__mode="k"})
local function memo(c,key,fn)
  local item=cache[c]
  if not item or item.rev~=c.revision then item={rev=c.revision,values={}}; cache[c]=item end
  if not item.values[key] then item.values[key]=fn() end
  return item.values[key]
end
local function displaced(before,after,except)
  local count=0
  for _,n in ipairs(before:clientList()) do
    if n.id~=except and (after.served[n.id] or 0)<(before.served[n.id] or 0) then count=count+1 end
  end
  return count
end
function E.pipePreview(c,a,b,trade,capacity,rail,grade)
  return memo(c,table.concat({"pipe",a,b,trade,tostring(capacity),tostring(rail),tostring(grade),c.money},":"),function()
    local err=c:pipeError(a,b,trade,rail)
    if err then return {error=err} end
    local q=c:pipeQuote(a,b,trade,capacity,rail,grade)
    local copy=assert(Save.unpack(Save.pack(c)))
    copy.money=math.max(copy.money,q.total)
    local before=c:dailyRevenue()-c:dailyExpenses()
    -- pipeError does not know the size being asked for, so a size either end
    -- refuses only shows up here.
    local laid,why=copy:layPipe(a,b,trade,capacity,rail,grade)
    if not laid then return {error=why} end
    local target=copy.g.nodes[b]
    return {cost=q.total,cash=c.money-q.total,delivery=copy.served[b] or 0,
      demand=target.kind=="client" and not target.prospect and target.demand or nil,
      net=copy:dailyRevenue()-copy:dailyExpenses()-before,
      customers=c.unserved-copy.unserved,displaced=displaced(c,copy,b)}
  end)
end
function E.offerPreview(c,id)
  return memo(c,"offer:"..id,function()
    local copy=assert(Save.unpack(Save.pack(c)))
    local n=assert(copy:acceptClient(id))
    local net=copy:dailyRevenue()-copy:dailyExpenses()-(c:dailyRevenue()-c:dailyExpenses())
    if (copy.served[id] or 0)>=n.demand then return {cost=0,delivery=n.demand,demand=n.demand,net=net,displaced=displaced(c,copy,id)} end
    local candidates={}
    for _,source in ipairs(copy.g:aliveNodes()) do
      if source.id~=id and not source.prospect and not copy:pipeError(source.id,id,n.commodity) then
        candidates[#candidates+1]={id=source.id,cost=copy:pipeCost(source.id,id,n.commodity,n.demand,false,copy.lining)}
      end
    end
    table.sort(candidates,function(a,b) return a.cost<b.cost or (a.cost==b.cost and a.id<b.id) end)
    for _,source in ipairs(candidates) do
      local p=E.pipePreview(copy,source.id,id,n.commodity,math.min(24,n.demand),false)
      if p.demand and p.delivery>=n.demand then
        p.net=p.net+net
        p.displaced=math.max(p.displaced,displaced(c,copy,id))
        return p
      end
    end
    return {delivery=copy.served[id] or 0,demand=n.demand}
  end)
end
function E.route(c,id)
  local target=c.g.nodes[id or 0]
  if not target or target.kind~="client" then return {} end
  local queue,seen,parent={id},{[id]=true},{}
  for _,u in ipairs(queue) do
    local n=c.g.nodes[u]
    if n.kind=="source" or n.kind=="terminal" or (n.kind=="depot" and (n.stored or 0)>0) then
      local edges={}
      while parent[u] do local p=parent[u]; edges[p.edge]=true; u=p.node end
      return edges
    end
    for _,ei in ipairs(c.g.adj[u] or {}) do
      local e=c.g.edges[ei]
      if e.alive and e.commodity==target.commodity then
        local v=e.a==u and e.b or e.a
        if not seen[v] then seen[v]=true; parent[v]={node=u,edge=ei}; queue[#queue+1]=v end
      end
    end
  end
  return {}
end
return E
