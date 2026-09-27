-- Where two pieces of text land on top of each other.
--
-- A panel is laid out in absolute coordinates, so a label that grows -- a
-- longer number, a longer client name, a translated word -- runs into the
-- thing beside it and nobody notices until a screenshot is looked at closely.
-- This measures it instead: every string the interface draws is recorded with
-- the box it actually occupies, and any two boxes that land on the same pixels
-- are reported with the screen they were on.
--
-- It is a measurement, not a test, in the same sense as `make anatomy`: run it
-- after moving anything in a panel, read the list, and fix what is real. Text
-- drawn over the map is separated out, because two labels on a city seen from
-- far out genuinely do collide and the cure for that is zoom, not layout.
--
-- Nothing here touches love.graphics until the recorder is switched on, so
-- the headless suites can load the application without a window.
local A = { findings = {}, squeezed = {}, broken = {}, seen = {}, frames = 0 }
local lg, SF
local rawPrint, rawPrintf

-- Overlaps smaller than this are the ordinary business of letters sitting
-- close to each other: a descender under the line below, a box rounded out by
-- a fraction of a pixel. Anything a player would actually see is bigger.
local MIN_W, MIN_H = 3, 4

local function plain(s)
  if type(s) == "table" then
    local out = {}
    for _, part in ipairs(s) do if type(part) == "string" then out[#out + 1] = part end end
    return table.concat(out)
  end
  return tostring(s)
end

-- Screen space, through whatever transform is in force.
local function toScreen(x, y)
  if lg.transformPoint then return lg.transformPoint(x, y) end
  return x, y
end

local function push(s, x, y, w, h)
  if s == "" or w <= 0 or h <= 0 then return end
  local sx, sy = toScreen(x, y)
  local ex, ey = toScreen(x + w, y + h)
  if ex < sx then sx, ex = ex, sx end
  if ey < sy then sy, ey = ey, sy end
  -- A clipped panel does not draw outside its scissor, so neither does this.
  local cx, cy, cw, ch = lg.getScissor()
  if cx then
    sx, sy = math.max(sx, cx), math.max(sy, cy)
    ex, ey = math.min(ex, cx + cw), math.min(ey, cy + ch)
    if ex - sx < 1 or ey - sy < 1 then return end
  end
  A.rects[#A.rects + 1] = { s = s, x = sx, y = sy, w = ex - sx, h = ey - sy }
end

function A.enable(on)
  A.on = on and true or false
  if not A.on or A.hooked then return end
  A.hooked = true
  lg = love.graphics
  SF = require("symbol_font")
  rawPrint, rawPrintf = lg.print, lg.printf
  local rawRect = lg.rectangle
  lg.rectangle = function(mode, x, y, w, h, ...)
    if mode == "fill" then A.cover(x, y, w, h) end
    return rawRect(mode, x, y, w, h, ...)
  end
  lg.print = function(s, x, y, r, sx, sy, ...)
    if A.recording then
      local font = lg.getFont()
      local scale = sx or 1
      local text = plain(s)
      -- A label drawn at less than full size is one that did not fit the space
      -- it was given. It does not collide with anything, because the squeeze is
      -- what stopped it, but it is the same fault seen a moment earlier.
      if scale < 0.92 and #text > 1 and not A.seen["squeeze|" .. text] then
        A.seen["squeeze|" .. text] = true
        -- The first caller outside the text helpers, so the report says
        -- which line to fix.
        local where
        for level = 2, 8 do
          local info = debug.getinfo(level, "Sl")
          if not info then break end
          where = info.short_src:match("[^/]+$") .. ":" .. info.currentline
          if not info.short_src:match("layout_audit") and not info.short_src:match("symbol_font") then
            local name = debug.getinfo(level, "n").name
            if name ~= "single" and name ~= "text" and name ~= "button" then break end
          end
        end
        A.squeezed[#A.squeezed + 1] = { s = text, scale = scale, tag = A.tag, where = where }
      end
      -- One box per line: a two-line string with a short second line does not
      -- occupy the rectangle its longest line implies.
      local ly, i = y or 0, 0
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        push(line, x or 0, ly + i * font:getHeight() * scale,
          SF.width(line, font) * scale, font:getHeight() * scale)
        i = i + 1
      end
    end
    return rawPrint(s, x, y, r, sx, sy, ...)
  end
  lg.printf = function(s, x, y, limit, align, ...)
    if A.recording and type(limit) == "number" then
      local font = lg.getFont()
      local lh = font:getHeight() * (font.getLineHeight and font:getLineHeight() or 1)
      local body = plain(s)
      local _, lines = font:getWrap(body, limit)
      -- A word too long for the column is broken in the middle rather than
      -- wrapped, which reads as two nonsense words. Worth knowing about.
      if #lines > 1 then
        local joined = table.concat(lines, " "):gsub("%s+", " ")
        local want = body:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        if joined ~= want and not A.seen["break|" .. body] then
          A.seen["break|" .. body] = true
          A.broken[#A.broken + 1] = { s = body, limit = limit, tag = A.tag, lines = lines }
        end
      end
      for i, line in ipairs(lines) do
        local w = SF.width(line, font)
        local dx = 0
        if align == "center" then dx = (limit - w) / 2
        elseif align == "right" then dx = limit - w end
        push(line, (x or 0) + dx, (y or 0) + (i - 1) * lh, w, font:getHeight())
      end
    end
    return rawPrintf(s, x, y, limit, align, ...)
  end
end

-- A filled rectangle hides what was drawn under it. A lesson panel over the
-- map, a tooltip over a sidebar, the dim behind a modal: the text beneath is
-- not on screen any more, so it is dropped rather than reported as a
-- collision with whatever is drawn on top.
function A.cover(x, y, w, h)
  if not A.recording or not x then return end
  local W, H = require("render").dimensions()
  -- Anything covering the whole screen ends the frame's history, opaque or
  -- not: that is a modal's dim, or the background of the frame itself.
  if x <= 2 and y <= 2 and w >= W * 0.9 and h >= H * 0.9 then A.rects = {}; return end
  local _, _, _, alpha = lg.getColor()
  if (alpha or 1) < 0.95 then return end
  local sx, sy = toScreen(x, y)
  local ex, ey = toScreen(x + w, y + h)
  local kept = {}
  for _, r in ipairs(A.rects) do
    local rx, ry, rex, rey = r.x, r.y, r.x + r.w, r.y + r.h
    if rx >= sx - 1 and ry >= sy - 1 and rex <= ex + 1 and rey <= ey + 1 then
      -- Hidden entirely.
    else
      -- Partly hidden: where the cover spans the text in one direction, only
      -- the part sticking out is still on screen, so only that part is kept.
      if rx >= sx - 1 and rex <= ex + 1 and ry < ey and rey > sy then
        if ry < sy then rey = math.min(rey, sy) else ry = math.max(ry, ey) end
      elseif ry >= sy - 1 and rey <= ey + 1 and rx < ex and rex > sx then
        if rx < sx then rex = math.min(rex, sx) else rx = math.max(rx, ex) end
      end
      if rex - rx >= 1 and rey - ry >= 1 then
        r.x, r.y, r.w, r.h = rx, ry, rex - rx, rey - ry
        kept[#kept + 1] = r
      end
    end
  end
  A.rects = kept
end

function A.begin(tag)
  if not A.on then return end
  A.recording, A.rects, A.tag = true, {}, tag or A.tag or "frame"
end

local function region(r, W, H)
  local UI = require("company_ui")
  if r.x + r.w <= UI.width + 1 then return "panel" end
  if r.y + r.h <= 82 then return "header" end
  if r.y >= H - 60 then return "footer" end
  return "map"
end

function A.finish()
  if not A.on or not A.recording then return end
  A.recording = false
  A.frames = A.frames + 1
  local W, H = require("render").dimensions()
  local rects = A.rects
  for i = 1, #rects do
    for j = i + 1, #rects do
      local a, b = rects[i], rects[j]
      local ow = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
      local oh = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
      if ow > MIN_W and oh > MIN_H then
        local ra, rb = region(a, W, H), region(b, W, H)
        -- Two labels on the city itself, or a tooltip over the map, are not a
        -- layout fault. Everything that involves a panel is.
        local where = (ra == "map" and rb == "map") and "map" or (ra ~= "map" and ra or rb)
        local key = where .. "|" .. a.s .. "|" .. b.s
        if not A.seen[key] then
          A.seen[key] = true
          A.findings[#A.findings + 1] = { where = where, tag = A.tag, a = a.s, b = b.s,
            x = math.floor(math.max(a.x, b.x)), y = math.floor(math.max(a.y, b.y)),
            w = math.floor(ow), h = math.floor(oh) }
        end
      end
    end
  end
  A.rects = {}
end

function A.report()
  if not A.on then return end
  local order = { panel = 1, header = 2, footer = 3, map = 4 }
  table.sort(A.findings, function(p, q)
    if p.where ~= q.where then return order[p.where] < order[q.where] end
    return p.w * p.h > q.w * q.h
  end)
  local counts = {}
  for _, f in ipairs(A.findings) do counts[f.where] = (counts[f.where] or 0) + 1 end
  print(string.format("\nlayout: %d frames measured, %d overlapping pairs, %d squeezed, %d broken words",
    A.frames, #A.findings, #A.squeezed, #A.broken))
  for _, key in ipairs({ "panel", "header", "footer", "map" }) do
    if counts[key] then print(string.format("  %s: %d", key, counts[key])) end
  end
  for _, f in ipairs(A.findings) do
    print(string.format("  [%s] %s  %dx%d at %d,%d\n        %q\n        %q",
      f.where, f.tag, f.w, f.h, f.x, f.y, f.a, f.b))
  end
  table.sort(A.squeezed, function(p, q) return p.scale < q.scale end)
  for _, f in ipairs(A.squeezed) do
    print(string.format("  [squeezed %.2f] %s  %q  %s", f.scale, f.tag, f.s, f.where or ""))
  end
  for _, f in ipairs(A.broken) do
    print(string.format("  [word broken at %d] %s  %q -> %q", f.limit, f.tag, f.s,
      table.concat(f.lines, " | ")))
  end
end

return A
