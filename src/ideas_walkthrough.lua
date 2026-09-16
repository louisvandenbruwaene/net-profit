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
 -- All private-use symbols have an actual renderer glyph in every font size.
 local S=require('symbols'); local R=require('render')
 for _,font in pairs(R.fonts) do
  for _,key in ipairs(S.keys) do check(font:hasGlyphs(S.get(key)),'icon glyph available: '..key) end
 end
end
