local P = require("palette")
local City = require("city")
local Graph = require("graph")
local R = require("render")
local Draw = require("company_render")
local Save = require("company_save")
local UI = {width=344, buttons={}}
local lg = love.graphics
local state, city, act, scroll, H, W

local M   = 22           -- sidebar margin
local CW  = 300          -- sidebar content width
local TOP = 174          -- first content line, before scrolling

local function text(s,x,y,font,color,width,align)
  lg.setFont(R.fonts[font or "body"])
  lg.setColor(color or P.text)
  if width then lg.printf(tostring(s),x,y,width,align) else lg.print(tostring(s),x,y) end
end

-- `emphasis` makes a button ask to be pressed. It is used for exactly one thing:
-- the repair on a main that is currently losing capacity. When the player clicks
-- a burst pipe the game owes them the fix, not a hunt for it.
local function button(id,label,x,y,w,h,fn,enabled,tip,active,color,emphasis)
  enabled = enabled ~= false
  local mx,my = love.mouse.getPosition()
  local hover = mx>=x and mx<x+w and my>=y and my<y+h
  local inClip = not scroll or (y>=160 and y+h<=H-62)
  color = color or P.flow
  local pulse = emphasis and enabled and (0.5+0.5*math.sin(R.t*4)) or 0
  lg.setColor(active and P.with(color,0.22) or emphasis and enabled and P.with(color,0.10+0.14*pulse)
    or hover and P.gridMajor or P.panel)
  lg.rectangle("fill",x,y,w,h,4)
  lg.setColor(active and color or emphasis and enabled and P.with(color,0.55+0.45*pulse) or P.panelEdge)
  lg.setLineWidth(emphasis and enabled and 2 or 1)
  lg.rectangle("line",x,y,w,h,4)
  local font = R.fonts.body
  if font:getWidth(label)>w-14 then font=R.fonts.small end
  if font:getWidth(label)>w-6 then font=R.fonts.tiny end
  lg.setFont(font); lg.setColor(enabled and ((active or emphasis) and color or P.text) or P.textFaint)
  lg.printf(label,x+3,y+(h-font:getHeight())/2,w-6,"center")
  if inClip then UI.buttons[#UI.buttons+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled,tip=tip} end
end

local function line(y)
  lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.line(M,y,M+CW,y)
end

local function row(label,value,y,color,tip)
  text(label,M,y,"small",P.textDim)
  lg.setFont(R.fonts.body); lg.setColor(color or P.text)
  lg.printf(tostring(value),M+CW-200,y-1,200,"right")
  if tip then
    local mx,my=love.mouse.getPosition()
    if mx>=M and mx<=M+CW and my>=y-3 and my<=y+17 then
      UI.buttons[#UI.buttons+1]={id="row",x=M,y=y-3,w=CW,h=20,fn=function() end,enabled=false,tip=tip}
    end
  end
end

local function heading(s,y) text(s,M,y,"small",P.textDim) end

-- The same droplet the map draws, inline in the sidebar.
local function drop(commodity,x,y,r) Draw.droplet(commodity,x,y,r or 8) end

--------------------------------------------------------------------------------

local toolTips = {
  junction="Junction: 3 ports, $22, $1 a day. The cheapest way to turn a corner or split a run.",
  manifold="Manifold: 6 ports, $46, $1 a day. Shared ground: water, beer and oil can all pass through one without mixing.",
  pump="Pump: 2 ports, reaches 520m instead of 300m, $38, $1 a day. The only way across a long gap.",
  tower="Treatment station: $92, $2 a day. Cuts leak risk by 55% for every main whose midpoint is within 220m. Stations do not stack.",
  gate="Gate: 2 ports, $30, $1 a day. A valve you set by hand -- throttle a branch to starve it on purpose and send scarce supply to the customers who pay more.",
  depot="Depot: 3 ports, $190, $3 a day. Takes in output you could not sell today, up to 18 units, and feeds it back into the network tomorrow.",
  terminal="Haven: 4 ports, $1400, $14 a day. Lands 24 units a day of one trade from outside the city -- far more than any well -- but bills you for every unit that moves. Only the port, the airfield and the highway head have the ground for one.",
}

local TOOLS = {"junction","manifold","pump","tower","gate","depot","terminal"}

-- The Network tab has two faces. With nothing selected it is a workshop: the
-- trade selector, the bore, the structures, and the state of the system. The
-- moment anything is selected it becomes that thing's control panel, at the top
-- of the sidebar, with its most urgent action first. Selecting a burst main
-- puts Repair under the cursor rather than three scrolls away, and "Back to
-- build" returns the workshop -- so navigation is one click in each direction
-- and nothing ever has to be hunted for.

local function inspectClient(n,y)
  local premium=city:ratePremium(n)
  local good,bad=premium>0.10,premium<-0.10
  row("Commodity",string.upper(n.commodity),y,Graph.COMMODITIES[n.commodity].color)
  row("Rate offered","$"..n.rate.." / unit",y+26,good and P.good or bad and P.bad or P.text,
    "Every customer negotiates their own price. The going rate for a "..
    string.lower(City.CLIENTS[n.clientType].name).." is $"..(n.rateBase or n.rate)..
    ". The spread widens as the company grows.")
  row("Against going rate",string.format("%+.0f%%",premium*100),y+52,
    good and P.good or bad and P.bad or P.textDim)
  row("Daily contract","$"..n.demand*n.rate,y+78,P.energy)
  row("Delivery",(city.served[n.id] or 0).." / "..n.demand,y+104)
  row(n.prospect and "Offer expires" or "Patience",
    n.prospect and (n.expires-city.day+1).." days" or n.grace.." days",y+130,P.warn)
  if n.prospect then
    button("accept","Sign contract",M,y+168,190,36,function() act("acceptClient",n.id) end,true,
      "The delivery deadline starts when signed",false,P.good,not bad)
    button("decline","Decline",M+198,y+168,102,36,function() act("declineClient",n.id) end,true,
      "No reputation penalty and no cost. A lowball offer is worth refusing once the spread opens up.",
      false,bad and P.bad or P.flow,bad)
    if bad then text("Paying "..string.format("%.0f%%",-premium*100).." under the going rate.",M,y+214,"small",P.bad,CW)
    elseif good then text("Paying "..string.format("%.0f%%",premium*100).." over the going rate.",M,y+214,"small",P.good,CW) end
  else
    button("supply-valve",n.supplyClosed and "[ ]  Customer supply" or "[x]  Customer supply",
      M,y+168,CW,36,function() act("toggleSupply",n.id) end,true,
      "Closes this customer's service only. The main stays open; an unsupplied customer still loses patience.",
      not n.supplyClosed,P.good)

    -- A customer showing 1/4 is a question. Answer it here, and offer the fix,
    -- rather than making the player trace the network by eye.
    local why,eid=city:constraintFor(n.id)
    if why then
      local dy=y+216
      heading("WHY IT IS SHORT",dy); dy=dy+26
      if why=="main" then
        local e=city.g.edges[eid]
        local carrying=math.abs(city.detail.edge[eid] or 0)
        text("The nearest main is already full.",M,dy,"body",P.warn,CW)
        row(string.upper(e.commodity).." "..(Graph.COMMODITIES[e.commodity].conduit)
          .." "..e.id,carrying.." / "..e.cap,dy+24,P.bad)
        local bore=city:boreCost(e,1)
        button("widen-bottleneck","Widen it  +1   $"..bore,M,dy+52,CW,36,
          function() act("upgradePipe",eid) end,city.money>=bore and e.capMax<24,
          "Adds one unit of capacity to the main that is holding this customer back.",
          false,P.good,true)
        button("inspect-bottleneck","Inspect that main",M,dy+94,CW,30,
          function() act("focusEdge",eid) end,true,"Select the main and centre on it")
      elseif why=="output" then
        text("Every "..n.commodity.." well is pumping flat out. A wider main will not help: deepen a well, sink another, or open a haven.",
          M,dy,"small",P.warn,CW)
        local src
        for _,w in ipairs(city.g:nodesOfKind("source")) do
          if w.commodity==n.commodity and (w.level or 1)<City.sourceMaxLevel then src=w; break end
        end
        if src then
          local cost=city:sourceUpgradeCost(src)
          button("deepen-for-client","Deepen "..string.upper(n.commodity).." well "..src.id.."   $"..cost,
            M,dy+52,CW,36,function() act("upgradeSource",src.id) end,city.money>=cost,
            "Adds output at the well, with no new route to pay for",false,P.good,true)
        end
      elseif why=="unconnected" then
        text("This customer is not connected to any "..n.commodity..
             " supply. Drag a main to it from a well or a structure that reaches.",
          M,dy,"small",P.bad,CW)
      elseif why=="valve" then
        text("You closed this customer's service valve. They keep losing patience while it is shut.",
          M,dy,"small",P.warn,CW)
      end
    end
  end
end

local function inspectSource(n,y)
  local level,trade=n.level or 1,City.trade[n.commodity]
  local capacity=n.output or 0
  local drawn=(city.produced or {})[n.id] or 0
  local spare=math.max(0,capacity-drawn)
  local maxed=spare<=0 and capacity>0
  -- Capacity in use against capacity installed. This is the first thing to know
  -- about a well: a well at 14/14 is the reason anything downstream of it is
  -- short, and no amount of wider pipe will change that.
  row("Capacity",drawn.." / "..capacity.." "..n.commodity,y,
    maxed and P.warn or P.good,
    "Left of the slash is what the network is drawing from this well today. "..
    "Right of it is everything the well can give. At "..capacity.." / "..capacity..
    " it is flat out, and the next customer needs a deeper well, another well, or a haven.")
  local bw=CW*(capacity>0 and math.min(1,drawn/capacity) or 0)
  lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+22,CW,6,2)
  lg.setColor(maxed and P.warn or Graph.COMMODITIES[n.commodity].color)
  lg.rectangle("fill",M,y+22,bw,6,2)
  row("In use now",drawn.." "..n.commodity,y+38,maxed and P.warn or P.text)
  row("Spare capacity",spare.." "..n.commodity,y+64,
    maxed and P.bad or spare>0 and P.good or P.textDim)
  row("Maximum output",capacity.." "..n.commodity.." / day",y+90,P.good)
  row("Well depth","level "..level.." / "..City.sourceMaxLevel,y+116)
  row("Wholesale income","+$"..city:sourceIncome(n).." / day",y+142,P.good)
  row("Upkeep","-$"..(trade.sourceUpkeep+(level-1)*2).." / day",y+168,P.warn)
  row("Ports",city.g:degree(n.id).." / "..n.ports,y+194)
  if level<City.sourceMaxLevel then
    local cost=city:sourceUpgradeCost(n)
    button("upgrade-source","Deepen well   +"..trade.upgradeStep.." output   $"..cost,
      M,y+232,CW,38,function() act("upgradeSource",n.id) end,city.money>=cost,
      "Adds "..trade.upgradeStep.." output to this well. No new route, no tie-in, no new ground and no second lot of upkeep -- which is why deepening beats a second well until the levels get steep.",
      false,P.good,maxed and city.money>=cost)
    text("A new "..n.commodity.." well costs $"..city:sourceCost(n.commodity)..
         " plus the route to reach it.",M,y+278,"small",P.textDim,CW)
  else
    text("This well is at full yield. Sink another, or buy ground with a seam on it.",
      M,y+236,"body",P.textDim,CW)
  end
  if n.seam then text("Sunk on a seam: yield multiplied at the wellhead.",M,y+312,"small",P.energy,CW) end
end

local function inspectGate(n,y)
  local t=n.throughput or 0
  row("Throughput limit",t.." units",y,t==0 and P.bad or P.warn)
  row("Carrying",math.floor(city.detail.node[n.id] or 0),y+26)
  row("Ports",city.g:degree(n.id).." / "..n.ports,y+52)
  button("gate-minus","-",M,y+90,44,36,function() act("setGate",n.id,t-1) end,t>0,"One unit tighter")
  button("gate-shut","Shut",M+52,y+90,74,36,function() act("setGate",n.id,0) end,t>0,"Close this branch entirely")
  button("gate-open","Open",M+134,y+90,74,36,function() act("setGate",n.id,24) end,t<24,"Open fully")
  button("gate-plus","+",M+216,y+90,44,36,function() act("setGate",n.id,t+1) end,t<24,"One unit looser")
  text("Everything downstream of this gate shares what it lets through. Tighten it to starve a cheap branch and send scarce supply to a better-paying one.",
    M,y+138,"small",P.textDim,CW)
  button("demolish-node","Demolish  +$"..math.floor((n.paid or city:nodeCost(n.kind))*0.4),
    M,y+196,CW,34,function() act("demolishNode",n.id) end,true,"Removes attached pipes; recovers 40%")
end

local function inspectDepot(n,y)
  local com=n.commodity or "water"
  row("Holding",(n.stored or 0).." / "..(n.capacityStore or City.depotCapacity),y,
    (n.stored or 0)>0 and P.good or P.textDim)
  row("Commodity",string.upper(com),y+26,Graph.COMMODITIES[com].color)
  row("Unsold at the wells",(city.wellSpare[com] or 0).." units",y+52,
    (city.wellSpare[com] or 0)>0 and P.energy or P.textDim,
    "A depot fills from product that was pumped and not sold. Unused haven berths are not that: nothing was landed and nothing was billed for.")
  row("Connected",city.g:degree(n.id)>0 and "yes" or "not yet",y+78,
    city.g:degree(n.id)>0 and P.good or P.warn)
  local w=CW*math.min(1,(n.stored or 0)/(n.capacityStore or City.depotCapacity))
  lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+108,CW,6,2)
  lg.setColor(Graph.COMMODITIES[com].color); lg.rectangle("fill",M,y+108,w,6,2)
  text("Takes in output the network could not sell, up to "..City.depotFillRate..
       " a day, and feeds it back the next morning. Worth having when a market event doubles what a trade pays.",
       M,y+128,"small",P.textDim,CW)
  button("demolish-node","Demolish  +$"..math.floor((n.paid or city:nodeCost(n.kind))*0.4),
    M,y+200,CW,34,function() act("demolishNode",n.id) end,true,"Removes attached pipes; recovers 40%")
end

local function inspectTerminal(n,y)
  local com=n.commodity or "water"
  local trade=City.trade[com]
  local landed=(city.produced or {})[n.id] or 0
  row("Haven",(City.HAVENS[n.haven or "port"] or {}).name or "TERMINAL",y,P.energy)
  row("Commodity",string.upper(com),y+26,Graph.COMMODITIES[com].color)
  row("Capacity",landed.." / "..(n.output or 0).." "..com,y+52,
    landed>=(n.output or 0) and P.warn or P.good,
    "Left of the slash is what the haven landed today and is billing you for. "..
    "Right of it is everything its berths can take.")
  local berths=n.output or 0
  local bw=CW*(berths>0 and math.min(1,landed/berths) or 0)
  lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+74,CW,6,2)
  lg.setColor(landed>=berths and P.warn or Graph.COMMODITIES[com].color)
  lg.rectangle("fill",M,y+74,bw,6,2)
  row("In use now",landed.." "..com,y+90,landed>=berths and P.warn or P.text)
  row("Spare capacity",math.max(0,berths-landed).." "..com,y+116,
    landed>=berths and P.bad or P.good)
  row("Maximum landed",berths.." "..com.." / day",y+142,P.good)
  row("Import charge",string.format("-$%.2f / unit",trade.importCost or 1),y+168,P.warn)
  row("Costing today",string.format("-$%.0f",landed*(trade.importCost or 1)),y+194,P.bad)
  row("Berth upkeep","-$"..City.terminalUpkeep.." / day",y+220,P.warn)
  text("A haven is supply bought, not supply owned: it lands more than any well and charges for every unit that moves. Run track inland to spend it.",
    M,y+250,"small",P.textDim,CW)
  button("demolish-node","Demolish  +$"..math.floor((n.paid or city:nodeCost(n.kind))*0.4),
    M,y+310,CW,34,function() act("demolishNode",n.id) end,true,"Removes attached links; recovers 40%")
end

local function inspectEdge(e,y)
  local broken=e.leaking or e.cap<(e.capMax or e.cap)
  local grade=city:gradeOf(e)
  if e.rail then
    row("Kind","RAILWAY",y,P.accent)
    row("Flow / capacity",math.abs(city.detail.edge[e.id] or 0).." / "..e.cap,y+26)
    row("Length",math.floor(city:pipeLength(e)).."m",y+52)
    row("Daily upkeep",string.format("-$%.2f",city:pipeUpkeep(e)),y+78,P.warn)
    row("Leak risk","none: track does not corrode",y+104,P.good)
    local bore=city:boreCost(e,1)
    button("upgrade","+1 capacity   $"..bore,M,y+142,CW,34,function() act("upgradePipe",e.id) end,
      city.money>=bore and e.capMax<24,"One more wagon path along this line")
    button("demolish-pipe","Lift the track  +$"..math.floor((e.paid or 0)*0.4),M,y+184,CW,32,
      function() act("demolishPipe",e.id) end,true,"Recovers 40% of everything paid into this line")
    return y+230
  end
  -- Repair sits at the top and pulses while there is anything to repair.
  button("repair",broken and ("Repair now   $"..city:repairCost(e)) or "Nothing to repair",
    M,y,CW,40,function() act("repairPipe",e.id) end,
    broken and city.money>=city:repairCost(e),
    "Stops the leak and restores every unit of installed capacity. Until it is fixed this main keeps losing capacity at every close.",
    false,P.bad,broken)
  y=y+52
  row("Condition",e.leaking and (e.cap==0 and "OUT OF SERVICE" or "LEAKING") or "Sound",y,
    e.leaking and P.bad or P.good)
  row("Flow / capacity",math.abs(city.detail.edge[e.id] or 0).." / "..e.cap,y+26)
  row("Installed capacity",e.capMax,y+52)
  row("Length",math.floor(city:pipeLength(e)).."m",y+78)
  row("Lining",grade.name,y+104,(e.grade or 1)>1 and P.good or P.textDim)
  row("Daily leak risk",string.format("%.2f%%",city:leakChance(e)*100),y+130)
  row("Daily upkeep",string.format("-$%.2f",city:pipeUpkeep(e)),y+156,P.warn)
  local bore=city:boreCost(e,1)
  button("upgrade","+1 capacity   $"..bore,M,y+194,146,34,function() act("upgradePipe",e.id) end,
    city.money>=bore and e.capMax<24,
    "One more unit through this trench: fittings at both ends plus the wider bore over all "..
    math.floor(city:pipeLength(e)).."m of it.")
  local lineCost=city:liningCost(e)
  local nextGrade=City.GRADES[(e.grade or 1)+1]
  button("reinforce",nextGrade and (nextGrade.name.."   $"..lineCost) or "Fully armoured",
    M+154,y+194,146,34,function() act("reinforcePipe",e.id) end,
    nextGrade~=nil and city.money>=(lineCost or 0),
    nextGrade and ("Permanent. Drops this main's leak risk to "..math.floor(nextGrade.risk*100)..
      "% of bare and its repair bill to "..math.floor(nextGrade.repair*100)..
      "%. Never required -- a bare pipe carries exactly as much -- but it stops you coming back here.")
      or "There is nothing beyond armour.",
    false,P.good)
  local perDay,days=city:liningPayback(e)
  if perDay then
    text(string.format("Lining saves about $%.2f a day in repairs and pays for itself in %d days, before counting the supply a burst main costs you.",
      perDay,days),M,y+236,"small",P.textDim,CW)
  end
  button("demolish-pipe","Demolish  +$"..math.floor((e.paid or 0)*0.4),M,y+286,CW,32,
    function() act("demolishPipe",e.id) end,true,"Recovers 40% of everything paid into this main")
  return y+330
end

-- Status first, then tools. What is wrong with the network is the thing a
-- player needs before deciding what to build next, and the panel is now tall
-- enough that anything below the structures would sit under the fold.
local function buildPanel()
  local y=TOP-state.scroll

  local leaks,worst=0,nil
  for _,pipe in ipairs(city.g.edges) do
    if pipe.alive and pipe.leaking then
      leaks=leaks+1
      if not worst or pipe.cap<worst.cap then worst=pipe end
    end
  end
  local bill,count=city:repairAllCost()
  heading("NETWORK HEALTH",y); y=y+28
  row("Open leaks",leaks,y,leaks>0 and P.bad or P.good)
  row("Supply shortfalls",city.unserved,y+24,city.unserved>0 and P.warn or P.good)
  row("Maintenance crews",(city.crews or 0).." / "..City.crewMax,y+48,
    (city.crews or 0)>0 and P.good or P.textDim)
  y=y+78
  -- Drawn against capacity, per trade. This is the number that decides whether
  -- the next offer can be signed at all, so it lives on the front panel.
  for _,name in ipairs(Graph.TRADES) do
    if city.licences[name] then
      local drawn,capacity=city:supplyFor(name)
      local full=capacity>0 and drawn>=capacity
      drop(name,M+7,y+8,8)
      text(string.upper(name),M+18,y,"small",P.textDim)
      lg.setFont(R.fonts.body)
      lg.setColor(full and P.warn or P.text)
      lg.printf(drawn.." / "..capacity,M+CW-200,y-1,200,"right")
      local bw=CW*(capacity>0 and math.min(1,drawn/capacity) or 0)
      lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+19,CW,3,1.5)
      lg.setColor(full and P.warn or Graph.COMMODITIES[name].color)
      lg.rectangle("fill",M,y+19,bw,3,1.5)
      y=y+30
    end
  end
  y=y+8
  if count>0 then
    button("repair-all","Repair everything   $"..bill,M,y,CW,36,function() act("repairAll") end,
      city.money>=bill,"Repairs all "..count.." damaged main"..(count==1 and "" or "s")..
      " in one decision, cheapest first (R)",false,P.bad,true)
    button("find-leak","Inspect the worst main",M,y+42,CW,30,
      function() if worst then act("focusEdge",worst.id) end end,worst~=nil,
      "Jump to the main losing the most capacity (L)")
    y=y+84
  else
    text("Every main is sound.",M,y,"body",P.good)
    text("Lining a pipe before it fails costs money now and saves both repair bills and clicks later.",
      M,y+22,"small",P.textDim,CW)
    y=y+60
  end
  line(y); y=y+20

  heading("LAY A LINE",y); y=y+26
  for i,name in ipairs(Graph.TRADES) do
    local held=city.licences[name]
    local spec=Graph.COMMODITIES[name]
    local bx=M+(i-1)*76
    button(name,"",bx,y,72,36,function() state.commodity=name end,held,
      held and ("Price and lay "..name.." "..string.lower(spec.conduit)..
        "s. A separate network on shared ground.")
        or ("Acquire the "..name.." licence in Company"),
      state.commodity==name,spec.color)
    drop(name,bx+36,y+10,9)
    text(string.upper(name):sub(1,5),bx,y+20,"tiny",
      held and (state.commodity==name and spec.color or P.text) or P.textFaint,72,"center")
  end
  y=y+46
  text("Bore",M,y+9,"body",P.textDim)
  button("capacity-minus","-",M+68,y,32,32,function() state.capacity=math.max(1,state.capacity-1) end,true,"Narrower bore")
  text(state.capacity,M+106,y+9,"body",P.text,26,"center")
  button("capacity-plus","+",M+142,y,32,32,function() state.capacity=math.min(24,state.capacity+1) end,true,
    "Wider bore. Capacity is charged per extra unit and per metre, so widening a long run costs far more than widening a short one.")
  local hasHaven=#city.g:nodesOfKind("terminal")>0
  button("rail-toggle",state.rail and "TRACK" or "PIPE",M+186,y,114,32,
    function() state.rail=not state.rail end,hasHaven,
    hasHaven and ("Switch between laying pipe and laying rail (T). Track runs up to "..
      City.rail.range.."m, must start or end at a haven, and never corrodes -- there is no such thing as a leaking railway.")
      or "Build a haven first: track has to start somewhere.",
    state.rail,P.accent)
  y=y+44
  local scost=city:sourceCost(state.commodity)
  local well=(state.commodity=="power") and "station" or "well"
  button("source","New "..state.commodity.." "..well.."   $"..scost,M,y,CW,36,
    function() state.tool=state.tool=="source" and nil or "source" end,city.money>=scost,
    "Sink a "..well..". Placed on a marked seam it costs less and yields more. Upkeep and wholesale income both scale with output.",
    state.tool=="source",P.good)
  y=y+52
  line(y); y=y+20

  heading("STRUCTURES",y); y=y+26
  for i,name in ipairs(TOOLS) do
    local col,rw=(i-1)%3,math.floor((i-1)/3)
    local bx,by=M+col*102,y+rw*52
    local afford=city.money>=City.price[name]
    button("tool-"..name,"",bx,by,96,44,function() state.tool=state.tool==name and nil or name end,
      afford,toolTips[name],state.tool==name,Graph.KINDS[name].color)
    lg.setColor(state.tool==name and Graph.KINDS[name].color or (afford and P.text or P.textFaint))
    Draw.structureGlyph(name,bx+19,by+22)
    text(string.upper(name):sub(1,8),bx+33,by+7,"tiny",
      state.tool==name and Graph.KINDS[name].color or (afford and P.text or P.textFaint))
    text("$"..City.price[name],bx+33,by+23,"small",P.textDim)
  end
  y=y+math.ceil(#TOOLS/3)*52+10
  row("Treatment grade",city.quality.." / 5",y)
  UI.contentBottom=y+50+state.scroll
end

local function inspectorPanel(n,e)
  local y=TOP-state.scroll
  button("back-to-build","<   Build tools",M,y,CW,30,function()
    state.node,state.edge,state.district=nil,nil,nil
    state.scroll=0
  end,true,"Clear the selection and return to the structures (Escape)")
  y=y+42
  local tail
  if n then
    local title=n.kind=="client" and (City.CLIENTS[n.clientType].name.." "..n.id)
      -- A well is called a well, and an electricity well is called a station.
      or (n.kind=="source" and (string.upper(n.commodity)..
          (n.commodity=="power" and " STATION " or " WELL ")..n.id))
      or (Graph.KINDS[n.kind].name.." "..n.id)
    if n.commodity then drop(n.commodity,M+9,y+10,10); text(title,M+24,y,"mid")
    else text(title,M,y,"mid") end
    y=y+36
    if n.kind=="client" then inspectClient(n,y); tail=y+400
    elseif n.kind=="source" then inspectSource(n,y); tail=y+350
    elseif n.kind=="gate" then inspectGate(n,y); tail=y+240
    elseif n.kind=="depot" then inspectDepot(n,y); tail=y+244
    elseif n.kind=="terminal" then inspectTerminal(n,y); tail=y+390
    else
      row("Ports",city.g:degree(n.id).." / "..n.ports,y)
      row("Carrying",math.floor(city.detail.node[n.id] or 0),y+26)
      if n.kind=="tower" then row("Local leak risk","-55% within 220m",y+52,P.energy)
      elseif n.kind=="pump" then row("Reach","520m",y+52,P.flow) end
      button("demolish-node","Demolish  +$"..math.floor((n.paid or city:nodeCost(n.kind))*0.4),
        M,y+94,CW,34,function() act("demolishNode",n.id) end,true,
        "Removes attached pipes; recovers 40% of the structure price")
      tail=y+140
    end
  else
    drop(e.commodity,M+9,y+10,10)
    text(string.upper(e.commodity).." "..(e.rail and "RAIL" or Graph.COMMODITIES[e.commodity].conduit)
      .." "..e.id,M+24,y,"mid",Graph.COMMODITIES[e.commodity].color)
    tail=inspectEdge(e,y+34)
  end
  UI.contentBottom=tail+state.scroll
end

local function network()
  local n=city.g.nodes[state.node or 0]
  local e=city.g.edges[state.edge or 0]
  if n and n.alive then inspectorPanel(n,nil)
  elseif e and e.alive then inspectorPanel(nil,e)
  else buildPanel() end
end

--------------------------------------------------------------------------------

local function company()
  local y=TOP-state.scroll
  heading("TREASURY",y)
  local b=city:expenseBreakdown()
  row("Projected revenue","+$"..city:dailyRevenue(),y+30,P.good)
  row("Operating costs","-$"..b.total,y+56,P.warn)
  row("Daily net",string.format("$%+d",city:dailyRevenue()-b.total),y+82,P.energy)
  row("Company value","$"..city:valuation(),y+108,P.text,"Cash, plant, ground and locked deposits, less anything owed.")
  text("office $"..b.office.."   wells $"..math.floor(b.sources)..
       "   plant $"..b.structures.."   mains $"..string.format("%.1f",b.pipes)..
       (b.crews>0 and ("   crews $"..b.crews) or "")..
       (b.imports>0 and ("   imports $"..math.floor(b.imports)) or "")..
       (b.interest>0 and ("   interest $"..b.interest) or ""),
       M,y+136,"small",P.textFaint,CW)
  line(y+168)

  heading("CAPITAL",y+186)
  button("invest-minus","-",M,y+214,34,34,function() state.invest=math.max(50,state.invest-50) end,true,"Less")
  button("invest","Invest $"..state.invest,M+41,y+214,218,34,function() act("invest",state.invest) end,
    city.money>=state.invest,"Locked for 7 closes. Mean return 10%, standard deviation 5%: losses are possible.")
  button("invest-plus","+",M+266,y+214,34,34,function() state.invest=state.invest+50 end,true,"More")
  local iy=y+254
  for _,inv in ipairs(city.investments) do
    row("$"..inv.amount.." on deposit",city:daysToMaturity(inv).." days left",iy,P.energy); iy=iy+24
  end

  -- Credit. The fixed rate is the point: the fund is a gamble, the bank is not.
  local limit,avail=city:loanLimit(),city:loanAvailable()
  row("Credit line","$"..(city.loan or 0).." / $"..limit,iy+10,
    (city.loan or 0)>0 and P.warn or P.textDim,
    "The bank lends up to 50% of what the company owns, excluding cash. Interest is a flat 10% a week on the balance, charged daily.")
  if (city.loan or 0)>0 then
    row("Daily interest","-$"..city:loanInterest(),iy+34,P.bad)
  end
  local by=iy+(((city.loan or 0)>0) and 60 or 36)
  -- The amount is clamped to what the bank will actually lend, so the button
  -- never sits dead just because the dial is above the limit.
  local want=math.min(state.borrow or 500,avail)
  button("borrow-minus","-",M,by,34,34,function() state.borrow=math.max(100,(state.borrow or 500)-100) end,true,"Less")
  button("borrow","Borrow $"..want,M+41,by,218,34,function() act("borrow",want) end,
    avail>0,
    "A flat 10% a week on the balance, charged daily -- no variance at all, unlike the deposit fund. $"..
    avail.." of credit available against $"..city:collateral().." of assets.")
  button("borrow-plus","+",M+266,by,34,34,function() state.borrow=(state.borrow or 500)+100 end,true,"More")
  button("repay",(city.loan or 0)>0 and ("Repay $"..math.min(city.loan,city.money)) or "Nothing outstanding",
    M,by+40,CW,32,function() act("repay",math.min(city.loan,city.money)) end,
    (city.loan or 0)>0 and city.money>0,"Pays down as much of the balance as the till allows")
  line(by+92)

  heading("GROWTH",by+110)
  local gy=by+138
  button("ads",city.adDaysLeft>0 and ("Advertising: "..city.adDaysLeft.." days left") or "Advertising campaign   $90",
    M,gy,CW,34,function() act("buyAds") end,city.money>=90 and city.adDaysLeft==0,
    "Five days of increased enquiries")
  button("quality",city.quality>=5 and "Treatment fully upgraded" or ("Treatment grade "..(city.quality+1).."   $"..city:qualityCost()),
    M,gy+41,CW,34,function() act("upgradeQuality") end,city.quality<5 and city.money>=city:qualityCost(),
    "Each grade removes 13% of the base leak risk on every main you own, everywhere")
  local crews=city.crews or 0
  button("hire-crew",crews>=City.crewMax and "Crews fully staffed" or ("Hire maintenance crew   $"..City.crewHire),
    M,gy+82,206,34,function() act("hireCrew") end,crews<City.crewMax and city.money>=City.crewHire,
    "$"..City.crewWage.." a day each. At every close, each crew repairs the worst leaking main on the books and bills you for the work. The wage is the price of not clicking.")
  button("fire-crew","Stand down",M+214,gy+82,86,34,function() act("dismissCrew") end,crews>0,
    "Remove one crew from the payroll")
  for i,name in ipairs({"power","beer","oil"}) do
    local cost=City.price[name.."Licence"]
    local held=city.licences[name]
    local by2=gy+123+(i-1)*40
    button("licence-"..name,held and (string.upper(name).." licence held") or (string.upper(name).." licence   $"..cost),
      M,by2,CW,34,function() act("buyLicence",name) end,not held and city.money>=cost,
      "Opens "..name.." wells, "..name.." mains and the customers who buy it",false,
      Graph.COMMODITIES[name].color)
    drop(name,M+16,by2+17,8)
  end
  line(gy+252)
  heading("RECENT CASH FLOW",gy+270)
  local start=math.max(1,#city.history-6)
  local hy=gy+298
  for i=start,#city.history do
    local h=city.history[i]
    local net=h.revenue-(h.expenses or 0)
    row("Day "..h.day,string.format("$%+d",net),hy,net>=0 and P.good or P.bad)
    hy=hy+24
  end
  UI.contentBottom=hy+state.scroll+24
end

--------------------------------------------------------------------------------

local function customers()
  local y=TOP-state.scroll
  if #city.tenders>0 then
    heading("MUNICIPAL TENDERS",y)
    y=y+30
    for _,t in ipairs(city.tenders) do
      local have=(city.flowBy[t.commodity] or 0)
      local meeting=have>=t.units
      drop(t.commodity,M+9,y+16,9)
      text(t.units.." "..string.upper(t.commodity).." for "..t.days.." closes",M+24,y,"body",
        meeting and P.good or P.text)
      text("$"..t.reward.." on delivery",M+24,y+19,"small",P.energy)
      lg.setFont(R.fonts.small); lg.setColor(meeting and P.good or P.warn)
      lg.printf(t.met.."/"..t.days.."  (now "..have..")",M+CW-160,y+2,160,"right")
      lg.setFont(R.fonts.tiny); lg.setColor(P.textDim)
      lg.printf("lapses day "..t.expires,M+CW-160,y+21,160,"right")
      local bw=CW*math.min(1,t.met/t.days)
      lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+38,CW,3)
      lg.setColor(meeting and P.good or P.warn); lg.rectangle("fill",M,y+38,bw,3)
      y=y+56
    end
    line(y); y=y+22
  end
  for _,prospect in ipairs({true,false}) do
    heading(prospect and "CONNECTION ENQUIRIES" or "ACTIVE CUSTOMERS",y)
    y=y+30
    local clients=city:clientList(prospect)
    if #clients==0 then
      text(prospect and "No open enquiries" or "No signed contracts",M,y,"small",P.textFaint); y=y+34
    end
    for _,c in ipairs(clients) do
      local met=(city.served[c.id] or 0)>=c.demand
      local premium=city:ratePremium(c)
      local status=prospect and "Offer" or met and "Supplied"
        or (c.supplyClosed and "Valve shut / " or "")..c.grace.." days left"
      button("client-"..c.id,"",M,y,CW,34,function() act("focusNode",c.id) end,true,
        "Locate and inspect this customer",state.node==c.id,Graph.COMMODITIES[c.commodity].color)
      drop(c.commodity,M+16,y+17,8)
      text(City.CLIENTS[c.clientType].name.." "..c.id,M+30,y+9,"body",P.text)
      lg.setFont(R.fonts.body); lg.setColor(P.energy)
      lg.printf("$"..c.rate*c.demand.."/day",M+CW-110,y+9,100,"right")
      -- A badge the player can read at a glance once the spread opens up.
      local tag = premium>0.12 and string.format("PREMIUM %+.0f%%",premium*100)
        or premium<-0.12 and string.format("LOWBALL %+.0f%%",premium*100)
        or string.format("$%d/unit",c.rate)
      text(c.demand.." "..c.commodity.."  /  "..status,M+8,y+40,"small",
        prospect and P.energy or met and P.good or P.warn)
      lg.setFont(R.fonts.small)
      lg.setColor(premium>0.12 and P.good or premium<-0.12 and P.bad or P.textDim)
      lg.printf(tag,M+CW-150,y+40,150,"right")
      y=y+74
    end
    y=y+18
  end
  UI.contentBottom=y+state.scroll
end

--------------------------------------------------------------------------------

local function mapTab()
  local y=TOP-state.scroll
  heading("DISTRICTS",y)
  local owned=#city:ownedDistricts()
  text(owned.." of "..#city.districts.." held",M+CW-150,y,"small",P.textDim,150,"right")
  y=y+28
  for i,d in ipairs(city.districts) do
    local spec=City.DISTRICTS[i]
    if d.owned then
      button("district-"..i,d.name.."   held",M,y,CW,30,function() act("focusDistrict",i) end,
        true,"Your ground. Customers here lean "..
        (next(spec.bias) and table.concat((function() local t={} for k in pairs(spec.bias) do t[#t+1]=k end table.sort(t) return t end)(),", ") or "mixed")..".",
        state.district==i,P.good)
    else
      local err=city:districtError(i)
      local cost=city:districtCost(d)
      button("district-"..i,d.name.."   $"..cost,M,y,CW,30,
        function() act("buyDistrict",i) end,not err,
        err and (d.name..": "..err) or
        ("Buy "..d.name..". Opens it for building and brings enquiries from the trades that live there."),
        state.district==i,err and P.textFaint or P.energy)
    end
    y=y+34
  end
  line(y+8)

  heading("PERMITS",y+26)
  text("Ground the company is not allowed to touch, until it is.",M,y+46,"small",P.textDim,CW)
  local py=y+90
  for _,kind in ipairs(City.PERMIT_ORDER) do
    local spec=City.PERMITS[kind]
    local held=city.permits and city.permits[kind]
    local o=City.OBSTACLES[kind]
    button("permit-"..kind,held and (spec.name.."  held") or (spec.name.."   $"..spec.cost),
      M,py,CW,34,function() act("buyPermit",kind) end,not held and city.money>=spec.cost,
      held and (o.name.." is now workable: crossings cost x"..spec.cross.." and you may build on it.")
        or ("Makes "..string.lower(o.name).." buildable and drops its crossing charge to x"..spec.cross..
            (o.cross and (" from x"..o.cross) or " from impassable")..". The richest seams are under bedrock."),
      false,held and P.good or {o.color[1],o.color[2],o.color[3]})
    py=py+40
  end
  line(py+10)

  heading("HAVENS",py+28)
  text("A terminal can only be built where freight can arrive.",M,py+48,"small",P.textDim,CW)
  local hy=py+72
  for _,h in ipairs(city:havenDistricts()) do
    local spec=City.HAVENS[h.haven]
    row(spec.name,h.district.owned and "held" or "$"..city:districtCost(h.district),hy,
      h.district.owned and P.good or P.energy,
      h.district.name.." has "..spec.blurb..". A haven lands 24 units a day of one trade.")
    hy=hy+24
  end
  line(hy+12)

  heading("SEAMS",hy+30)
  local free,buried=0,0
  for _,s in ipairs(city.deposits or {}) do
    if not s.taken then
      free=free+1
      if city:obstacleAt(s.x,s.y) then buried=buried+1 end
    end
  end
  row("Unclaimed on the map",free,hy+60,free>0 and P.energy or P.textDim)
  row("Of those, under obstacles",buried,hy+86,buried>0 and P.warn or P.textDim)
  text("A well sunk on a seam costs less and yields half again as much. Buried seams need the matching permit first.",
    M,hy+114,"small",P.textDim,CW)
  UI.contentBottom=hy+180+state.scroll
end

--------------------------------------------------------------------------------

local function ledger()
  local y=TOP-state.scroll
  if city.event then
    heading("MARKET",y)
    lg.setColor(P.with(city.event.rate>1 and P.good or P.bad,0.14))
    lg.rectangle("fill",M,y+24,CW,46,4)
    lg.setColor(P.with(city.event.rate>1 and P.good or P.bad,0.5))
    lg.rectangle("line",M,y+24,CW,46,4)
    text(city.event.head,M+10,y+31,"small",P.text,CW-20)
    text(string.format("%s x%.2f  /  %d day%s left",string.upper(city.event.commodity),
      city.event.rate,city.event.left,city.event.left==1 and "" or "s"),
      M+10,y+53,"tiny",city.event.rate>1 and P.good or P.bad)
    y=y+88
  end
  heading("COMPANY JOURNAL",y)
  y=y+34
  if #city.log==0 then text("The company opened today.",M,y,"body",P.textDim) end
  for _,entry in ipairs(city.log) do
    text("DAY "..entry.day,M,y,"tiny",P.flow)
    local _,lines=R.fonts.body:getWrap(entry.text,CW-6)
    text(entry.text,M,y+18,"body",P.text,CW-6)
    y=y+26+#lines*R.fonts.body:getHeight()+15
  end
  UI.contentBottom=y+state.scroll
end

--------------------------------------------------------------------------------

-- Six companies, side by side. The game still opens straight into whichever was
-- last played, so this is somewhere you go on purpose rather than a menu the
-- game makes you walk through every launch.
local function slotsPanel(x,y,w,h)
  text("Companies",x+32,y+26,"big")
  text("Six companies kept side by side. The one you are playing is saved automatically before you leave it.",
    x+32,y+68,"small",P.textDim,w-64)
  local slots=state.slots or {}
  local y0,rowH=y+106,74
  for i=1,Save.SLOTS do
    local info=slots[i] or {slot=i,empty=true}
    local active=(city.slot or 1)==i
    local ry=y0+(i-1)*rowH
    lg.setColor(active and P.with(P.good,0.10) or P.with(P.bg,0.55))
    lg.rectangle("fill",x+24,ry,w-48,64,4)
    lg.setColor(active and P.with(P.good,0.55) or P.panelEdge); lg.setLineWidth(1)
    lg.rectangle("line",x+24,ry,w-48,64,4)
    text(i,x+40,ry+18,"mid",active and P.good or P.textDim)

    local confirm=state.slotConfirm
    local confirming=confirm and confirm.slot==i
    if confirming then
      text(confirm.mode=="restart" and "Start over? This company is lost."
        or "Delete this company? It cannot be undone.",x+72,ry+24,"body",P.bad,w-260)
      button("slot-yes-"..i,confirm.mode=="restart" and "Start over" or "Delete",
        x+w-208,ry+16,84,32,function()
          act(confirm.mode=="restart" and "newSlot" or "deleteSlot",i)
        end,true,nil,false,P.bad)
      button("slot-no-"..i,"Cancel",x+w-116,ry+16,80,32,
        function() state.slotConfirm=nil end,true)
    elseif info.empty then
      text("Empty",x+72,ry+14,"body",P.textFaint)
      text("Start a new company here",x+72,ry+36,"small",P.textFaint)
      button("slot-new-"..i,"New company",x+w-176,ry+16,140,32,
        function() act("newSlot",i) end,true,
        "Begins a fresh company in this slot. The one you are playing is saved first.",
        false,P.good)
    else
      local headline="Day "..info.day.."      $"..info.money
      text(headline,x+72,ry+12,"body",info.bankrupt and P.bad or P.text)
      -- The trades this company has opened, as their own symbols, on the
      -- headline row where nothing else is competing for the space.
      local tx=x+236
      for _,name in ipairs(info.trades or {}) do
        drop(name,tx,ry+21,8); tx=tx+19
      end
      local bits={info.clients.." customer"..(info.clients==1 and "" or "s"),
                  info.districts.." district"..(info.districts==1 and "" or "s"),
                  "worth $"..info.worth}
      if info.bankrupt then table.insert(bits,1,"INSOLVENT") end
      text(table.concat(bits,"   /   "),x+72,ry+36,"small",
        info.bankrupt and P.bad or P.textDim,w-300)
      if active then
        text("PLAYING",x+w-216,ry+18,"small",P.good,90,"right")
        button("slot-restart-"..i,"Start over",x+w-116,ry+16,80,32,
          function() state.slotConfirm={slot=i,mode="restart"} end,true,
          "Replaces this company with a new one")
      else
        button("slot-play-"..i,"Play",x+w-208,ry+16,84,32,
          function() act("loadSlot",i) end,true,
          "Opens this company. The one you are playing is saved first.",false,P.flow)
        button("slot-delete-"..i,"Delete",x+w-116,ry+16,80,32,
          function() state.slotConfirm={slot=i,mode="delete"} end,true,
          "Removes this company for good")
      end
    end
  end
  button("slots-close","Close",x+32,y+h-56,w-64,38,
    function() state.modal=nil; state.slotConfirm=nil end,true,"Back to the network")
end

local function report()
  local r=city.lastReport
  local w,h = 580,540
  if state.modal=="slots" then w,h = 680,632 end
  local x,y=(W-w)/2,(H-h)/2
  lg.setColor(0,0,0,0.7); lg.rectangle("fill",0,0,W,H)
  lg.setColor(P.panel); lg.rectangle("fill",x,y,w,h,6)
  lg.setColor(P.panelEdge); lg.rectangle("line",x,y,w,h,6)
  if state.modal=="slots" then slotsPanel(x,y,w,h); return end
  if state.modal=="restart" then
    text("Start a new company?",x+32,y+34,"big")
    text("The current company save will be replaced.",x+32,y+95,"body",P.textDim,w-64)
    button("cancel-restart","Keep company",x+32,y+h-64,245,36,function() state.modal=nil end)
    button("confirm-restart","Start fresh",x+293,y+h-64,255,36,function() act("restart") end)
    return
  end
  text(city.bankrupt and "Company insolvent" or "Day "..r.day.." closed",x+32,y+28,"big")
  text("DAILY STATEMENT",x+32,y+74,"small",P.textDim)
  local entries={
    {"Customer & wholesale revenue",string.format("+$%d",r.revenue),P.good},
    {"Operating expenses",string.format("-$%d",r.expenses),P.warn},
    {"Crew repairs",string.format("-$%d",r.crewCost or 0),(r.crewCost or 0)>0 and P.warn or P.textDim},
    {"Investment profit / loss",string.format("$%+d",r.interest),P.energy},
    {"Tenders & grants",string.format("+$%d",(r.bonus or 0)+(r.tender or 0)),P.good},
    {"Cash available","$"..city.money,P.text},
  }
  for i,v in ipairs(entries) do
    text(v[1],x+32,y+102+(i-1)*30,"body",P.textDim)
    text(v[2],x+400,y+102+(i-1)*30,"body",v[3])
  end
  local ly=y+292
  text(string.format("%d supply shortfalls    %d customers lost",r.unhappy,#r.left),x+32,ly,"body",
    r.unhappy>0 and P.warn or P.good)
  text(string.format("%d leaking mains    %d out of service    %d fixed by crews",
    #r.leaks,#r.burst,r.crewFixed or 0),x+32,ly+28,"body",#r.leaks+#r.burst>0 and P.bad or P.textDim)
  if (r.stored or 0)>0 or (r.drawn or 0)>0 then
    text(string.format("Depots took in %d and gave back %d",r.stored or 0,r.drawn or 0),x+32,ly+56,"body",P.accent)
  end
  text(r.arrived and ("New enquiry: "..r.arrived.name) or "No new connection enquiries",x+32,ly+84,"body",P.flow)
  if r.event then text(r.event,x+32,ly+112,"small",P.energy,w-64)
  elseif r.tenderNew then
    text(string.format("Tender posted: %d units of %s for %d closes, $%d",
      r.tenderNew.units,r.tenderNew.commodity,r.tenderNew.days,r.tenderNew.reward),x+32,ly+112,"small",P.energy,w-64)
  end
  if city.bankrupt then
    button("new-company","Companies",x+32,y+h-66,w-64,38,function() act("openSlots") end,
      true,"Start again here, or open one of your other companies")
  else
    button("continue","Open day "..city.day,x+32,y+h-66,w-64,38,function() state.modal=nil end,true,"Return to the network")
  end
end

--------------------------------------------------------------------------------

local TABS={{"network","Network"},{"finance","Company"},{"customers","Clients"},{"map","Map"},{"ledger","Log"}}

function UI.draw(c,s,action)
  city,state,act=c,s,action
  W,H=R.dimensions()
  UI.buttons={}; scroll=false
  lg.setColor(P.panel); lg.rectangle("fill",0,0,UI.width,H)
  lg.rectangle("fill",UI.width,0,W-UI.width,80)
  lg.setColor(P.panelEdge); lg.line(UI.width,0,UI.width,H); lg.line(0,80,W,80)
  text("NET PROFIT",M,17,"big")
  text("MUNICIPAL UTILITY COMPANY",M+1,55,"tiny",P.textDim)

  local net=city:dailyRevenue()-city:dailyExpenses()
  local metrics={{"DAY",city.day,P.text},{"CASH","$"..city.money,P.energy},
    {"NET / DAY",string.format("$%+d",net),net>=0 and P.good or P.bad},
    {"CUSTOMERS",#city:clientList(),P.flow},
    {"VALUE","$"..city:valuation(),P.text},
    {"REPUTATION",city.reputation.."%",P.text}}
  if (city.loan or 0)>0 then
    metrics[5]={"DEBT","$"..city.loan,P.bad}
  end
  local width=(W-UI.width-34)/#metrics
  for i,m in ipairs(metrics) do
    local x=UI.width+22+(i-1)*width
    local font=R.fonts.big:getWidth(tostring(m[2]))>width-14 and "mid" or "big"
    text(m[1],x,15,"tiny",P.textDim); text(m[2],x,35,font,m[3])
  end

  for i,t in ipairs(TABS) do
    button("tab-"..t[1],t[2],8+(i-1)*66,103,64,34,function()
      state.tab=t[1]; state.scroll=0
      -- The Map tab is a map: opening it pulls the camera back to show the
      -- whole city, so the ground being priced is the ground being looked at.
      if t[1]=="map" then act("fitWorld") end
    end,true,nil,state.tab==t[1])
  end

  lg.setScissor(0,160,UI.width-1,H-222); scroll=true
  if state.tab=="network" then network()
  elseif state.tab=="finance" then company()
  elseif state.tab=="customers" then customers()
  elseif state.tab=="map" then mapTab()
  else ledger() end
  scroll=false; lg.setScissor()
  UI.maxScroll=math.max(0,(UI.contentBottom or H)-(H-65))
  if UI.maxScroll>0 then
    lg.setColor(P.panelEdge); lg.rectangle("fill",UI.width-9,165,3,H-236)
    lg.setColor(P.textDim)
    lg.rectangle("fill",UI.width-9,165+(H-266)*math.min(1,state.scroll/UI.maxScroll),3,30)
  end

  -- The strip above the map: the next milestone, or whatever is on fire.
  local leaks=0
  for _,pipe in ipairs(city.g.edges) do if pipe.alive and pipe.leaking then leaks=leaks+1 end end
  lg.setColor(P.with(P.bg,0.94)); lg.rectangle("fill",UI.width+1,81,W-UI.width-1,47)
  local bx=UI.width+22
  if leaks>0 or city.unserved>0 then
    local msg={}
    if leaks>0 then msg[#msg+1]=leaks.." leaking main"..(leaks==1 and "" or "s") end
    if city.unserved>0 then msg[#msg+1]=city.unserved.." customer"..(city.unserved==1 and "" or "s").." short" end
    text(table.concat(msg,"    /    "),bx,97,"body",leaks>0 and P.bad or P.warn)
    if leaks>0 then
      local bill,count=city:repairAllCost()
      button("banner-repair","Repair all  $"..bill,W-360,90,150,30,function() act("repairAll") end,
        city.money>=bill,"Fix every damaged main at once",false,P.bad,true)
      button("banner-next","Worst main",W-200,90,110,30,function()
        local worst
        for _,pipe in ipairs(city.g.edges) do
          if pipe.alive and pipe.leaking and (not worst or pipe.cap<worst.cap) then worst=pipe end
        end
        if worst then act("focusEdge",worst.id) end
      end,true,"Inspect the main losing the most capacity (L)")
    elseif city.unserved>0 then
      button("banner-short","Who is short?",W-200,90,150,30,function()
        local short=city:shortCustomers()[1]
        if short then act("focusNode",short.id) end
      end,true,"Open the first customer who is not getting what they signed for, and say why")
    end
  else
    local milestone
    for i,m in ipairs(City.MILESTONES) do if not city.milestones[i] then milestone=m; break end end
    if milestone then
      local count=#city:clientList()-city.unserved
      text(milestone.name.."   "..count.." / "..milestone.target.." supplied",bx,97,"body",P.text)
      text("$"..milestone.reward.." grant",math.max(720,W-170),97,"small",P.energy)
    elseif city.event then
      text(city.event.head,bx,97,"body",city.event.rate>1 and P.good or P.warn)
    else
      text("UTILITY EMPIRE   /   "..#city:ownedDistricts().." districts held",bx,97,"body",P.good)
    end
  end

  lg.setColor(P.panel); lg.rectangle("fill",0,H-58,W,58)
  lg.setColor(P.panelEdge); lg.line(0,H-58,W,H-58)
  button("undo","<",16,H-44,36,32,function() act("undo") end,#state.undo>0,"Undo last decision (Z); day closes are final")
  button("fit","[ ]",62,H-44,36,32,function() act("fit") end,true,"Fit the network (F)")
  button("mute",state.muted and "o" or "~",108,H-44,36,32,function() act("mute") end,true,"Toggle sound (M)")
  button("companies","Companies",158,H-44,142,32,
    function() act("openSlots") end,true,
    "Six companies, kept side by side. Switch, start another, or delete one.")
  local message=state.toast or (state.tool and (string.upper(state.tool).." selected: click the map to place") or "Operations open")
  text(message,UI.width+20,H-34,"small",state.toastBad and P.bad or P.textDim,math.max(100,W-UI.width-250))
  button("end-day","Close day "..city.day,W-193,H-46,173,36,function() act("endDay") end,
    not city.bankrupt,"Settle revenue, expenses, investments and pipe wear (Enter)",true,P.good)
  if state.modal then UI.buttons={}; report() end

  local mx,my=love.mouse.getPosition()
  for _,b in ipairs(UI.buttons) do
    if b.tip and mx>=b.x and mx<=b.x+b.w and my>=b.y and my<=b.y+b.h then
      local tw=math.min(340,W-24)
      local _,lines=R.fonts.small:getWrap(b.tip,tw-20)
      local th=#lines*R.fonts.small:getHeight()+20
      local tx=math.min(W-tw-12,math.max(12,mx+12))
      local ty=math.max(10,math.min(H-th-12,my-th-12))
      lg.setColor(P.bg); lg.rectangle("fill",tx,ty,tw,th,4)
      lg.setColor(P.panelEdge); lg.rectangle("line",tx,ty,tw,th,4)
      text(b.tip,tx+10,ty+10,"small",P.text,tw-20)
      break
    end
  end
end

-- Scroll straight to the inspector. Called whenever a selection is made, so a
-- click on a burst main lands the player on its Repair button rather than on
-- the top of a panel they then have to scroll.
-- The inspector is the whole panel now, so revealing it is just going there.
function UI.revealInspector() return 0 end

function UI.click(x,y)
  for _,b in ipairs(UI.buttons) do
    if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
      if b.enabled then b.fn() end
      return true
    end
  end
  return false
end

return UI
