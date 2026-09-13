local City = require("city")
local Camera = require("camera")
local Save = require("company_save")
local Draw = require("company_render")
local UI = require("company_ui")
local R = require("render")
local A = require("audio")
local P = require("palette")
local App = {}
local city,cam
local state={commodity="water",havenKind="port",plant="nuclear",recipe="turbine",size="small",grade=1,capacity=1,invest=100,borrow=500,tab="network",scroll=0,undo={}}
local testMode, frames = nil,0

local function toast(message,bad)
  state.toast,state.toastBad,state.toastTime=tostring(message),bad,5
end

local function save()
  if testMode then return end
  local ok,err=Save.write(city)
  if not ok then toast("Save failed: "..tostring(err),true) end
end

local function layout()
  local w,h=R.dimensions()
  cam:setViewport(UI.width,190,w-UI.width,h-248)
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
  cam.x,cam.y=(x0+x1)/2,(y0+y1)/2
  cam.scale=math.max(0.12,math.min(1.45,cam.vw/(x1-x0),cam.vh/(y1-y0)))
  cam.targetScale=cam.scale
end

local function fit()
  layout()
  local x0,y0,x1,y1=city.firstSource.x,city.firstSource.y,city.firstSource.x,city.firstSource.y
  for _,n in ipairs(city.g:aliveNodes()) do
    x0,y0,x1,y1=math.min(x0,n.x),math.min(y0,n.y),math.max(x1,n.x),math.max(y1,n.y)
  end
  cam.x,cam.y=(x0+x1)/2,(y0+y1)/2
  cam.scale=math.max(0.3,math.min(1.45,cam.vw/(x1-x0+330),cam.vh/(y1-y0+330)))
  cam.targetScale=cam.scale
end

local function clear()
  state.node,state.edge,state.tool,state.drag,state.pan=nil,nil,nil,nil,nil
  state.district=nil
  state.rename=nil; state.renameSelectAll=nil
end

-- Everything that belongs to the company being played rather than to the
-- player, reset when a different company is opened.
local function resetSession()
  clear()
  state.undo={}
  state.modal,state.slotConfirm=nil,nil
  state.scroll=0
  state.tab="network"
  state.commodity="water"
  state.capacity=1; state.size="small"
  state.borrow=500
  state.invest=100
  state.rail=nil
  state.filter=nil; state.bottlenecks=nil; state.rename=nil; state.advanced=nil
end

-- Selecting anything on the map is a question, and the sidebar is the answer.
-- Rather than leaving the player on whichever tab they happened to be reading,
-- every selection opens the tab that can act on it and scrolls straight to the
-- controls -- so clicking a burst main lands on its Repair button.
local function reveal(kind)
  if kind=="district" then
    state.tab="map"; state.scroll=0
  else
    state.tab="network"; state.scroll=UI.revealInspector()
  end
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
  if name=="addWagon" then
    local id,commodity=...
    local ok,err=city:addWagon(id,commodity)
    if not ok then toast(err,true) else A.play("upgrade") end
    return
  end
  if name=="hireOrder" or name=="dismissOrder" then
    local key=...
    local ok,err=city[name=="hireOrder" and "hireOrder" or "dismissOrder"](city,key)
    if not ok then toast(err,true) else A.play("upgrade") end
    return
  end
  if name=="replacePipe" then
    local id,size,grade=...
    local ok,err=city:replacePipe(id,size,grade)
    if not ok then toast(err,true) else A.play("upgrade"); state.edge=id end
    return
  end
  if name=="teach" then city:teach((...)); return end
  if name=="setDispatchRate" then city.dispatchRate=math.max(0,select(1,...)); return end
  if name=="setReserve" then city.estateReserve=math.max(0,select(1,...)); return end
  if name=="setHubFloor" then
    local id,value=...
    local n=city.g.nodes[id]
    if n and n.kind=="exchange" then n.floor=math.max(0,math.floor(value)); city:refresh() end
    return
  end
  if name=="setHubAuto" then
    local id,value=...
    local n=city.g.nodes[id]
    if n and n.kind=="exchange" then n.autoWiden=value and true or nil end
    return
  end
  if name=="fit" then if state.tab=="map" then fitWorld() else fit() end; return end
  if name=="fitWorld" then fitWorld(); return end
  if name=="mute" then state.muted=not state.muted; A.setEnabled(not state.muted); return end
  if name=="focusNode" then
    local id=...
    local n=city.g.nodes[id]
    clear(); state.filter=nil; state.modal=nil; state.node=id; reveal()
    cam:centerOn(n.x,n.y)
    return
  end
  if name=="focusEdge" then
    local id=...
    local e=city.g.edges[id]
    local a,b=city.g.nodes[e.a],city.g.nodes[e.b]
    clear(); state.filter=nil; state.modal=nil; state.edge=id; reveal()
    cam:centerOn((a.x+b.x)/2,(a.y+b.y)/2)
    return
  end
  if name=="focusDistrict" then
    local id=...
    local d=city.districts[id]
    clear(); state.district=id; reveal("district")
    fitWorld()
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
    save()
    local loaded,err=Save.read(slot)
    if not loaded then toast(err or "That company could not be opened",true); return end
    city=loaded
    resetSession(); Save.writeCurrent(slot)
    fit(); toast("Company "..slot.." opened")
    return
  end
  if name=="newSlot" then
    local slot=...
    save()
    city=City.new(); city.slot=slot
    resetSession()
    if not testMode then Save.writeSlot(city,slot) end
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
    local slot=city.slot or 1
    city=City.new(); city.slot=slot
    resetSession()
    if not testMode then Save.writeSlot(city,slot) end
    fit(); return
  end
  if name=="undo" then
    local snap=table.remove(state.undo)
    if snap then city=assert(Save.unpack(snap)); clear(); save(); toast("Decision undone") end
    return
  end
  if city.bankrupt then return end
  local snapshot=Save.pack(city)
  local result,err=city[name](city,...)
  if not result then toast(err or "Action unavailable",true); A.play("denied"); return nil end
  if name=="endDay" then
    state.undo={}; clear(); state.rename=nil; state.modal="report"; state.reportDetails=false
    for _,leak in ipairs(result.leaks) do R.ring(leak.x,leak.y,P.bad) end
    if result.arrived then R.ring(result.arrived.x,result.arrived.y,P.energy) end
    A.play(city.bankrupt and "collapse" or "held")
  else
    state.undo[#state.undo+1]=snapshot
    if #state.undo>30 then table.remove(state.undo,1) end
    if name=="layPipe" then
      state.edge=result.id; state.node=nil; A.play("link")
      for _,n in ipairs(city:clientList()) do
        if (city.served[n.id] or 0)>=n.demand then R.ring(n.x,n.y,P.good) end
      end
    elseif name=="build" or name=="buySource" then
      state.node=result.id; state.edge=nil; state.tool=nil; R.ring(result.x,result.y,P.good); A.play("place")
    elseif name=="buyDistrict" then
      state.district=result.id; R.ring(result.x+result.w/2,result.y+result.h/2,P.good); A.play("place")
    else A.play("upgrade") end
    if name=="repairAll" then
      toast(result.fixed.." main"..(result.fixed==1 and "" or "s").." repaired for $"..result.spent)
    elseif name=="buyDistrict" then
      toast(result.name.." acquired")
    elseif name=="layPipe" then
      toast(city.unserved==0 and "Everyone supplied! Close the day to collect your earnings." or "Connection built. Keep the supply flowing.")
    else
      toast(({repairPipe="Pipe repaired",replacePipe="Main replaced",buyAds="Advertising booked",
        invest="Investment placed",upgradeQuality="Treatment upgraded",buyLicence="Trade licence acquired",
        acceptClient="Customer signed",declineClient="Offer declined",upgradeSource="Well deepened",
        acceptTender="Tender signed, bond posted",declineTender="Tender declined",
        hireCrew="Crew hired",dismissCrew="Crew stood down",buyPermit="Permit granted",
        borrow="Funds drawn",repay="Loan repaid",setGate="Gate set"})[name] or "Network updated")
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
  if x<UI.width or y<130 or y>love.graphics.getHeight()-58 then return nil,nil end
  for _,n in ipairs(city.g:aliveNodes()) do
    local sx,sy=cam:toScreen(n.x,n.y)
    if (not state.filter or not n.commodity or n.commodity==state.filter) and
      (sx-x)^2+(sy-y)^2<math.max(13,R.sym(25,cam.scale))^2 then return n.id,nil end
  end
  local nearest,dist=nil,10
  for _,e in ipairs(city.g.edges) do
    if e.alive and (not state.filter or e.commodity==state.filter) then
      local ax,ay,bx,by=Draw.edgePoints(cam,city,e)
      local d=pointDistance(x,y,ax,ay,bx,by)
      if d<dist then nearest,dist=e.id,d end
    end
  end
  return nil,nearest
end

function love.load(args)
  for _,a in ipairs(args or {}) do
    if a=="--smoke" or a=="--soak" or a=="--shot" or a=="--tut" or a=="--audio"
       or a=="--probe" then testMode=a end
  end
  R.init(); A.init()
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
  if testMode then
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
  if err then toast("Could not load saved company: "..err,true) end
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
end

function love.update(dt)
  R.update(dt); cam:update(dt)
  state.hoverNode,state.hoverEdge=hit(love.mouse.getPosition())
  if state.toastTime then
    state.toastTime=state.toastTime-dt
    if state.toastTime<=0 then state.toast=nil; state.toastBad=nil end
  end
  state.scroll=math.max(0,math.min(state.scroll,UI.maxScroll or 0))
  if testMode then
    frames=frames+1
    if frames==3 then require("company_walkthrough").start(App,testMode) end
    if frames>3 then require("company_walkthrough").update(App,testMode,frames) end
  end
end

function love.draw()
  love.graphics.clear(P.bg)
  Draw.world(city,cam,state)
  UI.draw(city,state,action)
end

function love.mousepressed(x,y,button)
  if button==1 and UI.click(x,y) then return end
  if state.modal then return end
  if x<UI.width or y<130 or y>love.graphics.getHeight()-58 then return end
  if button==2 or button==3 then state.tool=nil; state.pan={x=x,y=y,moved=false}; return end
  if button~=1 then return end
  if state.tool then
    local wx,wy=cam:toWorld(x,y)
    if state.tool=="source" then action("buySource",state.commodity,wx,wy,state.plant)
    elseif state.tool=="terminal" then action("build",wx,wy,state.tool,state.havenKind or "port")
    elseif state.tool=="works" then action("build",wx,wy,state.tool,state.recipe or "brewery")
    else action("build",wx,wy,state.tool,state.commodity) end
    return
  end
  local node,edge=hit(x,y)
  if node or edge then
    state.node,state.edge,state.district=node,edge,nil
    reveal()
    if node then state.drag=node end
    return
  end
  -- Empty ground still answers a question: which district is this, and what
  -- would it cost? Clicking unowned ground opens the Map tab on that district.
  local wx,wy=cam:toWorld(x,y)
  local d=city:districtAt(wx,wy)
  state.node,state.edge=nil,nil
  if d and not d.owned then
    state.district=d.id
    reveal("district")
  else
    state.district=nil
  end
  state.pan={x=x,y=y,moved=false}
end

function love.mousemoved(x,y,dx,dy)
  state.hoverNode,state.hoverEdge=hit(x,y)
  if state.pan then
    local p=state.pan
    if p.moved then cam:pan(dx,dy)
    elseif (x-p.x)^2+(y-p.y)^2>16 then p.moved=true; cam:pan(x-p.x,y-p.y) end
  end
end

function love.mousereleased(x,y,button)
  if state.drag and button==1 then
    local target=hit(x,y)
    if target and target~=state.drag then
      action("layPipe",state.drag,target,state.commodity,
        state.rail and state.capacity or (state.size or "small"),state.rail,
        math.min(city.lining or 1,state.grade or 1))
    end
  end
  state.drag,state.pan=nil,nil
end

function love.wheelmoved(_,dy)
  if state.modal then return end
  local x,y=love.mouse.getPosition()
  if x<UI.width then state.scroll=math.max(0,math.min(UI.maxScroll or 0,state.scroll-dy*42))
  else cam:zoomAt(x,y,dy) end
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
  if state.modal then
    if key=="escape" or key=="return" then
      if not city.bankrupt then state.modal=nil end
    end
    return
  end
  if key=="escape" then clear()
  elseif key=="return" then action("endDay")
  elseif key=="f" then fit()
  elseif key=="t" then state.rail=(state.rail==nil) and "rail" or nil
  elseif key=="z" then action("undo")
  elseif key=="m" then action("mute")
  elseif key=="u" and state.edge then action("upgradePipe",state.edge)
  elseif key=="r" then
    if state.edge then action("repairPipe",state.edge) else action("repairAll") end
  elseif key=="l" then action("nextLeak")
  elseif key=="e" and state.edge then action("upgradePipe",state.edge)
  elseif key=="e" and state.node and city.g.nodes[state.node].kind=="source" then
    action("upgradeSource",state.node)
  elseif key=="delete" then
    if state.edge then action("demolishPipe",state.edge) elseif state.node then action("demolishNode",state.node) end
  elseif tonumber(key) and tonumber(key)>=1 and tonumber(key)<=9 then
    state.tool=({"junction","manifold","pump","tower","gate","depot","exchange","terminal","dc"})[tonumber(key)]
  end
end

function love.textinput(value)
  if state.rename then
    local previous=state.renameSelectAll and "" or state.rename
    if #previous+#value<=48 then state.rename=previous..value; state.renameSelectAll=nil end
  end
end

function love.resize() fit() end
function love.quit() save() end

return App
