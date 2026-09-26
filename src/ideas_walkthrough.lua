-- Real input callbacks for every newly introduced control. Uses an isolated
-- company, like the existing smoke suite; no player save is loaded or written.
local City=require('city')
local UI=require('company_ui')
return function(app,capture,click,scrollTo,check)
 local c=City.new({seed=24,obstacles=0}); c.money=100000; c.obstacles={}
 c.stock={steel=500,concrete=500}; c.lining=4; c.licences.power=true
 c.guideDismissed=true; c.permits={river=true,park=true,bedrock=true}
 for _,d in ipairs(c.districts) do d.owned=true end
 app.setTestCity(c)
 -- One control on the request window, coloured by the offer on it: above the
 -- going rate is worth taking, below it is not, and at it says nothing.
 local P=require('palette')
 do
  local offer=c:nextRequest(); local rate=offer.rate
  local function control()
   love.draw()
   for _,b in ipairs(UI.buttons) do if b.id=='request-open' then return b end end
  end
  local _,cost=c:clientMargin(offer)
  offer.rate=cost*3
  check(control().color==P.good,'an offer that keeps more than a unit costs reads green')
  offer.rate=cost*0.5
  check(control().color==P.bad,'and one that pays less than a unit costs reads red')
  offer.rate=cost*1.5
  check(control().color==nil and not control().active,'a thin margin stays plain')
  offer.rate=rate
 end
 local offer=c:nextRequest()
 click('request-open')
 check(app.state.node==offer.id,'the request control opens the contract for that house')
 check(app.camera().targetScale>=1.3,'and comes in closer than the map was')
 click('decline'); check(#c:clientList(true)==0,'the decision removes the current offer')
 for _=1,2 do assert(c:addClient('house',true)) end
 local best=c:nextRequest(); click('request-open')
 do
   -- The offer must land in the middle of the map area beside the panel.
   local cam=app.camera(); cam.scale=cam.targetScale; cam:update(1)
   for _=1,60 do cam:update(1/60) end
   local sx,sy=cam:toScreen(best.x,best.y)
   local k=UI.effectiveScale(); local left=UI.width*k
   local mid=left+(cam.vx+cam.vw-left)/2
   check(math.abs(sx-mid)<40 and math.abs(sy-(cam.vy+cam.vh/2))<40,'the best offer is centred in the visible map')
   check(cam.scale>=1.3,'and shown close up')
 end
 click('accept')
 check(not best.prospect,'the highest premium offer is the one signed')
 check(c:nextRequest()~=best,'next request appears immediately')
 click('back-to-build')
 click('power'); click('line-options')
 capture('net-profit-ideas-current-help',app,1100,700)
 click('line-options')
 click('water'); click('line-options')
 capture('net-profit-ideas-pipe-options',app,1100,700)
 click('line-options')
 -- Brine is not offered to a company that has barely started.
 love.draw(); local early=false
 for _,b in ipairs(UI.buttons) do early=early or b.id=='purifier' or b.id=='seawater' end
 check(not early and not c:unlocked('seawater'),'sea pump and purifier wait for the seawater unlock')
 for _=1,City.UNLOCKS.seawater.clients do c:acceptClient(assert(c:addClient('house',true)).id) end
 check(c:unlocked('seawater'),'enough customers open the seawater structures')
 scrollTo(app,'purifier'); click('purifier')
 check(app.state.tool=='works' and app.state.recipe=='purifier','purifier is beside the well controls')
 click('seawater'); check(app.state.commodity=='saltwater' and app.state.tool=='source','seawater pump tool is reachable from water')
 app.action('buySource','saltwater',200,-40)
 local sea=c.g.nodes[app.state.node]
 check(sea and sea.commodity=='saltwater','sea pump builds through the application')
 capture('net-profit-ideas-seapump',app,1100,700)
 app.action('build',200,40,'filtration'); local filter=c.g.nodes[app.state.node]
 app.action('build',260,100,'works','purifier'); local purifier=c.g.nodes[app.state.node]
 assert(app.action('layPipe',sea.id,filter.id,'saltwater','large',nil,3))
 assert(app.action('layPipe',filter.id,purifier.id,'saltwater','large',nil,3))
 app.action('focusNode',purifier.id)
 capture('net-profit-ideas-purification',app,1100,700)
 check(purifier.ready==16 and purifier.coproductReady==16,'purifier inspector has both real outputs')
 app.action('build',420,120,'depot','water'); local depot=c.g.nodes[app.state.node]; depot.stored=70; c:refresh()
 app.action('focusNode',depot.id)
 capture('net-profit-ideas-storage',app,1100,700)
 click('back-to-build'); app.state.commodity='water'
 capture('net-profit-ideas-compact-build',app,1100,700)
 click('tab-finance'); scrollTo(app,'order-analysts'); click('order-analysts')
 check(c:workerCount('analysts')==1,'market analyst can be hired through its icon')
 scrollTo(app,'order-analysts'); click('order-analysts')
 check(c:workerCount('analysts')==2,'the same control hires additional workers')
 scrollTo(app,'order-analysts')
 capture('net-profit-ideas-staff',app,1100,700)
 click('order-stop-analysts'); check(c:workerCount('analysts')==1,'dismissal removes only one analyst')
 -- Every symbol has a drawing behind it, and takes room in a line of text.
 local S=require('symbols'); local R=require('render')
 local lg=love.graphics; local SF=require('symbol_font')
 for _,key in ipairs(S.keys) do check(SF.has(key),'symbol can be drawn: '..key) end
 for _,font in pairs(R.fonts) do
  for _,key in ipairs(S.keys) do
   check(SF.width('3 '..S.get(key),font)>font:getWidth('3 '),'symbol takes room in a line: '..key)
  end
 end
 -- The letters are the typeface itself, rasterised for the screen in use.
 -- Baking them into a bitmap so they could carry the symbols cost them their
 -- kerning, which is what made the text look loose.
 for key,size in pairs(R.SIZES) do
  local plain=lg.newFont('assets/DejaVuSans-Bold.ttf',size)
  check(R.fonts[key]:getHeight()==plain:getHeight(),'font is the typeface itself: '..key)
  check(R.fonts[key]:getDPIScale()==R.density,'font is rasterised for this screen: '..key)
  check(R.fonts[key]:getWidth('AVAILABLE CASH')==plain:getWidth('AVAILABLE CASH'),
    'letters are spaced by the typeface: '..key)
 end
 -- A header window shows its figure whole, and the two that hold a decision
 -- hold the same control, centred between the lines that bound the window.
 local UIm=require('company_ui')
 for _,value in ipairs({'$94998','0 / 12','No contracts','All sound'}) do
  check(SF.width(value,R.fonts[UIm.headerFont(value,198)])<=198,'header figure is not cut off: '..value)
 end
 check(UIm.headerFont('$1200',198)=='big','a window with room keeps the large figure')
 for _,width in ipairs({144,212,300}) do
  local dx,bw,bh=UIm.headerButton(width)
  check(UIm.HEAD_VALUE+bh<=UIm.HEAD_BAR,'the header control fits the bar at '..width)
  check(math.abs((dx+bw/2)-(width/2-14))<0.01,'and is centred between its lines at '..width)
 end
end
