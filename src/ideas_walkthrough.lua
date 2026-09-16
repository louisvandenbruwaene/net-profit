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
 click('build-help'); check(app.state.buildHelp,'build instructions expand inline')
 click('build-help')
 click('quick-decline'); check(#c:clientList(true)==0,'top request decision removes the current offer')
 for _=1,2 do assert(c:addClient('house',true)) end
 local best=c:nextRequest(); click('quick-accept')
 check(not best.prospect,'top card accepts the highest premium offer')
 check(c:nextRequest()~=best,'next request appears immediately')
 click('power'); click('line-options'); click('ampere-help')
 check(app.state.ampereHelp,'separate cable current info button works')
 capture('net-profit-ideas-current-help',app,1100,700)
 click('ampere-help'); click('line-options')
 click('water'); scrollTo(app,'purifier'); click('purifier')
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
 click('tab-stats'); scrollTo(app,'autoplay'); click('autoplay')
 check(app.state.autoRemaining==300,'autoplay uses the requested minutes')
 capture('net-profit-ideas-autoplay',app,1100,700)
 click('autoplay'); check(not app.state.autoRemaining,'autoplay stops immediately')
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
 -- A header window with controls prints its figure clear of them.
 local UIm=require('company_ui')
 for _,value in ipairs({'3  $240','18  $12480','+140%','All sound'}) do
  local font=R.fonts[UIm.headerFont(value,198,true)]
  check(UIm.HEAD_VALUE+font:getHeight()<=UIm.HEAD_ROW,'header figure clears its controls: '..value)
  check(font:getWidth(value)<=198,'header figure is not cut off: '..value)
 end
 check(UIm.headerFont('$1200',198,false)=='big','a window without controls keeps the large figure')
end
