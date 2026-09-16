-- Text that has drawn symbols in it.
--
-- The commodity pictograms are drawings, not letters, and they travel inside
-- ordinary strings: "120 <steel>", "4 / 6 <crews>". The previous way to make
-- that work was to bake every letter of the alphabet into a bitmap so the
-- drawings could live in the same font, because LOVE refuses a fallback
-- between a TrueType font and an image one. A baked alphabet loses the
-- typeface's kerning and its fractional advances -- every letter is pushed
-- into a whole-pixel box -- and that, not the pixel grid, is what made the
-- text look loose.
--
-- So the letters stay a real font and love.graphics.print learns to draw the
-- symbols itself. A string with no symbol in it takes the original path and
-- nothing about it changes.
local S=require('symbols')
local F={}
local lg=love.graphics
local Draw
-- Held before the wrapper is put in place: the stretches of letters are drawn
-- with the real one, so a string that could not be taken apart cannot come
-- back round into the wrapper.
local rawPrint,rawPrintf=lg.print,lg.printf

-- Every symbol sits in the private-use block at 0xE001 upward, which is three
-- UTF-8 bytes beginning 0xEE 0x80. Finding that pair is enough to know a
-- string is worth taking apart.
local LEAD='\238\128'
local keyOf={}
for _,key in ipairs(S.keys) do keyOf[S.get(key)]=key end

function F.has(key) return keyOf[S.get(key)]~=nil end

-- A symbol occupies a square a little taller than the line, plus the single
-- point of separation the baked sheet used to leave between glyphs. Keeping
-- that measurement identical is what stops every panel from being relaid out.
local function box(font) return math.max(14,math.ceil(font:getHeight()*1.15))+1 end

-- Walks a string as alternating stretches of letters and symbols.
local function runs(s,fn)
  local i,n=1,#s
  while i<=n do
    local at=s:find(LEAD,i,true)
    if not at then fn(s:sub(i),nil); return end
    local glyph=s:sub(at,at+2)
    local key=keyOf[glyph]
    if not key then
      -- Some other three-byte character from the same block: leave it be.
      fn(s:sub(i,at+2),nil); i=at+3
    else
      if at>i then fn(s:sub(i,at-1),nil) end
      fn(nil,key); i=at+3
    end
  end
end

function F.width(s,font)
  s=tostring(s)
  font=font or lg.getFont()
  if not s:find(LEAD,1,true) then return font:getWidth(s) end
  local w=0
  runs(s,function(part,key)
    if part then w=w+font:getWidth(part) else w=w+box(font) end
  end)
  return w
end

-- The drawings themselves. Sizes are in points against the line height, so a
-- symbol in the sidebar and the same symbol in a heading are the same shape.
function F.mark(key,x,y,r)
  Draw=Draw or require('company_render')
  local cr,cg,cb,ca=lg.getColor()
  local lw=lg.getLineWidth()
  lg.setLineWidth(math.max(1.4,r*0.21))
  if key=='crews' then
    -- A hard hat, in its own yellow multiplied by the colour of the text
    -- around it, which is what the baked sheet did.
    lg.setColor(cr,cg*0.82,cb*0.2,ca)
    lg.arc('fill','pie',x,y+r*.4,r,math.pi,2*math.pi)
    lg.rectangle('fill',x-r*1.2,y+r*.3,r*2.4,r*.3)
  elseif key=='engineers' then
    -- A spanner. The crews mend what has broken and the engineers change a
    -- main before it does, so they cannot both be a hard hat.
    lg.line(x-r*.85,y+r*.85,x+r*.15,y-r*.15)
    lg.arc('line','open',x+r*.45,y-r*.45,r*.5,math.pi*0.15,math.pi*1.6)
  elseif key=='dispatchers' then
    -- A signal reaching outward: what a dispatcher buys is how far you can see.
    local sx,sy=x-r*.5,y+r*.75
    lg.circle('fill',sx,sy,r*.24)
    lg.arc('line','open',sx,sy,r*.8,-math.pi/2,0)
    lg.arc('line','open',sx,sy,r*1.3,-math.pi/2,0)
  elseif key=='surveyors' then
    -- A level on its tripod.
    lg.line(x,y-r*.2,x-r*.75,y+r)
    lg.line(x,y-r*.2,x+r*.75,y+r)
    lg.line(x,y-r*.2,x,y+r*.9)
    lg.line(x-r*.85,y-r*.55,x+r*.5,y-r*.55)
    lg.circle('line',x+r*.62,y-r*.55,r*.22)
  elseif key=='analysts' then
    -- A graduate's cap over a rising line. The coin that used to sit in front
    -- of the cap read as a blot on it.
    lg.polygon('line',x-r,y-r*.5,x,y-r,x+r,y-r*.5,x,y)
    lg.line(x+r*.78,y-r*.36,x+r*.78,y+r*.05)
    lg.line(x-r*.85,y+r,x-r*.3,y+r*.5,x+r*.1,y+r*.75,x+r*.85,y+r*.15)
  elseif key=='estates' then
    lg.polygon('line',x-r,y,x,y-r,x+r,y); lg.rectangle('line',x-r*.7,y,r*1.4,r)
  elseif key=='people' then
    lg.circle('fill',x,y-r*.65,r*.35); lg.line(x,y-r*.15,x,y+r*.5); lg.line(x-r*.6,y+r,x,y+r*.4,x+r*.6,y+r)
  elseif key=='roads' then
    lg.line(x-r,y-r,x-r,y+r); lg.line(x+r,y-r,x+r,y+r); lg.line(x,y-r,x,y-r*.3); lg.line(x,y+r*.3,x,y+r)
  elseif key=='goods' then
    lg.rectangle('line',x-r,y-r,r*2,r*2); lg.line(x-r,y,x+r,y)
  elseif key=='shield' then
    -- What a lining buys: the main behind it.
    lg.polygon('line',x-r*.85,y-r*.8,x+r*.85,y-r*.8,x+r*.85,y+r*.1,x,y+r,x-r*.85,y+r*.1)
  elseif key=='clean' then
    -- Seawater with the sparkle of having been through the purifier.
    Draw=Draw or require('company_render')
    Draw.mark('saltwater',x-r*.2,y+r*.1,r*.82)
    lg.setColor(cr,cg,cb,ca)
    local sx,sy,sr=x+r*.62,y-r*.62,r*.42
    lg.line(sx-sr,sy,sx+sr,sy); lg.line(sx,sy-sr,sx,sy+sr)
    lg.line(sx-sr*.55,sy-sr*.55,sx+sr*.55,sy+sr*.55)
    lg.line(sx-sr*.55,sy+sr*.55,sx+sr*.55,sy-sr*.55)
  else
    Draw.mark(key,x,y,r)
  end
  lg.setColor(cr,cg,cb,ca); lg.setLineWidth(lw)
end

-- One line of text, starting at the pen position, in the current font.
local function pen(s,font)
  local h=font:getHeight()
  local w=box(font)
  local x=0
  runs(s,function(part,key)
    if part then
      rawPrint(part,x,0); x=x+font:getWidth(part)
    else
      F.mark(key,x+w/2,h*0.53,math.min(w,h)*0.46); x=x+w
    end
  end)
end

-- Wrapping, for the one caller that wraps: words are measured the same way
-- they are drawn, so a symbol never hangs off the end of a line.
local function wrap(s,font,limit)
  local lines,start={},1
  s=tostring(s)
  while true do
    local nl=s:find('\n',start,true)
    local chunk=nl and s:sub(start,nl-1) or s:sub(start)
    local line
    for word in chunk:gmatch('%S+') do
      local try=line and (line..' '..word) or word
      if line and F.width(try,font)>limit then lines[#lines+1]=line; line=word else line=try end
    end
    lines[#lines+1]=line or ''
    if not nl then return lines end
    start=nl+1
  end
end

function F.install()
  if F.installed then return end
  F.installed=true

  lg.print=function(s,x,y,r,sx,sy,...)
    if type(s)~='string' or not s:find(LEAD,1,true) then return rawPrint(s,x,y,r,sx,sy,...) end
    local font=lg.getFont()
    lg.push()
    lg.translate(x or 0,y or 0)
    if r and r~=0 then lg.rotate(r) end
    if sx then lg.scale(sx,sy or sx) end
    pen(s,font)
    lg.pop()
  end

  lg.printf=function(s,x,y,limit,align,...)
    if type(s)~='string' or not s:find(LEAD,1,true) then return rawPrintf(s,x,y,limit,align,...) end
    local font=lg.getFont()
    local h=font:getHeight()*(font.getLineHeight and font:getLineHeight() or 1)
    for i,line in ipairs(wrap(s,font,limit)) do
      local w=F.width(line,font)
      local dx=0
      if align=='center' then dx=(limit-w)/2 elseif align=='right' then dx=limit-w end
      lg.push(); lg.translate(x+dx,y+(i-1)*h); pen(line,font); lg.pop()
    end
  end
end

return F
