local P = require("palette")
local City = require("city")
local Graph = require("graph")
local R = require("render")
local Draw = require("company_render")
local Save = require("company_save")
local E = require("experience")
local S=require("symbols")
local SF=require("symbol_font")
local UI = {width=344, buttons={}}
local lg = love.graphics
local state, city, act, scroll, H, W

local M   = 22           -- sidebar margin
local CW  = 300          -- sidebar content width
local TILE_TEXT = 64     -- a structure tile, less the icon on its left
local TOP = 81         -- first content line, before scrolling
local tooltipId,tooltipSince,tooltipX,tooltipY

local function text(s,x,y,font,color,width,align)
  lg.setFont(R.fonts[font or "body"])
  lg.setColor(color or P.text)
  if width then lg.printf(tostring(s),x,y,width,align) else lg.print(tostring(s),x,y) end
end

local function single(s,x,y,font,color,width)
  s=tostring(s)
  local f=R.fonts[font or "body"]
  local scale=math.min(1,width/math.max(1,SF.width(s,f)))
  lg.setFont(f); lg.setColor(color or P.text)
  lg.print(s,x,y,0,scale,scale)
end

-- `emphasis` makes a button ask to be pressed. It is used for exactly one thing:
-- the repair on a main that is currently losing capacity. When the player clicks
-- a burst pipe the game owes them the fix, not a hunt for it.
local function button(id,label,x,y,w,h,fn,enabled,tip,active,color,emphasis)
  enabled = enabled ~= false
  local mx,my = love.mouse.getPosition()
  local inClip = not scroll or (y>=67 and y+h<=H-62)
  local hover = enabled and inClip and mx>=x and mx<x+w and my>=y and my<y+h
  color = color or P.flow
  local pulse = emphasis and enabled and (0.5+0.5*math.sin(R.t*2)) or 0
  lg.setColor(active and P.with(color,0.18) or emphasis and enabled and P.with(color,0.14+0.04*pulse)
    or hover and P.hover or enabled and P.surface or P.panel)
  lg.rectangle("fill",x,y,w,h,6)
  lg.setColor(active and P.with(color,0.8) or emphasis and enabled and P.with(color,0.7) or hover and P.textFaint or P.with(P.panelEdge,enabled and 0.8 or 0.35))
  lg.setLineWidth(1)
  lg.rectangle("line",x,y,w,h,6)
  local font = R.fonts.body
  if SF.width(label,font)>w-14 then font=R.fonts.small end
  if SF.width(label,font)>w-6 then font=R.fonts.tiny end
  lg.setFont(font); lg.setColor(enabled and ((active or emphasis) and color or P.text) or P.textFaint)
  local labelWidth=SF.width(label,font)
  local scale=math.min(1,(w-10)/math.max(1,labelWidth))
  lg.print(label,x+(w-labelWidth*scale)/2,y+(h-font:getHeight()*scale)/2,0,scale,scale)
  if inClip then UI.buttons[#UI.buttons+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled,tip=tip} end
end

local function line(y)
  lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.line(M,y,M+CW,y)
end

local function row(label,value,y,color,tip)
  single(label,M,y,"small",P.textDim,142)
  single(value,M+152,y-1,"body",color or P.text,CW-152)
  if tip then
    local mx,my=love.mouse.getPosition()
    if mx>=M and mx<=M+CW and my>=y-3 and my<=y+17 then
      UI.buttons[#UI.buttons+1]={id="row",x=M,y=y-3,w=CW,h=20,fn=function() end,enabled=false,tip=tip}
    end
  end
end

-- Wrapped small print across the sidebar. Returns the height it took, so the
-- next line lands under the last wrapped line and not on top of it.
local function paragraph(s,y,color)
  text(s,M,y,"small",color or P.textDim,CW)
  local _,lines=R.fonts.small:getWrap(s,CW)
  return math.max(1,#lines)*R.fonts.small:getHeight()
end

local function heading(s,y)
  text(s,M,y,"small",P.textDim)
  local start=M+SF.width(s,R.fonts.small)+12
  if start<M+CW-20 then
    lg.setColor(P.with(P.panelEdge,0.65)); lg.setLineWidth(1)
    lg.line(start,y+7,M+CW,y+7)
  end
end

-- Working out who loses supply if a structure came out means running the flow
-- solver twice, so the answer is kept until the network actually changes.
local consequenceCache = {}
local function consequences(n)
  if consequenceCache.city ~= city or consequenceCache.id ~= n.id or consequenceCache.rev ~= city.revision then
    local pipes, sunk = city:demolitionCost(n.id)
    consequenceCache = { city=city, id = n.id, rev = city.revision, pipes = pipes or 0,
                         sunk = sunk or 0, cut = city:dependentsOf(n.id) }
  end
  return consequenceCache
end

-- One demolish button, with the damage spelled out underneath it. Removing a
-- structure cuts every main tied into it, and those mains are not recovered,
-- so the player is told the count, the money and the customers before pressing.
local function demolishBlock(n,y,label,tip)
  local c = consequences(n)
  local refund = math.floor((n.paid or city:nodeCost(n.kind))*0.4)
  button("demolish-node",(label or "Demolish").."   +$"..refund,M,y,CW,36,
    function() act("demolishNode",n.id) end,true,
    tip or "Removes this structure and cuts every main tied into it",
    false,c.cut>0 and P.bad or P.flow,false)
  local message=c.pipes>0 and ("Removes "..c.pipes.." pipes. Loses $"..c.sunk.." of pipe work. "..
    (c.cut>0 and (c.cut.." clients lose supply.") or "")) or "No pipes connected."
  local _,lines=R.fonts.small:getWrap(message,CW)
  text(message,M,y+42,"small",c.cut>0 and P.bad or P.textDim,CW)
  return y+54+#lines*R.fonts.small:getHeight()
end

-- The same droplet the map draws, inline in the sidebar.
local function drop(commodity,x,y,r) Draw.droplet(commodity,x,y,r or 8) end

-- A number set with - and +, laid out so the buttons never sit on the number.
local function stepper(id,label,value,y,onDown,onUp,canDown,canUp,tip,colour)
  text(label,M,y+6,"small",P.textDim)
  text(value,M+120,y+4,"body",colour or P.energy)
  button(id.."-down","-",M+CW-80,y,34,28,onDown,canDown,tip)
  button(id.."-up","+",M+CW-40,y,34,28,onUp,canUp,tip)
end

--------------------------------------------------------------------------------

local toolTips = {
  junction="3 connections. Changes pipe size. Splits a pipe into two. Costs $1/day.",
  manifold="6 connections. Changes pipe size. Carries several goods. Costs $1/day.",
  pump="2 pipe ports. Boosts pressure; reaches 950m. Costs $1/day.",
  tower="Reduces nearby leaks by 55%. Range: 220m. Costs $2/day.",
  gate="2 pipe ports. Sets how much supply passes through. Costs $1/day.",
  depot="Stores spare supply. Releases it when needed. Costs $3/day.",
  exchange="Serves clients within 700m. Accepts nearby requests. Needs a supply pipe. Can replace full feed pipes for you.",
  dc="Receives freight. Sends it through local pipes and roads.",
  terminal="Imports goods for a fee. Requires a freight route. Cannot import electricity.",
  stop="Buses board here. Attach to normal roads, then connect a bus route.",
  station="Requires petrol and a road. Sells petrol to drivers. Costs $5/day.",
  filtration="2 connections. Protects downstream pipes from mineral buildup. Upstream pipes remain untreated; deposits become harmful after 100 days.",
  binder="Short attachment range. Allows two identical parallel pipes; expensive upgrades allow up to five.",
  lab="Cleans soil and water in this district and its eight neighbours. Costs $24/day.",
  resort="Requires a coast or riverbank. Visitors pay you. Costs $40/day per level.",
  corner="2 road connections. Bends a road around what is in its way. Takes offroads and normal roads.",
}

local function towerTip(kind,rest)
  local v=City.INFRA.voltages[City.INFRA.towers[kind]]
  return v.name.." ("..v.kv.." kV) only. One every "..v.span.." m, a booster every "..v.boost.." m. "..rest
end
toolTips.hvtower=towerTip("hvtower","Carries generator output across the map. A transformer steps it down to standard towers and poles.")
toolTips.pylon=towerTip("pylon","With a transformer it feeds workshops, works and facilities, or steps down to poles.")
toolTips.pole=towerTip("pole","With a transformer it feeds homes.")

local TOOLS = {"junction","manifold","pump","filtration","hvtower","pylon","pole","transformer","binder","lab","gate","depot","exchange","terminal","dc","stop","station","resort","corner","intersection","roundabout","interchange"}

-- Replacing a structure where it stands. The mains never come off, so this is
-- the difference between buying three more ports and rebuilding a junction box
-- from scratch with every pipe relaid by hand.
local REPLACEMENTS = {"junction","manifold","pump","tower","gate","depot"}

local function replaceStrip(n,y)
  if not City.CONVERTIBLE[n.kind] then return y end
  heading("REPLACE WITH",y)
  text("Keeps its pipes.",M+CW-170,y,"small",P.textFaint,170,"right")
  y=y+22
  for i,kind in ipairs(REPLACEMENTS) do
    local col,rw=(i-1)%3,math.floor((i-1)/3)
    local bx,by=M+col*102,y+rw*50
    local err=city:convertError(n.id,kind)
    local cost=city:convertCost(n.id,kind)
    local here=(kind==n.kind)
    button("replace-"..kind,"",bx,by,96,42,
      function() act("convertNode",n.id,kind,state.commodity) end,err==nil,
      here and ("This is already a "..string.lower(Graph.KINDS[kind].name)..".")
        or (err and (Graph.KINDS[kind].name..": "..err))
        or ("Replace with a "..string.lower(Graph.KINDS[kind].name).." for $"..cost..
            ", keeping every main tied in. "..Graph.KINDS[kind].ports.." ports."),
      here,Graph.KINDS[kind].color)
    lg.setColor(here and Graph.KINDS[kind].color or (err==nil and P.text or P.textFaint))
    Draw.structureGlyph(kind,bx+19,by+21)
    text(string.upper(kind):sub(1,8),bx+33,by+6,"tiny",
      here and Graph.KINDS[kind].color or (err==nil and P.text or P.textFaint))
    text(here and "here" or (cost==0 and "free" or ("$"..cost)),bx+33,by+22,"small",
      err==nil and P.energy or P.textFaint)
  end
  return y+100
end

-- The Network tab has two faces. With nothing selected it is a workshop: the
-- trade selector, the bore, the structures, and the state of the system. The
-- moment anything is selected it becomes that thing's control panel, at the top
-- of the sidebar, with its most urgent action first. Selecting a burst main
-- puts Repair under the cursor rather than three scrolls away, and "Back to
-- build" returns the workshop -- so navigation is one click in each direction
-- and nothing ever has to be hunted for.

local function inspectClient(n,y)
  if n.demands then
    for _,key in ipairs(Graph.ALL) do
      local want=n.demands[key]
      if want then
        row(string.upper(key),city:quantity(key,((city.servedBy[n.id] or {})[key] or 0)).." / "..city:quantity(key,want),y,Graph.COMMODITIES[key].color)
        y=y+26
      end
    end
  end
  local premium=city:ratePremium(n)
  local good,bad=premium>0.10,premium<-0.10
  row("Supply",string.upper(n.commodity),y,Graph.COMMODITIES[n.commodity].color)
  row("Rate offered",n.commodity=="power" and string.format("$%.2f / kWh",n.rate/5) or ("$"..n.rate.." / unit"),y+26,good and P.good or bad and P.bad or P.text,
    "Every customer negotiates their own price. The going rate for a "..
    string.lower(City.CLIENTS[n.clientType].name).." is $"..(n.rateBase or n.rate)..
    ". The spread widens as the company grows.")
  row("Price difference",string.format("%+.0f%%",premium*100),y+52,
    good and P.good or bad and P.bad or P.textDim)
  row("Income / day","$"..city:contractValue(n),y+78,P.energy)
  row("Delivery",city:quantity(n.commodity,city.served[n.id] or 0).." / "..city:quantity(n.commodity,n.demand),y+104)
  row(n.prospect and "Offer expires" or "Patience",
    n.prospect and (n.expires-city.day+1).." days" or n.grace.." days",y+130,P.warn)
  if n.prospect then
    local p=E.offerPreview(city,n.id)
    text(p.multipleUtilities and "Connect both water and electricity before this household can be fully supplied."
      or p.cost==0 and "Ready to connect. No new pipe needed."
      or p.cost and ("New pipe: about $"..p.cost..".")
      or ("Supply: "..p.delivery.."/"..p.demand..". Connect more supply first."),
      M,y+242,"small",p.cost and P.good or P.warn,CW)
    if p.net then
      text(string.format("Profit change: $%+d/day",p.net),M,y+300,"small",p.net>=0 and P.good or P.warn,CW)
      if (p.displaced or 0)>0 then
        text("Other clients may get less supply.",M,y+326,"small",P.warn,CW)
      end
    end
    button("accept","Sign contract",M,y+168,190,36,function() act("acceptClient",n.id) end,true,
      "The delivery deadline starts when signed",false,P.good,not bad)
    button("decline","Decline",M+198,y+168,102,36,function() act("declineClient",n.id) end,true,
      "Lose 1 reputation. Ignoring it costs 2.",
      false,bad and P.bad or P.flow,bad)
    if bad then text("Paying "..string.format("%.0f%%",-premium*100).." under the going rate.",M,y+214,"small",P.bad,CW)
    elseif good then text("Paying "..string.format("%.0f%%",premium*100).." over the going rate.",M,y+214,"small",P.good,CW) end
  else
    button("supply-valve",n.supplyClosed and "[ ]  Customer supply" or "[x]  Customer supply",
      M,y+168,CW,36,function() act("toggleSupply",n.id) end,true,
      "Stops supply to this client. They may leave.",
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
        local bigger=city:biggerSize(e)
        local bore=bigger and (city:replaceQuote(e.id,bigger,e.grade) or {}).net or 0
        button("widen-bottleneck",
          bigger and ("Put a "..string.lower(City.sizeOf(bigger).name).." main in   $"..bore)
            or (e.size=="large" and not city:unlocked("massive") and "Massive mains are not open yet"
              or "That main is already the largest there is"),
          M,dy+52,CW,36,
          function() act("replacePipe",eid,bigger,e.grade) end,
          bigger~=nil and city.money>=bore,
          bigger and ("Digs out the "..string.lower(City.sizeOf(e.size or "small").name)..
            " main holding this customer back and lays a "..string.lower(City.sizeOf(bigger).name)..
            " one carrying "..City.sizeOf(bigger).cap..". Nothing widens a main in the ground.")
            or (e.size=="large" and city:unlockHint("massive") and ("Massive mains: "..
              string.lower(city:unlockHint("massive"))..".") or "Nothing carries more than a massive main."),
          false,P.good,true)
        button("inspect-bottleneck","Inspect that main",M,dy+94,CW,30,
          function() act("focusEdge",eid) end,true,"Select the main and centre on it")
      elseif why=="output" then
        text("Needs more "..n.commodity..". Upgrade or add a source.",
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
        text("No "..n.commodity.." connection. Drag a pipe from your network.",
          M,dy,"small",P.bad,CW)
      elseif why=="valve" then
        text("Supply is switched off. This client may leave.",
          M,dy,"small",P.warn,CW)
      end
    end
  end
end

local function inspectSource(n,y)
  local level,trade=n.level or 1,City.trade[n.commodity]
  if n.effectiveOutput==0 then
    text("Production stopped: water or soil polluted",M,y,"small",P.bad,CW)
    text("Build an environment lab nearby.",M,y+22,"small",P.textDim,CW); y=y+52
  elseif n.commodity=="power" then
    text("Generator output: 110 kV; energy metered per day",M,y,"small",P.accent,CW); y=y+28
  end
  local capacity=n.effectiveOutput or n.output or 0
  local drawn=(city.produced or {})[n.id] or 0
  local spare=math.max(0,capacity-drawn)
  local maxed=spare<=0 and capacity>0
  -- Capacity in use against capacity installed. This is the first thing to know
  -- about a well: a well at 14/14 is the reason anything downstream of it is
  -- short, and no amount of wider pipe will change that.
  row("Capacity",city:quantity(n.commodity,drawn).." / "..city:quantity(n.commodity,capacity),y,
    maxed and P.warn or P.good,
    "Used supply / maximum supply. Upgrade or add a source when full.")
  local bw=CW*(capacity>0 and math.min(1,drawn/capacity) or 0)
  lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+22,CW,6,2)
  lg.setColor(maxed and P.warn or Graph.COMMODITIES[n.commodity].color)
  lg.rectangle("fill",M,y+22,bw,6,2)
  row("In use now",city:quantity(n.commodity,drawn),y+38,maxed and P.warn or P.text)
  row("Spare capacity",city:quantity(n.commodity,spare),y+64,
    maxed and P.bad or spare>0 and P.good or P.textDim)
  row("Maximum output",city:quantity(n.commodity,capacity),y+90,P.good)
  local ceiling=n.cap or capacity
  if n.plant then
    local spec=City.PLANTS[n.plant] or {}
    row("Plant",spec.name or "PLANT",y+116,P.energy,spec.blurb)
    row("Fuel",(n.fuel or 0)>0 and ("-$"..string.format("%.2f",n.fuel).." / unit made")
      or "none at all",y+142,(n.fuel or 0)>0 and P.warn or P.good,
      "Reactors use fuel. Wind parks do not.")
  else
    -- The ground's own ceiling, which no amount of money moves. It is the reason
    -- the map has to keep going: more supply means further out.
    row("What this ground gives",ceiling.." / day",y+116,
      capacity>=ceiling and P.warn or P.textDim,
      "Maximum supply from this spot. Distant deposits give more.")
    row("Well depth","level "..level.." / "..(n.commodity=="water" and 4 or City.sourceMaxLevel),y+142)
  end
  row("Wholesale income","+$"..city:sourceIncome(n).." / day",y+168,P.good)
  row("Upkeep","-$"..((n.upkeep or trade.sourceUpkeep)+(level-1)*2).." / day",y+194,P.warn)
  row("Connections",city:connectionPorts(n.id).." / "..n.ports,y+220)
  if not n.plant and level<City.sourceMaxLevel and capacity<ceiling then
    local cost=city:sourceUpgradeCost(n)
    button("upgrade-source","Deepen well   +"..trade.upgradeStep.." output   $"..cost,
      M,y+258,CW,38,function() act("upgradeSource",n.id) end,city.money>=cost,
      "Adds "..trade.upgradeStep.." supply per day. Keeps existing pipes.",
      false,P.good,maxed and city.money>=cost)
    text("A new "..n.commodity.." well costs $"..city:sourceCost(n.commodity)..
         " plus the route to reach it.",M,y+304,"small",P.textDim,CW)
    y=y+336
  else
    local description=n.plant and ((City.PLANTS[n.plant] or {}).blurb or "")
      or capacity>=ceiling and ("Limit: "..ceiling.." per day. Build another source for more.")
      or "Fully upgraded. Build another well for more supply."
    local _,lines=R.fonts.body:getWrap(description,CW)
    text(description,M,y+262,"body",P.textDim,CW)
    y=y+262+#lines*R.fonts.body:getHeight()*R.fonts.body:getLineHeight()+14
  end
  if n.seam then
    text("Rich deposit. Gives extra supply.",M,y,"small",P.energy,CW)
    y=y+24
  end
  line(y); y=y+20

  -- Closing a well never takes the network with it. If mains are tied in, the
  -- wellhead is capped and a chamber is left holding them exactly where they
  -- were; that chamber is then an ordinary structure like any other.
  local degree=city.g:degree(n.id)
  local refund=math.floor((n.paid or city:sourceCost(n.commodity))*0.4)
  if degree>0 then
    local kind=city:chamberFor(degree)
    local chamber=city:nodeCost(kind)
    button("demolish-node","Cap the well   +$"..math.max(0,refund-chamber),M,y,CW,36,
      function() act("demolishNode",n.id) end,true,
      "Stops production and pays back part of the well. A "..string.lower(Graph.KINDS[kind].name)..
      " is built in its place for $"..chamber.." to hold the "..degree..
      " main"..(degree==1 and "" or "s").." that are tied in, so nothing is disconnected.",
      false,P.warn)
    text("Production stops. A "..string.lower(Graph.KINDS[kind].name).." is left holding its "..
      degree.." main"..(degree==1 and "" or "s")..", so nothing is cut.",
      M,y+42,"small",P.textDim,CW)
    y=y+82
  else
    y=demolishBlock(n,y,n.plant and "Decommission" or "Close the well",
      "Nothing is tied into it, so it can be removed outright.")
  end
  return y
end

local function inspectGate(n,y)
  local t=n.throughput or 0
  row("Throughput limit",t.." units",y,t==0 and P.bad or P.warn)
  row("Carrying",math.floor(city.detail.node[n.id] or 0),y+26)
  row("Ports",city.g:degree(n.id).." / "..n.ports,y+52)
  button("gate-minus","-",M,y+90,44,36,function() act("setGate",n.id,t-1) end,t>0,"One unit tighter")
  button("gate-shut","Shut",M+52,y+90,74,36,function() act("setGate",n.id,0) end,t>0,"Close this branch entirely")
  button("gate-open","Open",M+134,y+90,74,36,function() act("setGate",n.id,100) end,t<100,"Open fully")
  button("gate-plus","+",M+216,y+90,44,36,function() act("setGate",n.id,t+1) end,t<100,"One unit looser")
  text("Limits supply through this pipe. Lower it to save supply for other clients.",
    M,y+138,"small",P.textDim,CW)
  local tail=replaceStrip(n,y+198)
  return demolishBlock(n,tail+12)
end

local function inspectDepot(n,y)
  local com=n.commodity or "water"
  row("Holding",city:quantity(com,n.stored or 0).." / "..city:quantity(com,n.capacityStore or City.depotCapacity),y,
    (n.stored or 0)>0 and P.good or P.textDim)
  row("Supply",string.upper(com),y+26,Graph.COMMODITIES[com].color)
  row("Unsold at the wells",(city.wellSpare[com] or 0).." units",y+52,
    (city.wellSpare[com] or 0)>0 and P.energy or P.textDim,
    "Stores spare production. Imports arrive only when needed.")
  row("Connected",city.g:degree(n.id)>0 and "yes" or "not yet",y+78,
    city.g:degree(n.id)>0 and P.good or P.warn)
  local w=CW*math.min(1,(n.stored or 0)/(n.capacityStore or City.depotCapacity))
  lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+108,CW,6,2)
  lg.setColor(Graph.COMMODITIES[com].color); lg.rectangle("fill",M,y+108,w,6,2)
  text("Stores up to "..City.depotFillRate.." spare units per day. Releases them when needed.",
       M,y+128,"small",P.textDim,CW)
  button("load-depot","Load "..S.get(com).." from inventory",M,y+158,CW,28,function() act("loadDepot",n.id) end,(city.stock[com] or 0)>0 and (n.stored or 0)<(n.capacityStore or City.depotCapacity),"Move harvested goods into this depot for transport")
  local tail=replaceStrip(n,y+198)
  return demolishBlock(n,tail+12)
end

local function inspectWorks(n,y)
  local recipe=City.RECIPES[n.recipe or ""]
  if not recipe then return y+40 end
  if recipe.farm then
    text((recipe.product or "Crops").." / reserves "..(City.INFRA.farmRadius*2).."m of land",M,y,"small",P.good,CW)
    y=y+26
    if city:pollutionAt(n.x,n.y)>=City.INFRA.pollution.stopAt then
      text("Production stopped: soil is polluted",M,y,"small",P.bad,CW); y=y+28
    end
  end
  if recipe.coproduct then row("Also produces",city:quantity(recipe.coproduct,n.coproductReady or 0),y,P.good); y=y+28 end
  local got=(city.detail.works or {})[n.id] or {}
  row("Makes",city:quantity(recipe.makes,n.ready or 0).." / "..city:quantity(recipe.makes,recipe.rate),y,
    Graph.COMMODITIES[recipe.makes].color,
    "Missing supplies reduce output.")
  lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+24,CW,5,2)
  lg.setColor(Graph.COMMODITIES[recipe.makes].color)
  lg.rectangle("fill",M,y+24,CW*math.min(1,(n.ready or 0)/math.max(1,recipe.rate)),5,2)
  text("Requires per day",M,y+44,"small",P.textDim)
  local ly=y+66
  local short
  for _,name in ipairs(Graph.ALL) do
    local per=recipe.inputs[name]
    if per then
      local want=per*recipe.rate
      local have=got[name] or 0
      if have<want and not short then short=name end
      row(S.get(name),city:quantity(name,have).." / "..city:quantity(name,want),ly,have>=want and P.good or P.warn,
        per.." "..name.." for every "..recipe.makes..". Without it this works makes nothing.")
      lg.setColor(P.panelEdge); lg.rectangle("fill",M,ly+21,CW,4,2)
      lg.setColor(have>=want and P.good or P.warn)
      lg.rectangle("fill",M,ly+21,CW*math.min(1,want>0 and have/want or 0),4,2)
      ly=ly+38
    end
  end
  if short then
    text("Needs more "..short..". Add supply or a larger pipe.",
      M,ly+4,"small",P.warn,CW)
    ly=ly+34
  end
  row("Upkeep","-$"..recipe.upkeep.." / day",ly,P.warn)
  row("Ports",city.g:degree(n.id).." / "..n.ports,ly+26)
  return demolishBlock(n,ly+64,"Close the works",
    "Shuts it down. Every line tied into it is cut.")
end

local function inspectHub(n,y)
  local covered=#(n.covered or {})
  row("Customers on it",covered,y,covered>0 and P.good or P.textDim,
    "Everyone inside "..City.hub.radius.."m who pays at least the floor and has no main of their own. "..
    "Offers in range sign themselves.")
  row("Rate floor","$"..(n.floor or 0).." / unit",y+26,(n.floor or 0)>0 and P.energy or P.textDim,
    "Only serves clients who pay this price or more.")
  button("hub-floor-down","-",M,y+52,34,30,function() act("setHubFloor",n.id,(n.floor or 0)-City.hub.floorStep) end,
    (n.floor or 0)>0,"Serve cheaper customers too")
  button("hub-floor-up","+",M+40,y+52,34,30,function() act("setHubFloor",n.id,(n.floor or 0)+City.hub.floorStep) end,
    true,"Serve only better payers")
  button("hub-auto",n.autoWiden and "Auto-upgrade on" or "Auto-upgrade off",M+84,y+52,CW-84,30,
    function() act("setHubAuto",n.id,not n.autoWiden) end,true,
    "Replaces full feed pipes when this hub needs more supply. You pay the cost.",n.autoWiden,P.accent)
  local ly=y+96
  for _,name in ipairs(Graph.TRADES) do
    local want=(n.demandBy or {})[name] or 0
    if want>0 then
      local got=((city.detail.hub or {})[n.id] or {})[name] or 0
      row(string.upper(name),got.." / "..want,ly,got>=want and P.good or P.warn,
        "What the hub landed today against what its customers asked for. "..
        "Short means the mains into the hub are too narrow, or there is nothing upstream to send.")
      lg.setColor(P.panelEdge); lg.rectangle("fill",M,ly+21,CW,4,2)
      lg.setColor(got>=want and P.good or P.warn)
      lg.rectangle("fill",M,ly+21,CW*(want>0 and math.min(1,got/want) or 0),4,2)
      ly=ly+38
    end
  end
  if covered==0 then
    text("No clients in range. Range: 700m.",
      M,ly,"small",P.warn,CW)
    ly=ly+30
  end
  row("Running cost","-$"..string.format("%.1f",City.hub.upkeep+covered*City.hub.perClient).." / day",ly,P.warn,
    "$"..City.hub.upkeep.." for the hub and $"..City.hub.perClient.." for every customer on it.")
  text("Connect supply to this hub. It serves nearby clients without extra pipes.",
    M,ly+30,"small",P.textDim,CW)
  return demolishBlock(n,ly+96,"Demolish the hub",
    "Closes the hub. Its customers go back to having no connection at all.")
end

local function inspectTerminal(n,y)
  local spec=City.HAVENS[n.haven or "port"] or City.HAVENS.port
  local landed=(city.producedBy or {})[n.id] or {}
  local _,bill=city:importBill()
  row("Haven",spec.name,y,P.energy)
  row("Freight",string.format("x%.2f on every unit",spec.import),y+26,
    spec.import<=1 and P.good or P.warn,
    "What this door charges over list price. Sea freight is the cheap way in, "..
    "air the dear one. It is the only difference between the three havens.")
  text("Landed here today",M,y+58,"small",P.textDim)
  local ly=y+80
  local any=false
  for _,name in ipairs(Graph.TRADES) do
    local trade=City.trade[name]
    if trade.importCost then
      local units=landed[name] or 0
      if units>0 then any=true end
      row(string.upper(name),units>0 and (units.."  -$"..math.floor(units*trade.importCost*spec.import+0.5)) or "-",
        ly,units>0 and Graph.COMMODITIES[name].color or P.textFaint,
        "Unlimited at $"..string.format("%.2f",trade.importCost*spec.import).." a unit landed. "..
        "You are billed only for what the city actually draws.")
      ly=ly+24
    end
  end
  if not any then
    text("Nothing has moved yet: run track inland to draw on it.",M,ly,"small",P.warn,CW)
  end
  ly=ly+14
  row("Freight bill today","-$"..math.floor((bill[n.id] or 0)+0.5),ly,P.bad)
  row("Berth upkeep","-$"..City.terminalUpkeep.." / day",ly+26,P.warn)
  text("Imports goods for a fee. Requires freight routes. Cannot import electricity.",
    M,ly+56,"small",P.textDim,CW)
  return demolishBlock(n,ly+128,"Demolish the haven",
    "Closes the haven and frees its gateway. Every link tied into it is cut.")
end

local function transitRecord(id) return (((city.transit or {}).byNode) or {})[id] or {} end

local function inspectStop(n,y)
  local rec=transitRecord(n.id)
  local d=city:districtAt(n.x,n.y)
  row("Boarded today",rec.boarded or 0,y,(rec.boarded or 0)>0 and P.good or P.textDim,
    "Trips that started here. People board anywhere the people network reaches their district.")
  row("Living in "..(d and d.name or "the district"),d and (d.population or 0) or 0,y+26)
  local routes={}
  for _,l in ipairs(city.links or {}) do
    if l.alive and l.mode=="bus" and (l.a==n.id or l.b==n.id) then routes[#routes+1]=l end
  end
  row("Bus services",#routes,y+52,#routes>0 and P.text or P.warn)
  text("Bus boarding only. People can choose this bus stop as a daily destination. Buses share roads with cars; houses can connect directly.",
    M,y+86,"small",P.textDim,CW)
  local tail=y+164
  for _,l in ipairs(routes) do
    button("stop-bus-"..l.id,"Inspect bus service "..l.id,M,tail,CW,30,
      function() act("focusLink",l.id) end,true,"Show the bus path on existing roads and manage its buses and fare")
    tail=tail+36
  end
  return demolishBlock(n,tail,"Remove the bus stop","Removes this bus stop and its attached roads and bus services.")
end

local function inspectStation(n,y)
  local rec=transitRecord(n.id)
  local tank=city.served[n.id] or 0
  local price=n.price or City.PEOPLE.pumpPrice
  row("Petrol in the tank",tank.." / "..(n.fuelWanted or City.PEOPLE.stationTank),y,tank>0 and P.good or P.warn,
    "What a gasoline main delivered today. A station with nothing piped to it has nothing to sell.")
  row("Sold today",string.format("%.1f",rec.sold or 0),y+26,(rec.sold or 0)>0 and P.good or P.textDim)
  stepper("station-price","Pump price","$"..price.." a unit",y+52,
    function() act("setStationPrice",n.id,price-1) end,function() act("setStationPrice",n.id,price+1) end,
    price>0,price<City.PEOPLE.tollMax,
    "Drivers pay the going rate of $"..City.PEOPLE.pumpPrice.." without a second thought. Every dollar over it loses "..
    math.floor(City.PEOPLE.priceSensitivity*100).."% of the sales.")
  row("Takings today","+$"..math.floor((rec.sold or 0)*price+0.5),y+90,P.good)
  row("Upkeep","-$"..City.PEOPLE.stationUpkeep.." / day",y+116,P.warn)
  text("Requires petrol and a road. Sells petrol to passing drivers.",
    M,y+148,"small",P.textDim,CW)
  return demolishBlock(n,y+214,"Close the station","Removes the station and cuts every road and main tied into it.")
end

local function inspectResort(n,y)
  local rec=transitRecord(n.id)
  local level=n.level or 1
  row("Visitors today",rec.visitors or 0,y,(rec.visitors or 0)>0 and P.good or P.warn,
    "Leisure trips that reached it. Every populated district within "..
    (City.PEOPLE.resortPull*level/1000).."km sends some, if a road or route gets them here.")
  row("Spent here","+$"..(rec.visitors or 0)*City.PEOPLE.resortSpend*level,y+26,P.good)
  row("Grade","level "..level.." / "..City.PEOPLE.resortLevels,y+52,P.energy)
  row("Upkeep","-$"..City.PEOPLE.resortUpkeep*level.." / day",y+78,P.warn)
  local ly=y+112
  if level<City.PEOPLE.resortLevels then
    local cost=city:resortUpgradeCost(n)
    local bill=city:resortMaterials(n)
    local short=city:materialError(bill)
    button("upgrade-resort","Build it up   $"..cost,M,ly,CW,36,function() act("upgradeResort",n.id) end,
      city.money>=cost and not short,
      short or ("Reaches further, pulls more visitors, and each one spends more. Needs "..
        bill.concrete.." concrete and "..bill.glass.." glass."),false,P.good)
    ly=ly+46
  end
  text("Attracts visitors. Each visitor pays you.",
    M,ly,"small",P.textDim,CW)
  return demolishBlock(n,ly+44,"Close the resort","Closes the resort and cuts every road and route tied into it.")
end

local function inspectEdge(e,y)
  if e.voltage then
    local capacity,amps,kv,loss=city:powerRating(e)
    row("Voltage / rating",kv.." kV / "..amps.." A",y,P.accent)
    row("Daily energy limit",city:quantity("power",capacity),y+26,P.flow)
    row("Loss at rated load",string.format("%.1f%%",loss*100),y+52,P.textDim)
    y=y+88
    if e.unboosted then
      y=y+paragraph("More than "..City.INFRA.voltages[e.voltage].boost.." m from a booster: this cable carries nothing. "..
        "Upgrade a tower closer to the supply to a booster.",y,P.bad)+10
    end
  elseif e.commodity=="water" then
    text((e.filtered and "Filtered downstream" or "Untreated").." | deposits "..math.floor(e.calcification or 0).." / 100",M,y,"small",e.filtered and P.good or P.textDim,CW)
    y=y+28
    if e.hydraulic then
      local capacity,bar=city:waterRating(e)
      row("Design pressure",string.format("%.1f bar",bar),y,P.flow)
      row("Usable flow",capacity.." m3/h",y+26,P.flow); y=y+56
    end
  end
  local broken=e.leaking or e.cap<(e.capMax or e.cap)
  local grade=city:gradeOf(e)
  if e.rail then
    local spec=City.MODES[e.bulk or "rail"]
    local _,haul=city:haulageBill()
    row("Kind",spec.name,y,P.accent,spec.blurb)
    row("Flow / capacity",math.abs(city.detail.edge[e.id] or 0).." / "..e.cap,y+26)
    row("Length",math.floor(city:pipeLength(e)).."m",y+52)
    row("Haulage today",string.format("-$%.2f",haul[e.id] or 0),y+78,P.warn,
      "$"..spec.haulPerUnit.." a unit at the yard plus $"..
      string.format("%.5f",spec.haulPerM).." a unit a metre. This is what distance costs.")
    row("Standing upkeep",string.format("-$%.2f",city:pipeUpkeep(e)),y+104,P.warn)
    row("Leak risk","none: freight lines do not corrode",y+130,P.good)
    if e.bulk=="sea" and (e.wagons or {}).oil then
      row("Oil lost today",string.format("%.1f units",(city.oilSpills or {})[e.id] or 0),y+154,P.warn)
      y=y+28
    end
    -- The wagons. This is what a bulk line is: not a wider pipe but a train
    -- with things loaded onto it.
    text("Loaded with",M,y+162,"small",P.textDim)
    local ly=y+184
    for _,name in ipairs(Graph.ALL) do
      local cap=(e.wagons or {})[name]
      if cap then
        row(string.upper(name),cap,ly,Graph.COMMODITIES[name].color)
        ly=ly+24
      end
    end
    if not e.wagons then row(string.upper(e.commodity),e.cap,ly,Graph.COMMODITIES[e.commodity].color); ly=ly+24 end
    local cost=city:wagonCost(e.id)
    if cost and (e.wagonCount or 1)<8 then
      text((e.bulk=="highway" and "Add a container   $" or "Fit another wagon   $")..cost,M,ly+8,"small",P.textDim,CW)
      local col=0
      for _,name in ipairs(Graph.ALL) do
        if not city:wagonError(e.id,name) and col<10 then
          local bx=M+(col%5)*61
          local by=ly+30+math.floor(col/5)*30
          button("wagon-"..name,string.upper(name):sub(1,5),bx,by,57,26,
            function() act("addWagon",e.id,name) end,city.money>=cost,
            (e.bulk=="highway" and "Add a container for " or "Fit a wagon for ")..name..": "..City.MODES[e.bulk or "rail"].wagonCap.." more capacity, for that alone.",
            false,Graph.COMMODITIES[name].color)
          col=col+1
        end
      end
      ly=ly+30+math.ceil(math.max(1,col)/5)*30
    end
    if e.bulk=="highway" then
      text(e.transportBlocked and "Disconnected: trucks need a road path." or "Container trucks use the road network. Set tolls on highways.",M,ly+8,"small",e.transportBlocked and P.bad or P.textDim,CW)
      ly=ly+60
    end
    button("demolish-pipe","Lift the line  +$"..math.floor((e.paid or 0)*0.4),M,ly+10,CW,32,
      function() act("demolishPipe",e.id) end,true,"Recovers 40% of everything paid into this line")
    return ly+56
  end
  -- Repair sits at the top and pulses while there is anything to repair.
  button("repair",broken and ("Repair now   $"..city:repairCost(e)) or "Nothing to repair",
    M,y,CW,40,function() act("repairPipe",e.id) end,
    broken and city.money>=city:repairCost(e),
    "Stops the leak. Restores full pipe capacity.",
    false,P.bad,broken)
  y=y+52
  row("Condition",e.leaking and (e.cap==0 and "OUT OF SERVICE" or e.voltage and "DEGRADED" or "LEAKING") or "Sound",y,
    e.leaking and P.bad or P.good)
  row("Flow / capacity",city:quantity(e.commodity,math.abs(city.detail.edge[e.id] or 0)).." / "..city:quantity(e.commodity,e.effectiveCap or e.cap),y+26)
  local size=City.sizeOf(e.size or City.sizeFor(e.capMax or e.cap).key)
  row("What is in the ground",size.name.." "..string.lower(grade.name),y+52,
    (e.grade or 1)>1 and P.good or P.textDim,
    "Replace this pipe to change its size or leak protection.")
  row("Length",math.floor(city:pipeLength(e)).."m",y+78)
  row(e.voltage and "Daily fault risk" or "Daily leak risk",string.format("%.2f%%",city:leakChance(e)*100),y+104,
    (e.grade or 1)>=#City.GRADES and P.good or P.textDim)
  row("Daily upkeep",string.format("-$%.2f",city:pipeUpkeep(e)),y+130,P.warn)

  -- Replacing it. Any size, any lining the company knows how to lay, priced as
  -- the new main less scrap on the old one.
  text(e.voltage and "Replace cable" or "Replace pipe",M,y+162,"small",P.textDim)
  local ry=y+184
  for i,spec in ipairs(City.PIPE_SIZES) do
    local target=math.min(city.lining or 1,math.max(e.grade or 1,state.grade or 1))
    local q=city:replaceQuote(e.id,spec.key,target)
    local same=spec.key==(e.size or "") and target==(e.grade or 1)
    local open=city:sizeAllowed(spec)
    button("replace-"..spec.key,(e.commodity=="power" and (City.INFRA.amps[spec.key].." A") or (spec.cap..S.get(e.commodity))).." $"..(q and q.net or 0),M+(i-1)*76,ry,72,32,
      function() act("replacePipe",e.id,spec.key,target) end,
      open and not same and q~=nil and city.money>=(q and q.net or 0),
      same and "This is already what is in the ground."
        or not open and ("Massive mains: "..string.lower(city:unlockHint(spec.unlock))..".")
        or ("A "..string.lower(spec.name).." "..string.lower(City.GRADES[target].name)..
            " main carrying "..spec.cap..". $"..(q and q.total or 0).." of work, less $"..
            (q and q.salvage or 0).." of scrap on the one that comes out."),
      false,Graph.COMMODITIES[e.commodity].color)
  end
  ry=ry+40
  local have=city.lining or 1
  if have>(e.grade or 1) then
    text(City.GRADES[have].name.." pipes: "..string.format("%.2f%%",City.rules.leakBase*City.GRADES[have].risk*100).." leak risk/day.",
      M,ry,"small",P.textDim,CW)
    local perDay,days=city:liningPayback(e,have)
    if perDay and days then
      text(string.format("Saves $%.2f/day. Pays back in %d days.",
        perDay,days),M,ry+30,"small",P.good,CW)
      ry=ry+30
    end
    ry=ry+34
  end
  button("demolish-pipe","Demolish  +$"..math.floor((e.paid or 0)*0.4),M,ry+8,CW,32,
    function() act("demolishPipe",e.id) end,true,"Recovers 40% of everything paid into this main")
  return ry+52
end

-- Everyday construction stays above maintenance and specialist equipment.
-- Which commodities the player can actually do something with today: anything
-- a works here makes or eats, anything standing on the map produces, and
-- anything a haven could land once one is open.
function UI.goodsInPlay()
  local seen,list={},{}
  local function add(name)
    if name and not seen[name] and not city.licences[name] then
      -- The four licensed trades already have their own row.
      seen[name]=true; list[#list+1]=name
    end
  end
  for _,n in ipairs(city.g:aliveNodes()) do
    if n.kind=="works" then
      local recipe=City.RECIPES[n.recipe or ""]
      if recipe then
        add(recipe.makes)
        if recipe.coproduct then add(recipe.coproduct) end
        for input in pairs(recipe.inputs) do add(input) end
      end
    elseif n.kind=="source" and n.commodity then add(n.commodity)
    end
  end
  -- A haven can land almost anything, but listing almost anything is how a
  -- sidebar becomes a catalogue. Only what the company already moves appears.
  for _,e in ipairs(city.g.edges) do
    if e.alive then
      for name in pairs(e.wagons or {}) do add(name) end
      if e.commodity then add(e.commodity) end
    end
  end
  for key,amount in pairs(city.stock or {}) do if amount>0 then add(key) end end
  if #city.g:nodesOfKind("terminal")>0 then add("panels") end
  table.sort(list,function(a,b) return Graph.COMMODITIES[a].order<Graph.COMMODITIES[b].order end)
  return list
end

local function selectService(name)
  state.people=name=="people"
  if not state.people then state.commodity=name end
  state.transit=state.people and "road" or nil
  if state.people then state.filter=nil end
  state.rail=nil
  state.tool=nil; state.drag=nil; state.recipe=nil; state.plant=nil
  state.lineOptions=nil; state.scroll=0
end

local function buildPanel()
  local y=TOP-state.scroll
  heading("BUILD YOUR NETWORK",y)
  button("build-help","i",M+CW-22,y-4,22,22,function() state.buildHelp=not state.buildHelp end,true,"Building and network controls",state.buildHelp)
  y=y+26
  if state.buildHelp then y=y+paragraph("Drag between buildings to connect. Right-drag pans; scroll zooms. Sources need a hub or T split to distribute supply. Select a building or line to inspect, upgrade or repair it. Road networks carry people and commodity trucks.",y)+12 end
  -- The trades the company holds, and the one it could take on next. Nothing
  -- further out than that: a price you cannot pay for a trade you have not
  -- reached is not information, it is wallpaper.
  local trades={}
  for _,name in ipairs(Graph.TRADES) do
    if city.licences[name] then trades[#trades+1]=name end
  end
  local nextTrade=city:nextLicence()
  if nextTrade then trades[#trades+1]=nextTrade end
  for i,name in ipairs(trades) do
    local spec=Graph.COMMODITIES[name]
    local bx=M+((i-1)%4)*76
    local by=y+math.floor((i-1)/4)*40
    button(name,S.get(name),bx,by,72,36,function() selectService(name) end,
      city.licences[name],city.licences[name] and ("Build "..name.." lines")
      or ("The next trade to take on. Buy the "..name.." licence in Company: $"..
          City.price[name.."Licence"]..", and then one building."),
      not state.people and state.commodity==name,spec.color)
  end
  local pi=#trades
  button("people",S.get("roads"),M+(pi%4)*76,y+math.floor(pi/4)*40,72,36,
    function() selectService("people") end,city:unlocked("roads"),
    "Roads carry people and commodities. Available once people settle here.",state.people,P.energy)
  y=y+math.ceil((#trades+1)/4)*40+2
  -- Everything else the company moves. A commodity appears here once there is
  -- somewhere for it to come from, so the panel is four buttons on day one and
  -- fills up as the empire does.
  local goods=UI.goodsInPlay()
  if #goods>0 then
    local col=0
    for _,name in ipairs(goods) do
      local spec=Graph.COMMODITIES[name]
      local bx=M+(col%5)*61
      local by=y+math.floor(col/5)*30
      button("good-"..name,S.get(name),bx,by,57,26,
        function() selectService(name) end,true,
        spec.name..": "..({utility="sold to customers by the day",
          feed="feedstock for a works",material="spent on building",
          fuel="sold to drivers at a filling station",vehicle="taken in at a yard and sold to the districts"})[spec.role]..
        ", carried by "..({liquid="main",solid="road or rail",energy="cable",data="fibre"})[spec.form]..".",
        not state.people and state.commodity==name,spec.color)
      col=col+1
    end
    y=y+math.ceil(#goods/5)*30+6
  end
  y=y+4
  if not state.people then
  if state.commodity=="power" then
    heading("VOLTAGES",y)
    button("voltage-help","i",M+CW-22,y-4,22,22,function() state.voltageHelp=not state.voltageHelp end,true,
      state.voltageHelp and "Hide how voltage works" or "How voltage works",state.voltageHelp,P.accent)
    y=y+24
    if state.voltageHelp then
      local V=City.INFRA.voltages
      y=y+paragraph("Generators send out "..V.high.kv.." kV. A tower carries one voltage. A transformer on a tower "..
        "steps it down to every lower voltage, and customers only connect to a tower with a transformer: "..
        "homes to a low voltage pole, workshops, works and facilities to a standard tower.",y)+6
      for i=#City.INFRA.voltageOrder,1,-1 do
        local spec=V[City.INFRA.voltageOrder[i]]
        row(spec.kv.." kV  "..({hvtower="HV tower",pylon="tower",pole="pole"})[spec.tower],
          "every "..spec.span.." m, boost "..spec.boost.." m",y,P.accent)
        y=y+20
      end
      y=y+paragraph("A booster, a transformer or a generator restarts the booster distance.",y+2)+8
      y=y+paragraph("A (ampere) measures current through a cable. kW measures power. kWh measures energy: 1 kW used for 24 hours is 24 kWh/day. Higher voltage carries the same power with less current.",y)+12
    end
  end
  -- Bore for a main, wagons for a bulk line. They are different things bought
  -- in different units, so the label says which one you are buying.
  local bulk=City.modeOf(state.rail)
  if bulk then
    state.capacity=math.max(1,math.min(8,state.capacity))
    text(bulk=="highway" and "Trucks" or "Wagons",M,y+9,"body",P.textDim)
    button("capacity-minus","-",M+78,y,32,32,function() state.capacity=math.max(1,state.capacity-1) end,true,
      bulk=="highway" and "One container truck fewer" or "One wagon fewer")
    text(state.capacity,M+114,y+8,"body",P.text,26,"center")
    button("capacity-plus","+",M+144,y,32,32,function() state.capacity=math.min(8,state.capacity+1) end,true,
      bulk=="highway" and "One container truck more" or "One wagon more")
    y=y+40
  elseif state.lineOptions then
    -- Three sizes of main and nothing in between, because that is how pipe is
    -- sold. Too small later means digging it out.
    if state.commodity=="power" then
      button("ampere-help","i",M+CW-22,y-4,22,22,function() state.ampereHelp=not state.ampereHelp end,true,"How to choose cable current rating",state.ampereHelp)
      if state.ampereHelp then
        y=y+28+paragraph("Choose the maximum current the cable can safely carry. At the same voltage, more amperes means more capacity. Three-phase power = 1.732 x kV x A. Higher voltage delivers the same energy with lower current and less resistance loss; thicker conductors reduce that loss.",y+28)+12
      end
    end
    text(state.commodity=="power" and "CABLE CURRENT RATING" or (S.get(state.commodity).."  / day"),M,y,"small",P.textDim)
    y=y+18
    for i,spec in ipairs(City.PIPE_SIZES) do
      local bx=M+(i-1)*76
      local open=city:sizeAllowed(spec)
      if not open and state.size==spec.key then state.size="large" end
      button("size-"..spec.key,(state.commodity=="power" and (City.INFRA.amps[spec.key].." A") or (spec.cap.." "..S.get(state.commodity))),bx,y,72,30,function() state.size=spec.key; E.useSize(state,spec.key) end,open,
        open and (state.commodity=="power" and "Capacity depends on voltage, current rating and cable length." or ("Carries "..spec.cap..". Replace it if you need more capacity."))
          or ("Carries "..spec.cap..". "..city:unlockHint(spec.unlock).."."),
        (state.size or "small")==spec.key,Graph.COMMODITIES[state.commodity].color)
    end
    y=y+36
    -- And the lining, which is fixed on the day it is laid.
    text(S.get("shield"),M,y,"small",P.textDim)
    y=y+18
    local have=city.lining or 1
    for g=1,#City.GRADES do
      local spec=City.GRADES[g]
      local bx=M+(g-1)*76
      button("grade-"..g,spec.name,bx,y,72,28,function() state.grade=g end,g<=have,
        g<=have and (spec.name.." pipe: "..math.floor(spec.risk*100).."% leak risk. Build cost: +"..math.floor((spec.cost-1)*100).."%.")
          or ("The company cannot lay "..string.lower(spec.name).." pipe yet. Buy it in Company: $"..
              (spec.price or 0).."."),
        math.min(have,state.grade or have)==g,P.good)
    end
    y=y+38
  end
  if not bulk then
    button("line-options",state.lineOptions and "Hide line options" or (state.commodity=="power" and "Cable options" or "Pipe options"),M,y,CW,28,
      function() state.lineOptions=not state.lineOptions end,true,
      "Pipe sizes fit each building. Choose size and leak protection here.")
    y=y+38
  end
  -- How this line is built. A main, a cable or a road is decided by what is
  -- going down it; the four bulk modes are a decision the player makes.
  local haveBulk=Graph.formOf(state.commodity)~="energy" and Graph.formOf(state.commodity)~="data" and (#city.g:nodesOfKind("terminal")+#city.g:nodesOfKind("dc")>0)
  local localName=({liquid="MAIN",energy="CABLE",solid="ROAD",data="FIBRE"})[Graph.formOf(state.commodity)]
  if haveBulk then
    button("mode-local",localName,M,y,60,28,function() state.rail=nil; state.transit=nil end,true,
      "The city's own network: "..string.lower(localName).." laid between structures, priced by the metre.",
      not bulk,Graph.COMMODITIES[state.commodity].color)
    for i,key in ipairs(City.MODE_ORDER) do
      local spec=City.MODES[key]
      button("mode-"..key,({rail="RAIL",highway="TRUCK",sea="SEA",air="AIR"})[key],
        M+62+(i-1)*61,y,57,28,function() state.rail=key; state.transit=nil end,true,
        spec.name..": "..spec.blurb.."  Each wagon carries "..spec.wagonCap..
        ", and it runs between havens and depot yards only.",bulk==key,spec.colour)
    end
    y=y+40
  else
    state.rail=nil
  end
  end -- commodity line controls
  -- The people network, once there are people: roads first, then the three
  -- passenger routes once a road exists. A drag with one of these picked up
  -- lays it instead of a main.
  if state.people and city:unlocked("roads") then
    local modes={"road"}
    if city:unlocked("routes") then
      for _,key in ipairs(City.ROUTE_ORDER) do modes[#modes+1]=key end
    end
    text(S.get("people").."  /  "..S.get("goods"),M,y,"small",P.textDim)
    y=y+18
    for i,key in ipairs(modes) do
      local spec=City.ROUTES[key]
      button("transit-"..key,({road="ROAD",bus="BUS",ferry="FERRY",air="AIR"})[key],M+(i-1)*76,y,72,28,
        function()
          state.transit=key
          state.rail=nil; state.tool=nil; state.drag=nil; state.filter=nil
        end,true,
        key=="road" and ("Road: $"..City.PEOPLE.roadTiein*2 .." plus $"..string.format("%.2f",City.PEOPLE.roadPerM)..
          " a metre. Drag directly between houses or businesses, or via road junctions. Bus stops are only for boarding buses. Only highways charge tolls.")
          or (spec.name..": $"..spec.vehicle.." a vehicle, "..spec.seats.." seats a day. "..spec.blurb),
        state.transit==key,key=="road" and P.energy or spec.colour)
    end
    y=y+40
    for i,key in ipairs({"offroad","road","highway"}) do
      button("road-type-"..key,({offroad="Offroad",road="Normal",highway="Highway"})[key],M+(i-1)*102,y,98,28,
        function()
          city.buildRoadType=key; state.transit="road"
          state.rail=nil; state.tool=nil; state.drag=nil; state.filter=nil
        end,true,
        key=="offroad" and "Cars only. Uses offroad intersections." or key=="road" and "Cars, trucks and buses. Free to use. Uses roundabouts." or "All vehicles pay per highway segment. Dedicated interchanges; no bus stops.",
        (city.buildRoadType or "road")==key,City.ROAD_TYPES[key].colour)
    end
    y=y+40
  else
    state.transit=nil
  end
  -- One supply button, and it says what the selected trade actually allows:
  -- a well or a rig on a marked deposit, a reactor on any ground, and for beer
  -- nothing at all, because beer is landed rather than made.
  if not state.people then
  if state.commodity=="beer" then
    button("source","Beer is landed at a haven",M,y,CW,36,function() end,false,
      "Import beer, or build a brewery. A brewery needs malt, water and electricity.",
      false,P.textFaint)
  elseif state.commodity=="power" then
    -- Two ways to make electricity, and they want opposite ground.
    for i,key in ipairs(City.PLANT_ORDER) do
      local spec=City.PLANTS[key]
      local cost=city:plantCost(key)
      local bw=(CW-8)/2
      button("plant-"..key,({nuclear="Reactor",wind="Wind",hydro="River turbine",solar="Solar"})[key].."  $"..cost,
        M+((i-1)%2)*(bw+8),y+math.floor((i-1)/2)*44,bw,36,
        function()
          if state.tool=="source" and state.plant==key then state.tool=nil
          else state.tool,state.plant="source",key end
        end,
        city.money>=cost,spec.blurb.." Output "..spec.output.." a day, upkeep $"..spec.upkeep..".",
        state.tool=="source" and state.plant==key,P.good)
    end
    y=y+8+44*(math.ceil(#City.PLANT_ORDER/2)-1)
  elseif state.commodity=="saltwater" then
    button("source","Sea pump  $1600",M,y,CW,36,function() state.tool="source" end,city.money>=1600,"Place on the sea near your coastline. Use a filter and armoured pipes.",state.tool=="source",P.good)
  elseif City.EXTRACTOR_OF[state.commodity] and state.commodity~="wheat" then
    local scost=city:sourceCost(state.commodity)
    local title=City.EXTRACTORS[City.EXTRACTOR_OF[state.commodity]].name
    button("source",title.."  $"..scost,M,y,CW,36,
      function() state.tool=state.tool=="source" and nil or "source" end,city.money>=scost,
      state.commodity=="power"
        and "Requires land you own. Produces electricity."
        or ("Requires a marked "..state.commodity.." deposit. The buried ones yield more and need the matching permit first."),
      state.tool=="source",P.good)
  else
    local recipe=City.MADE_BY[state.commodity]
    local spec=City.RECIPES[recipe or ""]
    button("source",spec and (spec.name.."  $"..spec.cost) or "Import through a haven",M,y,CW,36,
      function() if spec then state.tool="works"; state.recipe=recipe end end,
      spec~=nil and city.money>=spec.cost,
      spec and spec.blurb or "Choose a freight mode and connect a haven to a depot yard.",false,P.good)
  end
  y=y+44
  end -- commodity supply
  -- Supply and maintenance sit above the structures: how full each trade is and
  -- whether anything needs mending is checked far more often than a new building.
  if not state.people then
    local drawn,capacity=city:supplyFor(state.commodity)
    button("supply-detail",city:quantity(state.commodity,drawn).." / "..city:quantity(state.commodity,capacity).."    "..S.get("crews").." "..(city.crews or 0).."/"..City.crewMax,M,y,CW,30,function() state.showSupply=not state.showSupply end,true,"Expand supply totals for every utility",state.showSupply)
    y=y+38
    if state.showSupply then
      for _,name in ipairs(Graph.TRADES) do
        if city.licences[name] then
          local used,total=city:supplyFor(name)
          row(S.get(name),city:quantity(name,used).." / "..city:quantity(name,total),y,Graph.COMMODITIES[name].color); y=y+26
        end
      end
    end
  end
  heading(state.people and "PASSENGER BUILDINGS" or "EVERYDAY STRUCTURES",y); y=y+24
  -- Every building the company has unlocked is on the panel. Hiding half of
  -- them behind a toggle only made the player press the toggle.
  local advanced=true
  -- Which tools exist yet. The first three are always there; the rest arrive
  -- when the company is the size where they are the obvious next move.
  local gate={tower="everyday",gate="everyday",depot="everyday",
              exchange="hub",terminal="haven",dc="yard",
              stop=City.BUILD_UNLOCK.stop,station=City.BUILD_UNLOCK.station,resort=City.BUILD_UNLOCK.resort}
  local shown=0
  for i,name in ipairs(TOOLS) do
    local form=Graph.formOf(state.commodity)
    local passenger=name=="stop" or name=="station" or name=="resort" or name=="corner" or name=="intersection" or name=="roundabout" or name=="interchange"
    local shared=name=="terminal" or name=="dc"
    local relevant
    if state.people then
      relevant=passenger or shared
    elseif passenger then
      relevant=false
    elseif City.INFRA.towers[name] or name=="transformer" then
      relevant=state.commodity=="power"
    elseif name=="filtration" or name=="tower" then
      relevant=state.commodity=="water" or state.commodity=="saltwater"
    elseif name=="lab" then
      relevant=state.commodity=="water" or state.commodity=="oil" or state.commodity=="wheat" or state.commodity=="food"
    elseif name=="junction" or name=="manifold" or name=="pump" or name=="binder" or name=="gate" then
      relevant=form=="liquid"
    elseif name=="depot" or shared then
      relevant=form=="liquid" or form=="solid"
    else
      relevant=true
    end
    if relevant and (i<=4 or City.INFRA.towers[name] or name=="transformer" or state.people or advanced)
      and (not City.BUILD_UNLOCK[name] or city:unlocked(City.BUILD_UNLOCK[name]))
      and (not gate[name] or city:unlocked(gate[name])) then
      local col,rw=shown%3,math.floor(shown/3)
      shown=shown+1
      local bx,by=M+col*102,y+rw*58
      local afford=city.money>=City.price[name]
      button("tool-"..name,"",bx,by,96,50,function() state.tool=state.tool==name and nil or name end,
        afford,toolTips[name],state.tool==name,Graph.KINDS[name].color)
      lg.setColor(afford and Graph.KINDS[name].color or P.textFaint)
      Draw.structureGlyph(name,bx+17,by+24)
      -- The icon holds the left of the tile; the name and the price share
      -- what it leaves, centred in it rather than pushed against it.
      text(({junction="T split",manifold="Hub",pump="Pump",filtration="Filter",hvtower="HV tower",pylon="Tower",pole="LV pole",transformer="Transformer",binder="Binder",lab="Env. lab",tower="Treat",gate="Valve",depot="Depot",exchange="Hub",terminal="Haven",dc="Yard",
             stop="Bus stop",station="Station",resort="Resort",corner="Corner",intersection="Crossing",roundabout="Roundabout",interchange="Interchange"})[name],
        bx+32,by+8,"tiny",P.text,TILE_TEXT,"center")
      text("$"..City.price[name],bx+32,by+28,"small",P.textDim,TILE_TEXT,"center")
    end
  end
  -- The sea pump and the purifier are structures like any other, so they are
  -- built from the same grid. Their marks are the water they handle: brine
  -- from the sea, and the same drop with the sparkle of having been cleaned.
  if not state.people and (state.commodity=="water" or state.commodity=="saltwater") then
    local extras={
      {id="seawater",name="Sea pump",mark="saltwater",price=1600,colour=Graph.COMMODITIES.saltwater.color,
       tip="Place on the sea near your coastline. Feed it through a filter and armoured saltwater main.",
       active=state.commodity=="saltwater" and state.tool=="source",
       press=function() state.commodity="saltwater"; state.tool="source"; state.grade=math.max(3,state.grade or 1) end},
      {id="purifier",name="Purifier",mark="clean",price=City.RECIPES.purifier.cost,colour=P.good,
       tip="Saltwater in; equal clean water and salt out. Place on owned land.",
       active=state.tool=="works" and state.recipe=="purifier",
       press=function() state.tool="works"; state.recipe="purifier" end},
    }
    for _,spec in ipairs(extras) do
      local col,rw=shown%3,math.floor(shown/3)
      shown=shown+1
      local bx,by=M+col*102,y+rw*58
      local afford=city.money>=spec.price
      button(spec.id,"",bx,by,96,50,spec.press,afford,spec.tip,spec.active,spec.colour)
      lg.setColor(afford and spec.colour or P.textFaint)
      SF.mark(spec.mark,bx+17,by+25,11)
      text(spec.name,bx+32,by+8,"tiny",P.text,TILE_TEXT,"center")
      text("$"..spec.price,bx+32,by+28,"small",P.textDim,TILE_TEXT,"center")
    end
  end
  y=y+math.ceil(math.max(shown,1)/3)*58+10
  -- What is not here yet, and what brings it.
  if advanced and not state.people then
    for _,key in ipairs({"hub","haven","yard"}) do
      local hint=city:unlockHint(key)
      if hint then
        y=y+paragraph(City.UNLOCKS[key].name..": "..string.lower(hint),y,P.textFaint)+4
      end
    end
    y=y+6
  end
  -- The works. Nine buildings that turn one thing into another, listed with
  -- what they eat, because that is the only thing worth knowing about them.
  if not state.people and advanced and city:unlocked("works") then
    heading("WORKS",y); y=y+24
    -- A works behind an unlock is not listed at all until it opens.
    local open={}
    for _,key in ipairs(City.RECIPE_ORDER) do
      local unlock=City.RECIPES[key].unlock
      -- The turbine is a power plant and the purifier is an everyday
      -- structure with a tile of its own; neither belongs in this list twice.
      if key~="turbine" and key~="purifier" and City.RECIPES[key].makes==state.commodity
        and (not unlock or city:unlocked(unlock)) then open[#open+1]=key end
    end
    for _,key in ipairs(open) do
      local r=City.RECIPES[key]
      local parts={}
      for _,name in ipairs(Graph.ALL) do
        if r.inputs[name] then parts[#parts+1]=r.inputs[name].." "..name end
      end
      local can=city:licensed(r.makes)
      button("works-"..key,r.name.."   $"..r.cost,M,y,CW,30,
        function()
          if state.tool=="works" and state.recipe==key then state.tool=nil
          else state.tool,state.recipe="works",key end
        end,
        can and city.money>=r.cost,
        E.recipeSummary(r)..(can and "" or " Requires a licence."),
        state.tool=="works" and state.recipe==key,Graph.COMMODITIES[r.makes].color)
      y=y+34
    end
    y=y+8
  end
  -- Which door the haven tool builds. Three small buttons that only appear
  -- while the tool is in hand, so the panel is no wider the rest of the time.
  if state.tool=="terminal" then
    for i,key in ipairs(City.GATEWAYS) do
      local spec=City.HAVENS[key]
      local bx=M+(i-1)*102
      local kind=state.havenKind or "port"
      button("haven-"..key,"",bx,y,96,46,function() state.havenKind=key end,
        city.money>=city:havenCost(key),
        spec.name..": "..spec.blurb..". Freight x"..string.format("%.2f",spec.import)..
        (spec.gate=="coast" and ", coast only." or ", anywhere you hold."),
        kind==key,P.energy)
      text(({port="Harbour",highway="Road head",airfield="Air freight"})[key],bx+8,y+6,"tiny",P.text)
      text("$"..city:havenCost(key),bx+8,y+24,"small",P.textDim)
    end
    y=y+56
  end
  UI.contentBottom=y+state.scroll
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
    local title=n.kind=="client" and E.clientName(city,n)
      -- A well is called a well, and an electricity well is called a station.
      or (n.kind=="works" and (((City.RECIPES[n.recipe or ""] or {}).name or "WORKS").." "..n.id))
      or (n.kind=="source" and ((n.plant and (City.PLANTS[n.plant] or {}).name
          or (string.upper(n.commodity).." WELL")).." "..n.id))
      or (Graph.KINDS[n.kind].name.." "..n.id)
    if n.commodity then drop(n.commodity,M+9,y+10,10); single(title,M+24,y,"mid",P.text,CW-24)
    else single(title,M,y,"mid",P.text,CW) end
    y=y+36
    if City.INFRA.kinds[n.kind] then
      row("Connections",city:connectionPorts(n.id).." / "..n.ports,y)
      text(toolTips[n.kind] or "",M,y+30,"small",P.textDim,CW)
      tail=y+118
      local carries=City.INFRA.towers[n.kind]
      if carries then
        local spec=City.INFRA.voltages[carries]
        row("Voltage",spec.kv.." kV"..(n.upgrade=="transformer" and " and lower" or ""),tail,P.accent); tail=tail+26
        row("Upgrade",n.upgrade and City.INFRA.upgrades[n.upgrade].name or "None",tail); tail=tail+26
        local run=city:boostRuns(carries)[n.id]
        row("Since last boost",run and (math.floor(run).." / "..spec.boost.." m") or "Not connected",tail,
          run and run>spec.boost*0.8 and P.warn or P.textDim); tail=tail+34
        if not n.upgrade then
          for _,key in ipairs({"transformer","booster"}) do
            local up=City.INFRA.upgrades[key]
            local price=up.cost[n.kind]
            button("upgrade-"..key,"Add "..string.lower(up.name).."  $"..price,M,tail,CW,34,
              function() act("upgradeTower",n.id,key) end,city.money>=price,
              key=="transformer" and "Lets this tower take cables at every lower voltage and connect customers of its own voltage. One upgrade per tower."
                or "Restarts the booster distance on this tower's voltage. One upgrade per tower.")
            tail=tail+42
          end
        end
      elseif n.kind=="binder" then
        row("Parallel lanes",n.bundleLanes or 2,tail); tail=tail+30
        local lanes=n.bundleLanes or 2
        local price=City.INFRA.binderPrices[lanes-1]
        button("upgrade-binder",price and ("Upgrade to "..(lanes+1).." lanes  $"..price) or "Maximum lanes",M,tail,CW,36,
          function() act("upgradeBinder",n.id) end,price~=nil and city.money>=price,
          price and ("Needs "..City.INFRA.binderClients[lanes-1].." clients.") or "Fully upgraded")
        tail=tail+48
      elseif n.kind=="lab" then
        row("Local pollution",string.format("%.1f / 100",city:pollutionAt(n.x,n.y)),tail,P.warn)
        tail=tail+32
      end
      tail=demolishBlock(n,tail)
    elseif n.kind=="client" then inspectClient(n,y); tail=y+400
    elseif n.kind=="source" then tail=inspectSource(n,y)
    elseif n.kind=="gate" then tail=inspectGate(n,y)
    elseif n.kind=="depot" then tail=inspectDepot(n,y)
    elseif n.kind=="terminal" then tail=inspectTerminal(n,y)
    elseif n.kind=="exchange" then tail=inspectHub(n,y)
    elseif n.kind=="works" then tail=inspectWorks(n,y)
    elseif n.kind=="stop" then tail=inspectStop(n,y)
    elseif n.kind=="station" then tail=inspectStation(n,y)
    elseif n.kind=="resort" then tail=inspectResort(n,y)
    else
      local degree=city.g:degree(n.id)
      row("Ports",degree.." / "..n.ports,y,degree>=n.ports and P.warn or P.text)
      row("Carrying",math.floor(city.detail.node[n.id] or 0),y+26)
      if n.kind=="tower" then row("Local leak risk","-55% within 220m",y+52,P.energy)
      elseif n.kind=="pump" then row("Reach","520m",y+52,P.flow) end
      if n.capped then
        text("Closed well. Its pipes stay connected.",
          M,y+80,"small",P.textDim,CW)
      end
      tail=replaceStrip(n,y+(n.capped and 128 or 84))
      tail=demolishBlock(n,tail+12)
    end
  else
    drop(e.commodity,M+9,y+10,10)
    text(string.upper(e.commodity).." "..(e.rail and "RAIL" or Graph.COMMODITIES[e.commodity].conduit)
      .." "..e.id,M+24,y,"mid",Graph.COMMODITIES[e.commodity].color)
    tail=inspectEdge(e,y+34)
  end
  UI.contentBottom=tail+state.scroll
end

-- A road or a passenger route: what it carried today, what it charges, and for
-- a route how many vehicles it runs.
local function linkPanel(l)
  local y=TOP-state.scroll
  button("back-to-build","<   Build tools",M,y,CW,30,function()
    state.node,state.edge,state.link,state.district=nil,nil,nil,nil
    state.scroll=0
  end,true,"Clear the selection and return to the structures (Escape)")
  y=y+42
  local road=l.mode=="road"
  local spec=City.ROUTES[l.mode]
  single((road and City.ROAD_TYPES[l.roadType or "road"].name or spec.name).." "..l.id,M,y,"mid",road and P.energy or spec.colour,CW)
  y=y+36
  local rec=(((city.transit or {}).byLink) or {})[l.id] or {}
  local capacity=road and City.PEOPLE.roadCapacity or (l.vehicles or 1)*spec.seats
  row("Trips today",road and tostring(rec.trips or 0) or ((rec.trips or 0).." / "..capacity),y,(rec.trips or 0)>=capacity and P.warn or P.text,
    road and ("Vehicles that used it today. Reference capacity: "..City.PEOPLE.roadCapacity.." trips a day.")
      or ("Seats filled against seats run: "..spec.seats.." a vehicle, every day."))
  local busLength
  if l.mode=="bus" then
    local path
    path,busLength=city:roadPath(l.a,l.b,"bus")
  end
  row("Length",l.mode=="bus" and (busLength and math.floor(busLength).."m on shared roads" or "No road connection") or math.floor(city:nodeDistance(l.a,l.b)).."m",y+26)
  row(road and "Tolls today" or "Fares today","+$"..math.floor((rec.income or 0)+0.5),y+52,P.good)
  row("Upkeep",string.format("-$%.1f / day",city:linkUpkeep(l)),y+78,P.warn)
  local price=road and (l.toll or 0) or (l.fare or 0)
  local max=road and (l.roadType=="highway" and City.PEOPLE.tollMax or 0) or spec.max
  stepper("link-price",road and "Toll" or "Fare","$"..price.." a trip",y+110,
    function() act("setLinkPrice",l.id,price-1) end,function() act("setLinkPrice",l.id,price+1) end,
    price>0,price<max,
    road and "Each vehicle pays on every highway segment it crosses. Normal roads and offroads are free."
      or "What every passenger pays for a seat. A driver takes the car instead if that is cheaper.")
  local ly=y+148
  if not road then
    stepper("vehicle","Vehicles",(l.vehicles or 1).." / "..City.PEOPLE.maxVehicles,ly,
      function() act("removeVehicle",l.id) end,function() act("addVehicle",l.id) end,
      (l.vehicles or 1)>1,(l.vehicles or 1)<City.PEOPLE.maxVehicles and city.money>=spec.vehicle,
      "Another vehicle is "..spec.seats.." more seats a day for $"..spec.vehicle.." and $"..spec.running..
      " a day to run. One sold back returns 40% of its price.")
    ly=ly+38
  end
  text(road and "Daily destinations are chosen per building. Vehicles travel when connected; only highways charge tolls."
    or spec.blurb,M,ly+4,"small",P.textDim,CW)
  button("demolish-link",(road and "Lift the road" or "Close the route").."   +$"..math.floor((l.paid or 0)*0.4),
    M,ly+66,CW,32,function() act("demolishLink",l.id) end,true,"Recovers 40% of everything paid into it (Delete)")
  UI.contentBottom=ly+110+state.scroll
end

local function network()
  local n=city.g.nodes[state.node or 0]
  local e=city.g.edges[state.edge or 0]
  local l=(city.links or {})[state.link or 0]
  if n and n.alive then inspectorPanel(n,nil)
  elseif e and e.alive then inspectorPanel(nil,e)
  elseif l and l.alive then linkPanel(l)
  else buildPanel() end
end

--------------------------------------------------------------------------------

local function company()
  local y=TOP-state.scroll
  single(E.companyName(city),M,y,"mid",P.text,CW)
  button("rename-company",state.rename and "Save name" or "Rename",M,y+30,88,28,function()
    if state.rename then
      if act("setCompanyName",state.rename) then state.rename=nil; state.renameSelectAll=nil end
    else state.rename=E.companyName(city); state.renameSelectAll=true end
  end,true,"Type to replace the name; Enter saves, Escape cancels")
  if state.rename then
    single(state.rename.."|",M+98,y+37,"small",P.energy,CW-98)
  end
  y=y+80
  button("company-permits",state.showPermits and "Hide land permits" or "Land permits",M,y,CW,32,
    function() state.showPermits=not state.showPermits end,true,"Build on trees, rock or water.")
  y=y+44
  if state.showPermits then
    for _,kind in ipairs(City.PERMIT_ORDER) do
      local spec=City.PERMITS[kind]
      local held=city.permits[kind]
      button("permit-"..kind,(held and "Owned: " or "Buy: ")..({park="Trees",river="Water",bedrock="Rock"})[kind]..(held and "" or ("  $"..spec.cost)),
        M,y,CW,32,function() act("buyPermit",kind) end,not held and city.money>=spec.cost,
        "Allows building here. Crossing cost: x"..spec.cross..".")
      y=y+40
    end
  end
  heading("MONEY",y)
  local b=city:expenseBreakdown()
  row("Income / day","+$"..city:dailyRevenue(),y+30,P.good)
  row("Costs / day","-$"..b.total,y+56,P.warn)
  row("Profit / day",string.format("$%+d",city:dailyRevenue()-b.total),y+82,P.energy)
  -- What the yards are holding. Materials are the second currency and the
  -- player needs to see the balance.
  local held,any={},false
  for _,name in ipairs(Graph.ALL) do
    local role=Graph.COMMODITIES[name].role
    if role=="material" or role=="vehicle" then
      local units=city:materialStock(name)
      held[#held+1]={name,units}
      if units>0 then any=true end
    end
  end
  local my=y+116
  if #city.g:nodesOfKind("dc")>0 or any then
    heading("YARDS",my); my=my+26
    for _,pair in ipairs(held) do
      local taken=((city.detail or {}).yard or {})[pair[1]] or 0
      row(string.upper(pair[1]),pair[2]..(taken>0 and ("   +"..taken.." today") or ""),my,
        pair[2]>0 and Graph.COMMODITIES[pair[1]].color or P.textFaint,
        "Materials are taken in at the depot yards and spent on building. "..
        "Each yard holds "..City.yardStock.." and takes "..City.yardIntakeRate.." a day.")
      my=my+24
    end
    my=my+10
  else
    text("Build a freight yard to store materials.",M,my,"small",P.textFaint,CW)
    my=my+30
  end
  line(my)

  heading("CAPITAL",my+18)
  button("invest-minus","-",M,my+46,34,34,function() state.invest=math.max(50,state.invest-50) end,true,"Less")
  button("invest","Invest $"..state.invest,M+41,my+46,218,34,function() act("invest",state.invest) end,
    city.money>=state.invest,"Locks cash for 7 days. The mean and spread shown below include your analysts. You can lose the invested money.")
  button("invest-plus","+",M+266,my+46,34,34,function() state.invest=state.invest+50 end,true,"More")
  local mean,sd=city:investmentDistribution()
  row("7-day mean / spread",string.format("%.0f%% / %.0f%%",mean*100,sd*100),my+86,P.energy)
  local iy=my+114
  for _,inv in ipairs(city.investments) do
    row("$"..inv.amount.." on deposit",city:daysToMaturity(inv).." days left",iy,P.energy); iy=iy+24
  end

  -- Credit. The fixed rate is the point: the fund is a gamble, the bank is not.
  local limit,avail=city:loanLimit(),city:loanAvailable()
  row("Credit line","$"..(city.loan or 0).." / $"..limit,iy+10,
    (city.loan or 0)>0 and P.warn or P.textDim,
    "Borrow up to half your assets. Interest: 10% per week, paid daily.")
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
    "Interest: 10% per week, paid daily. You can borrow $"..avail.." more.")
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
  local nextGrade=City.GRADES[(city.lining or 1)+1]
  button("quality",nextGrade and ("Unlock "..nextGrade.name.." pipes  $"..city:qualityCost()) or "All pipe types unlocked",
    M,gy+41,CW,34,function() act("upgradeQuality") end,nextGrade~=nil and city.money>=city:qualityCost(),
    "Unlocks better leak protection. Choose it in Pipe options. Existing pipes keep their old lining.")
  local crews=city.crews or 0
  button("hire-crew",S.get("crews").." "..crews.."/"..City.crewMax..(crews>=City.crewMax and "" or ("  + $"..City.crewHire)),
    M,gy+82,206,34,function() act("hireCrew") end,crews<City.crewMax and city.money>=City.crewHire,
    "$"..City.crewWage.." per day. Fixes one damaged pipe each day. Repairs cost extra.")
  button("fire-crew","Stand down",M+214,gy+82,86,34,function() act("dismissCrew") end,crews>0,
    "Remove one crew from the payroll")
  -- The rest of the ladder. Each rung is a rule the player writes once and pays
  -- for daily, and none of them appears until the company is big enough that
  -- doing that job by hand is clerical work.
  local oy=gy+124
  for _,key in ipairs(City.ORDER_LIST) do
    local spec=City.ORDERS[key]
    local count=city:workerCount(key)
    local held=count>0
    local can=city:orderAvailable(key)
    button("order-"..key,S.get(key).." "..count.."  + $"..spec.hire,M,oy,CW-92,32,
      function() act("hireOrder",key) end,
      can and city.money>=spec.hire and count<(key=="analysts" and math.huge or 4),
      spec.blurb.."  $"..spec.wage.." a day."..
      (can and "" or ("  Available at "..spec.clients.." customers.")),
      held,held and P.good or P.energy)
    if held then
      button("order-stop-"..key,"Stop",M+CW-86,oy,86,32,function() act("dismissOrder",key) end,
        true,"Take "..string.lower(spec.name).." off the payroll")
    end
    oy=oy+38
  end
  -- The two rules that need a number attached.
  if city:workerCount("dispatchers")>0 then row(S.get("dispatchers").." Visible rings",city:workerCount("dispatchers"),oy,P.energy); oy=oy+30 end
  if (city.orders or {}).estates then
    row("Minimum discount",math.floor((city.estateDiscount or .3)*100).."%",oy,P.energy)
    button("discount-less","-",M+220,oy+20,34,28,function() act("setEstatePolicy",(city.estateDiscount or .3)-.1,city.estateMax or 4000) end,true)
    button("discount-more","+",M+260,oy+20,34,28,function() act("setEstatePolicy",(city.estateDiscount or .3)+.1,city.estateMax or 4000) end,true)
    oy=oy+56
    row("Maximum land price","$"..(city.estateMax or 4000),oy,P.energy)
    button("estate-less","-",M+220,oy+20,34,28,function() act("setEstatePolicy",city.estateDiscount or .3,(city.estateMax or 4000)-1000) end,true)
    button("estate-more","+",M+260,oy+20,34,28,function() act("setEstatePolicy",city.estateDiscount or .3,(city.estateMax or 4000)+1000) end,true)
    oy=oy+56
    row("Cash reserve","$"..(city.estateReserve or 4000).." in hand",oy,P.energy)
    button("reserve-down","-",M+CW-80,oy+22,34,28,function() act("setReserve",(city.estateReserve or 4000)-1000) end,
      (city.estateReserve or 4000)>1000,"Keep less back")
    button("reserve-up","+",M+CW-40,oy+22,34,28,function() act("setReserve",(city.estateReserve or 4000)+1000) end,
      true,"Keep more back")
    oy=oy+60
  end
  gy=oy-124
  -- One trade at a time. The next licence is the only one offered, so the
  -- player is choosing when rather than which, and the panel is never a wall of
  -- prices they cannot pay.
  local offer={}
  for _,name in ipairs(City.LICENCE_ORDER) do
    if city.licences[name] then offer[#offer+1]=name end
  end
  local nextUp=city:nextLicence()
  if nextUp then offer[#offer+1]=nextUp end
  for i,name in ipairs(offer) do
    local cost=City.price[name.."Licence"]
    local held=city.licences[name]
    local by2=gy+123+(i-1)*40
    button("licence-"..name,held and (string.upper(name).." licence held") or (string.upper(name).." licence   $"..cost),
      M,by2,CW,34,function() act("buyLicence",name) end,not held and city.money>=cost,
      held and "Licence owned." or ("Allows "..name.." supply. Build a source or factory next."),false,
      Graph.COMMODITIES[name].color)
    drop(name,M+16,by2+17,8)
  end
  UI.contentBottom=gy+123+#offer*40+state.scroll+24
end

--------------------------------------------------------------------------------

local function customers()
  local y=TOP-state.scroll
  button("sort-clients",state.clientSort=="income" and "Sort: daily income" or "Sort: most urgent",M,y,CW,30,function()
    state.clientSort=state.clientSort=="income" and "urgency" or "income"
  end,true,"Switch between potential daily revenue and the nearest service or offer deadline")
  y=y+46
  for _,prospect in ipairs({true,false}) do
    heading(prospect and "REQUESTS" or "CLIENTS",y)
    y=y+30
    local clients=city:clientList(prospect)
    table.sort(clients,function(a,b)
      if state.clientSort=="income" then
        local av,bv=city:contractValue(a),city:contractValue(b)
        if av~=bv then return av>bv end
      else
        local av=prospect and a.expires or (not city:fullyServed(a) and a.grace or 999)
        local bv=prospect and b.expires or (not city:fullyServed(b) and b.grace or 999)
        if av~=bv then return av<bv end
      end
      return a.id<b.id
    end)
    if #clients==0 then
      text(prospect and "No open enquiries" or "No signed contracts",M,y,"small",P.textFaint); y=y+34
    end
    for _,c in ipairs(clients) do
      local met=city:fullyServed(c)
      local premium=city:ratePremium(c)
      local status=prospect and "Offer" or met and "Supplied"
        or (c.supplyClosed and "Valve shut / " or "")..c.grace.." days left"
      button("client-"..c.id,"",M,y,CW,80,function() act("focusNode",c.id) end,true,
        "Locate and inspect this customer",state.node==c.id,Graph.COMMODITIES[c.commodity].color)
      drop(c.commodity,M+16,y+17,8)
      single(E.clientName(city,c),M+30,y+9,"body",P.text,150)
      lg.setFont(R.fonts.body); lg.setColor(P.energy)
      lg.printf("$"..city:contractValue(c).."/day",M+CW-110,y+9,100,"right")
      -- A badge the player can read at a glance once the spread opens up.
      local tag = premium>0.12 and string.format("PREMIUM %+.0f%%",premium*100)
        or premium<-0.12 and string.format("LOWBALL %+.0f%%",premium*100)
        or (c.commodity=="power" and string.format("$%.2f/kWh",c.rate/5) or string.format("$%d/unit",c.rate))
      if prospect then status="Expires in "..math.max(0,c.expires-city.day+1).." days" end
      single((c.demands and c.demands.water and c.demands.power and ("Water + "..city:quantity("power",c.demands.power)) or city:quantity(c.commodity,c.demand)).." / "..status,M+12,y+35,"small",
        prospect and P.energy or met and P.good or P.warn,CW-16)
      lg.setFont(R.fonts.small)
      lg.setColor(premium>0.12 and P.good or premium<-0.12 and P.bad or P.textDim)
      lg.printf(tag,M+12,y+57,CW-24,"left")
      y=y+92
    end
    y=y+18
  end
  UI.contentBottom=y+state.scroll
end

--------------------------------------------------------------------------------

local function mapTab()
  local y=TOP-state.scroll
  if state.district then
    local d=city.districts[state.district]
    if d then
      single(d.name,M,y,"mid",P.energy,CW)
      y=y+36
      row("Pollution",string.format("%.1f / 100",d.pollution or 0),y,(d.pollution or 0)>=City.INFRA.pollution.stopAt and P.bad or P.good)
      y=y+30
      if (d.population or 0)>0 then
        row("People",d.population,y,P.text,
          "Good supply brings more people. Poor supply makes people leave.")
        row("Driving",math.floor(city:carShareOf(d.id)*100).."%",y+26,P.text,
          "The share who take the car. Cars sold to the district raise it; they wear out and it drifts back.")
        local trips=(((city.transit or {}).byDistrict) or {})[d.id]
        if trips then
          row("Trips today",(trips.carried or 0).." of "..trips.trips.." carried",y+52,
            (trips.carried or 0)>=trips.trips and P.good or P.warn)
        end
        y=y+(trips and 90 or 64)
      end
    end
  end
  local d=city.districts[state.district or 0]
  if d then
    local err=city:districtError(d.id)
    if not d.owned then row("Today only",math.floor(city:landDiscount(d)*100).."% discount",y,P.energy); y=y+28 end
    row("Price",d.owned and "Owned" or ("$"..city:districtCost(d)),y); y=y+36
    if not d.owned then
      button("district-"..d.id,"Buy land  $"..city:districtCost(d),M,y,CW,36,
        function() act("buyDistrict",d.id) end,not err,err or "Buy this land.")
      y=y+48
      if err then text(err,M,y,"small",P.warn,CW); y=y+48 end
    end
    if d.owned then
      for index,o in ipairs(city.obstacles) do
        if city:districtAt(o.x,o.y)==d and (o.kind=="park" or o.kind=="bedrock") then
          local cost=math.ceil(math.floor(o.r*o.r/100)*(o.kind=="park" and 4 or 35))
          button("clear-terrain-"..index,(o.kind=="park" and "Harvest " or "Demolish ")..S.get(o.kind=="park" and "timber" or "rock").."  $"..cost,M,y,CW,32,function() act("clearTerrain",index) end,city.money>=cost,"Requires the permit and all covered land. Mountain demolition has a 5% gem chance.")
          y=y+38
        end
      end
    end
    button("district-permits","Land permits",M,y,CW,32,function() state.tab="finance"; state.scroll=0; state.showPermits=true end,true,"Build on trees, rock or water.")
    y=y+48
  else text("Click land on the map to see its price.",M,y,"body",P.textDim,CW); y=y+60 end
  button("district-back","Back to build",M,y,CW,32,function() state.tab="network"; state.district=nil; state.scroll=0 end)
  UI.contentBottom=y+50+state.scroll
end

--------------------------------------------------------------------------------

local function ledger()
  local y=TOP-state.scroll
  button("stats-back","Back to stats",M,y,CW,30,function() state.tab="stats"; state.scroll=0 end)
  y=y+46
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
  text("Up to six saved companies. Changes save automatically.",
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
    elseif info.error then
      text("Company could not be loaded",x+72,ry+14,"body",P.bad)
      text("Save kept intact. Choose another slot or restore a backup.",x+72,ry+36,"small",P.textDim,w-110)
    elseif info.empty then
      text("Empty",x+72,ry+14,"body",P.textFaint)
      text("Start a new company here",x+72,ry+36,"small",P.textFaint)
      button("slot-new-"..i,"New company",x+w-176,ry+16,140,32,
        function() act("newSlot",i) end,true,
        "Begins a fresh company in this slot. The one you are playing is saved first.",
        false,P.good)
    else
      local headline=info.name or ("Company "..i)
      single(headline,x+72,ry+10,"body",info.bankrupt and P.bad or P.text,w-390)
      -- The trades this company has opened, as their own symbols, on the
      -- headline row where nothing else is competing for the space.
      local tx=x+w-310
      for _,name in ipairs(info.trades or {}) do
        drop(name,tx,ry+21,8); tx=tx+19
      end
      local bits={"Day "..info.day,"$"..info.money,info.clients.." clients",info.districts.." districts"}
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
  local w,h = 580,state.reportDetails and 620 or 440
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
  local profit=r.revenue-r.expenses-(r.crewCost or 0)-(r.preventCost or 0)
  text(city.bankrupt and "Company insolvent" or "Day "..r.day.." complete",x+32,y+24,"big")
  text("OPERATING PROFIT",x+32,y+74,"small",P.textDim)
  single(string.format("$%+d",profit),x+32,y+96,"big",profit>=0 and P.good or P.bad,246)
  text("CLOSING CASH",x+310,y+74,"small",P.textDim)
  single("$"..(r.money or city.money),x+310,y+96,"big",P.energy,w-342)
  text(string.format("%d supply shortfalls  /  %d customers lost",r.unhappy,#r.left),
    x+32,y+144,"body",r.unhappy>0 and P.warn or P.good)
  local reward=r.bonus or 0
  if reward>0 then
    lg.setColor(P.with(P.good,0.12)); lg.rectangle("fill",x+24,y+174,w-48,44,5)
    single("Bonus +$"..reward,x+32,y+186,"body",P.good,w-64)
  else
    text(profit>=0 and r.unhappy==0 and "A good day's work. Your city keeps moving."
      or "A new day to get the network back on track.",x+32,y+183,"body",P.textDim,w-64)
  end
  local newsY=y+230
  local leak
  for _,e in ipairs(city.g.edges) do if e.alive and e.leaking then leak=e; break end end
  local enquiry
  for _,n in ipairs(city:clientList(true)) do
    if r.arrived and n.x==r.arrived.x and n.y==r.arrived.y then enquiry=n; break end
  end
  if leak then
    button("report-leak","Inspect leaking main",x+32,newsY,246,32,function() act("focusEdge",leak.id) end,true,nil,false,P.warn)
  else text("No mains need repair",x+32,newsY+8,"small",P.good) end
  if enquiry then
    button("report-enquiry","View new requests",x+290,newsY,258,32,function() if #(r.arrivals or {})>1 then state.modal=nil; state.tab="customers"; state.scroll=0 else act("focusNode",enquiry.id) end end,true,nil,false,P.flow)
  else
    button("report-clients","Review customers",x+290,newsY,258,32,function()
      state.modal=nil; state.tab="customers"; state.scroll=0
    end,true,"Review offers and deadlines")
  end
  local event=r.event
  if event then single(event,x+32,y+274,"small",P.energy,w-64) end
  button("report-details",state.reportDetails and "Hide accounting" or "Show accounting",x+32,y+316,w-64,30,
    function() state.reportDetails=not state.reportDetails end,true,"Revenue, expenses, repairs, investments and awards")
  if state.reportDetails then
    local entries={
      {"Revenue",r.revenue},{"Costs / day",-r.expenses},{"Repairs / prevention",-(r.crewCost or 0)-(r.preventCost or 0)},
      {"Investment profit / loss",r.interest or 0},{"Grants",reward},
    }
    for i,v in ipairs(entries) do
      text(v[1],x+32,y+360+(i-1)*24,"small",P.textDim)
      text(string.format("$%+d",v[2]),x+400,y+360+(i-1)*24,"small",v[2]<0 and P.warn or P.good)
    end
    if (r.stored or 0)>0 or (r.drawn or 0)>0 or (r.crewFixed or 0)>0 then
      text(string.format("Crews fixed %d mains / Depots: %d stored, %d drawn",r.crewFixed or 0,r.stored or 0,r.drawn or 0),
        x+32,y+502,"small",P.textDim,w-64)
    end
    if (r.trips or 0)>0 or (r.carsSold or 0)>0 then
      single(string.format("Trips: %d/%d. Travel income: $%d.%s",
        r.tripsCarried or 0,r.trips or 0,r.transitIncome or 0,
        (r.carsSold or 0)>0 and string.format(" Cars sold: %d ($%d).",r.carsSold,r.carIncome or 0) or ""),
        x+32,y+526,"small",P.textDim,w-64)
    end
  end
  if city.bankrupt then
    button("new-company","Companies",x+32,y+h-66,w-64,38,function() act("openSlots") end,
      true,"Start again here, or open one of your other companies")
  else
    button("continue","Back to stats",x+32,y+h-66,w-64,38,function() state.modal=nil; state.tab="stats"; state.scroll=0 end,true,"Close these results",true,P.good)
  end
end

--------------------------------------------------------------------------------

local function goals()
  local y=TOP-state.scroll
  button("stats-back","Back to stats",M,y,CW,30,function() state.tab="stats"; state.scroll=0 end)
  y=y+46
  heading("GOALS",y)
  text("Choose a goal. Each reward is paid once. Switching keeps your progress.",M,y+26,"small",P.textDim,CW)
  y=y+80
  for _,a in ipairs(E.ambitions) do
    local done=city.ambitionsDone and city.ambitionsDone[a.id]
    local value=math.min(a.target,E.progress(city,a))
    single(a.name,M,y,"mid",done and P.good or P.text,CW)
    text(a.description,M,y+28,"small",P.textDim,CW)
    lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+67,CW,5,2)
    lg.setColor(P.good); lg.rectangle("fill",M,y+67,CW*value/a.target,5,2)
    text(done and "ACHIEVED" or (value.." / "..a.target),M,y+80,"small",P.good)
    button("ambition-"..a.id,done and "Grant earned" or city.ambition==a.id and "Pursuing" or ("Choose  +$"..a.reward),
      M+150,y+78,150,30,function() act("chooseAmbition",a.id) end,not done,nil,city.ambition==a.id,P.good)
    y=y+132
  end
  heading("YOUR NEXT TOOLS",y); y=y+28
  local nextTools=0
  for _,key in ipairs({"everyday","hub","orders","haven","yard","works","massive","roads","routes","internet"}) do
    local hint=city:unlockHint(key)
    if hint and nextTools<3 then
      text(City.UNLOCKS[key].name,M,y,"body",P.flow)
      local _,wrapped=R.fonts.small:getWrap(hint,CW)
      text(hint,M,y+24,"small",P.textDim,CW)
      y=y+34+#wrapped*R.fonts.small:getHeight(); nextTools=nextTools+1
    end
  end
  if nextTools==0 then text("Every system is open. Build your own city.",M,y,"small",P.good); y=y+32 end
  y=y+16
  heading("BONUSES",y); y=y+30
  for i,m in ipairs(City.MILESTONES) do
    row(m.name,city.milestones[i] and "Earned" or (m.target.." clients / $"..m.reward),y,city.milestones[i] and P.good or P.textDim)
    y=y+30
  end
  UI.contentBottom=y+state.scroll+20
end

local function stats()
  local y=TOP-state.scroll
  local previous=city.lastReport
  if previous then
    heading("DAY "..previous.day.." RESULTS",y); y=y+28
    local profit=previous.revenue-previous.expenses-(previous.crewCost or 0)-(previous.preventCost or 0)
    row("Operating profit",string.format("$%+d",profit),y,profit>=0 and P.good or P.bad); y=y+28
    row("Supply shortfalls",previous.unhappy or 0,y,(previous.unhappy or 0)>0 and P.warn or P.good); y=y+28
    row("Customers lost",#(previous.left or {}),y); y=y+32
    button("previous-results","Full day results",M,y,CW,30,function()
      state.modal="report"; state.reportDetails=false
    end,true,"Revenue, costs, grants and events from the previous day")
    y=y+46
  end
  button("auto-minus","-",M,y,30,30,function() state.autoMinutes=math.max(1,(state.autoMinutes or 5)-1) end,true)
  button("autoplay",state.autoRemaining and ("Stop  "..math.ceil(state.autoRemaining).."s") or ("Autoplay "..(state.autoMinutes or 5).." min"),M+36,y,228,30,function() act("autoplay",state.autoMinutes or 5) end,true,"Temporary assistant: builds water service, accepts viable contracts, repairs and advances days. Uses this company's cash; Stop ends it immediately.")
  button("auto-plus","+",M+270,y,30,30,function() state.autoMinutes=math.min(120,(state.autoMinutes or 5)+1) end,true)
  y=y+40
  button("tab-ambitions","Goals",M,y,CW,36,function() state.tab="ambitions"; state.scroll=0 end,true,"Choose a goal. Earn a cash reward.")
  y=y+46
  button("tab-ledger","History",M,y,CW,32,function() state.tab="ledger"; state.scroll=0 end,true,"Past events and payments.")
  y=y+48
  heading("STATS",y); y=y+30
  for _,v in ipairs({{"Day",city.day},{"Clients",#city:clientList()},{"Open requests",#city:clientList(true)},
    {"Company value","$"..city:valuation()},{"Reputation",city.reputation.."%"},
    {"Requests per day","Up to "..city:requestLimit()},{"Land owned",#city:ownedDistricts()},
    {"Debt","$"..(city.loan or 0)}}) do row(v[1],v[2],y); y=y+30 end
  y=y+16
  text("Decline a request: -1 reputation.\nLet it expire: -2 reputation.\nBetter reputation brings more requests.",M,y,"small",P.textDim,CW)
  y=y+80
  heading("RECENT PROFIT",y); y=y+28
  for i=math.max(1,#city.history-6),#city.history do
    local h=city.history[i]
    row("Day "..h.day,string.format("$%+d",h.revenue-(h.expenses or 0)),y)
    y=y+28
  end
  y=y+16
  heading("DAILY COSTS",y); y=y+28
  local costs=city:expenseBreakdown()
  for _,v in ipairs({{"Office",costs.office},{"Sources",costs.sources},{"Buildings",costs.structures},
    {"Pipes",costs.pipes},{"Staff",costs.crews},{"Imports",costs.imports},{"Freight",costs.haulage},
    {"Hubs",costs.hubs},{"Fuel",costs.fuel},{"Travel",costs.transit},{"Interest",costs.interest}}) do
    if (v[2] or 0)>0 then row(v[1],string.format("$%.1f",v[2]),y); y=y+26 end
  end
  y=y+16
  heading("MAP SUPPLIES",y); y=y+28
  local free,buried={water=0,oil=0},0
  for _,deposit in ipairs(city.deposits or {}) do
    if not deposit.taken and free[deposit.commodity] then
      free[deposit.commodity]=free[deposit.commodity]+1
      if city:obstacleAt(deposit.x,deposit.y) then buried=buried+1 end
    end
  end
  row("Unused water marks",free.water,y); y=y+26
  row("Unused oil marks",free.oil,y); y=y+26
  row("Need a permit",buried,y); y=y+36
  for _,key in ipairs(City.GATEWAYS) do
    local count=0
    for _,n in ipairs(city.g:nodesOfKind("terminal")) do if n.haven==key then count=count+1 end end
    row(City.HAVENS[key].name,count.." built",y); y=y+26
  end
  UI.contentBottom=y+24+state.scroll
end
local TABS={{"network","Build"},{"finance","Company"},{"customers","Clients"},{"stats","Stats"}}

-- The header windows: the figure is printed from HEAD_VALUE, and the windows
-- that carry controls put them on HEAD_ROW.
UI.HEAD_VALUE,UI.HEAD_ROW=34,58

-- The largest size the figure fits in, and one that leaves the control row
-- alone. Counting the price of a repair in 30pt and then drawing the Repair
-- button under it printed the two through each other; a window with controls
-- is 24 points shorter than one without, and has to be measured that way.
function UI.headerFont(value,room,controls)
  local headroom=controls and (UI.HEAD_ROW-UI.HEAD_VALUE) or math.huge
  for _,key in ipairs({"big","mid","small"}) do
    local f=R.fonts[key]
    if SF.width(value,f)<=room and f:getHeight()<=headroom then return key end
  end
  return "small"
end

function UI.draw(c,s,action)
  city,state,act=c,s,action
  W,H=R.dimensions()
  UI.buttons={}; scroll=false
  lg.setColor(P.panel); lg.rectangle("fill",0,0,UI.width,H)
  lg.rectangle("fill",UI.width,0,W-UI.width,80)
  lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.line(UI.width,0,UI.width,H); lg.line(UI.width,80,W,80)

  local net=city:dailyRevenue()-city:dailyExpenses()
  local clients=city:clientList()
  local supplied=0
  for _,client in ipairs(clients) do
    if city:fullyServed(client) then supplied=supplied+1 end
  end
  local metrics={{"AVAILABLE CASH","$"..city.money,P.energy},
    {"EST. PROFIT / DAY",string.format("$%+d",net),net>=0 and P.good or P.bad},
    {"CUSTOMERS SUPPLIED",#clients==0 and "No contracts" or supplied.." / "..#clients,
      #clients==0 and P.textDim or supplied==#clients and P.good or P.warn}}
  local request=city:nextRequest()
  local bill,broken=city:repairAllCost()
  local premium=request and city:requestPremium(request) or 0
  metrics[4]={"CLIENT REQUEST","None",P.energy}
  metrics[5]={"FIX ALL PIPES",broken>0 and (broken.." damaged") or "All sound",broken>0 and P.warn or P.good}
  local width=(W-UI.width-34)/#metrics
  for i,m in ipairs(metrics) do
    local x=UI.width+22+(i-1)*width
    local room=width-16
    -- The heading is measured too: at the narrowest window CUSTOMERS SUPPLIED
    -- is wider than the window it names and ran into CLIENT REQUEST.
    single(m[1],x,16,"tiny",P.textDim,room)
    if i==4 and request then
      -- One control, carrying the only number that ranks an offer: how far
      -- above or below the going rate it is. Pressing it opens the contract.
      button("request-open",string.format("%+.0f%%",premium*100),x,UI.HEAD_VALUE,room,36,
        function() act("focusRequest",request.id) end,true,
        "Open this contract"..(request.powerRequest and " for electricity" or "")..
        ": the best offer on the table, "..string.format("%+.0f%%",premium*100)..
        " against the going rate.",false,premium>=0 and P.good or P.warn)
    else
      local controls=i==5 and broken>0
      local font=(i==3 and #clients==0) and "mid" or UI.headerFont(m[2],width-14,controls)
      single(m[2],x,UI.HEAD_VALUE,font,m[3],room)
      -- The price is the whole of the decision, so the price is the whole of
      -- the button, and it fills the window rather than hugging its left edge.
      if controls then
        button("repair-all","$"..bill,x,UI.HEAD_ROW,room,20,function() act("repairAll") end,
          city.money>=bill,"Repair every damaged line")
      end
    end
    if i>1 then lg.setColor(P.panelEdge); lg.line(x-14,20,x-14,60) end
  end

  local tabX=8
  for i,t in ipairs(TABS) do
    local tabWidth=({74,90,74,70})[i]
    button("tab-"..t[1],t[2],tabX,10,tabWidth,34,function()
      state.rename=nil
      state.tab=t[1]; state.scroll=0
      -- The Map tab is a map: opening it pulls the camera back to show the
      -- whole city, so the ground being priced is the ground being looked at.
      if t[1]=="map" then act("fitWorld") end
    end,true,nil,state.tab==t[1] or (t[1]=="stats" and (state.tab=="ambitions" or state.tab=="ledger")))
    tabX=tabX+tabWidth+4
  end
  lg.setColor(P.with(P.panelEdge,0.65)); lg.line(M,58,M+CW,58)

  lg.setScissor(0,67,UI.width-1,H-129); scroll=true
  if state.tab=="network" then network()
  elseif state.tab=="finance" then company()
  elseif state.tab=="customers" then customers()
  elseif state.tab=="map" then mapTab()
  elseif state.tab=="stats" then stats()
  elseif state.tab=="ambitions" then goals()
  else ledger() end
  scroll=false; lg.setScissor()
  UI.maxScroll=math.max(0,(UI.contentBottom or H)-(H-65))
  state.scroll=math.min(state.scroll,UI.maxScroll)
  if UI.maxScroll>0 then
    local track=H-143
    local thumb=math.max(30,track*track/(track+UI.maxScroll))
    lg.setColor(P.panelEdge); lg.rectangle("fill",UI.width-9,72,3,track,1)
    lg.setColor(P.textFaint)
    lg.rectangle("fill",UI.width-9,72+(track-thumb)*math.min(1,state.scroll/UI.maxScroll),3,thumb,1)
  end

  -- The first day, one step at a time. Everything the player will go on doing
  -- for the rest of the game happens once here, in order, with the panel saying
  -- only what the next action is.
  local step,stepNo,steps=city:tutorialStep()
  if state.buildHelp and step and not state.modal and state.tab=="network" then
    local gx,gw=UI.width+20,math.min(600,W-UI.width-40)
    local font=R.fonts.body
    local _,lines=font:getWrap(step.body,gw-32)
    local gh=84+#lines*20
    local gy=H-72-gh
    lg.setColor(P.panel); lg.rectangle("fill",gx,gy,gw,gh,8)
    lg.setColor(P.with(P.good,0.6)); lg.rectangle("line",gx,gy,gw,gh,8)
    single(stepNo.." / "..steps.."   "..step.title,gx+16,gy+12,"mid",P.good,gw-32)
    text(step.body,gx+16,gy+40,"body",P.text,gw-32)
    button("dismiss-guide","Skip",gx+gw-70,gy+gh-32,58,24,
      function() act("dismissGuide") end,true,"Stop showing the opening steps")
  end

  -- One short panel the first time something new is worth explaining, and never
  -- again. It sits where the opening guide sits, and only when the player is
  -- not in the middle of something.
  local lesson=not state.modal and not (step and state.tab=="network") and city:pendingLesson()
  if state.buildHelp and lesson and (city.day>2 or city.guideDismissed) then
    local gx,gw=UI.width+20,math.min(620,W-UI.width-40)
    local font=R.fonts.body
    local _,lines=font:getWrap(lesson.body,gw-32)
    local gh=84+#lines*20
    local gy=H-72-gh
    lg.setColor(P.panel); lg.rectangle("fill",gx,gy,gw,gh,8)
    lg.setColor(P.with(P.energy,0.6)); lg.rectangle("line",gx,gy,gw,gh,8)
    single(lesson.title,gx+16,gy+12,"mid",P.energy,gw-32)
    text(lesson.body,gx+16,gy+38,"body",P.text,gw-32)
    button("lesson-ok","Got it",gx+gw-78,gy+gh-34,66,26,
      function() act("teach",lesson.key) end,true,"Understood: do not show this again")
  end

  lg.setColor(P.panel); lg.rectangle("fill",0,H-58,W,58)
  lg.setColor(P.panelEdge); lg.line(0,H-58,W,H-58)
  button("undo","Undo",10,H-44,52,32,function() act("undo") end,#state.undo>0,"Undo last decision (Z); day closes are final")
  button("fit","Show all",68,H-44,74,32,function() act("fit") end,true,"Zoom out to show all your buildings. Shortcut: F.")
  button("mute",state.muted and "Muted" or "Sound",148,H-44,58,32,function() act("mute") end,true,"Toggle sound (M)")
  button("companies","Companies",214,H-44,112,32,
    function() act("openSlots") end,true,
    "Six companies, kept side by side. Switch, start another, or delete one.")
  local message=state.toast or (state.tool and (string.upper(state.tool).." selected: click the map to place, right-click or Esc to put it down")
    or (state.node or state.edge) and "Click it again, right-click or press Esc to deselect" or "")
  single(message,UI.width+20,H-34,"small",state.toastBad and P.bad or P.textDim,math.max(100,W-UI.width-250))
  button("end-day","End day "..city.day.."   >",W-193,H-46,173,36,function() act("endDay") end,
    not city.bankrupt,"Settle revenue, expenses, investments and pipe wear (Enter)",true,P.good)

  -- The opening guide does not only say what to press: it points at it. A
  -- sidebar button gets a ring and an arrow from the map side; the bottom bar
  -- gets one from above. Map targets are drawn with the world.
  local target=not state.modal and E.tutorialTarget(city,state)
  if target and target.button then
    for _,b in ipairs(UI.buttons) do
      if b.id==target.button then
        local pulse=0.5+0.5*math.sin(R.t*2)
        local bob=3*math.sin(R.t*2)
        lg.setColor(P.with(P.good,0.45+0.25*pulse)); lg.setLineWidth(2)
        lg.rectangle("line",b.x-4,b.y-4,b.w+8,b.h+8,6)
        if b.x>W/2 or b.y>H-70 then
          local ax,ay=b.x+b.w/2,b.y-14+bob
          lg.polygon("fill",ax,ay,ax-11,ay-16,ax+11,ay-16)
          lg.rectangle("fill",ax-4,ay-34,8,19)
        elseif not b.id:match("^tab%-") then
          local ax,ay=b.x+b.w+14+bob,b.y+b.h/2
          lg.polygon("fill",ax,ay,ax+16,ay-11,ax+16,ay+11)
          lg.rectangle("fill",ax+15,ay-4,19,8)
        end
        lg.setLineWidth(1)
        break
      end
    end
  end
  if state.modal then UI.buttons={}; report() end

  local mx,my=love.mouse.getPosition()
  local hovered
  for _,b in ipairs(UI.buttons) do
    if b.tip and mx>=b.x and mx<=b.x+b.w and my>=b.y and my<=b.y+b.h then
      hovered=b.id..":"..b.tip
      if tooltipId~=hovered or math.abs(mx-(tooltipX or mx))>4 or math.abs(my-(tooltipY or my))>4 then
        tooltipId,tooltipSince,tooltipX,tooltipY=hovered,R.t,mx,my
      end
      if R.t-(tooltipSince or R.t)<0.45 then break end
      local tw=math.min(340,W-24)
      local _,lines=R.fonts.small:getWrap(b.tip,tw-20)
      local th=#lines*R.fonts.small:getHeight()*R.fonts.small:getLineHeight()+20
      local tx,ty
      if b.x+b.w+12+tw<=W-12 then
        tx=b.x+b.w+12; ty=math.max(10,math.min(H-th-12,b.y))
      elseif b.y-th-12>=10 then
        tx=math.max(12,math.min(W-tw-12,b.x)); ty=b.y-th-12
      else
        tx=math.max(12,math.min(W-tw-12,b.x)); ty=math.min(H-th-12,b.y+b.h+12)
      end
      lg.setColor(P.bg); lg.rectangle("fill",tx,ty,tw,th,4)
      lg.setColor(P.panelEdge); lg.rectangle("line",tx,ty,tw,th,4)
      text(b.tip,tx+10,ty+10,"small",P.text,tw-20)
      break
    end
  end
  if not hovered then tooltipId=nil end
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
