local City = require("city")
local Camera = require("camera")
local Save = require("company_save")
local Draw = require("company_render")
local E = require("experience")
local UI = require("company_ui")
local R = require("render")
local A = require("audio")
local P = require("palette")
local Audit = require("layout_audit")
local Graph = require("graph")
local App = {}
local city,cam
local state={commodity="water",havenKind="port",plant="nuclear",recipe="turbine",size="small",recentSizes={"small"},grade=1,capacity=1,invest=100,borrow=500,tab="network",scroll=0,undo={}}
local testMode, frames = nil,0
local walkthroughRunning=false
local saveBlocked=false

local function toast(message,bad)
  state.toast,state.toastBad,state.toastTime=tostring(message),bad,5
  state.toastChoke=nil
end

local function save()
  if testMode then return true end
  if saveBlocked then
    toast("Save damaged: pick another slot",true)
    return nil
  end
  local ok,err=Save.write(city)
  if not ok then toast("Save failed: "..tostring(err),true) end
  return ok
end

-- The map is the whole window under the top bar. Menus open over its left
-- edge rather than pushing it aside, so opening one never moves the city.
local function layout()
  local w,h=R.dimensions()
  local top=UI.BAR*UI.effectiveScale()
  cam:setViewport(0,top,w,h-top)
end

-- Centre on a point in the part of the map a menu is not covering.
local function centerOn(x,y)
  if UI.drawerOpen(state) then x=x-(UI.width*UI.effectiveScale()/2)/cam.targetScale end
  -- Automated runs cut straight there: a check or a screenshot taken right
  -- after the action must see the camera where it was sent.
  if testMode then cam:centerOn(x,y) else cam:glideTo(x,y) end
end

-- The player's own preferences, kept apart from any company: the text size,
-- whether hints are shown, and whether the sound is on.
local SETTINGS_FILE="settings.lua"
local function saveSettings()
  if testMode or not (love.filesystem and love.filesystem.write) then return end
  love.filesystem.write(SETTINGS_FILE,string.format("return {ui=%.2f,hints=%s,muted=%s,minimap=%s}",
    UI.pref or 1.2,state.hintsChosen and tostring(state.buildHelp and true or false) or "nil",tostring(state.muted and true or false),
    tostring(state.minimap and true or false)))
end
local function loadSettings()
  if testMode or not (love.filesystem and love.filesystem.getInfo) or not love.filesystem.getInfo(SETTINGS_FILE) then return end
  local chunk=load(love.filesystem.read(SETTINGS_FILE) or "","settings","t",{})
  local ok,t=pcall(chunk or function() end)
  if ok and type(t)=="table" then
    if type(t.ui)=="number" then UI.pref=math.max(1,math.min(1.6,t.ui)) end
    state.buildHelp=t.hints==true
    state.hintsChosen=type(t.hints)=="boolean"
    if t.muted==true then state.muted=true; A.setEnabled(false) end
    state.minimap=t.minimap==true
  end
end

-- Pull back far enough to see every district, bought or not.
local function fitWorld()
  layout()
  -- Frame what the company holds plus the ground it could buy next, not every
  -- cell that has ever been surveyed. On an endless map those are very
  -- different numbers, and only one of them fits on a screen.
  local x0,y0,x1,y1=city:ownedBounds()
  local margin=City.MAP.w*0.8
  x0,y0,x1,y1=x0-margin,y0-margin,x1+margin,y1+margin
  local covered=UI.drawerOpen(state) and UI.width*UI.effectiveScale() or 0
  cam.scale=math.max(0.12,math.min(1.45,(cam.vw-covered)/(x1-x0),cam.vh/(y1-y0)))
  cam.targetScale=cam.scale
  cam.glide=nil; cam.x,cam.y=(x0+x1)/2-covered/2/cam.scale,(y0+y1)/2
end

local function fit()
  layout()
  local x0,y0,x1,y1=city.firstSource.x,city.firstSource.y,city.firstSource.x,city.firstSource.y
  for _,n in ipairs(city.g:aliveNodes()) do
    x0,y0,x1,y1=math.min(x0,n.x),math.min(y0,n.y),math.max(x1,n.x),math.max(y1,n.y)
  end
  local covered=UI.drawerOpen(state) and UI.width*UI.effectiveScale() or 0
  cam.scale=math.max(0.3,math.min(1.45,(cam.vw-covered)/(x1-x0+330),cam.vh/(y1-y0+330)))
  cam.targetScale=cam.scale
  cam.glide=nil; cam.x,cam.y=(x0+x1)/2-covered/2/cam.scale,(y0+y1)/2
end

local function clear()
  state.node,state.edge,state.tool,state.drag,state.pan=nil,nil,nil,nil,nil
  state.link=nil
  state.district=nil
  state.rename=nil; state.renameSelectAll=nil
end

-- Everything that belongs to the company being played rather than to the
-- player, reset when a different company is opened.
local function resetSession()
  clear()
  state.flashEdge=nil
  state.undo={}
  state.modal,state.slotConfirm=nil,nil
  state.scroll=0
  state.tab="network"
  state.commodity="water"; state.people=nil
  state.capacity=1; state.size="small"; state.recentSizes={"small"}
  state.borrow=500
  state.invest=100
  state.rail=nil; state.transit=nil
  state.filter=nil; state.spof=nil; state.advisorFocus=nil; state.job=nil; state.rename=nil; state.lineOptions=nil; state.jump=nil
end

-- Putting a different trade in hand. Used when the structures being joined
-- only accept one, so the panel, the preview and the main that gets laid all
-- agree without the player having to go back and press the trade first.
local function setTrade(key)
  if not key or key==state.commodity then return end
  state.commodity=key
  state.people=nil
  -- Electricity and fibre have no bulk mode: nothing is landed at a haven.
  if Graph.formOf(key)=="energy" or Graph.formOf(key)=="data" then state.rail=nil end
  state.filter=nil
  toast(string.upper(key).." selected")
end

-- Selecting anything on the map is a question, and the sidebar is the answer.
-- Rather than leaving the player on whichever tab they happened to be reading,
-- every selection opens the tab that can act on it and scrolls straight to the
-- controls -- so clicking a burst main lands on its Repair button.
local function reveal()
  state.tab="network"; state.scroll=UI.revealInspector()
end

-- Clicking ground: a plot for sale asks once whether to buy it, a wood or a
-- range on owned ground asks once whether to clear it. There is no land menu.
local function askAboutGround(id,wx,wy)
  local d=city.districts[id]
  if not d then return false end
  if not d.owned then
    state.district=id; state.landId=id; state.modal="land"
    return true
  end
  if wx then
    for i,o in ipairs(city.obstacles) do
      if (o.kind=="park" or o.kind=="bedrock") and city:obstacleAt(wx,wy)==o and city:districtAt(o.x,o.y)==d then
        state.terrainId=i; state.modal="terrain"
        return true
      end
    end
  end
  return false
end

-- A test run must not read, show or touch the player's real companies, so the
-- harness gets a fabricated set of slots to drive the picker with.
local function slotSummaries()
  if not testMode then return Save.summaries() end
  local t={}
  for i=1,Save.SLOTS do
    t[i]=(i==1)
      and {slot=1,empty=false,day=3,money=400,clients=2,worth=900,districts=1,trades={"water"}}
      or {slot=i,empty=true}
  end
  return t
end

local function action(name,...)
  if name=="fit" then fit(); return end
  if name=="fitWorld" then fitWorld(); return end
  if name=="lookAt" then local x,y=...; centerOn(x,y); return end
  if name=="minimap" then state.minimap=not state.minimap; saveSettings(); return end
  if name=="mute" then state.muted=not state.muted; A.setEnabled(not state.muted); saveSettings(); return end
  if name=="uiScale" then UI.pref=...; saveSettings(); layout(); return end
  if name=="hints" then state.buildHelp=not state.buildHelp; state.hintsChosen=true; saveSettings(); return end
  if name=="solo" then city.hideUnfocusedNetworks=not city.hideUnfocusedNetworks; return end
  if name=="focusNode" then
    local id=...
    local n=city.g.nodes[id]
    clear(); state.filter=nil; state.modal=nil; state.node=id; reveal()
    centerOn(n.x,n.y)
    return
  end
  -- The header's one request control. The contract opens, the house it is
  -- about sits under the pointer, and the map comes in closer than it was: a
  -- request is about one building, so the view should be about one building.
  -- From the Clients window: the map goes to the customer, the window stays,
  -- so the next offer can be answered straight after.
  -- `openClient` does the same and opens the customer's own panel: a click on
  -- a customer in the Clients window goes to that customer.
  if name=="showClient" or name=="openClient" then
    local id=...
    local n=city.g.nodes[id]
    if not n then return end
    clear(); state.filter=nil; state.node=id
    if name=="openClient" then reveal() end
    -- Zoom first, then centre: the offset for the panel depends on the scale.
    cam.targetScale=math.max(cam.targetScale or cam.scale,1.35)
    centerOn(n.x,n.y)
    return
  end
  if name=="focusRequest" then
    local id=...
    local n=city.g.nodes[id]
    if not n then return end
    clear(); state.filter=nil; state.modal=nil; state.node=id; reveal()
    -- Zoom first, then centre: the offset for the open panel depends on the
    -- scale, so centring at the old scale left the house off to one side.
    cam.targetScale=1.35
    centerOn(n.x,n.y)
    return
  end
  if name=="focusEdge" then
    local id=...
    local e=city.g.edges[id]
    local a,b=city.g.nodes[e.a],city.g.nodes[e.b]
    clear(); state.filter=nil; state.modal=nil; state.edge=id; reveal()
    centerOn((a.x+b.x)/2,(a.y+b.y)/2)
    return
  end
  if name=="focusLink" then
    local id=...
    local l=city.links[id]
    local a,b=city.g.nodes[l.a],city.g.nodes[l.b]
    clear(); state.filter=nil; state.modal=nil; state.link=id; reveal()
    centerOn((a.x+b.x)/2,(a.y+b.y)/2)
    return
  end
  if name=="focusDistrict" then
    local id=...
    local d=city.districts[id]
    clear()
    if d then centerOn(d.x+d.w/2,d.y+d.h/2); askAboutGround(id) end
    return
  end
  if name=="nextLeak" then
    local worst
    for _,pipe in ipairs(city.g.edges) do
      if pipe.alive and pipe.leaking and (not worst or pipe.cap<worst.cap) then worst=pipe end
    end
    if worst then action("focusEdge",worst.id) else toast("No leaking mains") end
    return
  end
  -- Six companies. Leaving one always saves it first: switching away should
  -- never be a way to lose a day's work.
  if name=="openSlots" then
    state.rename=nil
    save()
    state.modal="slots"; state.slotConfirm=nil
    state.slots=slotSummaries()
    return
  end
  if name=="loadSlot" then
    local slot=...
    if slot==(city.slot or 1) then state.modal=nil; return end
    if testMode then state.modal=nil; return end
    if not saveBlocked and not save() then return end
    local loaded,err=Save.read(slot)
    if not loaded then toast(err or "That company could not be opened",true); return end
    city=loaded
    saveBlocked=false
    resetSession(); Save.writeCurrent(slot)
    fit(); toast("Company "..slot.." opened")
    return
  end
  if name=="newSlot" then
    local slot=...
    if not Save.validSlot(slot) then toast("No such company slot",true); return end
    if not saveBlocked and not save() then return end
    if not testMode then
      local info=Save.summarize(slot)
      if info.error then toast("Damaged save: pick an empty slot",true); return end
    end
    local fresh=City.new(); fresh.slot=slot
    if not testMode then
      local ok,err=Save.writeSlot(fresh,slot)
      if not ok then toast("Save failed: "..tostring(err),true); return end
    end
    city=fresh; saveBlocked=false
    resetSession()
    fit(); toast("New company in slot "..slot)
    return
  end
  if name=="deleteSlot" then
    local slot=...
    if not testMode then Save.deleteSlot(slot) end
    state.slotConfirm=nil
    if slot==(city.slot or 1) then
      city=City.new(); city.slot=slot
      clear(); state.undo={}; state.scroll=0; state.tab="network"
      if not testMode then Save.writeSlot(city,slot) end
      fit()
    end
    state.slots=slotSummaries()
    toast("Company "..slot.." deleted")
    return
  end
  if name=="restart" then
    if saveBlocked then save(); return end
    return action("newSlot",city.slot or 1)
  end
  if name=="undo" then
    local snap=table.remove(state.undo)
    if snap then city=assert(Save.unpack(snap)); clear(); save(); toast("Decision undone") end
    return
  end
  -- A resilience check changes nothing in the company, so it is neither an
  -- undoable decision nor a reason to write the save.
  if name=="assessResilience" then city:assessResilience(); return true end
  if name=="startResilience" then state.job=city:startResilience(); return true end
  if city.bankrupt then return end
  local snapshot=Save.pack(city)
  local result,err
  -- What each customer is about to pay, so the close can show it landing.
  local paying,wasOpen
  -- Mains that exist before the action, so any laid by it (by hand, or by a
  -- distribution hub at the close) can be traced into the ground after.
  local edgesBefore=#city.g.edges
  local milestonesBefore={}
  for i in pairs(city.milestones or {}) do milestonesBefore[i]=true end
  if name=="endDay" then
    wasOpen={}
    for key in pairs(City.UNLOCKS) do wasOpen[key]=city:unlocked(key) end
    wasOpen.tools={}
    for _,t in ipairs(City.PROGRESSION.TOOL_UNLOCK) do wasOpen.tools[t.tool]=city:toolOpen(t.tool) end
    paying={}
    for _,c in ipairs(city:clientList()) do
      local v=city:clientIncome(c)
      local missed=math.max(0,city:clientIncome(c,true)-v)
      if v>0 or missed>0 then paying[#paying+1]={x=c.x,y=c.y,v=v,missed=missed} end
    end
  end
  result,err=city[name](city,...)
  if not result then toast(err or "Action unavailable",true); A.play("denied"); return nil end
  -- Every main that came into being, drawn in with a pulse from end to end.
  do
    local fresh=0
    for id=edgesBefore+1,#city.g.edges do
      local e=city.g.edges[id]
      local a,b=e and city.g.nodes[e.a],e and city.g.nodes[e.b]
      if e and e.alive and a and b and fresh<40 then
        fresh=fresh+1
        R.trace(a.x,a.y,b.x,b.y,(Graph.COMMODITIES[e.commodity] or {}).color or P.flow,name=="endDay" and 0.5+fresh*0.05 or 0)
      end
    end
    if name=="replacePipe" or name=="upgradePipe" then
      local e=city.g.edges[...]
      local a,b=e and city.g.nodes[e.a],e and city.g.nodes[e.b]
      if a and b then R.trace(a.x,a.y,b.x,b.y,(Graph.COMMODITIES[e.commodity] or {}).color or P.flow) end
    end
  end
  -- A milestone reached gets its banner.
  for i,m in ipairs(City.MILESTONES) do
    if (city.milestones or {})[i] and not milestonesBefore[i] then
      state.banner={title=m.name,sub="+$"..m.reward,t=R.t}
      A.play("unlock",0.9)
    end
  end
  if name=="endDay" and result.loyal then
    for i,l in ipairs(result.loyal) do
      if i>20 then break end
      R.floatText(l.x,l.y-52,"Loyal +$"..City.LOYALTY.step,P.energy,1+i*0.05)
      R.ring(l.x,l.y,P.energy)
    end
  end
  if name=="endDay" and result.referred then
    for i,f in ipairs(result.referred) do
      local n=city.g.nodes[f.id]
      if n then R.floatText(n.x,n.y-52,"Referral",P.good,1.2+i*0.05); R.ring(n.x,n.y,P.good) end
    end
  end
  if name=="endDay" and result.grew then
    for i,g in ipairs(result.grew) do
      if i>20 then break end
      R.floatText(g.x,g.y-52,"Wants +1",P.flow,1.1+i*0.05)
    end
  end
  if name=="endDay" and result.achievement then
    state.banner={title=result.achievement,t=R.t}
  end
  -- The market and the weather are news, not a line in a log.
  if name=="endDay" and not state.banner and (result.shock or result.event) then
    state.banner={title=result.shock or result.event,t=R.t,warn=result.shock~=nil}
  end
  if name=="endDay" then
    state.undo={}; clear(); state.rename=nil; state.modal=city.bankrupt and "report" or nil; state.reportDetails=false
    state.dusk=R.t
    local profit=(result.revenue or 0)-(result.expenses or 0)-(result.crewCost or 0)
    local opened={}
    for key,spec in pairs(City.UNLOCKS) do
      if not wasOpen[key] and city:unlocked(key) then opened[#opened+1]=spec.name end
    end
    -- A tool that opened today: named in the toast, and its tile pulses.
    for _,t in ipairs(City.PROGRESSION.TOOL_UNLOCK) do
      if not wasOpen.tools[t.tool] and city:toolOpen(t.tool) then
        opened[#opened+1]=t.name
        state.newTiles=state.newTiles or {}
        state.newTiles["tool-"..t.tool]=true
        if not state.banner then state.banner={title="New: "..t.name,t=R.t} end
      end
    end
    table.sort(opened)
    -- What the chokes cost today, and a click away from the worst of them.
    local missed=0
    for _,p in ipairs(paying) do missed=missed+p.missed end
    missed=math.floor(missed+0.5)
    toast("Day "..(city.day-1)..": "..City.signed(profit)..
      (missed>0 and ("   -$"..missed.." short") or "")..
      (#opened>0 and ("  New: "..table.concat(opened,", ")) or ""),profit<0)
    if #opened>0 then state.toastTime=9; A.play("unlock",0.7) end
    local edges,nodes=city:chokes()
    local worst,most=nil,0
    for id,n in pairs(edges) do if n>most or (n==most and worst and worst.edge and id<worst.edge) then worst,most={edge=id},n end end
    for id,n in pairs(nodes) do if n>most then worst,most={node=id},n end end
    if worst and missed>0 then state.toastChoke=worst; state.toastTime=9 end
    table.sort(paying,function(p,q) return p.x+p.y<q.x+q.y end)
    for i,p in ipairs(paying) do
      if i>60 then break end
      local delay=math.min(0.9,i*0.035)
      if p.v>0 then
        R.floatText(p.x,p.y-26,"+$"..p.v,P.good,delay)
        -- A coin leaves the customer for the cash counter.
        if i<=40 then
          state.coins=state.coins or {}
          table.insert(state.coins,{wx=p.x,wy=p.y,t0=R.t+delay+0.25,seed=i})
        end
      end
      -- What a short customer did not pay, so the problem is on the map.
      if p.missed>0 then R.floatText(p.x,p.y+(p.v>0 and 4 or -26),"-$"..p.missed,P.warn,delay+0.1) end
      -- A tick per landing, rising, so a good day sounds like one.
      if i<=14 then state.sfx=state.sfx or {}; table.insert(state.sfx,{t=delay,pitch=0.85+i*0.035}) end
    end
    for _,leak in ipairs(result.leaks) do R.ring(leak.x,leak.y,P.bad) end
    if result.arrived then R.ring(result.arrived.x,result.arrived.y,P.energy) end
    A.play(city.bankrupt and "collapse" or "held")
  else
    state.undo[#state.undo+1]=snapshot
    if #state.undo>30 then table.remove(state.undo,1) end
    if name=="layPipe" then
      state.edge=result.id; state.node=nil; A.play("link")
      for _,n in ipairs(city:clientList()) do
        if city:fullyServed(n) then R.ring(n.x,n.y,P.good) end
      end
    elseif name=="layLink" or name=="drawRoad" then
      state.link=result.id; state.node=nil; state.edge=nil; A.play("link")
    elseif name=="buildShop" then
      state.node=result.id; state.edge=nil; state.tool=nil; state.shop=nil
      R.ring(result.x,result.y,P.good); A.play("place")
    elseif name=="buildBench" then
      R.ring(result.x,result.y,P.good); A.play("place")
    elseif name=="buildProject" then
      state.node=result.id; state.edge=nil; state.tool=nil; state.project=nil
      R.ring(result.x,result.y,P.good); R.burst(result.x,result.y,P.energy,30); A.play("unlock",0.8)
    elseif name=="build" or name=="buySource" or name=="placeJunction" then
      state.node=result.id; state.edge=nil; state.tool=nil; R.ring(result.x,result.y,P.good); A.play("place")
    elseif name=="buyDistrict" then
      state.district=nil; R.ring(result.x+result.w/2,result.y+result.h/2,P.good); A.play("place")
    else A.play("upgrade") end
    if name=="buildProject" then
      toast(City.CLIENTS[result.clientType].name.." built")
    elseif name=="repairAll" then
      toast(result.fixed.." main"..(result.fixed==1 and "" or "s").." repaired for $"..result.spent)
    elseif name=="buyDistrict" then
      toast(result.name.." acquired")
    elseif name=="upgradeLevel" and result.kind and city:levelName(result) then
      local run=result.lastRun
      toast(city:levelName(result).." ready"..(run and string.format(": %d signed, %d connected, %d widened",
        run.signed,run.wired,run.widened) or ""))
      R.ring(result.x,result.y,P.good); R.burst(result.x,result.y,P.energy,26)
    elseif name=="setHubFloor" then
      toast("Minimum price $"..city:hubFloor(result).." a unit")
    elseif name=="layPipe" then
      toast(city.unserved==0 and "Everyone supplied" or "Connected")
    else
      toast(({repairPipe="Pipe repaired",replacePipe="Main replaced",buyAds="Advertising booked",
        invest="Investment placed",upgradeQuality="Better pipe unlocked",buyLicence="Trade licence acquired",
        acceptClient="Customer signed",declineClient="Offer declined",upgradeSource="Well deepened",
        buildShop="Shop opened",buildBench="Bench placed",expandShop="Shop expanded",setShopPrice="Price set",
        hireCrew="Crew hired",dismissCrew="Crew stood down",declineCrew="No crew",buyPermit="Permit granted",
        borrow="Funds drawn",repay="Loan repaid",setGate="Gate set",
        layLink=(name=="layLink" and result.mode=="road") and (result.roadType=="bridge" and "Bridge built" or "Road laid") or "Route opened",
        drawRoad=(name=="drawRoad" and result.roadType=="bridge") and "Road and bridge laid" or "Road laid",
        orderImport="Ordered: lands tomorrow",
        setImportYard=(name=="setImportYard" and result.importYard) and ("Orders go to yard "..result.importYard) or "Orders go to the nearest yard",
        setLinkPrice="Price set",setStationPrice="Pump price set",
        addVehicle="Vehicle added",removeVehicle="Vehicle sold",demolishLink="Line lifted",
        upgradeResort="Resort built up",upgradeTower="Tower upgraded",raiseTowerVoltage="Voltage raised",upgradeCable="Cable upgraded",upgradeLevel="Building upgraded"})[name] or "Network updated")
    end
  end
  save()
  return result
end

local function pointDistance(x,y,ax,ay,bx,by)
  local dx,dy=bx-ax,by-ay
  local t=math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy)/math.max(1,dx*dx+dy*dy)))
  return math.sqrt((x-ax-t*dx)^2+(y-ay-t*dy)^2)
end

local function hit(x,y)
  if UI.covers(x,y) then return nil,nil end
  for _,n in ipairs(city.g:aliveNodes()) do
    local sx,sy=cam:toScreen(n.x,n.y)
    if (not state.filter or not n.commodity or n.commodity==state.filter or (n.demands and n.demands[state.filter])) and
      (sx-x)^2+(sy-y)^2<math.max(13,R.sym(25,cam.scale))^2 then return n.id,nil end
  end
  local nearest,dist=nil,10
  for _,e in ipairs(city.g.edges) do
    if e.alive and (not state.filter or e.commodity==state.filter) then
      local pts=Draw.edgePath(cam,city,e)
      for i=1,#pts-3,2 do
        local d=pointDistance(x,y,pts[i],pts[i+1],pts[i+2],pts[i+3])
        if d<dist then nearest,dist=e.id,d end
      end
    end
  end
  if nearest or state.filter then return nil,nearest,nil end
  local link,linkDist=nil,10
  for _,l in ipairs(city.links or {}) do
    if l.alive and l.mode=="road" then
      -- A road is as wide as it is drawn, and follows its own curves.
      local wx,wy=cam:toWorld(x,y)
      local d,half=require("road_shape").distanceTo(city,l,wx,wy)
      if d then
        d=math.max(0,d-half)*cam.scale
        if d<linkDist then link,linkDist=l.id,d end
      end
    elseif l.alive and l.mode~="bus" then
      local ax,ay,bx,by=Draw.linkPoints(cam,city,l)
      local d=pointDistance(x,y,ax,ay,bx,by)
      if d<linkDist then link,linkDist=l.id,d end
    end
  end
  return nil,nil,link
end

function love.load(args)
  local audit=false
  for _,a in ipairs(args or {}) do
    if a=="--smoke" or a=="--soak" or a=="--shot" or a=="--tut" or a=="--audio"
       or a=="--probe" then testMode=a end
    if a=="--audit" then audit=true end
  end
  R.init(); A.init()
  -- After R.init, so the recorder wraps the symbol-aware print rather than
  -- being wrapped by it.
  if audit then Audit.enable(true) end
  if love.window and love.window.setIcon and love.image then love.window.setIcon(love.image.newImageData("assets/net-profit.png")) end
  -- Reports where this build keeps its company and what it found there, then
  -- quits. The one question that is genuinely hard to answer any other way,
  -- because the answer depends on how the game was launched.
  if testMode=="--probe" then
    print("save directory: "..love.filesystem.getSaveDirectory())
    print("fused:          "..tostring(love.filesystem.isFused()))
    for _,dir in ipairs(Save.candidates()) do print("candidate:      "..dir) end
    print("current slot:   "..Save.readCurrent())
    for slot=1,Save.SLOTS do
      local loaded=Save.readSlot(slot)
      if loaded then
        print(string.format("  slot %d:       day %d, $%d, %d structures%s",slot,
          loaded.day,loaded.money,#loaded.g:aliveNodes(),
          loaded.adoptedFrom and ("  (carried over from "..loaded.adoptedFrom..")") or ""))
      else
        print(string.format("  slot %d:       empty",slot))
      end
    end
    love.event.quit()
    return
  end
  -- Keep the harness off the user's screen: offscreen, minimised and silent.
  loadSettings()
  if testMode then
    -- The tests click through the menus as they were drawn at one scale with
    -- the drawer open; they do not also have to open it.
    UI.pref=1
    state.drawer=true
    state.foldAll=true
    A.setEnabled(false)
    state.muted = true
    pcall(love.window.setPosition, -5000, -5000)
    pcall(love.window.minimize)
  end
  local err
  if not testMode then city,err=Save.read() end
  city=city or City.new(testMode and {seed=24,obstacles=4} or nil)
  city.slot=city.slot or (testMode and 1 or Save.readCurrent())
  cam=Camera.new(city.bounds.w,city.bounds.h); cam:follow(city.bounds); fit()
  UI.camera=cam
  if err then
    saveBlocked=true
    toast("Save damaged: pick another slot",true)
    state.modal="slots"; state.slots=slotSummaries()
  end
  if city.bankrupt then state.modal="report" end
  if testMode=="--audio" then
    local report=A.report()
    assert(#report>0,"no audio generated")
    for _,sound in ipairs(report) do
      assert(sound.peak>0 and sound.peak<1 and sound.rms>0,"silent or clipped sound: "..sound.name)
      print(string.format("%s: peak %.3f, RMS %.3f",sound.name,sound.peak,sound.rms))
    end
    print(#report.." sounds checked")
    love.event.quit()
    return
  end
  App.state,App.action,App.hit=state,action,hit
  App.city=function() return city end
  App.camera=function() return cam end
  App.setTestCity=function(value)
    assert(testMode,"test cities are only available in isolated test runs")
    city=value; resetSession(); fit()
  end
end

local Magnify=require("magnify")

function love.update(dt)
  R.update(dt); layout(); cam:update(dt)
  -- A trackpad pinch since the last frame, about the pointer, and two
  -- fingers' exact movement: the map follows them point for point, the
  -- sidebar scrolls, and with Cmd held they zoom.
  do
    local m=Magnify.take()
    local sx,sy=Magnify.scroll()
    if not state.modal then
      local mx,my=love.mouse.getPosition()
      if m~=0 and not UI.covers(mx,my) then cam:zoomAt(mx,my,m/0.16) end
      if sx~=0 or sy~=0 then
        if UI.overDrawer(mx,my) then state.scroll=math.max(0,math.min(UI.maxScroll or 0,state.scroll-sy))
        elseif UI.covers(mx,my) then
        elseif love.keyboard.isDown("lgui","rgui","lctrl","rctrl") then cam:zoomAt(mx,my,sy*0.02)
        else cam:pan(sx,sy) end
      end
    end
  end
  -- The map pans under WASD or the arrow keys, faster with shift held.
  if not state.rename and not state.modal and love.keyboard then
    local kd=love.keyboard.isDown
    local dx=(kd("a","left") and 1 or 0)-(kd("d","right") and 1 or 0)
    local dy=(kd("w","up") and 1 or 0)-(kd("s","down") and 1 or 0)
    if dx~=0 or dy~=0 then
      local speed=(kd("lshift","rshift") and 1500 or 700)*dt
      cam:pan(dx*speed,dy*speed)
    end
  end
  -- Sounds booked for a moment from now, like the ticks of a day landing.
  if state.sfx then
    for i=#state.sfx,1,-1 do
      local s=state.sfx[i]
      s.t=s.t-dt
      if s.t<=0 then A.play("click",0.35,s.pitch); table.remove(state.sfx,i) end
    end
    if #state.sfx==0 then state.sfx=nil end
  end
  if state.flashTime then
    state.flashTime=state.flashTime-dt
    if state.flashTime<=0 then state.flashTime,state.flashEdge=nil,nil end
  end
  state.hoverNode,state.hoverEdge,state.hoverLink=hit(love.mouse.getPosition())
  -- Bare ground under the pointer, for the hover card that says what it is.
  do
    local mx,my=love.mouse.getPosition()
    if state.fakeMouse then local k=UI.scale or 1; mx,my=state.fakeMouse[1]*k,state.fakeMouse[2]*k end
    local bare=not (state.hoverNode or state.hoverEdge or state.hoverLink) and not UI.covers(mx,my)
    state.hoverGround=bare and {cam:toWorld(mx,my)} or nil
  end
  -- Every frame, not only when the mouse moves: whatever is under the cursor
  -- can change under a held drag, and the preview must never quote a size
  -- either end would refuse.
  if state.drag and not state.rail and not state.transit then
    local target=state.hoverNode~=state.drag and state.hoverNode or nil
    -- A cable dragged out of a tower is a cable whatever was selected in the
    -- panel: the trade follows the two structures, and the panel follows it.
    if target then setTrade(E.dragTrade(city,state.drag,target,state)) end
    state.size=E.dragSize(city,state.drag,target,state)
  end
  if state.toastTime then
    state.toastTime=state.toastTime-dt
    if state.toastTime<=0 then state.toast=nil; state.toastBad=nil end
  end
  state.scroll=math.max(0,math.min(state.scroll,UI.maxScroll or 0))
  if testMode and not walkthroughRunning then
    frames=frames+1
    if frames==3 then
      walkthroughRunning=true
      require("company_walkthrough").start(App,testMode)
      walkthroughRunning=false
    end
    if frames>3 then require("company_walkthrough").update(App,testMode,frames,dt) end
  end
end

function love.draw()
  Audit.begin(state.modal and ("modal:"..state.modal) or state.tab)
  love.graphics.clear(P.bg)
  Draw.world(city,cam,state)
  UI.draw(city,state,action)
  Audit.finish()
end

function love.mousepressed(x,y,button,_,presses)
  if button==1 and UI.click(x,y) then return end
  if state.modal then return end
  if UI.covers(x,y) then return end
  -- A double click flies there: to a building, closer in and centred on it;
  -- on open ground, a step closer in on that spot.
  if button==1 and (presses or 1)>=2 and not state.tool then
    local node=hit(x,y)
    local n=node and city.g.nodes[node]
    local wx,wy=cam:toWorld(x,y)
    if n then wx,wy=n.x,n.y end
    cam.targetScale=math.min(2.2,math.max(cam.targetScale*1.6,n and 1.4 or 0))
    centerOn(wx,wy)
    state.pan=nil
    return
  end
  -- With a road in hand, a right-drag draws one: from a building, off the
  -- middle of a road, or out of bare ground. The left button still pans.
  local roadMode=state.people and (state.transit or "road")=="road"
  if button==2 and roadMode and not state.tool then
    local wx,wy=cam:toWorld(x,y)
    state.roadDrag={x=wx,y=wy,sx=x,sy=y}
    return
  end
  -- Right-click puts down whatever is in hand. With nothing in hand, a right
  -- click that does not turn into a pan clears the selection on release.
  if button==2 or button==3 then
    state.pan={x=x,y=y,moved=false,deselect=not state.tool}
    state.tool=nil
    return
  end
  if button~=1 then return end
  if state.tool then
    local wx,wy=cam:toWorld(x,y)
    if state.tool=="source" then action("buySource",state.commodity,wx,wy,state.plant)
    elseif state.tool=="terminal" then action("build",wx,wy,state.tool,state.havenKind or "port")
    elseif state.tool=="works" then action("build",wx,wy,state.tool,state.recipe or "brewery")
    elseif state.tool=="project" then action("buildProject",state.project,wx,wy)
    elseif state.tool=="shop" then action("buildShop",state.shop,wx,wy)
    elseif state.tool=="bench" then action("buildBench",wx,wy)
    elseif City.ROAD_JRANK[state.tool] then action("placeJunction",state.tool,wx,wy)
    else
      local kind=state.tool=="grid" and "pole" or state.tool
      action("build",wx,wy,kind,state.commodity)
    end
    return
  end
  local node,edge,link=hit(x,y)
  if node or edge or link then
    -- Clicking what is already selected puts it down. A structure waits for the
    -- release, because pressing on it is also how a main is dragged out of it.
    if edge and not node and state.edge==edge then state.edge=nil; return end
    if link and state.link==link then state.link=nil; return end
    state.deselect=node and state.node==node and node or nil
    state.node,state.edge,state.link,state.district=node,edge,link,nil
    reveal()
    -- In road mode a press on a building or a road selects it, and a drag
    -- from it pans the camera like a drag anywhere else.
    if roadMode and (node or link) then
      state.rail=nil
      state.pan={x=x,y=y,moved=false}
    elseif node then
      if state.people then state.transit=state.transit or "road"; state.rail=nil end
      state.drag=node
      if not state.rail and not state.transit then
        setTrade(E.dragTrade(city,node,nil,state))
        state.size=E.dragSize(city,node,nil,state)
      end
    end
    return
  end
  -- Empty ground: dragging just pans the camera. A plain click (no drag) on
  -- unowned ground opens the Map tab so it can be bought; owned ground has
  -- nothing left to show, so it only clears the selection.
  local wx,wy=cam:toWorld(x,y)
  local d=city:districtAt(wx,wy)
  state.node,state.edge,state.link,state.district=nil,nil,nil,nil
  state.pan={x=x,y=y,moved=false,district=(d and city:districtVisible(d)) and d.id or nil}
end

function love.mousemoved(x,y,dx,dy)
  state.hoverNode,state.hoverEdge,state.hoverLink=hit(x,y)
  local rd=state.roadDrag
  if rd then
    if not rd.moved and (x-rd.sx)^2+(y-rd.sy)^2>64 then rd.moved=true end
    if rd.moved then
      local wx,wy=cam:toWorld(x,y)
      state.roadPlan=city:roadPlan(rd.x,rd.y,wx,wy,city.buildRoadType)
    end
    return
  end
  if state.pan then
    local p=state.pan
    if p.moved then cam:pan(dx,dy)
    elseif (x-p.x)^2+(y-p.y)^2>16 then p.moved=true; cam:pan(x-p.x,y-p.y) end
  end
end

function love.mousereleased(x,y,button)
  local rd=state.roadDrag
  state.roadDrag,state.roadPlan=nil,nil
  if rd and button==2 then
    if rd.moved then
      local wx,wy=cam:toWorld(x,y)
      -- A highway is laid one stretch at a time; the next road drawn is a
      -- normal one unless Highway is picked again, so a side road across it
      -- never becomes a highway by accident.
      if action("drawRoad",rd.x,rd.y,wx,wy,city.buildRoadType) and city.buildRoadType=="highway" then
        city.buildRoadType="road"
      end
    else
      -- A right click that drew nothing clears the selection, as anywhere.
      state.node,state.edge,state.link,state.district=nil,nil,nil,nil
    end
    state.drag,state.pan,state.deselect=nil,nil,nil
    return
  end
  if state.drag and button==1 then
    local target=hit(x,y)
    if target and target~=state.drag and state.transit then
      action("layLink",state.drag,target,state.transit)
    elseif target and target~=state.drag and not state.people then
      if not state.rail then setTrade(E.dragTrade(city,state.drag,target,state)) end
      local size=not state.rail and E.dragSize(city,state.drag,target,state) or nil
      if size then state.size=size end
      if action("layPipe",state.drag,target,state.commodity,
        state.rail and state.capacity or size,state.rail,
        math.min(city.lining or 1,state.grade or 1)) and size then
        E.useSize(state,size)
      end
    elseif target==state.drag and state.deselect==state.drag then
      state.node=nil
    end
  end
  if state.pan and state.pan.deselect and not state.pan.moved and button~=1 then
    state.node,state.edge,state.link,state.district=nil,nil,nil,nil
  end
  if state.pan and not state.pan.moved and button==1 then
    local wx,wy=cam:toWorld(x,y)
    if state.pan.district and askAboutGround(state.pan.district,wx,wy) then
      -- The question is open over the map.
    else
      -- Ground you already own, or nothing at all: there is nothing to show
      -- for it, so a plain click just goes back to building.
      reveal()
    end
  end
  state.drag,state.pan,state.deselect=nil,nil,nil
end

-- Where the pointer is: the real one, or the one a test run stands in.
local function pointer()
  if state.fakeMouse then local k=UI.scale or 1; return state.fakeMouse[1]*k,state.fakeMouse[2]*k end
  return love.mouse.getPosition()
end

-- On a trackpad two fingers move the map and a pinch zooms it; with Cmd or
-- Ctrl held the wheel zooms too, for a mouse.
function love.wheelmoved(dx,dy)
  if state.modal then return end
  -- A trackpad's scrolling is taken smoothly in love.update instead.
  if Magnify.trackpad() then return end
  local x,y=pointer()
  if UI.overDrawer(x,y) then state.scroll=math.max(0,math.min(UI.maxScroll or 0,state.scroll-dy*42))
  elseif UI.covers(x,y) then return
  elseif love.keyboard.isDown("lgui","rgui","lctrl","rctrl") then cam:zoomAt(x,y,dy)
  else cam:pan(-dx*14,dy*14) end
end

-- A pinch: two fingers on the trackpad drawing apart or together zoom about
-- the pointer. Two fingers moving side by side are a scroll and leave the
-- zoom alone, since the gap between them hardly changes.
local fingers,pinchGap={},nil
local function gap()
  local a,b
  for _,f in pairs(fingers) do if not a then a=f elseif not b then b=f end end
  if not (a and b) then return nil end
  return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
function love.touchpressed(id,x,y) fingers[id]={x=x,y=y}; pinchGap=gap() end
function love.touchreleased(id) fingers[id]=nil; pinchGap=gap() end
function love.touchmoved(id,x,y)
  if not fingers[id] then return end
  fingers[id].x,fingers[id].y=x,y
  local g=gap()
  if not (g and pinchGap and pinchGap>1) then pinchGap=g; return end
  local mx,my=pointer()
  if not state.modal and not UI.covers(mx,my) then
    local ratio=g/pinchGap
    if math.abs(ratio-1)>0.004 then cam:zoomAt(mx,my,(ratio-1)/0.16) end
  end
  pinchGap=g
end

function love.keypressed(key)
  if state.rename then
    if key=="escape" then state.rename=nil
    elseif key=="return" then
      if action("setCompanyName",state.rename) then state.rename=nil end
    elseif key=="backspace" then
      if state.renameSelectAll then state.rename=""; state.renameSelectAll=nil
      else
        local utf8=require("utf8")
        local offset=utf8.offset(state.rename,-1)
        if offset then state.rename=state.rename:sub(1,offset-1) end
      end
    elseif key=="a" and love.keyboard.isDown("lgui","rgui","lctrl","rctrl") then
      state.renameSelectAll=true
    end
    return
  end
  if state.modal=="land" or state.modal=="terrain" then
    if key=="escape" then state.modal=nil; state.district=nil
    elseif key=="return" or key=="y" then UI.confirmModal() end
    return
  end
  if state.modal then
    if key=="escape" or key=="return" then
      if not city.bankrupt or state.modal=="slots" then state.modal=nil end
    end
    return
  end
  if key=="escape" then
    -- Esc folds things away one layer at a time: a menu, then what is in hand
    -- or selected, then the drawer.
    if state.settings then state.settings=nil
    elseif state.tool or state.node or state.edge or state.link or state.district then clear()
    else UI.closeDrawer(state) end
  elseif key=="=" or key=="+" or key=="kp+" or key=="-" or key=="kp-" then
    local w,h=love.graphics.getDimensions()
    cam:zoomAt(w/2,h/2,(key=="-" or key=="kp-") and -1.5 or 1.5)
  elseif (key=="y" or key=="n") and state.node and city.g.nodes[state.node] and city.g.nodes[state.node].prospect then
    action(key=="y" and "acceptClient" or "declineClient",state.node)
  elseif key=="b" then
    UI.closeDrawer(state)
  elseif key=="tab" then
    UI.closeDrawer(state)
  elseif key=="return" then action("endDay")
  elseif key=="f" then fit()
  elseif key=="t" and (#city.g:nodesOfKind("terminal")+#city.g:nodesOfKind("dc")>0) then state.rail=(state.rail==nil) and "rail" or nil
  elseif key=="z" then action("undo")
  elseif key=="m" then action("mute")
  elseif key=="o" then action("minimap")
  elseif key=="h" then action("solo")
  elseif key=="u" and state.edge then action("upgradePipe",state.edge)
  elseif key=="r" then
    if state.edge then action("repairPipe",state.edge) else action("repairAll") end
  elseif key=="l" then action("nextLeak")
  elseif key=="e" and state.edge then action("upgradePipe",state.edge)
  elseif key=="e" and state.node and city.g.nodes[state.node].kind=="source" then
    action("upgradeSource",state.node)
  -- A Mac's delete key sends "backspace"; "delete" is fn+delete.
  elseif key=="delete" or key=="backspace" then
    if state.edge then action("demolishPipe",state.edge)
    elseif state.link then action("demolishLink",state.link)
    elseif state.node then action("demolishNode",state.node) end
  elseif tonumber(key) and tonumber(key)>=1 and tonumber(key)<=9 then
    local name=(UI.toolKeys or {})[tonumber(key)]
    if name then state.tool=state.tool~=name and name or nil end
  end
end

function love.textinput(value)
  if state.rename then
    local previous=state.renameSelectAll and "" or state.rename
    if #previous+#value<=48 then state.rename=previous..value; state.renameSelectAll=nil end
  end
end

function love.resize() R.retune(); fit() end
function love.quit()
  Audit.report()
  if saveBlocked then return end
  if not save() then return true end
end

return App
