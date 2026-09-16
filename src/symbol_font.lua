local S=require('symbols')
local F={}
function F.install(fonts)
 local lg=love.graphics
 local Draw=require('company_render')
 for fontKey,font in pairs(fonts) do
  local h=font:getHeight(); local w=math.max(14,math.ceil(h*1.15)); local stride=w+2
  local canvas=lg.newCanvas(stride*#S.keys+1,h,{dpiscale=1})
  lg.push('all'); lg.setCanvas(canvas); lg.clear(0,0,0,0)
  for i,key in ipairs(S.keys) do
   local x=(i-1)*stride+1+w/2; local y=h*.53; local r=math.min(w,h)*.46
   lg.setColor(1,1,1,1); lg.setLineWidth(math.max(1.4,h*.095))
   if key=='crews' or key=='engineers' then
    lg.setColor(1,.82,.2); lg.arc('fill','pie',x,y+r*.4,r,math.pi,2*math.pi); lg.rectangle('fill',x-r*1.2,y+r*.3,r*2.4,r*.3)
    lg.line(x,y-r*.7,x,y+r*.4)
   elseif key=='analysts' then
    lg.polygon('line',x-r,y-r*.3,x,y-r,x+r,y-r*.3,x,y+r*.2)
    lg.line(x-r*.65,y,x-r*.65,y+r*.45,x+r*.65,y+r*.45,x+r*.65,y)
    local cx,cy=x+r*.55,y+r*.55
    lg.circle('line',cx,cy,r*.5)
    lg.line(cx,cy-r*.38,cx,cy+r*.38)
    lg.line(cx+r*.22,cy-r*.23,cx-r*.2,cy-r*.23,cx-r*.2,cy,cx+r*.2,cy,cx+r*.2,cy+r*.23,cx-r*.22,cy+r*.23)
   elseif key=='dispatchers' then
    lg.rectangle('line',x-r*.7,y-r*.5,r*1.4,r*1.5)
    lg.line(x+r*.3,y-r*.5,x+r*.7,y-r*1.2)
    lg.line(x-r*.35,y,x+r*.35,y); lg.line(x-r*.35,y+r*.4,x+r*.35,y+r*.4)
   elseif key=='surveyors' then
    lg.circle('line',x,y,r); lg.line(x-r*1.3,y,x+r*1.3,y); lg.line(x,y-r*1.3,x,y+r*1.3)
   elseif key=='estates' then
    lg.polygon('line',x-r,y,x,y-r,x+r,y); lg.rectangle('line',x-r*.7,y,r*1.4,r)
   elseif key=='people' then
    lg.circle('fill',x,y-r*.65,r*.35); lg.line(x,y-r*.15,x,y+r*.5); lg.line(x-r*.6,y+r,x,y+r*.4,x+r*.6,y+r)
   elseif key=='roads' then
    lg.line(x-r,y-r,x-r,y+r); lg.line(x+r,y-r,x+r,y+r); lg.line(x,y-r,x,y-r*.3); lg.line(x,y+r*.3,x,y+r)
   elseif key=='goods' then lg.rectangle('line',x-r,y-r,r*2,r*2); lg.line(x-r,y,x+r,y)
   else Draw.mark(key,x,y,r) end
  end
  lg.setCanvas(); lg.pop()
  local data=canvas:newImageData()
  -- ImageFont uses the top-left colour to delimit glyph columns.
  for i=0,#S.keys do for y=0,h-1 do data:setPixel(i*stride,y,1,0,1,1) end end
  local glyphs={}; for _,key in ipairs(S.keys) do glyphs[#glyphs+1]=S.get(key) end
  local fallback=lg.newImageFont(data,table.concat(glyphs),0)
  local chars={}
  for cp=32,126 do chars[#chars+1]=string.char(cp) end
  for _,char in ipairs({'…','–','—','°','×','÷','£','€','±','→','←','↑','↓','•','✓','≤','≥'}) do chars[#chars+1]=char end
  local widths,total={},1
  for i,char in ipairs(chars) do widths[i]=math.max(1,math.ceil(font:getWidth(char))); total=total+widths[i]+1 end
  local letters=lg.newCanvas(total,h,{dpiscale=1})
  lg.push('all'); lg.setCanvas(letters); lg.clear(0,0,0,0); lg.setColor(1,1,1); lg.setFont(font)
  local offset=1
  for i,char in ipairs(chars) do lg.print(char,offset,0); offset=offset+widths[i]+1 end
  lg.setCanvas(); lg.pop()
  local pixels=letters:newImageData()
  for x=0,total-1 do
   for y=0,h-1 do
    local r,g,b,a=pixels:getPixel(x,y)
    if a>0 then pixels:setPixel(x,y,1,1,1,math.min(1,a*1.15)) end
   end
  end
  offset=0
  for i=1,#chars+1 do
   for y=0,h-1 do pixels:setPixel(offset,y,1,0,1,1) end
   offset=offset+(widths[i] or 0)+1
  end
  local base=lg.newImageFont(pixels,table.concat(chars),0)
  base:setFallbacks(fallback); fonts[fontKey]=base
 end
end
return F
