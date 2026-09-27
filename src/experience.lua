-- Presentation helpers and planning simulations. Previews never mutate a company.
local E = {}
local City = require("city")
local Graph = require("graph")
local Save = require("company_save")

-- The main a drag out of `a` lays, into `b` once it has a target: the most
-- recently chosen size both ends accept, or failing that the accepted size
-- nearest the last choice. A well always answers with a trunk and a house
-- always with the smallest main, whatever was laid before.
function E.dragSize(c,a,b,state)
  local recent=state.recentSizes or {state.size or "small"}
  local lo,hi=c:sizeRange(a,b)
  if not lo then return recent[1] end
  while hi>lo and not c:sizeAllowed(City.PIPE_SIZES[hi]) do hi=hi-1 end
  for _,key in ipairs(recent) do
    local _,i=City.sizeOf(key)
    if i>=lo and i<=hi then return key end
  end
  local _,i=City.sizeOf(recent[1])
  return City.PIPE_SIZES[math.max(lo,math.min(hi,i))].key
end

-- A structure that answers to one commodity and refuses every other. A power
-- tower is the whole of this list: it carries electricity or it carries
-- nothing, and picking one up with water in hand is never a request for a
-- water main out of a pylon.
function E.soleTrade(c,n)
  if not n then return nil end
  local D=City.INFRA
  if D and (D.towers[n.kind] or n.kind=="transformer") then
    return c:licensed("power") and "power" or nil
  end
  return nil
end

-- What a drag out of `a` is carrying. The trade in hand while both ends take
-- it; otherwise the one the ends themselves ask for.
--
-- Only commodities already standing at one of the two structures are
-- considered -- what they produce, what they want, what is already tied into
-- them -- and only when exactly one of those fits. A drag whose refusal has
-- more than one cure keeps the trade in hand and says why it refused, because
-- guessing between two answers is worse than asking.
function E.dragTrade(c,a,b,state)
  local want=state.commodity
  local na=c.g.nodes[a]
  local sole=E.soleTrade(c,na)
  if not b then return sole or want end
  local nb=c.g.nodes[b]
  if not c:pipeError(a,b,want,state.rail) then return want end
  sole=sole or E.soleTrade(c,nb)
  if sole and sole~=want and not c:pipeError(a,b,sole,state.rail) then return sole end
  local here={}
  for _,n in ipairs({na,nb}) do
    if n.commodity then here[n.commodity]=true end
    for key in pairs(n.demands or {}) do here[key]=true end
    for _,e in ipairs(c.g:edgesAt(n.id)) do
      if e.alive and e.commodity then here[e.commodity]=true end
    end
  end
  local found
  for _,key in ipairs(Graph.ALL) do
    if here[key] and key~=want and c:licensed(key) and not c:pipeError(a,b,key,state.rail) then
      if found then return want end
      found=key
    end
  end
  return found or want
end

function E.useSize(state,key)
  local recent={key}
  for _,k in ipairs(state.recentSizes or {}) do
    if k~=key then recent[#recent+1]=k end
  end
  state.recentSizes=recent
end
-- What a trade costs after its licence. A licence is a piece of paper: the
-- money is in the first thing that can actually make the commodity, and in
-- the last hundred metres to the first customer. Quoting the paper alone is
-- how a company ends up holding a licence it cannot use.
function E.tradeEntry(c,name)
  if name=="power" then
    local cost,who
    for _,key in ipairs(City.PLANT_ORDER) do
      local price=c:plantCost(key)
      if not cost or price<cost then cost,who=price,string.lower(City.PLANTS[key].name) end
    end
    -- A household connects to a pole with a transformer on it, and nothing
    -- else, so that pole is part of the price of the first customer.
    local pole=(City.INFRA.kinds.pole or {}).cost or 0
    local fitting=(City.INFRA.upgrades.transformer.cost or {}).pole or 0
    return cost+pole+fitting,
      string.format("the cheapest generator is a %s at $%d, and a household connects through a pole with a transformer ($%d)",
        who,cost,pole+fitting)
  end
  local extractor=City.EXTRACTOR_OF[name]
  if extractor then
    local cost=c:sourceCost(name)
    return cost,string.format("a %s costs about $%d, and it needs a marked deposit",
      string.lower(City.EXTRACTORS[extractor].name),cost)
  end
  local recipe=City.RECIPES[City.MADE_BY[name] or ""]
  if recipe then
    return recipe.cost,string.format("a %s costs $%d and eats %s",
      string.lower(recipe.name),recipe.cost,E.recipeInputs(recipe))
  end
  local haven
  for _,key in ipairs(City.GATEWAYS) do
    local cost=c:havenCost(key)
    if not haven or cost<haven then haven=cost end
  end
  return haven,string.format("it is landed at a haven (from $%d) and hauled inland",haven)
end

-- The inputs of a recipe, written out.
function E.recipeInputs(r)
  local parts={}
  for _,name in ipairs(Graph.ALL) do
    if (r.inputs or {})[name] then parts[#parts+1]=r.inputs[name].." "..name end
  end
  if #parts==0 then return "nothing" end
  return table.concat(parts,", ")
end

function E.recipeSummary(r)
  local needs,materials={},{}
  local function name(key) return key=="power" and "electricity" or key end
  for _,key in ipairs(Graph.ALL) do
    if r.inputs[key] then needs[#needs+1]=(r.inputs[key]*r.rate).." "..name(key) end
    if (r.materials or {})[key] then materials[#materials+1]=r.materials[key].." "..name(key) end
  end
  return (#needs>0 and ("Requires "..table.concat(needs,", ").." per day. ") or "No supply needed. ")
    .."Produces "..r.rate.." "..name(r.makes).." per day. Costs $"..r.upkeep.." per day."
    ..(#materials>0 and (" Build with "..table.concat(materials,", ")..".") or "")
    ..(r.coastal and " Build on the coast." or "")
end
E.ambitions = {
  {id="districts", name="A city connected", target=12, description="Hold twelve districts at once.", reward=1200},
  {id="service", name="A company people trust", target=7, description="Supply every signed customer for seven consecutive closes.", reward=350},
  {id="customers", name="The next metropolis", target=50, description="Fully supply fifty customers at a close.", reward=1500},
  {id="diversified", name="Everyday essentials", target=4, description="Fully supply customers in four trades at once.", reward=1800},
  {id="efficient", name="Built to last", target=250, description="Earn $250 net/day with 20+ customers and no shortfalls.", reward=2400},
}
function E.companyName(c) return c.companyName or "Millbrook Utilities" end
function E.clientName(c,n)
  if n.businessName then return n.businessName end
  local names={house={"Willow House","Rose Cottage","Maple House","Elm Cottage"},
    estate={"Garden Court","Riverside Flats","Orchard Court"},
    pub={"The Copper Tap","The Fox & Fir","The Little Barrel"},
    workshop={"Finch & Sons","Atlas Repairs","Cooper Works"},
    home={"Hazel Cottage","Birch House","Linden Terrace","Ash Cottage"},
    factory={"Northstar Mills","Union Foundry","Beacon Works"},
    subscriber={"Home Office","Corner Studio","Attic Flat"}}
  local list=names[n.clientType] or names.house
  return list[(n.id-1)%#list+1].." "..n.id
end
function E.progress(c,a)
  if a.id=="districts" then return #c:ownedDistricts() end
  if a.id=="service" then return c.serviceStreak or 0 end
  if a.id=="diversified" then
    local trades,count={},0
    for _,n in ipairs(c:clientList()) do
      if c:fullyServed(n) and not trades[n.commodity] then
        trades[n.commodity]=true; count=count+1
      end
    end
    return count
  end
  if a.id=="efficient" then
    if #c:clientList()<20 or c.unserved>0 then return 0 end
    return math.max(0,c:dailyRevenue()-c:dailyExpenses())
  end
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
  if state.tab~="network" or not (state.drawer or state.node or state.edge or state.link) then
    return {button="tab-network"}
  end
  if step.key=="well" then
    if state.node or state.edge then return {button="tab-network"} end
    if state.commodity~="water" then return {button="water"} end
    if state.tool~="source" then return {button="source"} end
    for _,d in ipairs(c.deposits or {}) do
      if d.opening and not d.taken then return {x=d.x,y=d.y} end
    end
    return nil
  end
  if step.key=="junction" then
    if state.node or state.edge then return {button="tab-network"} end
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
--------------------------------------------------------------------------------
-- The shape of the network
--
-- Horton-Strahler ordering, which is how a river system or a vascular tree is
-- measured. A main that ends at a building is order 1. Where two mains of the
-- same order meet, the main carrying them both is one order higher. What comes
-- out is how many orders deep the network is, and three ratios that say
-- whether the same shape repeats at every one of them:
--
--   branching, how many mains of an order feed each main of the next
--   capacity,  how much more the main below carries, which is Murray's law
--              holding if it matches the branching
--   length,    how much longer the main below is, which in a tree that fills
--              its ground would be the cube root of the branching
--
-- The last one is the hard one, and it is printed rather than promised.
--------------------------------------------------------------------------------
function E.anatomy(c,commodity)
  return memo(c,"anatomy:"..tostring(commodity),function()
    local adj,mains={},{}
    for _,e in ipairs(c.g.edges) do
      if e.alive and e.commodity==commodity and not e.bulk then
        mains[#mains+1]=e
        adj[e.a]=adj[e.a] or {}; adj[e.b]=adj[e.b] or {}
        table.insert(adj[e.a],e); table.insert(adj[e.b],e)
      end
    end
    -- Ratios taken over a handful of mains are noise, not shape. A company
    -- with a well, a split and four houses has no anatomy worth describing.
    if #mains<12 then return nil end
    local roots={}
    for _,n in ipairs(c.g:nodesOfKind("source")) do
      if n.alive and n.commodity==commodity and adj[n.id] then roots[#roots+1]=n.id end
    end
    if #roots==0 then return nil end
    -- Point every main away from the sources, so the tree has a direction.
    local seen,queue,below={},{},{}
    for _,r in ipairs(roots) do seen[r]=true; queue[#queue+1]=r end
    local head=1
    while head<=#queue do
      local id=queue[head]; head=head+1
      below[id]=below[id] or {}
      for _,e in ipairs(adj[id] or {}) do
        local other=(e.a==id) and e.b or e.a
        if not seen[other] then
          seen[other]=true; queue[#queue+1]=other
          table.insert(below[id],{edge=e,to=other})
        end
      end
    end
    -- Walked with an explicit stack: a long thin network is deep enough that
    -- recursing it would be a stack overflow on somebody's machine.
    local ord,order,stack={},{},{}
    for _,r in ipairs(roots) do stack[#stack+1]={id=r,done=false} end
    while #stack>0 do
      local frame=stack[#stack]
      if frame.done then
        stack[#stack]=nil
        local best,count=0,0
        for _,k in ipairs(below[frame.id] or {}) do
          local o=math.max(1,order[k.to] or 0)
          ord[k.edge]=o
          if o>best then best,count=o,1 elseif o==best then count=count+1 end
        end
        order[frame.id]=count>1 and best+1 or best
      else
        frame.done=true
        for _,k in ipairs(below[frame.id] or {}) do stack[#stack+1]={id=k.to,done=false} end
      end
    end
    local band,top={},0
    for _,e in ipairs(mains) do
      local o=ord[e] or 1
      band[o]=band[o] or {n=0,len=0,cap=0}
      band[o].n=band[o].n+1
      band[o].len=band[o].len+c:pipeLength(e)
      band[o].cap=band[o].cap+(e.capMax or e.cap or 0)
      if o>top then top=o end
    end
    local rb,rl,rc={},{},{}
    for o=1,top-1 do
      local lo,hi=band[o],band[o+1]
      if lo and hi and hi.n>0 then
        rb[#rb+1]=lo.n/hi.n
        rl[#rl+1]=(hi.len/hi.n)/(lo.len/lo.n)
        rc[#rc+1]=(hi.cap/hi.n)/(lo.cap/lo.n)
      end
    end
    local function mean(t) local s=0; for _,v in ipairs(t) do s=s+v end; return #t>0 and s/#t or nil end
    local RB,RL,RC=mean(rb),mean(rl),mean(rc)
    return {band=band,top=top,mains=#mains,RB=RB,RL=RL,RC=RC,
      -- The dimension only means anything once the mains lengthen with order.
      dimension=(RB and RL and RL>1.02) and math.log(RB)/math.log(RL) or nil,
      -- What a tree that filled its ground would want the length step to be.
      wantLength=RB and RB^(1/3) or nil}
  end)
end

function E.pipePreview(c,a,b,trade,capacity,rail,grade)
  return memo(c,table.concat({"pipe",a,b,trade,tostring(capacity),tostring(rail),tostring(grade),c.money},":"),function()
    local err=c:pipeError(a,b,trade,rail,not rail and capacity or nil)
    if err then return {error=err} end
    local q=c:pipeQuote(a,b,trade,capacity,rail,grade)
    local copy=assert(Save.unpack(Save.pack(c)))
    copy.money=math.max(copy.money,q.total)
    -- Measured on the copy, before and after, so the gain is the change and
    -- nothing that reloading a company tidies up on the way.
    local before=copy:dailyRevenue()-copy:dailyExpenses()
    -- pipeError is told the size, but only layPipe knows whether the two ends
    -- will accept it, so a size either end refuses still shows up here.
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
  return memo(c,"offer:"..id..":"..c.money,function()
    local copy=assert(Save.unpack(Save.pack(c)))
    local before=copy:dailyRevenue()-copy:dailyExpenses()
    local n=assert(copy:acceptClient(id))
    local net=copy:dailyRevenue()-copy:dailyExpenses()-before
    if copy:fullyServed(n) then return {cost=0,delivery=n.demand,demand=n.demand,net=net,displaced=displaced(c,copy,id)} end
    -- A multi-utility offer needs a complete plan for every supply. Do not
    -- label one primary pipe as a complete connection for the household.
    if n.demands and n.demands.water and n.demands.power then
      return {delivery=copy.served[id] or 0,demand=n.demand,multipleUtilities=true}
    end
    local candidates={}
    for _,source in ipairs(copy.g:aliveNodes()) do
      if source.id~=id and not source.prospect and not copy:pipeError(source.id,id,n.commodity) then
        candidates[#candidates+1]={id=source.id,cost=copy:pipeCost(source.id,id,n.commodity,n.demand,false,copy.lining)}
      end
    end
    table.sort(candidates,function(a,b) return a.cost<b.cost or (a.cost==b.cost and a.id<b.id) end)
    for _,source in ipairs(candidates) do
      -- Priced the way it was ranked: this demand's main, at the lining the
      -- company lays today.
      local p=E.pipePreview(copy,source.id,id,n.commodity,n.demand,false,copy.lining)
      if p.demand and p.delivery>=n.demand then
        p.net=p.net+net
        p.displaced=math.max(p.displaced,displaced(c,copy,id))
        return p
      end
    end
    return {delivery=copy.served[id] or 0,demand=n.demand}
  end)
end
-- What an upgrade would earn, found by doing it on a copy of the company and
-- letting the flow solver say what changed. `fn` performs it on the copy.
-- Nothing here advances time or draws a random number.
local function trial(c,key,cost,fn)
  return memo(c,key..":"..c.money,function()
    local copy=assert(Save.unpack(Save.pack(c)))
    copy.money=math.max(copy.money,cost)
    local before=copy:dailyRevenue()-copy:dailyExpenses()
    local ok,why=fn(copy)
    if not ok then return {error=why or "not possible"} end
    local net=copy:dailyRevenue()-copy:dailyExpenses()-before
    return {cost=cost,net=net,payback=net>0 and math.ceil(cost/net) or nil,
      customers=c.unserved-copy.unserved,affordable=c.money>=cost}
  end)
end
function E.replacePreview(c,id,size,grade)
  local q=c:replaceQuote(id,size,grade)
  if not q then return {error="no such main"} end
  return trial(c,table.concat({"replace",id,tostring(size),tostring(grade)},":"),q.net,
    function(copy) return copy:replacePipe(id,size,grade) end)
end
function E.sourcePreview(c,id)
  local n=c.g.nodes[id]
  if not n then return {error="no such source"} end
  -- A station with no unit ladder of its own has no next step to price.
  local cost=c:sourceUpgradeCost(n)
  if not cost then return {error="this station is built, not extended"} end
  return trial(c,"source:"..id,cost,function(copy) return copy:upgradeSource(id) end)
end
function E.levelPreview(c,id)
  local spec=c:levelNext(id)
  if not spec then return {error="already at the highest level"} end
  return trial(c,"level:"..id,spec.cost,function(copy) return copy:upgradeLevel(id) end)
end

-- Who outgrows the network soon: every supplied customer due to grow within
-- `horizon` closes is grown on a copy, and whoever that leaves short is
-- counted. `choke` is the worst limit on the copy (ids match the real company),
-- so the player can go and fix it before anyone is short.
function E.growthForecast(c,horizon)
  horizon=horizon or 10
  return memo(c,"growth:"..horizon,function()
    local copy=assert(Save.unpack(Save.pack(c)))
    local soon
    for _,cl in ipairs(copy:clientList()) do
      local d=copy:fullyServed(cl) and copy:daysToGrowth(cl)
      if d and d<=horizon then
        cl.baseDemand=cl.baseDemand or cl.demand
        cl.demand=cl.demand+1
        soon=math.min(soon or d,d)
      end
    end
    if not soon then return {count=0} end
    copy:refresh()
    local count=0
    for _,cl in ipairs(copy:shortCustomers()) do
      if c:fullyServed(c.g.nodes[cl.id]) then count=count+1 end
    end
    local edges,nodes=copy:chokes()
    local choke,most
    for id,n in pairs(edges) do if not most or n>most or (n==most and id<choke.id) then choke,most={kind="edge",id=id},n end end
    for id,n in pairs(nodes) do if not most or n>most then choke,most={kind="node",id=id},n end end
    return {count=count,soon=soon,choke=count>0 and choke or nil}
  end)
end

-- Where a second well for a maxed one would go: the nearest free deposit of
-- its trade, tied into the nearest node on the same network with a connection
-- free. Each candidate is tried on a copy, so what is offered is known to work,
-- and priced by what the copy spent and earned.
function E.wellPlan(c,id)
  return memo(c,"wellplan:"..id..":"..c.money,function()
    local w=c.g.nodes[id]
    if not (w and w.alive and w.kind=="source" and w.commodity) then return nil end
    local com=w.commodity
    local net=c:flowNetworks(com)[id]
    local deposits={}
    for _,d in ipairs(c.deposits or {}) do
      if d.commodity==com and not d.taken and not c:sourceError(com,d.x,d.y) then
        deposits[#deposits+1]={d=d,far=(d.x-w.x)^2+(d.y-w.y)^2}
      end
    end
    table.sort(deposits,function(a,b) return a.far<b.far end)
    for i=1,math.min(4,#deposits) do
      local d=deposits[i].d
      local best,far
      for _,n in ipairs(c.g:aliveNodes()) do
        if n.kind~="client" and n.kind~="source" and c:flowNetworks(com)[n.id]==net
           and c.g:freePorts(n.id)>=1 then
          local f=(n.x-d.x)^2+(n.y-d.y)^2
          if not far or f<far then best,far=n,f end
        end
      end
      if best then
        local copy=assert(Save.unpack(Save.pack(c)))
        copy.money=math.max(copy.money,1e7)
        local before,cash=copy:dailyRevenue()-copy:dailyExpenses(),copy.money
        if copy:sinkWellAt(com,d.x,d.y,best.id) then
          local cost=cash-copy.money
          local gain=copy:dailyRevenue()-copy:dailyExpenses()-before
          return {x=d.x,y=d.y,target=best.id,commodity=com,cost=cost,net=gain,
            payback=gain>0 and math.ceil(cost/gain) or nil,affordable=c.money>=cost}
        end
      end
    end
    return nil
  end)
end

-- Every upgrade the company could buy that is worth pricing, ranked by how
-- fast it pays for itself. The candidates are exactly what the map glows:
-- City:chokes(), the mains, wells and valves some customer is short behind,
-- so the advisor only ever suggests a fix that wins back lost income.
E.ADVISE_LIMIT=16
function E.advise(c)
  return memo(c,"advise:"..c.money,function()
    local found={}
    local edges,nodes=c:chokes()
    for id,starved in pairs(edges) do
      local e=c.g.edges[id]
      local bigger=c:biggerSize(e)
      -- Where the ground says no (a house takes only the smallest main) the
      -- advisor stays quiet; only a shortage of cash is worth showing.
      local why=bigger and c:replaceError(e.id,bigger,e.grade)
      if bigger and not e.leaking and (why==nil or why=="not enough cash") then
        found[#found+1]={kind="pipe",id=id,size=bigger,grade=e.grade,starved=starved}
      end
    end
    for id,starved in pairs(nodes) do
      local n=c.g.nodes[id]
      if n.kind=="source" and not n.plant and (n.level or 1)<c:maxLevel(n) then
        found[#found+1]={kind="source",id=id,starved=starved}
      elseif c:levelFamily(n) and c:levelNext(id) then
        found[#found+1]={kind="level",id=id,starved=starved}
      end
    end
    table.sort(found,function(a,b)
      if a.starved~=b.starved then return a.starved>b.starved end
      return a.kind==b.kind and a.id<b.id or a.kind<b.kind
    end)
    local list={}
    for i=1,math.min(#found,E.ADVISE_LIMIT) do
      local item=found[i]
      local p=item.kind=="pipe" and E.replacePreview(c,item.id,item.size,item.grade)
        or item.kind=="source" and E.sourcePreview(c,item.id)
        or E.levelPreview(c,item.id)
      if not p.error and p.net>0 then
        item.cost,item.net,item.payback,item.customers,item.affordable=p.cost,p.net,p.payback,p.customers,p.affordable
        list[#list+1]=item
      end
    end
    table.sort(list,function(a,b)
      local pa,pb=a.payback or math.huge,b.payback or math.huge
      if pa~=pb then return pa<pb end
      if a.net~=b.net then return a.net>b.net end
      return a.id<b.id
    end)
    while #list>6 do list[#list]=nil end
    return list
  end)
end
return E
