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
-- A structure tile: the name across its full width, the glyph and the price
-- on the line under it. The name used to share a line with the icon, in 64
-- points, which broke "Roundabout" into "Roundab / out".
local TILE_W, TILE_H = 96, 50
local TILE_TEXT = TILE_W - 8
local TOP = 78         -- first content line, before scrolling
local tooltipId,tooltipSince,tooltipX,tooltipY

-- The mouse in interface units, which differ from screen points when the
-- interface is drawn larger.
local function mouse()
  -- A walkthrough can rest a pointer on the map without a real mouse.
  if state and state.fakeMouse then return state.fakeMouse[1],state.fakeMouse[2] end
  local x,y=love.mouse.getPosition()
  local k=UI.scale or 1
  return x/k,y/k
end

local function text(s,x,y,font,color,width,align)
  lg.setFont(R.fonts[font or "body"])
  lg.setColor(color or P.text)
  if width then lg.printf(tostring(s),x,y,width,align) else lg.print(tostring(s),x,y) end
end

local function single(s,x,y,font,color,width,align)
  s=tostring(s)
  local f=R.fonts[font or "body"]
  local natural=SF.width(s,f)
  local scale=math.min(1,width/math.max(1,natural))
  if align=="right" then x=x+width-natural*scale
  elseif align=="center" then x=x+(width-natural*scale)/2 end
  lg.setFont(f); lg.setColor(color or P.text)
  lg.print(s,x,y,0,scale,scale)
end

-- `emphasis` makes a button ask to be pressed. It is used for exactly one thing:
-- the repair on a main that is currently losing capacity. When the player clicks
-- a burst pipe the game owes them the fix, not a hunt for it.
local function button(id,label,x,y,w,h,fn,enabled,tip,active,color,emphasis)
  enabled = enabled ~= false
  local mx,my = mouse()
  local inClip = not scroll or (y>=UI.BAR+2 and y+h<=H-2)
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
  if inClip then UI.buttons[#UI.buttons+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled,tip=tip,
    active=active or false,color=(active or emphasis) and color or nil} end
end

local function line(y)
  lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.line(M,y,M+CW,y)
end

local function row(label,value,y,color,tip)
  single(label,M,y,"small",P.textDim,142)
  single(value,M+152,y-1,"body",color or P.text,CW-152)
  if tip then
    local mx,my=mouse()
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
  junction="A T split: 3 connections. Upgrade it in place to a hub, a large hub and finally a distribution hub that signs, connects and widens for its neighbourhood. Every main stays tied in. Costs $1/day.",
  manifold="6 connections. Changes pipe size. Carries several goods. Costs $1/day.",
  pump="2 pipe ports. Boosts pressure; reaches 950m, further with each upgrade. Costs $1/day.",
  tower="Reduces nearby leaks by 55%. Range: 220m. Costs $2/day.",
  gate="2 pipe ports. Sets how much supply passes through. Costs $1/day.",
  depot="A tank that stores spare supply and releases it on a short day. Upgrade it to a cistern, a reservoir and a water tower. Costs $3/day.",
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
toolTips.grid="One tower for every voltage: choose it above. It starts with three connections and little capacity; upgrade it for more connections, capacity and reach. A transformer upgrade lets it feed customers."

-- Fewer buildings, each one grown by upgrading it. A junction becomes a hub at
-- level 2, and one tower is built at whichever voltage is chosen above the
-- grid (a transformer is an upgrade, not a building). The older kinds still
-- exist in saved companies; they are simply no longer sold as separate things.
local TOOLS = {"junction","pump","filtration","grid","binder","lab","gate","depot","terminal","dc","stop","station","resort","corner","intersection","roundabout","interchange"}
local function toolKind(name)
  if name=="grid" then return City.INFRA.voltages[state.voltage or "low"].tower end
  return name
end

-- Replacing a structure where it stands. The mains never come off, so this is
-- the difference between buying three more ports and rebuilding a junction box
-- from scratch with every pipe relaid by hand.
-- A manifold is what a junction becomes by levelling up, so it is not offered here.
local REPLACEMENTS = {"junction","pump","tower","gate","depot"}

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

-- What an upgrade earns, in a sentence, or "" when it earns nothing. The
-- flow solver has to be run on a copy to know, so callers only ask for the
-- ones that matter: the one the player is pointing at, or the one that is
-- the only fix for a starved customer.
local function gainText(p)
  if not p or p.error or (p.net or 0)<=0 then return "" end
  return string.format(" Earns about $%d/day, pays back in %s.",math.floor(p.net+0.5),
    p.payback and (p.payback.." day"..(p.payback==1 and "" or "s")) or "no time")
end
-- A price a unit, the way the customer rows already quote it: electricity in
-- kWh, everything else by the unit.
local function perUnit(commodity,v)
  if v==nil then return "-" end
  if commodity=="power" then return City.money2(v/5).." / kWh" end
  return City.money2(v).." / unit"
end

local function marginText(commodity,m)
  if m==nil then return "-" end
  return (m>=0 and "+" or "-")..perUnit(commodity,math.abs(m))
end

-- The price as one bar: the amber part is what a unit costs you, the green
-- part is what you keep. A price below cost shows red where the loss is.
local function marginBar(cost,price,y)
  lg.setColor(P.panelEdge); lg.rectangle("fill",M,y,CW,8,3)
  if not price or price<=0 then return y+14 end
  local top=math.max(price,cost or 0)
  local cw,pw=CW*math.min(1,(cost or 0)/top),CW*price/top
  if cost and cost>price then
    lg.setColor(P.bad); lg.rectangle("fill",M,y,cw,8,3)
    lg.setColor(P.warn); lg.rectangle("fill",M,y,pw,8,3)
  else
    lg.setColor(P.good); lg.rectangle("fill",M,y,pw,8,3)
    lg.setColor(P.warn); lg.rectangle("fill",M,y,cw,8,3)
  end
  return y+14
end

-- What a unit of one trade costs the company and what it sells for, for the
-- source inspector. `n` is the source being looked at, for its own share.
local function economics(commodity,y,n)
  local t=city:tradeCosts(commodity)
  heading("WHAT A UNIT COSTS",y); y=y+28
  row("One more unit",perUnit(commodity,t.marginal),y,P.warn,
    "The pumping cost: what lifting one more unit costs at your cheapest source.")
  y=y+24
  if n then
    local trade=City.trade[n.commodity] or City.trade.water
    local upkeep=(n.upkeep or trade.sourceUpkeep or 0)+((n.level or 1)-1)*2
    local drawn=(city.produced or {})[n.id] or 0
    local rate=n.plant and (n.fuel or trade.fuelPerUnit or 0) or (trade.extractPerUnit or 0)
    row("This source today",drawn>0 and perUnit(commodity,(upkeep+drawn*rate)/drawn) or ("idle, -$"..upkeep.." a day"),y,
      drawn>0 and P.text or P.warn,"Its upkeep of $"..upkeep.." a day plus "..City.money2(rate)..
      " for every unit it lifts, over the units it lifted today. The more it pumps, the cheaper each unit.")
    y=y+24
  end
  row("All "..string.lower(Graph.COMMODITIES[commodity].name).." together",perUnit(commodity,t.perUnit),y,P.warn,
    "Every source, every unit pumped and every main of this trade, over every unit your customers took today.")
  y=y+24
  row("Customers pay",t.price and (perUnit(commodity,t.price).." avg") or "-",y,P.text)
  y=y+24
  row("You keep",marginText(commodity,t.margin),y,t.margin and (t.margin>=0 and P.good or P.bad) or P.textDim,
    "Price minus cost, for every unit sold.")
  y=y+26
  y=marginBar(t.perUnit,t.price,y)
  y=y+paragraph(t.perUnit and "Amber is cost, green is profit. More customers on the same mains make every unit cheaper."
    or "Nothing delivered yet: connect a customer to see the cost of a unit.",y,P.textDim)+10
  return y
end

local function pointing(x,y,w,h)
  local mx,my=mouse()
  return mx>=x and mx<x+w and my>=y and my<y+h
end

-- One building, four levels. Shows what this level gives, what the next one
-- would give, and the button that buys it. When the structure is the thing
-- holding the network back, the button also says what upgrading it earns.
local function levelBlock(n,y)
  if not city:levelFamily(n) then return y end
  local level,count=city:levelOf(n),city:levelCount(n)
  heading("LEVEL "..level.." OF "..count,y); y=y+26
  single(city:levelName(n),M,y,"body",P.accent,CW); y=y+26
  local blurb=city:levelBlurb(n)
  if blurb and not city:isDistribution(n) then y=y+paragraph(blurb,y,P.textDim)+12 end
  local used=city:connectionPorts(n.id)
  row("Connections",used.." / "..n.ports,y,used>=n.ports and P.warn or P.text); y=y+24
  local through=n.throughput or 999
  local carried=math.floor(city.detail.node[n.id] or 0)
  row("Capacity",through>=999 and "Unlimited" or (carried.." / "..through.." a day"),y,
    through<999 and carried>=through and P.bad or P.text,
    "What passes through it in a day against what it is allowed to pass."); y=y+24
  if n.capacityStore and city:levelFamily(n)=="storage" then
    row("Holds",(n.capacityStore).." units, "..(n.fillRate or City.depotFillRate).." in a day",y); y=y+24
  end
  local reach=city:reachBonus(n)
  if reach>0 then row("Reach",string.format("+%d%%",math.floor(reach*100+0.5)),y,P.energy,
    "Added to how far a cable or pipe from here may run."); y=y+24 end
  local nxt=city:levelNext(n.id)
  if not nxt then
    text("Fully upgraded.",M,y+2,"small",P.textDim,CW)
    return y+30
  end
  local err=city:levelError(n.id)
  local full=through<999 and carried>=through
  local mx,my=mouse()
  local hover=mx>=M and mx<M+CW and my>=y+4 and my<y+40
  if hover and nxt.radius then state.previewRadius={x=n.x,y=n.y,r=nxt.radius} end
  local gain
  if full and hover then
    local p=E.levelPreview(city,n.id)
    if not p.error and p.net>0 then
      gain=string.format("Earns about $%+d/day, pays back in %s days.",p.net,p.payback or "many")
    end
  end
  local gives=(nxt.store and "" or (nxt.ports.." connections, "..(nxt.throughput>=999 and "unlimited" or nxt.throughput).." a day"))
    ..(nxt.reach and nxt.reach>0 and string.format(", +%d%% reach",nxt.reach*100+0.5) or "")
    ..(nxt.radius and (", runs everything within "..nxt.radius.." m") or "")
    ..(nxt.store and ("holds "..nxt.store..", takes in "..nxt.fill.." a day") or "")
  button("level-up","Upgrade to "..string.lower(nxt.name).."  $"..nxt.cost,M+0,y+4,CW,36,
    function() act("upgradeLevel",n.id) end,err==nil,
    err and (err..". Level "..nxt.level..": "..gives..".") or ("Level "..nxt.level..": "..gives..". "..(gain or "")),
    false,P.good,full)
  y=y+48
  y=y+paragraph("Next: "..(nxt.blurb or gives)..(err and ("  ("..err..")") or ""),y,err and P.textFaint or P.textDim)+8
  return y
end

local function inspectClient(n,y)
  if n.demands then
    for _,key in ipairs(Graph.ALL) do
      local want=n.demands[key]
      if want then
        row(string.upper(key),city:quantityPair(key,(city.servedBy[n.id] or {})[key] or 0,want),y,Graph.COMMODITIES[key].color)
        y=y+26
      end
    end
  end
  local premium=city:ratePremium(n)
  local margin,cost,rate,guess=city:clientMargin(n)
  local good,bad=margin>=cost,margin<0
  row("Your cost",perUnit(n.commodity,cost),y,P.warn,
    (guess and "Your marginal cost: nothing is delivered yet. " or "")..
    "Every source, every unit pumped and every "..string.lower(n.commodity).." main, over every unit your customers take"..
    (n.prospect and ", counting this customer as signed." or "."))
  row("Rate offered",n.commodity=="power" and string.format("$%.2f / kWh",n.rate/5) or ("$"..n.rate.." / unit"),y+26,good and P.good or bad and P.bad or P.text,
    "Every customer negotiates their own price. The going rate for a "..
    string.lower(City.CLIENTS[n.clientType].name).." is $"..(n.rateBase or n.rate)..
    ". The spread widens as the company grows.")
  if n.secure then
    local exposure=(not n.prospect) and city:exposureOf(n.id)
    local state_=n.prospect and "" or exposure==nil and " (unchecked)" or exposure and " (exposed)" or " (protected)"
    row("Contract","SECURE"..state_,y+52,exposure and P.bad or P.energy,
      "Pays "..math.floor((City.SECURE.rate-1)*100+0.5).."% over the going rate. Every day it is not fully supplied you refund the missing "..
      "units at its rate, and it leaves after "..City.SECURE.patience.." short days. "..
      (n.prospect and "" or exposure==nil and "Run a resilience check in Stats > Advisor to see whether one failure would cut it off. "
        or exposure and "One failure would cut it off: see the Advisor. " or "It survives any single failure. "))
  else
    row("You keep",marginText(n.commodity,margin),y+52,
      bad and P.bad or margin>0 and P.good or P.textDim,
      string.format("Rate minus your cost. This offer is %+.0f%% against the going rate for a %s.",
        premium*100,string.lower(City.CLIENTS[n.clientType].name)))
  end
  local L=City.LOYALTY
  local lv=n.loyalty or 0
  local left=L.every-((n.streak or 0)%L.every)
  row("Income / day","$"..city:contractValue(n)..(lv>0 and ("   loyal +$"..(lv*L.step)) or ""),y+78,P.energy,
    not n.prospect and (lv>=L.max and ("A loyal customer: pays $"..(lv*L.step).." a unit more than it signed for.")
      or ("Supplied in full for "..L.every.." days running, a customer pays $"..L.step.." a unit more, up to "..L.max..
          " times. This one: "..left.." more full "..(left==1 and "day" or "days")..".")) or nil)
  row("Delivery",city:quantityPair(n.commodity,city.served[n.id] or 0,n.demand),y+104)
  marginBar(cost,rate,y+153)
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
    if n.secure then text("Secure contract: pays well, refunds every short day.",M,y+214,"small",P.energy,CW)
    elseif bad then text("Pays less than a unit costs you: every unit loses "..City.money2(-margin)..".",M,y+214,"small",P.bad,CW)
    else text(string.format("%+.0f%% against the going rate.",premium*100),M,y+214,"small",premium>0.10 and P.good or premium<-0.10 and P.warn or P.textDim,CW) end
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
        -- The next size up may exist and simply not be open to this company
        -- yet, which is a different thing from there being nothing wider, and
        -- the button says which. Neither is spelled out in terms of whichever
        -- size happens to be the widest today.
        local _,here=City.sizeOf(e.size or "small")
        local shut=City.PIPE_SIZES[here+1]
        -- The two ends may refuse a wider main however much the company knows
        -- how to lay: a customer takes a small main and nothing else. That is
        -- a different answer from the company not having reached the size yet.
        local _,hi=city:sizeRange(e.a,e.b)
        local capped=shut and hi and here+1>hi
        button("widen-bottleneck",
          bigger and ("Put a "..string.lower(City.sizeOf(bigger).name).." main in   $"..bore)
            or capped and "A customer's main is as wide as it goes"
            or (shut and (City.sizeOf(shut.key).name:sub(1,1)..string.lower(shut.name:sub(2)))
                .." mains are not open yet"
              or "That main is already the largest there is"),
          M,dy+52,CW,36,
          function() act("replacePipe",eid,bigger,e.grade) end,
          bigger~=nil and city.money>=bore,
          bigger and ("Digs out the "..string.lower(City.sizeOf(e.size or "small").name)..
            " main holding this customer back and lays a "..string.lower(City.sizeOf(bigger).name)..
            " one carrying "..City.sizeOf(bigger).cap..". Nothing widens a main in the ground."..
            gainText(bigger and E.replacePreview(city,eid,bigger,e.grade)))
            or capped and ("A "..string.lower(City.PIPE_SIZES[hi].name)..
              " main is the most either end of this one will take. Put a junction in the run and feed them from it.")
            or (shut and city:sizeGate(shut))
            or ("Nothing carries more than a "..string.lower(City.PIPE_SIZES[#City.PIPE_SIZES].name).." main."),
          false,P.good,true)
        button("inspect-bottleneck","Inspect that main",M,dy+94,CW,30,
          function() act("focusEdge",eid) end,true,"Select the main and centre on it")
      elseif why=="repair" then
        local e=city.g.edges[eid]
        local cost=city:repairCost(e)
        text("The main feeding them is damaged and carrying "..
          (e.cap==0 and "nothing" or (e.cap.." of "..(e.capMax or e.cap)))..".",M,dy,"body",P.bad,CW)
        button("repair-bottleneck","Repair that main   $"..cost,M,dy+52,CW,36,
          function() act("repairPipe",eid) end,city.money>=cost,
          "Stops the leak and restores the full capacity of the main this customer is fed through.",
          false,P.bad,true)
        button("inspect-bottleneck","Inspect that main",M,dy+94,CW,30,
          function() act("focusEdge",eid) end,true,"Select the main and centre on it")
      elseif why=="output" then
        text("Needs more "..n.commodity..". Upgrade or add a source.",
          M,dy,"small",P.warn,CW)
        local src
        for _,w in ipairs(city.g:nodesOfKind("source")) do
          if w.commodity==n.commodity and (w.level or 1)<city:maxLevel(w)
             and city:sourceUpgradeCost(w) then src=w; break end
        end
        if src then
          local cost=city:sourceUpgradeCost(src)
          button("deepen-for-client","Extend "..string.upper(n.commodity).." source "..src.id.."   $"..cost,
            M,dy+52,CW,36,function() act("upgradeSource",src.id) end,city.money>=cost,
            "Adds output at the well, with no new route to pay for."..gainText(E.sourcePreview(city,src.id)),false,P.good,true)
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
  row("Capacity",city:quantityPair(n.commodity,drawn,capacity),y,
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
    row((spec.unitName or "unit").."s",level.." / "..city:maxLevel(n),y+142,P.energy,
      "A station takes further units on the one site. That is always cheaper "..
      "per unit than commissioning a second station somewhere else.")
    row("Fuel",(n.fuel or 0)>0 and ("-$"..string.format("%.2f",n.fuel).." / unit made")
      or "none at all",y+168,(n.fuel or 0)>0 and P.warn or P.good,
      "Reactors use fuel. Wind parks do not.")
    y=y+26
  else
    -- The ground's own ceiling, which no amount of money moves. It is the reason
    -- the map has to keep going: more supply means further out.
    row(n.intake=="river" and "This channel gives"
      or n.intake and "The works can lift"
      or "This ground gives",ceiling.." / day",y+116,
      capacity>=ceiling and P.warn or P.textDim,
      n.intake=="river" and "The river's width here sets the ceiling. A wider reach gives more."
      or n.intake and "A sea intake is limited by the treatment works, not the water."
      or "Maximum supply from this spot. Distant deposits give more.")
    local names=City.LEVELS.WELL_NAMES
    row(n.intake and "Treatment stages" or "Well",
      n.intake and ("level "..level.." / "..city:maxLevel(n))
        or ((names[level] or "Well").."  "..level.."/"..city:maxLevel(n)),y+142,P.accent,
      not n.intake and ("Hand well, well, deep well, borehole, deep borehole, aquifer station: each one is this well deepened.") or nil)
  end
  row(n.plant and "Fuel a unit" or "Pumping cost",perUnit(n.commodity,n.plant and (n.fuel or trade.fuelPerUnit or 0) or (trade.extractPerUnit or 0)),y+168,P.warn,
    "Paid for every unit this source lifts. Customers are your only income.")
  row("Upkeep","-$"..((n.upkeep or trade.sourceUpkeep)+(level-1)*2).." / day",y+194,P.warn)
  row("Connections",city:connectionPorts(n.id).." / "..n.ports,y+220)
  local step,unit=city:upgradeStep(n)
  local upCost=city:sourceUpgradeCost(n)
  if upCost and level<city:maxLevel(n) and capacity<ceiling then
    local verb=n.plant and ("Add a "..unit) or n.intake and "Add a stage"
      or ("To "..string.lower(City.LEVELS.WELL_NAMES[level+1] or "deeper"))
    button("upgrade-source",verb.."   +"..step.." output   $"..upCost,
      M,y+258,CW,38,function() act("upgradeSource",n.id) end,city.money>=upCost,
      "Adds "..step.." supply per day. Keeps existing pipes, needs no new route."..
      (maxed and gainText(E.sourcePreview(city,n.id)) or ""),
      false,P.good,maxed and city.money>=upCost)
    -- The comparison that decides the shape of the whole network: another unit
    -- here, against another source somewhere else that needs its own mains.
    text("A second "..(n.plant and ((City.PLANTS[n.plant] or {}).name or "station"):lower()
         or n.commodity.." source").." costs $"..city:sourceCost(n.commodity,nil,nil,n.plant)..
         " plus the route to reach it.",M,y+304,"small",P.textDim,CW)
    y=y+336
  else
    local description=capacity>=ceiling
        and ("Limit: "..ceiling.." per day. Build another source for more.")
      or n.plant and ((City.PLANTS[n.plant] or {}).blurb or "")
      or "Fully upgraded. Build another source for more supply."
    local _,lines=R.fonts.body:getWrap(description,CW)
    text(description,M,y+262,"body",P.textDim,CW)
    y=y+262+#lines*R.fonts.body:getHeight()*R.fonts.body:getLineHeight()+14
  end
  if n.seam then
    text("Rich deposit. Gives extra supply.",M,y,"small",P.energy,CW)
    y=y+24
  end
  y=economics(n.commodity,y+6,n)
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
  row("Holding",city:quantityPair(com,n.stored or 0,n.capacityStore or City.depotCapacity),y,
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
  text("Stores up to "..(n.fillRate or City.depotFillRate).." spare units per day. Releases them when needed.",
       M,y+128,"small",P.textDim,CW)
  button("load-depot","Load "..S.get(com).." from inventory",M,y+158,CW,28,function() act("loadDepot",n.id) end,(city.stock[com] or 0)>0 and (n.stored or 0)<(n.capacityStore or City.depotCapacity),"Move harvested goods into this depot for transport")
  local tail=levelBlock(n,y+198)+8
  tail=replaceStrip(n,tail)
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
  row("Makes",city:quantityPair(recipe.makes,n.ready or 0,recipe.rate),y,
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
      row(S.get(name),city:quantityPair(name,have,want),ly,have>=want and P.good or P.warn,
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

-- The top of the fitting ladder. One number to set, and everything it did.
local function inspectDistribution(n,y)
  local D=City.DISTRIBUTION
  heading("DISTRIBUTION",y); y=y+26
  y=y+paragraph("Every day it signs offers, connects customers and widens full mains within "..city:hubRadius(n)..
    " m, for anyone paying at least your minimum price. You pay the normal price for everything it builds.",y,P.textDim)+14
  local floor=city:hubFloor(n)
  row("Minimum a unit","$"..floor,y,P.energy,
    "Customers who pay less are left for you to decide by hand. Every customer shows what a unit costs you to deliver.")
  button("hub-floor-down","-",M+CW-80,y-4,36,30,function() act("setHubFloor",n.id,floor-D.floorStep) end,
    floor>0,"Take cheaper customers too")
  button("hub-floor-up","+",M+CW-38,y-4,36,30,function() act("setHubFloor",n.id,floor+D.floorStep) end,
    true,"Only take better payers")
  y=y+34
  local trades=city:hubTrades(n)
  local names={}
  for _,key in ipairs(Graph.TRADES) do if trades[key] then names[#names+1]=string.lower(key) end end
  row("Hands out",#names>0 and table.concat(names,", ") or "nothing yet",y,#names>0 and P.good or P.warn,
    "The trades that reach this hub over a main. Connect a supply main to it first."); y=y+26
  local paying,cheap,offers,short=0,0,0,0
  for _,c in ipairs(city:hubClients(n)) do
    if trades[c.commodity] then
      if (c.rate or 0)>=floor then
        if c.prospect then offers=offers+1 else paying=paying+1 end
        if not c.prospect and not city:fullyServed(c) then short=short+1 end
      else cheap=cheap+1 end
    end
  end
  row("Customers it runs",paying,y,paying>0 and P.good or P.textDim); y=y+24
  if offers>0 then row("Offers it will sign",offers,y,P.energy,"Signed at the next close."); y=y+24 end
  if short>0 then row("Still short",short,y,P.warn,"It widens up to "..D.perDay.." mains a day, while there is cash for them."); y=y+24 end
  if cheap>0 then row("Below your minimum",cheap,y,P.textDim,"Left for you. Lower the minimum to take them on."); y=y+24 end
  row("Running cost","-$"..D.upkeep.." / day",y,P.warn); y=y+26
  local last=n.lastRun
  if last and (last.signed+last.wired+last.widened+(last.repaired or 0))>0 then
    y=y+paragraph(string.format("Last run: %d signed, %d connected, %d widened for $%d.",
      last.signed,last.wired,last.widened,last.spent),y,P.textDim)+4
  end
  if #names==0 then y=y+paragraph("Connect a supply main to this hub.",y,P.warn)+4 end
  return y+6
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
    ly=ly+paragraph("Nothing has moved yet: run track inland to draw on it.",ly,P.warn)+6
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
    row("Leak risk","None",y+130,P.good,"Freight lines do not corrode: there is nothing in the ground to leak.")
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
  row("Flow / capacity",city:quantityPair(e.commodity,math.abs(city.detail.edge[e.id] or 0),e.effectiveCap or e.cap),y+26)
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
  -- Capacity and price on one face needs the width of a tile, so these go
  -- three to a row like the structures rather than five across the panel.
  for i,spec in ipairs(City.PIPE_SIZES) do
    local target=math.min(city.lining or 1,math.max(e.grade or 1,state.grade or 1))
    local q=city:replaceQuote(e.id,spec.key,target)
    local same=spec.key==(e.size or "") and target==(e.grade or 1)
    local open=city:sizeAllowed(spec)
    local bx,by=M+((i-1)%3)*102,ry+math.floor((i-1)/3)*38
    local gain=(open and not same and q~=nil and pointing(bx,by,TILE_W,32))
      and gainText(E.replacePreview(city,e.id,spec.key,target)) or ""
    button("replace-"..spec.key,(e.commodity=="power" and (City.INFRA.amps[spec.key].." A") or (spec.cap..S.get(e.commodity))).." $"..(q and q.net or 0),bx,by,TILE_W,32,
      function() act("replacePipe",e.id,spec.key,target) end,
      open and not same and q~=nil and city.money>=(q and q.net or 0),
      same and "This is already what is in the ground."
        or not open and ("Massive mains: "..string.lower(city:unlockHint(spec.unlock))..".")
        or ("A "..string.lower(spec.name).." "..string.lower(City.GRADES[target].name)..
            " main carrying "..spec.cap..". $"..(q and q.total or 0).." of work, less $"..
            (q and q.salvage or 0).." of scrap on the one that comes out."..gain),
      false,Graph.COMMODITIES[e.commodity].color)
  end
  ry=ry+math.ceil(#City.PIPE_SIZES/3)*38+4
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
      or ("The next trade to take on. The "..name.." licence is $"..
          City.price[name.."Licence"].." in Company, and then "..
          select(2,E.tradeEntry(city,name)).."."),
      not state.people and state.commodity==name,spec.color)
  end
  local pi=#trades
  do
    button("people",S.get("roads"),M+(pi%4)*76,y+math.floor(pi/4)*40,72,36,
      function() selectService("people") end,city:unlocked("roads"),
      "Roads carry people and commodities. Available once people settle here.",state.people,P.energy)
    pi=pi+1
  end
  y=y+math.ceil(pi/4)*40+2
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
      text("span  /  booster",M+152,y,"tiny",P.textFaint,CW-152)
      y=y+16
      for i=#City.INFRA.voltageOrder,1,-1 do
        local spec=V[City.INFRA.voltageOrder[i]]
        row(spec.kv.." kV  "..({hvtower="HV tower",pylon="tower",pole="pole"})[spec.tower],
          spec.span.." m  /  "..spec.boost.." m",y,P.accent,
          "A tower every "..spec.span.." m, and a booster, transformer or generator every "..spec.boost.." m.")
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
    -- The ladder has five rungs, so the row is pitched to hold five. At the
    -- old four-wide pitch the widest main was drawn past the sidebar and its
    -- button took clicks meant for the map.
    local pitch=math.floor((CW+4)/#City.PIPE_SIZES)
    for i,spec in ipairs(City.PIPE_SIZES) do
      local bx=M+(i-1)*pitch
      local open=city:sizeAllowed(spec)
      if not open and state.size==spec.key then state.size="large" end
      button("size-"..spec.key,(state.commodity=="power" and (City.INFRA.amps[spec.key].." A") or (spec.cap.." "..S.get(state.commodity))),bx,y,pitch-4,30,function() state.size=spec.key; E.useSize(state,spec.key) end,open,
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
    button("supply-detail",city:quantityPair(state.commodity,drawn,capacity).."    "..S.get("crews").." "..(city.crews or 0).."/"..City.crewMax,M,y,CW,30,function() state.showSupply=not state.showSupply end,true,"Expand supply totals for every utility",state.showSupply)
    y=y+38
    if state.showSupply then
      for _,name in ipairs(Graph.TRADES) do
        if city.licences[name] then
          local used,total=city:supplyFor(name)
          row(S.get(name),city:quantityPair(name,used,total),y,Graph.COMMODITIES[name].color); y=y+26
        end
      end
    end
  end
  if not state.people and state.commodity=="power" then
    heading("TOWER VOLTAGE",y); y=y+24
    for i,key in ipairs(City.INFRA.voltageOrder) do
      local v=City.INFRA.voltages[key]
      button("voltage-"..key,(v.name:gsub(" voltage","")),M+(i-1)*102,y,96,30,
        function() state.voltage=key end,true,
        v.name.." ("..v.kv.." kV): a tower every "..v.span.." m, a booster every "..v.boost..
        " m. Carries "..(key=="high" and "generator output across the map." or key=="medium" and "power to workshops and works." or "power to homes."),
        (state.voltage or "low")==key,City.INFRA.voltages[key] and Graph.KINDS[v.tower].color)
    end
    y=y+42
  end
  heading(state.people and "PASSENGER BUILDINGS" or "EVERYDAY STRUCTURES",y); y=y+24
  -- Every building the company has unlocked is on the panel. Hiding half of
  -- them behind a toggle only made the player press the toggle.
  local advanced=true
  -- Which tools exist yet. The first three are always there; the rest arrive
  -- when the company is the size where they are the obvious next move.
  local gate={tower="everyday",gate="everyday",depot="everyday",
              terminal="haven",dc="yard",
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
    elseif name=="grid" then
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
    if relevant and (i<=4 or name=="grid" or state.people or advanced)
      and (not City.BUILD_UNLOCK[name] or city:unlocked(City.BUILD_UNLOCK[name]))
      and (not gate[name] or city:unlocked(gate[name])) then
      local col,rw=shown%3,math.floor(shown/3)
      shown=shown+1
      local bx,by=M+col*102,y+rw*58
      local kind=toolKind(name)
      local afford=city.money>=City.price[kind]
      button("tool-"..name,"",bx,by,TILE_W,TILE_H,function() state.tool=state.tool==name and nil or name end,
        afford,toolTips[name],state.tool==name,Graph.KINDS[kind].color)
      -- The name owns the top of the tile, so it is never broken in the
      -- middle of a word; the glyph and the price share the line beneath it.
      text(({junction="Junction",grid="Tower",pump="Pump",filtration="Filter",binder="Binder",lab="Env. lab",tower="Treat",gate="Valve",depot="Tank",terminal="Haven",dc="Yard",
             stop="Bus stop",station="Station",resort="Resort",corner="Corner",intersection="Crossing",roundabout="Roundabout",interchange="Interchange"})[name],
        bx+4,by+5,"tiny",P.text,TILE_TEXT,"center")
      lg.setColor(afford and Graph.KINDS[kind].color or P.textFaint)
      Draw.structureGlyph(kind,bx+20,by+32)
      text("$"..City.price[kind],bx+34,by+26,"small",P.textDim,TILE_W-42,"center")
    end
  end
  -- The sea pump and the purifier are structures like any other, so they are
  -- built from the same grid. Their marks are the water they handle: brine
  -- from the sea, and the same drop with the sparkle of having been cleaned.
  if not state.people and (state.commodity=="water" or state.commodity=="saltwater") and city:unlocked("seawater") then
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
      button(spec.id,"",bx,by,TILE_W,TILE_H,spec.press,afford,spec.tip,spec.active,spec.colour)
      text(spec.name,bx+4,by+5,"tiny",P.text,TILE_TEXT,"center")
      lg.setColor(afford and spec.colour or P.textFaint)
      SF.mark(spec.mark,bx+20,by+32,11)
      text("$"..spec.price,bx+34,by+26,"small",P.textDim,TILE_W-42,"center")
    end
  end
  y=y+math.ceil(math.max(shown,1)/3)*58+10
  -- What is not here yet, and what brings it.
  if advanced and not state.people and state.buildHelp then
    for _,key in ipairs({"seawater","haven","yard"}) do
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
    state.scroll=0; state.drawer=true
  end,true,"Clear the selection and return to the structures (Escape)")
  y=y+42
  local tail
  if n then
    local title=n.kind=="client" and E.clientName(city,n)
      -- A well is called a well, and an electricity well is called a station.
      or (n.kind=="works" and (((City.RECIPES[n.recipe or ""] or {}).name or "WORKS").." "..n.id))
      or (n.kind=="source" and ((n.plant and (City.PLANTS[n.plant] or {}).name
          or (string.upper(n.commodity).." WELL")).." "..n.id))
      or (city:levelFamily(n) and city:levelFamily(n)~="tower" and (string.upper(city:levelName(n)).." "..n.id))
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
      tail=levelBlock(n,tail)
      tail=demolishBlock(n,tail)
    elseif n.kind=="client" then inspectClient(n,y); tail=y+400
    elseif n.kind=="source" then tail=inspectSource(n,y)
    elseif n.kind=="gate" then tail=inspectGate(n,y)
    elseif n.kind=="depot" then tail=inspectDepot(n,y)
    elseif n.kind=="terminal" then tail=inspectTerminal(n,y)
    elseif n.kind=="works" then tail=inspectWorks(n,y)
    elseif n.kind=="stop" then tail=inspectStop(n,y)
    elseif n.kind=="station" then tail=inspectStation(n,y)
    elseif n.kind=="resort" then tail=inspectResort(n,y)
    else
      local degree=city.g:degree(n.id)
      -- A building on a ladder shows its connections in its level block.
      if city:levelFamily(n) then
        row("Carrying",math.floor(city.detail.node[n.id] or 0).." a day",y)
      else
        row("Ports",degree.." / "..n.ports,y,degree>=n.ports and P.warn or P.text)
        row("Carrying",math.floor(city.detail.node[n.id] or 0),y+26)
      end
      if n.kind=="tower" then row("Local leak risk","-55% within 220m",y+52,P.energy)
      elseif n.kind=="pump" then row("Reach",math.floor(City.INFRA.pumpRange*(1+city:reachBonus(n))).." m",y+52,P.flow) end
      if n.capped then
        text("Closed well. Its pipes stay connected.",
          M,y+80,"small",P.textDim,CW)
      end
      tail=y+(n.capped and 128 or 84)
      if city:isDistribution(n) then tail=inspectDistribution(n,tail) end
      if city:levelFamily(n) then tail=levelBlock(n,tail)+8 end
      tail=replaceStrip(n,tail)
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
    state.scroll=0; state.drawer=true
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
  row("Length",l.mode=="bus" and (busLength and (math.floor(busLength).." m") or "No road connection")
    or (math.floor(city:nodeDistance(l.a,l.b)).." m"),y+26,nil,
    l.mode=="bus" and "Measured along the roads these buses share with cars." or nil)
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

-- A section of a menu that opens when it is wanted. Only what is looked at
-- every day starts open; the rest is one line saying what is inside.
local function fold(key,title,y,summary,default)
  state.folds=state.folds or {}
  local open=state.foldAll or state.folds[key]
  if open==nil then open=default or false end
  button("fold-"..key,"",M,y,CW,38,function() state.folds[key]=not open end,true,nil,open)
  local label=(open and "\u{25BE}  " or "\u{25B8}  ")..title
  local tw=math.min(CW-24,SF.width(label,R.fonts.body))
  single(label,M+12,y+10,"body",open and P.flow or P.text,tw)
  local room=CW-24-tw-12
  if summary and summary~="" and room>40 then single(summary,M+CW-12-room,y+12,"small",P.textDim,room,"right") end
  return y+(open and 50 or 46),open
end

local function company()
  local y=TOP-state.scroll
  single(E.companyName(city),M,y+4,"mid",P.text,CW-100)
  button("rename-company",state.rename and "Save" or "Rename",M+CW-88,y,88,30,function()
    if state.rename then
      if act("setCompanyName",state.rename) then state.rename=nil; state.renameSelectAll=nil end
    else state.rename=E.companyName(city); state.renameSelectAll=true end
  end,true,"Type to replace the name; Enter saves, Escape cancels")
  if state.rename then
    single(state.rename.."|",M,y+36,"small",P.energy,CW)
    y=y+24
  end
  y=y+46

  -- Money: the one section open by default.
  local b=city:expenseBreakdown()
  local open
  y,open=fold("money","Money",y,string.format("$%+d a day",city:dailyRevenue()-b.total),true)
  if open then
    row("Income / day","+$"..city:dailyRevenue(),y,P.good)
    row("Costs / day","-$"..b.total,y+26,P.warn)
    row("Profit / day",string.format("$%+d",city:dailyRevenue()-b.total),y+52,P.energy)
    y=y+86
    -- Each trade's unit cost against its price, so the margin behind the
    -- profit line is never a guess.
    for _,name in ipairs(Graph.TRADES) do
      if city.licences[name] then
        local t=city:tradeCosts(name)
        if t.perUnit or t.price then
          row(string.upper(name),t.perUnit and ("cost "..City.money2(t.perUnit).."  sells "..City.money2(t.price))
            or "nothing delivered yet",y,
            t.margin and (t.margin>=0 and P.good or P.bad) or P.textDim,
            "What a unit costs you (sources, pumping and mains, over units delivered) and what customers pay for it on average."..
            (t.margin and (" You keep "..City.money2(t.margin).." a unit.") or ""))
          y=t.perUnit and marginBar(t.perUnit,t.price,y+24)+6 or y+28
        end
      end
    end
    y=y+10
  end

  -- Trades: one at a time. The next licence is the only one offered, so the
  -- player is choosing when rather than which.
  local offer,held={},{}
  for _,name in ipairs(City.LICENCE_ORDER) do
    if city.licences[name] then offer[#offer+1]=name; held[#held+1]=name end
  end
  local nextUp=city:nextLicence()
  if nextUp then offer[#offer+1]=nextUp end
  y,open=fold("trades","Trades",y,nextUp and ("next: "..nextUp) or (#held.." held"))
  if open then
    for _,name in ipairs(offer) do
      local cost=City.price[name.."Licence"]
      local has=city.licences[name]
      local entry,how=E.tradeEntry(city,name)
      button("licence-"..name,has and (string.upper(name).." licence held") or (string.upper(name).." licence   $"..cost),
        M,y,CW,34,function() act("buyLicence",name) end,not has and city.money>=cost,
        has and "Licence owned." or ("Allows "..name.." supply: "..how.."."),false,
        Graph.COMMODITIES[name].color)
      drop(name,M+16,y+17,8)
      y=y+38
      if not has then
        y=y+paragraph("Then about $"..entry.." more before the first customer: "..how..".",y,P.textDim)+8
      end
    end
    y=y+8
  end

  -- Staff and growth.
  local crews=city.crews or 0
  local staff=crews
  for _,key in ipairs(City.ORDER_LIST) do staff=staff+city:workerCount(key) end
  y,open=fold("staff","Staff and growth",y,staff>0 and (staff.." on the payroll") or "")
  if open then
    button("ads",city.adDaysLeft>0 and ("Advertising: "..city.adDaysLeft.." days left") or "Advertising campaign   $90",
      M,y,CW,34,function() act("buyAds") end,city.money>=90 and city.adDaysLeft==0,
      "Five days of increased enquiries")
    local nextGrade=City.GRADES[(city.lining or 1)+1]
    button("quality",nextGrade and ("Unlock "..nextGrade.name.." pipes  $"..city:qualityCost()) or "All pipe types unlocked",
      M,y+41,CW,34,function() act("upgradeQuality") end,nextGrade~=nil and city.money>=city:qualityCost(),
      "Unlocks better leak protection. Choose it in Pipe options. Existing pipes keep their old lining.")
    button("hire-crew",S.get("crews").." "..crews.."/"..City.crewMax..(crews>=City.crewMax and "" or ("  + $"..City.crewHire)),
      M,y+82,206,34,function() act("hireCrew") end,crews<City.crewMax and city.money>=City.crewHire,
      "$"..City.crewWage.." per day. Fixes one damaged pipe each day. Repairs cost extra.")
    button("fire-crew","Stand down",M+214,y+82,86,34,function() act("dismissCrew") end,crews>0,
      "Remove one crew from the payroll")
    y=y+124
    for _,key in ipairs(City.ORDER_LIST) do
      local spec=City.ORDERS[key]
      local count=city:workerCount(key)
      local has=count>0
      local can=city:orderAvailable(key)
      button("order-"..key,S.get(key).." "..count.."  + $"..spec.hire,M,y,CW-92,32,
        function() act("hireOrder",key) end,
        can and city.money>=spec.hire and count<(key=="analysts" and math.huge or 4),
        spec.name..": "..spec.blurb.."  $"..spec.wage.." a day."..
        (can and "" or ("  Available at "..spec.clients.." customers.")),
        has,has and P.good or P.energy)
      if has then
        button("order-stop-"..key,"Stop",M+CW-86,y,86,32,function() act("dismissOrder",key) end,
          true,"Take "..string.lower(spec.name).." off the payroll")
      end
      y=y+38
    end
    y=y+8
  end

  -- Investing and credit. The fixed rate is the point: the fund is a gamble,
  -- the bank is not.
  local invested=city:investedTotal()
  y,open=fold("capital","Invest and borrow",y,
    (city.loan or 0)>0 and ("loan $"..city.loan) or invested>0 and ("$"..invested.." invested") or "")
  if open then
    button("invest-minus","-",M,y,34,34,function() state.invest=math.max(50,state.invest-50) end,true,"Less")
    button("invest","Invest $"..state.invest,M+41,y,218,34,function() act("invest",state.invest) end,
      city.money>=state.invest,"Locks cash for 7 days. The mean and spread shown below include your analysts. You can lose the invested money.")
    button("invest-plus","+",M+266,y,34,34,function() state.invest=state.invest+50 end,true,"More")
    local mean,sd=city:investmentDistribution()
    row("7-day mean / spread",string.format("%.0f%% / %.0f%%",mean*100,sd*100),y+40,P.energy)
    y=y+68
    for _,inv in ipairs(city.investments) do
      row("$"..inv.amount.." on deposit",city:daysToMaturity(inv).." days left",y,P.energy); y=y+24
    end
    local limit,avail=city:loanLimit(),city:loanAvailable()
    row("Credit line","$"..(city.loan or 0).." / $"..limit,y+6,
      (city.loan or 0)>0 and P.warn or P.textDim,
      "Borrow up to half your assets. Interest: 10% per week, paid daily.")
    y=y+32
    if (city.loan or 0)>0 then row("Daily interest","-$"..city:loanInterest(),y,P.bad); y=y+26 end
    -- The amount is clamped to what the bank will actually lend, so the
    -- button never sits dead just because the dial is above the limit.
    local want=math.min(state.borrow or 500,avail)
    button("borrow-minus","-",M,y,34,34,function() state.borrow=math.max(100,(state.borrow or 500)-100) end,true,"Less")
    button("borrow","Borrow $"..want,M+41,y,218,34,function() act("borrow",want) end,
      avail>0,"Interest: 10% per week, paid daily. You can borrow $"..avail.." more.")
    button("borrow-plus","+",M+266,y,34,34,function() state.borrow=(state.borrow or 500)+100 end,true,"More")
    button("repay",(city.loan or 0)>0 and ("Repay $"..math.min(city.loan,city.money)) or "Nothing outstanding",
      M,y+40,CW,32,function() act("repay",math.min(city.loan,city.money)) end,
      (city.loan or 0)>0 and city.money>0,"Pays down as much of the balance as the till allows")
    y=y+84
  end

  -- Land permits.
  local owned=0
  for _,kind in ipairs(City.PERMIT_ORDER) do if city.permits[kind] then owned=owned+1 end end
  y,open=fold("permits","Land permits",y,owned.." of "..#City.PERMIT_ORDER)
  if open then
    text("Build on trees, rock or water.",M,y,"small",P.textDim,CW); y=y+24
    for _,kind in ipairs(City.PERMIT_ORDER) do
      local spec=City.PERMITS[kind]
      local has=city.permits[kind]
      button("permit-"..kind,(has and "Owned: " or "Buy: ")..({park="Trees",river="Water",bedrock="Rock"})[kind]..(has and "" or ("  $"..spec.cost)),
        M,y,CW,32,function() act("buyPermit",kind) end,not has and city.money>=spec.cost,
        "Allows building here. Crossing cost: x"..spec.cross..".")
      y=y+40
    end
    y=y+6
  end

  -- What the yards hold, once there are yards. Materials are the second
  -- currency and the player needs to see the balance.
  local rows,any={},false
  for _,name in ipairs(Graph.ALL) do
    local role=Graph.COMMODITIES[name].role
    if role=="material" or role=="vehicle" then
      local units=city:materialStock(name)
      rows[#rows+1]={name,units}
      if units>0 then any=true end
    end
  end
  if #city.g:nodesOfKind("dc")>0 or any then
    y,open=fold("yards","Yards",y,"")
    if open then
      for _,pair in ipairs(rows) do
        local taken=((city.detail or {}).yard or {})[pair[1]] or 0
        row(string.upper(pair[1]),pair[2]..(taken>0 and ("   +"..taken.." today") or ""),y,
          pair[2]>0 and Graph.COMMODITIES[pair[1]].color or P.textFaint,
          "Materials are taken in at the depot yards and spent on building. "..
          "Each yard holds "..City.yardStock.." and takes "..City.yardIntakeRate.." a day.")
        y=y+24
      end
      y=y+10
    end
  end
  UI.contentBottom=y+state.scroll+24
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
      local tag = c.secure and "SECURE CONTRACT"
        or premium>0.12 and string.format("PREMIUM %+.0f%%",premium*100)
        or premium<-0.12 and string.format("LOWBALL %+.0f%%",premium*100)
        or (c.commodity=="power" and string.format("$%.2f/kWh",c.rate/5) or string.format("$%d/unit",c.rate))
      if prospect then status="Expires in "..math.max(0,c.expires-city.day+1).." days" end
      single((c.demands and c.demands.water and c.demands.power and ("Water + "..city:quantity("power",c.demands.power)) or city:quantity(c.commodity,c.demand)).." / "..status,M+12,y+35,"small",
        prospect and P.energy or met and P.good or P.warn,CW-16)
      lg.setFont(R.fonts.small)
      lg.setColor(c.secure and P.energy or premium>0.12 and P.good or premium<-0.12 and P.bad or P.textDim)
      lg.printf(tag,M+12,y+57,CW-24,"left")
      -- What each unit leaves after its cost, on the right of the same line.
      local margin=city:clientMargin(c)
      local shown=c.commodity=="power" and 5 or 1
      single("keep "..(margin>=0 and "+" or "-")..City.money2(math.abs(margin)/shown),M+CW-120,y+57,"small",
        margin<0 and P.bad or P.good,108,"right")
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
      y=y+30
      local kind,colour,words=Draw.landStatus(city,d)
      single(((d.island and "ISLAND") or (d.spec and d.spec.label) or "TOWN").."  ·  "..words,M,y,"small",colour,CW)
      y=y+22
      if d.spec and d.spec.story then
        text(d.spec.story,M,y,"small",P.textDim,CW)
        local _,wrapped=R.fonts.small:getWrap(d.spec.story,CW)
        y=y+#wrapped*R.fonts.small:getHeight()+8
      end
      local f=Draw.landContents(city,d)
      local parts={}
      if f.surveyed then
        for _,name in ipairs(Graph.TRADES) do if f.deposits[name] then parts[#parts+1]=f.deposits[name].." "..name end end
        if #parts==0 then parts[1]="no deposits" end
      elseif not d.island then parts[1]="deposits unsurveyed" end
      if f.woods>0 then parts[#parts+1]=f.woods..(f.woods>1 and " woods" or " wood") end
      if f.ranges>0 then parts[#parts+1]=f.ranges..(f.ranges>1 and " ranges" or " range") end
      if #parts>0 then text(table.concat(parts,", "),M,y,"small",P.text,CW); y=y+26 end
      y=y+6
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
  else
    -- Nothing picked yet: what the colours on the map mean, and the plots
    -- that can be bought, cheapest first, one click from their deed.
    text("Click a plot on the map, or pick one below.",M,y,"body",P.textDim,CW); y=y+44
    for _,k in ipairs({{P.good,"Green: buy it now"},{P.warn,"Amber: next door, needs more cash"},{P.textFaint,"Grey: not next to your land yet"}}) do
      lg.setColor(k[1]); lg.rectangle("fill",M,y+4,14,14,3)
      text(k[2],M+22,y+2,"small",P.textDim,CW-22); y=y+22
    end
    y=y+12
    local near={}
    for _,pl in ipairs(city.districts) do
      if not pl.owned and city:districtVisible(pl) then
        local err=city:districtError(pl.id)
        if not err or err=="not enough cash" then near[#near+1]=pl end
      end
    end
    table.sort(near,function(a,b) return city:districtCost(a)<city:districtCost(b) end)
    if #near>0 then
      text("NEXT DOOR",M,y,"tiny",P.textFaint,CW); y=y+20
      for i,pl in ipairs(near) do
        if i>8 then break end
        local short=city:districtError(pl.id)
        local tag=pl.island and "island" or string.lower((pl.spec and pl.spec.label) or "town")
        button("near-"..pl.id,pl.name.."  ("..tag..")  $"..city:districtCost(pl),M,y,CW,30,
          function() act("focusDistrict",pl.id) end,true,short and "Needs more cash" or "Show its deed",nil,short and P.warn or P.good)
        y=y+36
      end
      y=y+8
    end
  end
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
  if city.shock then
    heading("SUPPLY SHOCK",y)
    lg.setColor(P.with(P.bad,0.14)); lg.rectangle("fill",M,y+24,CW,46,4)
    lg.setColor(P.with(P.bad,0.5)); lg.rectangle("line",M,y+24,CW,46,4)
    text(city.shock.head,M+10,y+31,"small",P.text,CW-20)
    text(string.format("%s output x%.2f  /  %d day%s left",string.upper(city.shock.commodity),
      city.shock.output,city.shock.left,city.shock.left==1 and "" or "s"),M+10,y+53,"tiny",P.bad)
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

-- The two questions a maturing network asks: what is the one thing that could
-- hurt most, and what is the best thing to spend on next. Both are answered by
-- running the flow solver on a copy, and neither changes the company.
local function adviceLabel(item)
  if item.kind=="pipe" then
    return "Widen "..string.lower(city:describeElement("edge",item.id)).." to "..item.size
  elseif item.kind=="source" then
    local n=city.g.nodes[item.id]
    return "Extend "..string.lower(n.commodity).." source "..item.id
  end
  local n=city.g.nodes[item.id]
  local nxt=city:levelNext(item.id)
  return "Upgrade "..string.lower(Graph.KINDS[n.kind].name).." "..item.id.." to "..string.lower(nxt and nxt.name or "the next level")
end

local function advisor()
  local y=TOP-state.scroll
  state.advisorFocus=nil
  button("stats-back","Back to stats",M,y,CW,30,function() state.tab="stats"; state.scroll=0; state.spof=nil end)
  y=y+46

  if city.shock then
    lg.setColor(P.with(P.bad,0.14)); lg.rectangle("fill",M,y,CW,46,4)
    lg.setColor(P.with(P.bad,0.5)); lg.rectangle("line",M,y,CW,46,4)
    text(city.shock.head,M+10,y+7,"small",P.text,CW-20)
    text(string.format("%d day%s left",city.shock.left,city.shock.left==1 and "" or "s"),M+10,y+29,"tiny",P.bad)
    y=y+58
  end

  heading("RESILIENCE",y); y=y+30
  -- A check on a large company is dozens of flow solves, so it runs a little
  -- each frame and the panel shows how far it has got.
  if state.job and state.job.city~=city then state.job=nil end
  local progress
  if state.job then
    local done,fraction=city:stepResilience(state.job,0.012)
    if done then state.job=nil else progress=fraction end
  end
  local r,stale=city:resilienceReport()
  if progress then
    text(string.format("Checking... %d%%",math.floor(progress*100)),M,y,"small",P.warn,CW)
    lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+22,CW,5,2)
    lg.setColor(P.warn); lg.rectangle("fill",M,y+22,CW*progress,5,2)
    y=y+40
  end
  if not r then
    y=y+paragraph("Fails every loaded main and structure, one at a time, and reports what each would cost you. Nothing in your company changes.",y)+10
  elseif not r.grade then
    y=y+paragraph("Nothing is earning yet, so there is nothing to protect.",y)+10
  else
    local colour=({A=P.good,B=P.good,C=P.warn,D=P.warn,F=P.bad})[r.grade] or P.text
    text(r.grade,M,y-6,"big",colour)
    if r.worst then
      single("Worst single failure: "..string.lower(r.worst.label),M+46,y,"small",P.textDim,CW-46)
      text(string.format("Would cost $%d/day (%d%% of revenue), %d customer%s",
        math.floor(r.worst.loss+0.5),math.floor(r.share*100+0.5),r.worst.hurt,r.worst.hurt==1 and "" or "s"),
        M+46,y+20,"small",colour,CW-46)
    else
      text("Nothing single failure can take from you.",M+46,y+6,"small",colour,CW-46)
    end
    y=y+64
    row("Checked",r.checked.." of "..r.total.." loaded items",y,P.textDim); y=y+26
    if stale then text("Out of date: the network has changed since.",M,y,"small",P.warn,CW); y=y+24 end
  end
  button("assess",r and "Check again" or "Check resilience",M,y,r and r.grade and 150 or CW,32,
    function() act("startResilience") end,progress==nil,
    "Runs in the background and takes a few seconds on a large company. Nothing is changed.",false,P.good,progress==nil and (not r or stale))
  if r and r.grade and #r.points>0 then
    button("spof-toggle",state.spof and "Hide on map" or "Show on map",M+158,y,CW-158,32,
      function() state.spof=not state.spof end,true,"Marks the single points of failure on the map",state.spof,P.bad)
  end
  y=y+44
  if r then
    for i=1,math.min(#r.points,6) do
      local p=r.points[i]
      button("spof-"..i,"",M,y,CW,44,function()
        act(p.kind=="edge" and "focusEdge" or "focusNode",p.id)
      end,true,"Select it on the map",false,P.bad)
      single(p.label,M+10,y+6,"small",P.text,CW-100)
      lg.setFont(R.fonts.small); lg.setColor(P.bad)
      lg.printf(string.format("-$%d/day",math.floor(p.loss+0.5)),M+CW-96,y+6,86,"right")
      single(p.hurt.." customer"..(p.hurt==1 and "" or "s").." would lose supply",M+10,y+25,"tiny",P.textDim,CW-20)
      y=y+50
    end
    if #r.points>6 then text("and "..(#r.points-6).." more",M,y,"small",P.textFaint); y=y+26 end
  end
  y=y+10

  heading("BEST NEXT UPGRADES",y); y=y+30
  local list=E.advise(city)
  if #list==0 then
    y=y+paragraph("Nothing that is full is holding an earning customer back. When a main, a well or a structure runs flat out and a wider or stronger one would earn more, it appears here with what it pays back.",y)+10
  end
  local mx,my=mouse()
  for i,item in ipairs(list) do
    local hover=mx>=M and mx<M+CW and my>=y and my<y+54
    if hover then state.advisorFocus={kind=item.kind=="pipe" and "edge" or "node",id=item.id} end
    button("advice-"..i,"",M,y,CW,54,function()
      if item.kind=="pipe" then act("replacePipe",item.id,item.size,item.grade)
      elseif item.kind=="source" then act("upgradeSource",item.id)
      else act("upgradeLevel",item.id) end
    end,item.affordable,item.affordable and "Buy it now" or "Not enough cash yet",false,P.good)
    single(adviceLabel(item),M+10,y+6,"small",item.affordable and P.text or P.textFaint,CW-84)
    lg.setFont(R.fonts.small); lg.setColor(item.affordable and P.energy or P.textFaint)
    lg.printf("$"..item.cost,M+CW-76,y+6,66,"right")
    single(string.format("+$%d/day  /  pays back in %s",math.floor(item.net+0.5),
      item.payback and (item.payback.." day"..(item.payback==1 and "" or "s")) or "no time"),
      M+10,y+28,"tiny",P.good,CW-20)
    y=y+60
  end
  UI.contentBottom=y+state.scroll+24
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
  if r.shock then single(r.shock,x+32,y+296,"small",P.bad,w-64) end
  button("report-details",state.reportDetails and "Hide accounting" or "Show accounting",x+32,y+316,w-64,30,
    function() state.reportDetails=not state.reportDetails end,true,"Revenue, expenses, repairs, investments and awards")
  if state.reportDetails then
    local entries={
      {"Revenue",r.revenue},{"Costs / day",-r.expenses},{"Repairs / prevention",-(r.crewCost or 0)-(r.preventCost or 0)},
      {"Investment profit / loss",r.interest or 0},{"Grants",reward},
    }
    if (r.credits or 0)>0 then entries[#entries+1]={"Secure contract refunds",-r.credits} end
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
  for _,key in ipairs({"everyday","hub","orders","haven","yard","works","massive","trunk","roads","routes","internet"}) do
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
  button("tab-ambitions","Goals",M,y,CW,36,function() state.tab="ambitions"; state.scroll=0 end,true,"Choose a goal. Earn a cash reward.")
  y=y+46
  button("tab-advisor","Advisor: resilience and upgrades",M,y,CW,32,function() state.tab="advisor"; state.scroll=0 end,true,
    "Which single failure would hurt most, and which upgrade earns the most.")
  y=y+42
  button("tab-ledger","History",M,y,CW,32,function() state.tab="ledger"; state.scroll=0 end,true,"Past events and payments.")
  y=y+48
  local open
  y,open=fold("overview","Company at a glance",y,city.reputation.."% rep")
  if open then
  for _,v in ipairs({{"Day",city.day},{"Clients",#city:clientList()},{"Open requests",#city:clientList(true)},
    {"Company value","$"..city:valuation()},{"Reputation",city.reputation.."%"},
    {"Requests per day","Up to "..city:requestLimit()},{"Land owned",#city:ownedDistricts()},
    {"Debt","$"..(city.loan or 0)}}) do row(v[1],v[2],y); y=y+30 end
  y=y+16
  text("Decline a request: -1 reputation.\nLet it expire: -2 reputation.\nBetter reputation brings more requests.",M,y,"small",P.textDim,CW)
  y=y+80
  end
  y,open=fold("recent","Recent profit",y,#city.history>0 and string.format("$%+d last",
    city.history[#city.history].revenue-(city.history[#city.history].expenses or 0)) or "")
  if open then
    -- The last fortnight as bars either side of a zero line: green days up,
    -- red days down, the latest one labelled.
    local first=math.max(1,#city.history-13)
    local n=#city.history-first+1
    if n<=0 then
      text("No days closed yet.",M,y,"small",P.textDim,CW); y=y+30
    else
      local lo,hi=0,1
      for i=first,#city.history do
        local v=city.history[i].revenue-(city.history[i].expenses or 0)
        lo,hi=math.min(lo,v),math.max(hi,v)
      end
      local ch=110
      local zero=y+ch*hi/(hi-lo)
      local bw=CW/14
      lg.setColor(P.with(P.textFaint,0.6)); lg.setLineWidth(1); lg.line(M,zero,M+CW,zero)
      for i=first,#city.history do
        local h=city.history[i]
        local v=h.revenue-(h.expenses or 0)
        local bx=M+(i-first)*bw+2
        local bh=math.abs(v)/(hi-lo)*ch
        lg.setColor(v>=0 and P.good or P.bad)
        lg.rectangle("fill",bx,v>=0 and zero-bh or zero,bw-4,math.max(1,bh),2)
      end
      local last=city.history[#city.history]
      single("Day "..last.day..": "..string.format("$%+d",last.revenue-(last.expenses or 0)),M,y+ch+8,"small",P.textDim,CW)
      y=y+ch+36
    end
  end
  local costs=city:expenseBreakdown()
  y,open=fold("costs","Daily costs",y,"$"..costs.total)
  if open then
  for _,v in ipairs({{"Office",costs.office},{"Sources",costs.sources},{"Buildings",costs.structures},
    {"Pipes",costs.pipes},{"Staff",costs.crews},{"Imports",costs.imports},{"Freight",costs.haulage},
    {"Distribution hubs",costs.hubs},{"Pumping",costs.pumping},{"Fuel",costs.fuel},{"Travel",costs.transit},{"Interest",costs.interest}}) do
    if (v[2] or 0)>0 then row(v[1],string.format("$%.1f",v[2]),y); y=y+26 end
  end
  y=y+16
  end
  -- What shape the network has grown into. A company that follows the prices
  -- ends up with a tree: many narrow mains into buildings, fewer and wider
  -- ones carrying them, and a trunk under all of it. This is that tree,
  -- counted, and it is the one panel that describes the network as a whole
  -- rather than one piece of it.
  local shape=E.anatomy(city,"water")
  local shapeOpen=false
  if shape and shape.top>1 then y,shapeOpen=fold("shape","Network shape",y,"") end
  if shape and shape.top>1 and shapeOpen then
    local NAME={"stubs","feeders","trunks","the trunk"}
    for o=1,shape.top do
      local b=shape.band[o]
      if b then
        row("Order "..o..", "..(NAME[o] or "above"),
          string.format("%d x %.0f m, carries %.0f",b.n,b.len/b.n,b.cap/b.n),y,
          o==shape.top and P.energy or P.text,
          "A main into a building is order 1. Where two of the same order meet, "..
          "the main carrying them both is one order higher. That is how a river "..
          "system and a set of blood vessels are both measured. This row is how "..
          "many mains of this order there are, how long they run on average, and "..
          "how much each one carries.")
        y=y+26
      end
    end
    if shape.RB then
      row("Branching",string.format("%.1f to 1",shape.RB),y,P.text,
        "How many mains of one order run into each main of the next. Rivers run three to five.")
      y=y+26
    end
    if shape.RC and shape.RB then
      local murray=shape.RC/shape.RB
      row("Capacity step",string.format("%.1fx per order",shape.RC),y,
        murray>0.85 and P.good or P.warn,
        "How much more the main below carries. Murray's law wants this to match the "..
        "branching, because every drop that goes into the branches came down the "..
        "main below them. At "..string.format("%.0f%%",murray*100)..
        " of it, the wide mains are "..(murray>0.85 and "carrying their share." or "narrower than the flow they take."))
      y=y+26
    end
    if shape.RL and shape.wantLength then
      row("Length step",string.format("%.2fx per order",shape.RL),y,
        shape.RL>1.2 and P.good or P.warn,
        "How much longer the main below is. A tree that fills its ground wants "..
        string.format("%.2fx",shape.wantLength)..", because a main that supplies several "..
        "times the ground has to reach across it. Below 1 means every main is about "..
        "as long as every other, whatever it carries.")
      y=y+26
    end
    row("Self-similar",shape.dimension and string.format("dimension %.2f",shape.dimension)
      or "not yet",y,shape.dimension and P.good or P.textDim,
      shape.dimension and "The same shape repeats at every scale. Two is a tree that fills a flat map."
      or "The network has a hierarchy of capacities on a single length scale: the trunks "..
         "are no longer than the stubs. Carry a wide main further before splitting it.")
    y=y+36
  end
  y,open=fold("supplies","Map supplies",y,"")
  if open then
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
  end
  UI.contentBottom=y+24+state.scroll
end
local TABS={{"network","Build"},{"finance","Company"},{"customers","Clients"},{"stats","Stats"}}

-- The header windows: whatever the window says, it starts at HEAD_VALUE, and
-- the bar it says it in is HEAD_BAR deep.
UI.HEAD_VALUE,UI.HEAD_BAR=34,80

-- The largest size the figure fits the window in.
function UI.headerFont(value,room)
  for _,key in ipairs({"big","mid","small"}) do
    if SF.width(value,R.fonts[key])<=room then return key end
  end
  return "small"
end

-- The two windows that hold a decision rather than a figure hold the same
-- control: one size, centred between the lines that bound the window, with
-- the whole of the decision on its face.
function UI.headerButton(width)
  local w=math.max(60,width-30)
  return (width-w)/2-14,w,36
end

-- The screen is the map. Above it runs one bar: the four menus on the left,
-- the cash and the day's profit, anything that needs a decision now (an offer,
-- a burst main), and the day button. Everything else lives in the menus, which
-- open as a drawer over the map's left edge, or behind the settings button.
UI.BAR=60
-- The size the player chose in Settings, and the ones on offer.
UI.pref=1.2
UI.SIZES={{"Normal",1.0},{"Large",1.2},{"Huge",1.4}}

-- The scale the interface is drawn at: the chosen one, unless the window is
-- too small to hold the bar at that size.
function UI.effectiveScale()
  local w,h=R.dimensions()
  return math.max(1,math.min(UI.pref or 1,w/1120,h/690))
end

function UI.drawerOpen(s)
  s=s or state
  return (s and (s.drawer or s.node or s.edge or s.link or s.district)) and true or false
end

local function inside(x,y,r) return x>=r[1] and x<=r[1]+r[3] and y>=r[2] and y<=r[2]+r[4] end

-- Whether a point on the real screen belongs to the interface rather than the map.
function UI.covers(x,y)
  local k=UI.scale or 1
  x,y=x/k,y/k
  if y<UI.BAR then return true end
  for _,r in ipairs(UI.blocks or {}) do if inside(x,y,r) then return true end end
  for _,b in ipairs(UI.buttons or {}) do if inside(x,y,{b.x,b.y,b.w,b.h}) then return true end end
  return false
end

function UI.overDrawer(x,y)
  local k=UI.scale or 1
  return UI.drawerOpen() and x/k<UI.width and y/k>=UI.BAR
end

local function closeDrawer()
  state.drawer=nil
  state.node,state.edge,state.link,state.district=nil,nil,nil,nil
  state.scroll=0; state.rename=nil
end
UI.closeDrawer=function(s) state=s or state; closeDrawer() end

local function openTab(key)
  state.rename=nil
  if UI.drawerOpen() and state.tab==key and not (state.node or state.edge or state.link or state.district) then
    closeDrawer(); return
  end
  state.node,state.edge,state.link,state.district=nil,nil,nil,nil
  state.tab=key; state.scroll=0; state.drawer=true; state.settings=nil
  if key=="map" then act("fitWorld") end
end

-- A gear, drawn rather than lettered.
local function gear(x,y,r,color)
  lg.setColor(color)
  for i=0,7 do
    local a=i*math.pi/4
    lg.circle("fill",x+math.cos(a)*r*0.82,y+math.sin(a)*r*0.82,r*0.24)
  end
  lg.circle("fill",x,y,r*0.7)
  lg.setColor(P.panel); lg.circle("fill",x,y,r*0.3)
end

local function topBar(open)
  lg.setColor(P.panel); lg.rectangle("fill",0,0,W,UI.BAR)
  lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.line(0,UI.BAR,W,UI.BAR)

  local tabX=10
  for i,t in ipairs(TABS) do
    local tw=({76,98,82,70})[i]
    local here=state.tab==t[1] or (t[1]=="stats" and (state.tab=="ambitions" or state.tab=="ledger" or state.tab=="advisor"))
      or (t[1]=="network" and state.tab=="map")
    local offers=t[1]=="customers" and #city:clientList(true) or 0
    button("tab-"..t[1],t[2],tabX,11,tw,38,function() openTab(t[1]) end,true,
      ({network="Build pipes and buildings (B)",finance="Money, loans, staff and licences",
        customers="Offers and contracts",stats="Results, goals, advisor and history"})[t[1]],open and here)
    if offers>0 then
      -- A dot with the number of open offers, the one reason to look in there.
      local bx,by=tabX+tw-6,13
      lg.setColor(P.energy); lg.circle("fill",bx,by,9)
      single(tostring(offers),bx-9,by-7,"tiny",P.bg,18,"center")
    end
    tabX=tabX+tw+5
  end

  -- From the right: the day, the settings, then whatever wants deciding.
  local rx=W-10
  button("end-day","End day "..city.day.."   >",rx-168,10,168,40,function() act("endDay") end,
    not city.bankrupt,"Settle revenue, expenses, investments and pipe wear (Enter)",true,P.good)
  rx=rx-176
  button("settings","",rx-44,10,44,40,function() state.settings=not state.settings end,true,
    "Settings: undo, sound, text size, companies",state.settings)
  gear(rx-22,30,11,state.settings and P.flow or P.textDim)
  rx=rx-52
  if #state.undo>0 then
    button("undo","Undo",rx-66,10,66,40,function() act("undo") end,true,"Undo the last decision (Z). Closing a day is final.")
    rx=rx-74
  end
  local bill,broken=city:repairAllCost()
  if broken>0 then
    button("repair-all","Fix  $"..bill,rx-116,10,116,40,function() act("repairAll") end,
      city.money>=bill,broken.." damaged "..(broken==1 and "line" or "lines")..". Repair every one of them.",true,P.bad)
    rx=rx-124
  end
  local request=city:nextRequest()
  if request then
    -- Who is asking, what they pay a unit, and what that leaves after a
    -- unit's cost: green when it pays well, red when it would lose money.
    local premium=city:requestPremium(request)
    local margin,cost,rate=city:clientMargin(request)
    local tint=margin<0 and P.bad or margin>=cost and P.good or nil
    local who=((City.CLIENTS[request.clientType] or {}).name or "REQUEST")
    who=request.powerRequest and "Power" or who:sub(1,1)..who:sub(2):lower()
    local bw=math.min(200,math.max(150,rx-tabX-300))
    button("request-open",who.." "..City.money2(rate).."  "..(margin>=0 and "+" or "-")..City.money2(math.abs(margin)),
      rx-bw,10,bw,40,function() act("focusRequest",request.id) end,true,
      "New offer"..(request.powerRequest and " for electricity" or "")..
      ": pays "..City.money2(rate).." a unit, a unit costs you "..City.money2(cost)..
      ", so you keep "..City.money2(margin).." a unit ("..string.format("%+.0f%%",premium*100)..
      " against the going rate).",tint~=nil,tint)
    rx=rx-bw-8
  end

  -- The two numbers that matter every day, in the room that is left.
  local net=city:dailyRevenue()-city:dailyExpenses()
  local clients=city:clientList()
  local supplied=0
  for _,client in ipairs(clients) do if city:fullyServed(client) then supplied=supplied+1 end end
  local x0=tabX+14
  local room=rx-x0-8
  if room>90 then
    -- Cash rolls to its new value rather than jumping, and flashes the colour
    -- of the change, so a day's takings or a big purchase is felt.
    local target=city.money
    UI.cashShown=UI.cashShown or target
    if UI.cashShown~=target then
      local diff=target-UI.cashShown
      if not UI.cashFlash or UI.cashFlashTarget~=target then
        UI.cashFlash,UI.cashFlashTarget,UI.cashFlashUp=R.t,target,diff>0
      end
      local step=math.max(1,math.abs(diff)*0.12)
      UI.cashShown=math.abs(diff)<=step and target or UI.cashShown+(diff>0 and step or -step)
    end
    local cash="$"..math.floor(UI.cashShown+0.5)
    local flash=UI.cashFlash and math.max(0,1-(R.t-UI.cashFlash)/0.9) or 0
    local cashColor=flash>0 and P.mix and P.mix(P.energy,UI.cashFlashUp and P.good or P.bad,flash)
      or (flash>0.3 and (UI.cashFlashUp and P.good or P.bad)) or P.energy
    local cashW=math.min(room*0.55,math.max(90,SF.width(cash,R.fonts.big)+28))
    single(cash,x0,20,UI.headerFont(cash,cashW),cashColor,cashW)
    single("CASH",x0,8,"tiny",P.textDim,cashW)
    local dx=x0+cashW+12
    local dayW=rx-dx-8
    if dayW>70 then
      local trading=not (#city.g:nodesOfKind("source")==0 and #clients==0)
      -- Losing money: how long the cash lasts at this rate says more than the rate.
      local runway=trading and net<0 and city.money>0 and math.floor(city.money/-net) or nil
      if runway and runway<=30 then
        single("PER DAY   CASH LASTS "..runway..(runway==1 and " DAY" or " DAYS"),dx,8,"tiny",
          runway<=7 and P.bad or P.warn,dayW)
      else
        single("PER DAY"..(#clients>0 and dayW>=170 and ("   "..supplied.."/"..#clients.." SUPPLIED") or ""),dx,8,"tiny",
          #clients>0 and supplied<#clients and P.warn or P.textDim,dayW)
      end
      local day=trading and string.format("$%+d",net) or "Not trading"
      local dayFont=dayW>=120 and "mid" or "body"
      single(day,dx,24,dayFont,trading and (net>=0 and P.good or P.bad) or P.textDim,dayW)
      -- The last fortnight of closes as a line, so the trend reads at a glance.
      local hist=city.history or {}
      local sw=math.min(110,dayW-SF.width(day,R.fonts[dayFont])-18)
      if #hist>=3 and sw>=50 then
        local sx0=dx+SF.width(day,R.fonts[dayFont])+14
        local first=math.max(1,#hist-13)
        local lo,hi=0,0
        for i=first,#hist do
          local v=hist[i].revenue-(hist[i].expenses or 0)
          lo,hi=math.min(lo,v),math.max(hi,v)
        end
        local span=math.max(1,hi-lo)
        local pts={}
        for i=first,#hist do
          local v=hist[i].revenue-(hist[i].expenses or 0)
          pts[#pts+1]=sx0+(i-first)/math.max(1,#hist-first)*sw
          pts[#pts+1]=48-(v-lo)/span*20
        end
        if lo<0 and hi>0 then
          local zy=48-(0-lo)/span*20
          lg.setColor(P.with(P.textFaint,0.5)); lg.setLineWidth(1); lg.line(sx0,zy,sx0+sw,zy)
        end
        local last=hist[#hist].revenue-(hist[#hist].expenses or 0)
        lg.setColor(P.with(last>=0 and P.good or P.bad,0.85)); lg.setLineWidth(1.6)
        lg.line(pts)
        lg.circle("fill",pts[#pts-1],pts[#pts],2.5)
      end
    end
  end
end

local function settingsMenu()
  local pw=270
  local px,py=W-10-pw,UI.BAR+8
  local rows={
    {"fit","Show all buildings   F",function() act("fit") end,true,"Zoom out to show all your buildings."},
    {"undo","Undo last decision   Z",function() act("undo") end,#state.undo>0,"Closing a day is final."},
    {"mute",state.muted and "Sound off   M" or "Sound on   M",function() act("mute") end,true,"Toggle sound."},
    {"solo",city.hideUnfocusedNetworks and "Other networks: hidden   H" or "Other networks: dimmed   H",
      function() act("solo") end,true,"Hide every network but the one you are working on, instead of dimming it."},
    {"hints",state.buildHelp and "Hints: on" or "Hints: off",function() act("hints") end,true,
      "The opening guide, and a short note the first time something new opens."},
    {"companies","Companies...",function() state.settings=nil; act("openSlots") end,true,
      "Six companies, kept side by side. Switch, start another, or delete one."},
    {"keys",state.showKeys and "Hide keyboard" or "Keyboard...",function() state.showKeys=not state.showKeys end,true,
      "Every shortcut in one list."},
  }
  local ph=16+#rows*44+30+44
  lg.setColor(P.bg); lg.rectangle("fill",px-1,py-1,pw+2,ph+2,8)
  lg.setColor(P.panel); lg.rectangle("fill",px,py,pw,ph,8)
  lg.setColor(P.panelEdge); lg.rectangle("line",px,py,pw,ph,8)
  UI.blocks[#UI.blocks+1]={px,py,pw,ph}
  local y=py+10
  for _,r in ipairs(rows) do
    button(r[1],r[2],px+10,y,pw-20,38,r[3],r[4],r[5],r[1]=="hints" and state.buildHelp)
    y=y+44
  end
  single("TEXT SIZE",px+12,y+6,"tiny",P.textDim,pw-24)
  y=y+24
  local bw=(pw-20-12)/3
  for i,sz in ipairs(UI.SIZES) do
    button("size-ui-"..i,sz[1],px+10+(i-1)*(bw+6),y,bw,36,function() act("uiScale",sz[2]) end,true,
      "Draw the menus and text at "..math.floor(sz[2]*100).."%.",math.abs((UI.pref or 1)-sz[2])<0.01)
  end
  if state.showKeys then
    local keys={{"Enter","End the day"},{"B","Build menu"},{"Tab","Open or close the menu"},{"Esc","Put down, deselect, close"},
      {"Z","Undo"},{"Y / N","Sign or decline the selected offer"},{"F","Show all buildings"},{"R","Repair the selected main, or all"},{"L","Worst leak"},
      {"U / E","Bigger main, or deepen a well"},{"Delete","Demolish the selection"},{"T","Bulk freight lines"},
      {"H","Hide other networks"},{"M","Sound"},{"1-8","Pick up a building"},{"Right drag","Pan"},{"Wheel","Zoom"}}
    local kw,kh=350,20+#keys*22
    local kx,ky=px-kw-10,py
    lg.setColor(P.bg); lg.rectangle("fill",kx-1,ky-1,kw+2,kh+2,8)
    lg.setColor(P.panel); lg.rectangle("fill",kx,ky,kw,kh,8)
    lg.setColor(P.panelEdge); lg.rectangle("line",kx,ky,kw,kh,8)
    UI.blocks[#UI.blocks+1]={kx,ky,kw,kh}
    for i,k in ipairs(keys) do
      single(k[1],kx+14,ky+10+(i-1)*22,"small",P.flow,90)
      single(k[2],kx+110,ky+10+(i-1)*22,"small",P.text,kw-124)
    end
  end
end

-- A short line at the foot of the map: what just happened, or what the tool
-- in hand does. It is the only text that is not in a menu.
local function toastPill(open)
  local message=state.toast or (state.tool and (string.upper(state.tool).." in hand: click the map to place it. Right-click or Esc puts it down."))
  if not message or message=="" then return end
  local left=open and UI.width or 0
  local f=R.fonts.body
  local tw=math.min(W-left-40,SF.width(message,f)+36)
  local tx,ty=left+(W-left-tw)/2,H-50
  lg.setColor(P.with(P.bg,0.92)); lg.rectangle("fill",tx,ty,tw,34,17)
  lg.setColor(state.toastBad and P.with(P.bad,0.7) or P.panelEdge); lg.rectangle("line",tx,ty,tw,34,17)
  single(message,tx+18,ty+9,"body",state.toastBad and P.bad or P.text,tw-36)
end

-- A small card beside the pointer for whatever it rests on: the two or three
-- numbers that matter about it, so the map can be read without opening a
-- menu. It waits a moment, and never covers a drag or a menu.
local hoverKey,hoverSince
local function hoverCard()
  if state.modal or state.drag or state.settings or state.tool then hoverKey=nil; return end
  local n=state.hoverNode and city.g.nodes[state.hoverNode]
  local e=not n and state.hoverEdge and city.g.edges[state.hoverEdge]
  if (n and state.node==n.id) or (e and state.edge==e.id) then hoverKey=nil; return end
  -- Bare ground: what is standing on it and what it costs to cross or buy.
  local ground,plot
  if not n and not e and state.hoverGround and state.tab~="map" then
    local gx,gy=state.hoverGround[1],state.hoverGround[2]
    plot=city:districtAt(gx,gy)
    if plot and not city:districtVisible(plot) then plot=nil end
    ground=plot and city:obstacleAt(gx,gy)
  end
  local key=n and ("n"..n.id) or e and ("e"..e.id)
    or ground and ("g"..(ground.river and "river" or tostring(ground.x)..":"..tostring(ground.y)))
    or plot and not plot.owned and ("d"..plot.id) or nil
  if key~=hoverKey then hoverKey,hoverSince=key,R.t end
  if not key or R.t-(hoverSince or R.t)<0.3 then return end
  local title,lines="",{}
  local function add(text,color) lines[#lines+1]={text,color or P.textDim} end
  if n and n.kind=="client" then
    title=E.clientName(city,n)
    local margin,cost,rate=city:clientMargin(n)
    local unit=n.commodity=="power" and " / kWh" or " / unit"
    local shown=n.commodity=="power" and 5 or 1
    if n.prospect then
      add("Offer: "..City.money2(rate/shown)..unit..", "..(n.expires-city.day+1).." days to answer",P.energy)
      local p=E.offerPreview(city,n.id)
      if p.cost==0 then add("Ready to connect: no new pipe needed",P.good)
      elseif p.cost then add(string.format("New pipe about $%d, then $%+d a day",p.cost,p.net or 0),(p.net or 0)>=0 and P.good or P.warn)
      elseif not p.multipleUtilities then add("Needs more supply before it can be served",P.warn) end
    else
      local got=city.served[n.id] or 0
      add(string.upper(n.commodity).."  "..got.." / "..n.demand,got>=n.demand and P.good or P.warn)
    end
    add("You keep "..(margin>=0 and "+" or "-")..City.money2(math.abs(margin)/shown)..unit..
      "  (cost "..City.money2(cost/shown)..")",margin<0 and P.bad or margin>=cost and P.good or P.text)
  elseif n and n.kind=="source" then
    title=n.plant and ((City.PLANTS[n.plant] or {}).name or "PLANT")
      or ((City.LEVELS.WELL_NAMES[n.level or 1] or "Well").." ("..string.lower(n.commodity)..")")
    local drawn=(city.produced or {})[n.id] or 0
    local cap=n.effectiveOutput or n.output or 0
    add("Pumping "..drawn.." of "..cap.." a day",drawn>=cap and cap>0 and P.warn or P.good)
    local t=city:tradeCosts(n.commodity)
    if t.perUnit then add("A unit costs "..City.money2(t.perUnit)..", sells "..City.money2(t.price)) end
  elseif n then
    title=city:levelFamily(n) and city:levelName(n) or (Graph.KINDS[n.kind] or {}).name or n.kind
    if city:levelFamily(n) then add("Level "..city:levelOf(n).." of "..city:levelCount(n)) end
    add("Carrying "..math.floor(city.detail.node[n.id] or 0)..", "..city:connectionPorts(n.id).." / "..(n.ports or 0).." connections")
    if city:isDistribution(n) then add("Runs customers paying $"..city:hubFloor(n).." or more",P.energy) end
  elseif e then
    title=string.upper(e.commodity).." "..(e.rail and "LINE" or ((Graph.COMMODITIES[e.commodity] or {}).conduit or "MAIN"))
    local flow=math.floor(math.abs((city.detail.edge or {})[e.id] or 0))
    add("Carrying "..flow.." of "..e.cap,flow>=e.cap and P.warn or P.good)
    if e.leaking then add(e.cap==0 and "Burst: repair it" or "Leaking: repair it",P.bad) end
  end
  if ground then
    local spec=City.OBSTACLES[ground.kind] or {}
    title=ground.river and city:riverName()
      or ground.massive and (ground.kind=="park" and "Protected park" or "Mountain range")
      or ground.kind=="park" and "Woodland" or ground.kind=="bedrock" and "Bedrock outcrop" or (spec.name or "Ground")
    local cross=city:groundCross(ground.kind,ground)
    if not cross then add("Closed: no main may cross it",P.bad)
    elseif cross>1 then add(string.format("Mains across it cost x%.1f",cross),P.warn)
    else add("Open: mains cross at the normal price",P.good) end
    local permit=City.PERMITS[ground.kind]
    if permit and not (city.permits or {})[ground.kind] and not ground.massive then
      add(permit.name..": $"..permit.cost.." lowers it to "..(permit.cross>1 and string.format("x%.1f",permit.cross) or "normal"),P.textDim)
    end
    if plot and not plot.owned then add(plot.name..": not yours yet",P.textFaint) end
  elseif plot and not plot.owned then
    title=plot.name
    local err=city:districtError(plot.id)
    add("$"..city:districtCost(plot)..(err and "" or "  click to open the sale"),err and P.textDim or P.energy)
    if (plot.population or 0)>0 then add("Population "..plot.population) end
    if not city:districtAdjacent(plot) then add("Not next to your land",P.textFaint) end
  end
  if #lines==0 and title=="" then return end
  local mx,my=mouse()
  local w=0
  w=math.max(w,SF.width(title,R.fonts.body))
  for _,l in ipairs(lines) do w=math.max(w,SF.width(l[1],R.fonts.small)) end
  w=math.min(w+24,W*0.5)
  local h=30+#lines*20
  local x,y=mx+18,my+18
  if x+w>W-8 then x=mx-18-w end
  if y+h>H-8 then y=my-18-h end
  lg.setColor(P.with(P.bg,0.94)); lg.rectangle("fill",x,y,w,h,7)
  lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.rectangle("line",x,y,w,h,7)
  single(title,x+12,y+8,"body",P.text,w-24)
  for i,l in ipairs(lines) do single(l[1],x+12,y+10+i*20,"small",l[2],w-24) end
end

function UI.draw(c,s,action)
  city,state,act=c,s,action
  local k=UI.effectiveScale()
  UI.scale=k
  if math.abs((R.uiScale or 1)-k)>0.01 then R.uiScale=k; R.retune() end
  local RW,RH=R.dimensions()
  W,H=RW/k,RH/k
  UI.buttons={}; UI.blocks={}; scroll=false
  state.previewRadius=nil
  lg.push(); lg.scale(k)
  local open=UI.drawerOpen()

  -- Dusk: the close sweeps a moment of evening over the map, then day again.
  if state.dusk then
    local a=(R.t-state.dusk)/1.1
    if a>=1 then state.dusk=nil
    else
      lg.setColor(0.03,0.05,0.12,0.5*math.sin(a*math.pi))
      lg.rectangle("fill",0,UI.BAR,W,H-UI.BAR)
    end
  end

  if open then
    lg.setColor(P.panel); lg.rectangle("fill",0,UI.BAR,UI.width,H-UI.BAR)
    lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.line(UI.width,UI.BAR,UI.width,H)
    UI.blocks[#UI.blocks+1]={0,UI.BAR,UI.width,H-UI.BAR}
    lg.setScissor(0,(UI.BAR+2)*k,(UI.width-1)*k,(H-UI.BAR-2)*k); scroll=true
    if state.tab=="network" then network()
    elseif state.tab=="finance" then company()
    elseif state.tab=="customers" then customers()
    elseif state.tab=="map" then mapTab()
    elseif state.tab=="stats" then stats()
    elseif state.tab=="ambitions" then goals()
    elseif state.tab=="advisor" then advisor()
    else ledger() end
    scroll=false; lg.setScissor()
    UI.maxScroll=math.max(0,(UI.contentBottom or H)-(H-12))
    state.scroll=math.min(state.scroll,UI.maxScroll)
    if UI.maxScroll>0 then
      local track=H-UI.BAR-16
      local thumb=math.max(30,track*track/(track+UI.maxScroll))
      lg.setColor(P.panelEdge); lg.rectangle("fill",UI.width-9,UI.BAR+8,3,track,1)
      lg.setColor(P.textFaint)
      lg.rectangle("fill",UI.width-9,UI.BAR+8+(track-thumb)*math.min(1,state.scroll/UI.maxScroll),3,thumb,1)
    end
    -- A tab on the drawer's edge that folds it away again.
    button("drawer-close","<",UI.width-1,UI.BAR+12,24,46,function() closeDrawer() end,true,"Close the panel (Esc)")
  else
    UI.maxScroll=0
  end
  topBar(open)


  -- The first day, one step at a time. Everything the player will go on doing
  -- for the rest of the game happens once here, in order, with the panel saying
  -- only what the next action is.
  local step,stepNo,steps=city:tutorialStep()
  local left=open and UI.width or 0
  -- The opening guide shows by itself until the player has said either way
  -- about hints: a first company should never start with nothing to go on.
  if (state.buildHelp or not state.hintsChosen) and step and not state.modal then
    local gx,gw=left+20,math.min(600,W-left-40)
    local font=R.fonts.body
    local _,lines=font:getWrap(step.body,gw-32)
    local gh=84+#lines*20
    local gy=H-66-gh
    UI.blocks[#UI.blocks+1]={gx,gy,gw,gh}
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
  local lesson=not state.modal and not step and city:pendingLesson()
  if state.buildHelp and lesson and (city.day>2 or city.guideDismissed) then
    local gx,gw=left+20,math.min(620,W-left-40)
    local font=R.fonts.body
    local _,lines=font:getWrap(lesson.body,gw-32)
    local gh=84+#lines*20
    local gy=H-66-gh
    UI.blocks[#UI.blocks+1]={gx,gy,gw,gh}
    lg.setColor(P.panel); lg.rectangle("fill",gx,gy,gw,gh,8)
    lg.setColor(P.with(P.energy,0.6)); lg.rectangle("line",gx,gy,gw,gh,8)
    single(lesson.title,gx+16,gy+12,"mid",P.energy,gw-32)
    text(lesson.body,gx+16,gy+38,"body",P.text,gw-32)
    button("lesson-ok","Got it",gx+gw-78,gy+gh-34,66,26,
      function() act("teach",lesson.key) end,true,"Understood: do not show this again")
  end

  toastPill(open)
  hoverCard()
  -- A milestone or an ambition reached gets a banner of its own for a moment.
  if state.banner and not state.drag and not state.tool then
    local b=state.banner
    local age=R.t-b.t
    if age>3.2 then state.banner=nil
    else
      local pop=math.min(1,age*6)
      local fade=math.min(1,(3.2-age)/0.5)
      local bw,bh=math.min(560,W-40),96
      local bx,by=((open and UI.width or 0)+W)/2-bw/2,UI.BAR+40
      lg.push(); lg.translate(bx+bw/2,by+bh/2); lg.scale(0.7+0.3*pop); lg.translate(-bw/2,-bh/2)
      lg.setColor(P.with(P.bg,0.92*fade)); lg.rectangle("fill",0,0,bw,bh,12)
      local tone=b.warn and P.warn or P.energy
      lg.setColor(P.with(tone,0.8*fade)); lg.setLineWidth(2); lg.rectangle("line",0,0,bw,bh,12)
      local c1=P.with(tone,fade)
      single(b.title,20,14,"big",c1,bw-40,"center")
      single(b.sub or "",20,62,"body",P.with(b.warn and P.text or P.good,fade),bw-40,"center")
      lg.pop()
    end
  end
  if state.settings and not state.modal then settingsMenu() end

  -- The opening guide does not only say what to press: it points at it. A
  -- sidebar button gets a ring and an arrow from the map side; the bottom bar
  -- gets one from above. Map targets are drawn with the world.
  local target=not state.modal and not state.settings and E.tutorialTarget(city,state)
  if target and target.button then
    -- A button inside a closed menu cannot be pointed at, so the arrow points
    -- at the menu that holds it.
    local want=target.button
    local found=false
    for _,b in ipairs(UI.buttons) do if b.id==want then found=true end end
    if not found then want="tab-network" end
    for _,b in ipairs(UI.buttons) do
      if b.id==want then
        local pulse=0.5+0.5*math.sin(R.t*2)
        local bob=3*math.sin(R.t*2)
        lg.setColor(P.with(P.good,0.45+0.25*pulse)); lg.setLineWidth(2)
        lg.rectangle("line",b.x-4,b.y-4,b.w+8,b.h+8,6)
        if b.y<UI.BAR then
          local ax,ay=b.x+b.w/2,b.y+b.h+14-bob
          lg.polygon("fill",ax,ay,ax-11,ay+16,ax+11,ay+16)
          lg.rectangle("fill",ax-4,ay+15,8,19)
        elseif b.x>W/2 or b.y>H-70 then
          local ax,ay=b.x+b.w/2,b.y-14+bob
          lg.polygon("fill",ax,ay,ax-11,ay-16,ax+11,ay-16)
          lg.rectangle("fill",ax-4,ay-34,8,19)
        else
          local ax,ay=b.x+b.w+14+bob,b.y+b.h/2
          lg.polygon("fill",ax,ay,ax+16,ay-11,ax+16,ay+11)
          lg.rectangle("fill",ax+15,ay-4,19,8)
        end
        lg.setLineWidth(1)
        break
      end
    end
  end
  if state.modal then
    UI.buttons={}
    report()
  end

  local mx,my=mouse()
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
  lg.pop()
end

-- Scroll straight to the inspector. Called whenever a selection is made, so a
-- click on a burst main lands the player on its Repair button rather than on
-- the top of a panel they then have to scroll.
-- The inspector is the whole panel now, so revealing it is just going there.
function UI.revealInspector() return 0 end

function UI.click(x,y)
  local k=UI.scale or 1
  x,y=x/k,y/k
  -- An open settings menu takes the next click: its own buttons act, and a
  -- click anywhere else just closes it.
  if state and state.settings then
    for _,b in ipairs(UI.buttons) do
      if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
        if b.enabled then b.fn() end
        if b.id~="settings" and not b.id:match("^size%-ui") and b.id~="mute" and b.id~="solo" and b.id~="hints" and b.id~="keys" then state.settings=nil end
        return true
      end
    end
    state.settings=nil
    return true
  end
  for _,b in ipairs(UI.buttons) do
    if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
      if b.enabled then b.fn() end
      return true
    end
  end
  for _,r in ipairs(UI.blocks or {}) do if inside(x,y,r) then return true end end
  return false
end

return UI
