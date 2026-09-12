local P = require("palette")
local City = require("city")
local Graph = require("graph")
local R = require("render")
local Draw = require("company_render")
local Save = require("company_save")
local E = require("experience")
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

local function single(s,x,y,font,color,width)
  s=tostring(s)
  local f=R.fonts[font or "body"]
  if f:getWidth(s)>width then
    local utf8=require("utf8")
    repeat s=s:sub(1,(utf8.offset(s,-1) or 1)-1) until s=="" or f:getWidth(s.."...")<=width
    s=s.."..."
  end
  text(s,x,y,font,color)
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
  local scale=math.min(1,(w-10)/math.max(1,font:getWidth(label)))
  lg.print(label,x+(w-font:getWidth(label)*scale)/2,y+(h-font:getHeight()*scale)/2,0,scale,scale)
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

-- Working out who loses supply if a structure came out means running the flow
-- solver twice, so the answer is kept until the network actually changes.
local consequenceCache = {}
local function consequences(n)
  if consequenceCache.id ~= n.id or consequenceCache.rev ~= city.revision then
    local pipes, sunk = city:demolitionCost(n.id)
    consequenceCache = { id = n.id, rev = city.revision, pipes = pipes or 0,
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
  if c.pipes > 0 then
    text("Cuts "..c.pipes.." main"..(c.pipes==1 and "" or "s").." ($"..c.sunk..
         " of work, not recovered)"..
         (c.cut>0 and (" and leaves "..c.cut.." customer"..(c.cut==1 and "" or "s")..
          " unsupplied.") or "."),
      M,y+42,"small",c.cut>0 and P.bad or P.warn,CW)
  else
    text("Nothing is tied into it.",M,y+42,"small",P.textDim,CW)
  end
  return y+(c.pipes>0 and 82 or 66)
end

-- The same droplet the map draws, inline in the sidebar.
local function drop(commodity,x,y,r) Draw.droplet(commodity,x,y,r or 8) end

--------------------------------------------------------------------------------

local toolTips = {
  junction="Junction: 3 ports, $22, $1 a day. The cheapest way to turn a corner or split a run.",
  manifold="Manifold: 6 ports, $46, $1 a day. Shared ground: water, power, beer and oil can all pass through one without mixing.",
  pump="Pump: 2 ports, reaches 520m instead of 300m, $38, $1 a day. The only way across a long gap.",
  tower="Treatment station: $92, $2 a day. Cuts leak risk by 55% for every main whose midpoint is within 220m. Stations do not stack.",
  gate="Gate: 2 ports, $30, $1 a day. A valve you set by hand -- throttle a branch to starve it on purpose and send scarce supply to the customers who pay more.",
  depot="Depot: 3 ports, $190, $3 a day. Takes in output you could not sell today, up to 18 units, and feeds it back into the network tomorrow.",
  exchange="Hub: 8 ports, $1400, $9 a day plus $0.70 a customer. Stands in a neighbourhood and serves everyone inside 700m who pays at least the rate you set, with no main drawn to any of them. Offers in range sign themselves. Its feed widens itself when it runs short, at the usual price, until you switch that off.",
  terminal="Haven: 4 ports, $2200, $26 a day. The city's door to the outside world: every trade but power lands here in unlimited quantity, billed per unit as it moves. It can only stand on the strip of ground along the estuary, the highway or the apron, one haven to each, and it ships by track only.",
}

local TOOLS = {"junction","manifold","pump","tower","gate","depot","exchange","terminal"}

-- Replacing a structure where it stands. The mains never come off, so this is
-- the difference between buying three more ports and rebuilding a junction box
-- from scratch with every pipe relaid by hand.
local REPLACEMENTS = {"junction","manifold","pump","tower","gate","depot"}

local function replaceStrip(n,y)
  if not City.CONVERTIBLE[n.kind] then return y end
  heading("REPLACE WITH",y)
  text("The mains stay connected.",M+CW-170,y,"small",P.textFaint,170,"right")
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
    local p=E.offerPreview(city,n.id)
    text(p.cost==0 and "Ready: existing lines can fully supply this customer."
      or p.cost and ("Direct connection estimate: $"..p.cost.." for full supply. Quote assumes a new "..n.demand.."-unit line.")
      or ("Currently "..p.delivery.."/"..p.demand.." supplied if signed. Needs more supply or a route with intermediate structures."),
      M,y+242,"small",p.cost and P.good or P.warn,CW)
    if p.net then
      text(string.format("Projected net change: $%+d/day",p.net),M,y+300,"small",p.net>=0 and P.good or P.warn,CW)
      if (p.displaced or 0)>0 then
        text("Shared supply: other customers may receive less.",M,y+326,"small",P.warn,CW)
      end
    end
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
  -- The ground's own ceiling, which no amount of money moves. It is the reason
  -- the map has to keep going: more supply means further out.
  local ceiling=n.cap or capacity
  row("What this ground gives",ceiling.." / day",y+116,
    capacity>=ceiling and P.warn or P.textDim,
    "A deposit has a daily limit and the works on it cannot pass it. Deposits "..
    "further from the old city give more. This one is "..
    (capacity>=ceiling and "worked out." or ("worked to "..capacity.." of "..ceiling..".")))
  row("Well depth","level "..level.." / "..City.sourceMaxLevel,y+142)
  row("Wholesale income","+$"..city:sourceIncome(n).." / day",y+168,P.good)
  row("Upkeep","-$"..(trade.sourceUpkeep+(level-1)*2).." / day",y+194,P.warn)
  row("Ports",city.g:degree(n.id).." / "..n.ports,y+220)
  if level<City.sourceMaxLevel and capacity<ceiling then
    local cost=city:sourceUpgradeCost(n)
    button("upgrade-source","Deepen well   +"..trade.upgradeStep.." output   $"..cost,
      M,y+258,CW,38,function() act("upgradeSource",n.id) end,city.money>=cost,
      "Adds "..trade.upgradeStep.." output to this well. No new route, no tie-in, no new ground and no second lot of upkeep -- which is why deepening beats a second well until the levels get steep.",
      false,P.good,maxed and city.money>=cost)
    text("A new "..n.commodity.." well costs $"..city:sourceCost(n.commodity)..
         " plus the route to reach it.",M,y+304,"small",P.textDim,CW)
    y=y+336
  else
    text(capacity>=ceiling
      and ("This ground is worked out at "..ceiling.." a day. Deposits further from the old city give more.")
      or "This well is at full depth. Sink another, or buy ground with a richer deposit.",
      M,y+262,"body",P.textDim,CW)
    y=y+300
  end
  if n.seam then
    text("Sunk on a seam: yield multiplied at the wellhead.",M,y,"small",P.energy,CW)
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
    y=demolishBlock(n,y,"Close the well",
      "Nothing is tied into this well, so it can be removed outright.")
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
  button("gate-open","Open",M+134,y+90,74,36,function() act("setGate",n.id,24) end,t<24,"Open fully")
  button("gate-plus","+",M+216,y+90,44,36,function() act("setGate",n.id,t+1) end,t<24,"One unit looser")
  text("Everything downstream of this gate shares what it lets through. Tighten it to starve a cheap branch and send scarce supply to a better-paying one.",
    M,y+138,"small",P.textDim,CW)
  local tail=replaceStrip(n,y+186)
  return demolishBlock(n,tail+12)
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
  local tail=replaceStrip(n,y+186)
  return demolishBlock(n,tail+12)
end

local function inspectHub(n,y)
  local covered=#(n.covered or {})
  row("Customers on it",covered,y,covered>0 and P.good or P.textDim,
    "Everyone inside "..City.hub.radius.."m who pays at least the floor and has no main of their own. "..
    "Offers in range sign themselves.")
  row("Rate floor","$"..(n.floor or 0).." / unit",y+26,(n.floor or 0)>0 and P.energy or P.textDim,
    "The hub refuses anyone paying less. Raise it and the cheap houses drop off, "..
    "which is how scarce supply is pointed at the customers worth having.")
  button("hub-floor-down","-",M,y+52,34,30,function() act("setHubFloor",n.id,(n.floor or 0)-City.hub.floorStep) end,
    (n.floor or 0)>0,"Serve cheaper customers too")
  button("hub-floor-up","+",M+40,y+52,34,30,function() act("setHubFloor",n.id,(n.floor or 0)+City.hub.floorStep) end,
    true,"Serve only better payers")
  button("hub-auto",n.autoWiden and "Feed widens itself" or "Feed left alone",M+84,y+52,CW-84,30,
    function() act("setHubAuto",n.id,not n.autoWiden) end,true,
    "With this on, a saturated main into this hub gains one unit of bore at each close, "..
    "at the usual price, whenever the hub is short.",n.autoWiden,P.accent)
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
    text("Nobody in range yet. A hub pays for itself only where the customers are.",
      M,ly,"small",P.warn,CW)
    ly=ly+30
  end
  row("Running cost","-$"..string.format("%.1f",City.hub.upkeep+covered*City.hub.perClient).." / day",ly,P.warn,
    "$"..City.hub.upkeep.." for the hub and $"..City.hub.perClient.." for every customer on it.")
  text("A hub is the last mile, charged rather than drawn. Feed it with mains from the trunk network and it wires the neighbourhood itself.",
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
  text("A haven has no bottom: every trade but power lands here in any quantity, "..
       "and is paid for by the unit as it moves. It ships by track only, and the "..
       "haulage is charged by the metre, so what it costs you is distance.",
    M,ly+56,"small",P.textDim,CW)
  return demolishBlock(n,ly+128,"Demolish the haven",
    "Closes the haven and frees its gateway. Every link tied into it is cut.")
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

-- Everyday construction stays above maintenance and specialist equipment.
local function buildPanel()
  local y=TOP-state.scroll
  heading("BUILD YOUR NETWORK",y); y=y+26
  text("Drag between buildings to connect them.",M,y,"small",P.textDim); y=y+30
  for i,name in ipairs(Graph.TRADES) do
    local spec=Graph.COMMODITIES[name]
    local bx=M+(i-1)*76
    button(name,string.upper(name),bx,y,72,36,function() state.commodity=name end,
      city.licences[name],city.licences[name] and ("Build "..name.." lines")
      or ("Acquire the "..name.." licence in Company"),state.commodity==name,spec.color)
  end
  y=y+46
  text("Capacity",M,y+9,"body",P.textDim)
  button("capacity-minus","-",M+78,y,32,32,function() state.capacity=math.max(1,state.capacity-1) end,true,"Narrower bore")
  text(state.capacity,M+114,y+8,"body",P.text,26,"center")
  button("capacity-plus","+",M+144,y,32,32,function() state.capacity=math.min(24,state.capacity+1) end,true,"Wider bore")
  button("rail-toggle",state.rail and "TRACK" or "PIPE",M+186,y,114,32,function() state.rail=not state.rail end,
    #city.g:nodesOfKind("terminal")>0,"Track must start or end at a haven (T)",state.rail,P.accent)
  y=y+44
  -- One supply button, and it says what the selected trade actually allows:
  -- a well or a rig on a marked deposit, a reactor on any ground, and for beer
  -- nothing at all, because beer is landed rather than made.
  if state.commodity=="beer" then
    button("source","Beer is landed at a haven",M,y,CW,36,function() end,false,
      "Nobody brews. Beer arrives at a haven like any other import: build one on the edge of the map and run track inland.",
      false,P.textFaint)
  else
    local scost=city:sourceCost(state.commodity)
    local title=({water="Sink a water well",oil="Sink an oil rig",power="Build a nuclear plant"})[state.commodity]
    button("source",title.."  $"..scost,M,y,CW,36,
      function() state.tool=state.tool=="source" and nil or "source" end,city.money>=scost,
      state.commodity=="power"
        and "Electricity cannot be imported: it is generated here. A reactor needs no deposit, only ground you hold. Enormous to build, cheap by the unit."
        or ("Only on a marked "..state.commodity.." deposit. The buried ones yield more and need the matching permit first."),
      state.tool=="source",P.good)
  end
  y=y+52
  heading("EVERYDAY STRUCTURES",y); y=y+24
  local advanced=state.advanced==true or (state.advanced==nil and city.day>3)
  for i,name in ipairs(TOOLS) do
    if i<=3 or advanced then
      local col,rw=(i-1)%3,math.floor((i-1)/3)
      local bx,by=M+col*102,y+rw*58
      local afford=city.money>=City.price[name]
      button("tool-"..name,"",bx,by,96,50,function() state.tool=state.tool==name and nil or name end,
        afford,toolTips[name],state.tool==name,Graph.KINDS[name].color)
      lg.setColor(afford and Graph.KINDS[name].color or P.textFaint)
      Draw.structureGlyph(name,bx+17,by+24)
      text(({junction="Junction",manifold="Manifold",pump="Pump",tower="Treat",gate="Valve",depot="Depot",exchange="Hub",terminal="Haven"})[name],
        bx+32,by+8,"tiny",P.text)
      text("$"..City.price[name],bx+32,by+28,"small",P.textDim)
    end
  end
  y=y+(advanced and 232 or 58)+8
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
  button("advanced",advanced and "Less equipment" or "More equipment: treatment, valves, freight",
    M,y,CW,32,function() state.advanced=not advanced end,true,"Show or hide specialist structures")
  y=y+48
  line(y); y=y+20
  heading("SUPPLY & MAINTENANCE",y); y=y+28
  for _,name in ipairs(Graph.TRADES) do
    if city.licences[name] then
      local drawn,capacity=city:supplyFor(name)
      row(string.upper(name),drawn.." / "..capacity,y,Graph.COMMODITIES[name].color)
      lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+21,CW,4,2)
      lg.setColor(Graph.COMMODITIES[name].color)
      lg.rectangle("fill",M,y+21,CW*(capacity>0 and math.min(1,drawn/capacity) or 0),4,2)
      y=y+38
    end
  end
  local bill,count=city:repairAllCost()
  if count>0 then
    button("repair-all","Repair "..count.." mains  $"..bill,M,y,CW,36,function() act("repairAll") end,
      city.money>=bill,"Repair every damaged main",false,P.bad)
    y=y+44
  else text("All mains sound",M,y,"body",P.good); y=y+28 end
  row("Maintenance crews",(city.crews or 0).." / "..City.crewMax,y)
  UI.contentBottom=y+40+state.scroll
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
      or (n.kind=="source" and (string.upper(n.commodity)..
          (n.commodity=="power" and " STATION " or " WELL ")..n.id))
      or (Graph.KINDS[n.kind].name.." "..n.id)
    if n.commodity then drop(n.commodity,M+9,y+10,10); single(title,M+24,y,"mid",P.text,CW-24)
    else single(title,M,y,"mid",P.text,CW) end
    y=y+36
    if n.kind=="client" then inspectClient(n,y); tail=y+400
    elseif n.kind=="source" then tail=inspectSource(n,y)
    elseif n.kind=="gate" then tail=inspectGate(n,y)
    elseif n.kind=="depot" then tail=inspectDepot(n,y)
    elseif n.kind=="terminal" then tail=inspectTerminal(n,y)
    elseif n.kind=="exchange" then tail=inspectHub(n,y)
    else
      local degree=city.g:degree(n.id)
      row("Ports",degree.." / "..n.ports,y,degree>=n.ports and P.warn or P.text)
      row("Carrying",math.floor(city.detail.node[n.id] or 0),y+26)
      if n.kind=="tower" then row("Local leak risk","-55% within 220m",y+52,P.energy)
      elseif n.kind=="pump" then row("Reach","520m",y+52,P.flow) end
      if n.capped then
        text("A capped wellhead. It holds the mains the well was carrying.",
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
       (b.haulage>0 and ("   haulage $"..math.floor(b.haulage)) or "")..
       (b.hubs>0 and ("   hubs $"..math.floor(b.hubs)) or "")..
       (b.fuel>0 and ("   fuel $"..math.floor(b.fuel)) or "")..
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
  if #city.history>1 then
    local low,high=0,1
    for i=start,#city.history do local h=city.history[i]; local n=h.revenue-(h.expenses or 0); low=math.min(low,n); high=math.max(high,n) end
    local points={}
    for i=start,#city.history do
      local h=city.history[i]; local n=h.revenue-(h.expenses or 0)
      points[#points+1]=M+(i-start)/math.max(1,#city.history-start)*CW
      points[#points+1]=hy+70-(n-low)/(high-low)*64
    end
    lg.setColor(P.panelEdge); lg.line(M,hy+70-(0-low)/(high-low)*64,M+CW,hy+70-(0-low)/(high-low)*64)
    lg.setColor(P.good); lg.setLineWidth(2); lg.line(points)
    text("$"..high,M,hy-12,"tiny",P.textDim)
    text("$"..low,M,hy+74,"tiny",P.textDim)
    hy=hy+98
  end
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
  button("sort-clients",state.clientSort=="income" and "Sort: daily income" or "Sort: most urgent",M,y,CW,30,function()
    state.clientSort=state.clientSort=="income" and "urgency" or "income"
  end,true,"Switch between potential daily revenue and the nearest service or offer deadline")
  y=y+46
  if #city.tenders>0 then
    heading("MUNICIPAL TENDERS",y)
    text("The council pays for supply held at a level, not for one good day.",
      M,y+20,"small",P.textFaint,CW)
    y=y+60
    for _,t in ipairs(city.tenders) do
      local have=(city.flowBy[t.commodity] or 0)
      local short=city:tenderShortfall(t)
      local meeting=short<=0
      local spec=Graph.COMMODITIES[t.commodity]
      drop(t.commodity,M+9,y+10,9)
      text("Deliver "..t.units.." "..string.lower(spec.name).." a day",M+24,y,"body",P.text)

      if t.status=="offered" then
        -- An offer. Say the whole deal in a sentence, then ask.
        text("on "..t.days.." day closes, for $"..t.reward..".",M,y+24,"small",P.textDim,CW)
        text("You deliver "..have.." now"..
             (short>0 and (", so you need "..short.." more.") or ", which already meets it."),
          M,y+42,"small",short>0 and P.warn or P.good,CW)
        button("tender-accept-"..t.id,"Accept   $"..t.bond.." bond",M,y+64,182,34,
          function() act("acceptTender",t.id) end,city.money>=t.bond,
          "Posting the bond signs the contract. Deliver "..t.units.." "..t.commodity..
          " on "..t.days.." day closes and you get the $"..t.reward.." plus the bond back. "..
          "Miss the deadline and the bond is forfeited.",false,P.good,short<=0)
        button("tender-decline-"..t.id,"Decline",M+190,y+64,110,34,
          function() act("declineTender",t.id) end,true,
          "Costs nothing. An offer nobody answers is withdrawn in a few days anyway.")
        lg.setFont(R.fonts.tiny); lg.setColor(P.textFaint)
        lg.printf("offer open until day "..t.offerExpires,M,y+104,CW,"left")
        y=y+124
      else
        -- Signed. Show what is still owed and how long there is to do it.
        text(t.met.." of "..t.days.." closes met   /   $"..t.reward.." plus $"..t.bond.." bond",
          M,y+24,"small",P.textDim,CW)
        text(meeting and ("Delivering "..have..": this close counts.")
          or ("Delivering "..have..", "..short.." short. This close does not count."),
          M,y+42,"small",meeting and P.good or P.warn,CW)
        local bw=CW*math.min(1,t.met/t.days)
        lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+64,CW,4,2)
        lg.setColor(meeting and P.good or P.warn); lg.rectangle("fill",M,y+64,bw,4,2)
        local left=t.expires-city.day+1
        lg.setFont(R.fonts.tiny); lg.setColor(left<=2 and P.bad or P.textFaint)
        lg.printf(left.." day"..(left==1 and "" or "s").." left to finish, or the bond is lost",
          M,y+74,CW,"left")
        y=y+100
      end
    end
    line(y); y=y+22
  end
  for _,prospect in ipairs({true,false}) do
    heading(prospect and "CONNECTION ENQUIRIES" or "ACTIVE CUSTOMERS",y)
    y=y+30
    local clients=city:clientList(prospect)
    table.sort(clients,function(a,b)
      if state.clientSort=="income" then
        local av,bv=a.demand*a.rate,b.demand*b.rate
        if av~=bv then return av>bv end
      else
        local av=prospect and a.expires or ((city.served[a.id] or 0)<a.demand and a.grace or 999)
        local bv=prospect and b.expires or ((city.served[b.id] or 0)<b.demand and b.grace or 999)
        if av~=bv then return av<bv end
      end
      return a.id<b.id
    end)
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
      single(E.clientName(city,c),M+30,y+9,"small",P.text,166)
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
  if state.district then
    local d=city.districts[state.district]
    if d then
      text(d.name,M,y,"mid",P.energy)
      text(E.districtStory(city,state.district),M,y+28,"small",P.textDim,CW)
      y=y+100
    end
  end
  heading("GROUND",y)
  local owned=city:ownedDistricts()
  text(#owned.." held",M+CW-150,y,"small",P.textDim,150,"right")
  y=y+28

  -- On an endless map a list of every district is not a list, it is a scroll.
  -- What the player actually needs is what they hold and what they could buy
  -- next, nearest first, and a count of the rest.
  local forSale={}
  for _,d in ipairs(city.districts) do
    if not d.owned and city:districtAdjacent(d) then forSale[#forSale+1]=d end
  end
  table.sort(forSale,function(a,b)
    local ca,cb=city:districtCost(a),city:districtCost(b)
    if ca~=cb then return ca<cb end
    return a.id<b.id
  end)
  table.sort(owned,function(a,b) return a.id<b.id end)

  local function districtRow(d,forSaleRow)
    local spec=d.spec or {}
    local lean=(function()
      local t={} for k in pairs(spec.bias or {}) do t[#t+1]=k end
      table.sort(t) return #t>0 and table.concat(t,", ") or "mixed"
    end)()
    if not forSaleRow then
      button("district-"..d.id,d.name.."   held",M,y,CW,30,
        function() act("focusDistrict",d.id) end,true,
        "Your ground, ring "..(d.ring or 0)..". Customers here lean "..lean..".",
        state.district==d.id,P.good)
    else
      local err=city:districtError(d.id)
      local cost=city:districtCost(d)
      button("district-"..d.id,d.name.."   $"..cost,M,y,CW,30,
        function() act("buyDistrict",d.id) end,not err,
        err and (d.name..": "..err) or
        ("Buy "..d.name..", ring "..(d.ring or 0)..". Customers here lean "..lean..
         ". Deposits out here cap at "..City.depositCap("water",d.ring or 0).." water and "..
         City.depositCap("oil",d.ring or 0).." oil a day."),
        state.district==d.id,err and P.textFaint or P.energy)
    end
    y=y+34
  end

  local shown=0
  for _,d in ipairs(owned) do
    if shown<8 then districtRow(d,false); shown=shown+1 end
  end
  if #owned>shown then
    text("and "..(#owned-shown).." more held",M,y,"small",P.textFaint,CW); y=y+22
  end
  y=y+8
  heading("FOR SALE NEXT DOOR",y); y=y+26
  shown=0
  for _,d in ipairs(forSale) do
    if shown<8 then districtRow(d,true); shown=shown+1 end
  end
  if #forSale>shown then
    text("and "..(#forSale-shown).." more on the frontier",M,y,"small",P.textFaint,CW); y=y+22
  end
  if #forSale==0 then
    text("Nothing adjacent is surveyed yet.",M,y,"small",P.textFaint,CW); y=y+22
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
  text("Three ways into the city from outside it. Freight costs what it costs to carry.",M,py+48,"small",P.textDim,CW)
  local hy=py+72
  for _,key in ipairs(City.GATEWAYS) do
    local spec=City.HAVENS[key]
    local held=0
    for _,n in ipairs(city.g:nodesOfKind("terminal")) do if n.haven==key then held=held+1 end end
    row(spec.name,held>0 and (held.." open") or ("$"..city:havenCost(key)),hy,
      held>0 and P.good or P.energy,
      spec.blurb..". Freight through it costs x"..string.format("%.2f",spec.import)..
      " of list. "..(spec.gate=="coast" and "It can only stand within 150m of the coast."
        or "It can stand on any ground you hold.").." Run track inland from it.")
    hy=hy+24
  end
  line(hy+12)

  heading("DEPOSITS",hy+30)
  local free,buried={water=0,oil=0},0
  for _,s in ipairs(city.deposits or {}) do
    if not s.taken and free[s.commodity] then
      free[s.commodity]=free[s.commodity]+1
      if city:obstacleAt(s.x,s.y) then buried=buried+1 end
    end
  end
  row("Water, unclaimed",free.water,hy+60,free.water>0 and P.energy or P.textDim)
  row("Oil, unclaimed",free.oil,hy+86,free.oil>0 and P.energy or P.textDim)
  row("Of those, under obstacles",buried,hy+112,buried>0 and P.warn or P.textDim)
  text("Water and oil can only be taken where the survey marked them: a well or a rig on the mark, and nowhere else. Everything else is landed at a haven. Buried deposits need the matching permit first.",
    M,hy+140,"small",P.textDim,CW)
  UI.contentBottom=hy+210+state.scroll
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
  local w,h = 580,state.reportDetails and 590 or 440
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
  local profit=r.revenue-r.expenses-(r.crewCost or 0)
  text(city.bankrupt and "Company insolvent" or "Day "..r.day.." complete",x+32,y+24,"big")
  text("OPERATING PROFIT",x+32,y+74,"small",P.textDim)
  text(string.format("$%+d",profit),x+32,y+96,"big",profit>=0 and P.good or P.bad)
  text("CASH AVAILABLE",x+310,y+74,"small",P.textDim)
  text("$"..city.money,x+310,y+96,"big",P.energy)
  text(string.format("%d supply shortfalls  /  %d customers lost",r.unhappy,#r.left),
    x+32,y+144,"body",r.unhappy>0 and P.warn or P.good)
  local reward=(r.bonus or 0)+(r.tender or 0)
  if reward>0 then
    lg.setColor(P.with(P.good,0.12)); lg.rectangle("fill",x+24,y+174,w-48,44,5)
    text(r.achievement or ("Municipal award!  +$"..reward),x+32,y+186,"body",P.good,w-64)
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
    button("report-enquiry","New enquiry: view offer",x+290,newsY,258,32,function() act("focusNode",enquiry.id) end,true,nil,false,P.flow)
  else
    button("report-clients","Review customers",x+290,newsY,258,32,function()
      state.modal=nil; state.tab="customers"; state.scroll=0
    end,true,"Review offers, deadlines and tenders")
  end
  local event=r.event or (r.tenderNew and "A new council tender is waiting in Clients.")
  if event then text(event,x+32,y+274,"small",P.energy,w-64) end
  button("report-details",state.reportDetails and "Hide accounting" or "Show accounting",x+32,y+316,w-64,30,
    function() state.reportDetails=not state.reportDetails end,true,"Revenue, expenses, repairs, investments and awards")
  if state.reportDetails then
    local entries={
      {"Revenue",r.revenue},{"Operating costs",-r.expenses},{"Crew repairs",-(r.crewCost or 0)},
      {"Investment profit / loss",r.interest or 0},{"Tenders & grants",reward},{"Bonds forfeited",-(r.tenderLost or 0)},
    }
    for i,v in ipairs(entries) do
      text(v[1],x+32,y+360+(i-1)*24,"small",P.textDim)
      text(string.format("$%+d",v[2]),x+400,y+360+(i-1)*24,"small",v[2]<0 and P.warn or P.good)
    end
    if (r.stored or 0)>0 or (r.drawn or 0)>0 or (r.crewFixed or 0)>0 then
      text(string.format("Crews fixed %d mains / Depots: %d stored, %d drawn",r.crewFixed or 0,r.stored or 0,r.drawn or 0),
        x+32,y+502,"small",P.textDim,w-64)
    end
  end
  if city.bankrupt then
    button("new-company","Companies",x+32,y+h-66,w-64,38,function() act("openSlots") end,
      true,"Start again here, or open one of your other companies")
  else
    button("continue","Open day "..city.day,x+32,y+h-66,w-64,38,function() state.modal=nil end,true,"Return to the network")
  end
end

--------------------------------------------------------------------------------

local function goals()
  local y=TOP-state.scroll
  heading("WHAT WILL YOUR COMPANY BECOME?",y)
  text("Choose an ambition. Progress is kept when you switch; each grant can be earned once.",M,y+26,"small",P.textDim,CW)
  y=y+80
  for _,a in ipairs(E.ambitions) do
    local done=city.ambitionsDone and city.ambitionsDone[a.id]
    local value=math.min(a.target,E.progress(city,a))
    text(a.name,M,y,"mid",done and P.good or P.text)
    text(a.description,M,y+28,"small",P.textDim,CW)
    lg.setColor(P.panelEdge); lg.rectangle("fill",M,y+67,CW,5,2)
    lg.setColor(P.good); lg.rectangle("fill",M,y+67,CW*value/a.target,5,2)
    text(done and "ACHIEVED" or (value.." / "..a.target),M,y+80,"small",P.good)
    button("ambition-"..a.id,done and "Grant earned" or city.ambition==a.id and "Pursuing" or ("Choose  +$"..a.reward),
      M+150,y+78,150,30,function() act("chooseAmbition",a.id) end,not done,nil,city.ambition==a.id,P.good)
    y=y+132
  end
  heading("MUNICIPAL MILESTONES",y); y=y+30
  for i,m in ipairs(City.MILESTONES) do
    row(m.name,city.milestones[i] and "Earned" or (m.target.." clients / $"..m.reward),y,city.milestones[i] and P.good or P.textDim)
    y=y+30
  end
  UI.contentBottom=y+state.scroll+20
end

local TABS={{"network","Build"},{"finance","Company"},{"customers","Clients"},{"map","Map"},{"ambitions","Goals"},{"ledger","Log"}}

function UI.draw(c,s,action)
  city,state,act=c,s,action
  W,H=R.dimensions()
  UI.buttons={}; scroll=false
  lg.setColor(P.panel); lg.rectangle("fill",0,0,UI.width,H)
  lg.rectangle("fill",UI.width,0,W-UI.width,80)
  lg.setColor(P.panelEdge); lg.line(UI.width,0,UI.width,H); lg.line(0,80,W,80)
  text("NET PROFIT",M,17,"big")
  single(E.companyName(city),M+1,55,"small",P.textDim,CW)

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

  local tabX=8
  for i,t in ipairs(TABS) do
    local tabWidth=({50,70,54,42,51,41})[i]
    button("tab-"..t[1],t[2],tabX,103,tabWidth,34,function()
      state.rename=nil
      state.tab=t[1]; state.scroll=0
      -- The Map tab is a map: opening it pulls the camera back to show the
      -- whole city, so the ground being priced is the ground being looked at.
      if t[1]=="map" then act("fitWorld") end
    end,true,nil,state.tab==t[1])
    tabX=tabX+tabWidth+4
  end

  lg.setScissor(0,160,UI.width-1,H-222); scroll=true
  if state.tab=="network" then network()
  elseif state.tab=="finance" then company()
  elseif state.tab=="customers" then customers()
  elseif state.tab=="map" then mapTab()
  elseif state.tab=="ambitions" then goals()
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
    local ambition
    for _,a in ipairs(E.ambitions) do
      if a.id==city.ambition and not (city.ambitionsDone and city.ambitionsDone[a.id]) then ambition=a end
    end
    if ambition then
      text(ambition.name.."   "..E.progress(city,ambition).." / "..ambition.target,bx,97,"body",P.text)
      text("$"..ambition.reward.." grant",W-170,97,"small",P.energy)
    elseif milestone then
      local count=#city:clientList()-city.unserved
      text(milestone.name.."   "..count.." / "..milestone.target.." supplied",bx,97,"body",P.text)
      text("$"..milestone.reward.." grant",math.max(720,W-170),97,"small",P.energy)
    elseif city.event then
      text(city.event.head,bx,97,"body",city.event.rate>1 and P.good or P.warn)
    else
      text("UTILITY EMPIRE   /   "..#city:ownedDistricts().." districts held",bx,97,"body",P.good)
    end
  end

  -- Map tools stay available while an inspector or a long list is open.
  for i,name in ipairs({"all","water","power","beer","oil"}) do
    button("filter-"..name,name=="all" and "All trades" or name:sub(1,1):upper()..name:sub(2),
      UI.width+16+(i-1)*77,138,72,28,function() state.filter=name~="all" and name or nil end,
      true,"Filter visible utility lines and customers",(state.filter or "all")==name,
      name=="all" and P.flow or Graph.COMMODITIES[name].color)
  end
  button("bottlenecks","Supply overlay",UI.width+409,138,130,28,function() state.bottlenecks=not state.bottlenecks end,
    true,"Amber: damaged or full mains. Blue: a route from the selected customer to supply; alternate routes may exist.",state.bottlenecks,P.warn)
  button("quick-build","Build tools",W-151,138,130,28,function()
    state.node,state.edge,state.tool=nil,nil,nil; state.tab="network"; state.scroll=0
  end,true,"Return to construction without moving the map")
  if state.bottlenecks then
    text("AMBER: FULL / DAMAGED     BLUE: SELECTED ROUTE",UI.width+20,177,"tiny",P.warn)
  end
  if city.day<=2 and not city.guideDismissed and not state.modal and state.tab=="network" and
    (city.day==1 or (not state.node and not state.edge)) then
    local gx,gy,gw=UI.width+20,H-173,math.min(570,W-UI.width-40)
    lg.setColor(P.panel); lg.rectangle("fill",gx,gy,gw,100,8)
    lg.setColor(P.with(P.good,0.55)); lg.rectangle("line",gx,gy,gw,100,8)
    local count=#city:clientList()-city.unserved
    local title=city.day>1 and "Your company is open for business" or count==0 and "1 / 3   Make your first connection"
      or city.unserved>0 and "2 / 3   Bring the next house online" or "3 / 3   Everyone supplied!"
    text(title,gx+16,gy+12,"mid",P.good)
    local hint=city.day>1 and "Watch for enquiries in Clients. Choose your next ambition in Goals."
      or city.unserved>0 and "Drag from the glowing well to a house. Each connection earns income every day."
      or "Close the day to collect income and your first municipal grant."
    text(hint,gx+16,gy+43,"body",P.text,gw-92)
    button("dismiss-guide","Got it",gx+gw-72,gy+62,60,26,function() act("dismissGuide") end,true,"Dismiss this introduction")
  end

  lg.setColor(P.panel); lg.rectangle("fill",0,H-58,W,58)
  lg.setColor(P.panelEdge); lg.line(0,H-58,W,H-58)
  button("undo","Undo",10,H-44,52,32,function() act("undo") end,#state.undo>0,"Undo last decision (Z); day closes are final")
  button("fit","Fit",68,H-44,44,32,function() act("fit") end,true,"Fit the network (F)")
  button("mute",state.muted and "Muted" or "Sound",118,H-44,58,32,function() act("mute") end,true,"Toggle sound (M)")
  button("companies","Companies",184,H-44,142,32,
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
