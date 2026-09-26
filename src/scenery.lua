-- scenery.lua -- what the ground looks like: forests of trees, mountain ranges,
-- ponds and the grass on a plot.
--
-- Every piece of terrain is built once, in coordinates relative to its own
-- centre, and cached against the obstacle table: a forest is one SpriteBatch of
-- tree sprites, a range is one Mesh of shaded faces. Drawing it is then a single
-- call with the camera's translation and scale, so a massive forest of four
-- thousand trees costs the frame what one icon used to.
--
-- Nothing here uses City:random(). Placement comes from a hash of the obstacle's
-- own position, so the same forest grows the same trees on every load and in
-- every order the map is looked at.
local Scenery = {}
local lg = love.graphics
local Shape = require("terrain_shape")

local function hash(a, b, c)
  local v = math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453
  return v - math.floor(v)
end

-- The outline comes from terrain_shape, which the rules use too, so what is
-- drawn is exactly the ground that charges to be crossed.
local function edgeAt(o, t, k)
  return Shape.fraction(o, t) * (k or 1)
end

-- A disc of ground with a feathered rim: solid inside, fading to nothing at the
-- outline. Returns triangles for a Mesh.
local function groundBlob(v, o, inner, outer, feather, k)
  local n = 72
  local r = o.r
  for i = 0, n - 1 do
    local t0, t1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
    local e0, e1 = edgeAt(o, t0, k), edgeAt(o, t1, k)
    local c0, s0, c1, s1 = math.cos(t0), math.sin(t0), math.cos(t1), math.sin(t1)
    local ax, ay = c0 * r * e0 * (1 - feather), s0 * r * e0 * (1 - feather)
    local bx, by = c1 * r * e1 * (1 - feather), s1 * r * e1 * (1 - feather)
    local px, py = c0 * r * e0, s0 * r * e0
    local qx, qy = c1 * r * e1, s1 * r * e1
    local ir, ig, ib, ia = inner[1], inner[2], inner[3], inner[4] or 1
    local orr, og, ob, oa = outer[1], outer[2], outer[3], outer[4] or 1
    v[#v + 1] = { 0, 0, 0, 0, ir, ig, ib, ia }
    v[#v + 1] = { ax, ay, 0, 0, orr, og, ob, oa }
    v[#v + 1] = { bx, by, 0, 0, orr, og, ob, oa }
    -- Feathered rim.
    v[#v + 1] = { ax, ay, 0, 0, orr, og, ob, oa }
    v[#v + 1] = { px, py, 0, 0, orr, og, ob, 0 }
    v[#v + 1] = { qx, qy, 0, 0, orr, og, ob, 0 }
    v[#v + 1] = { ax, ay, 0, 0, orr, og, ob, oa }
    v[#v + 1] = { qx, qy, 0, 0, orr, og, ob, 0 }
    v[#v + 1] = { bx, by, 0, 0, orr, og, ob, oa }
  end
end

local function tri(v, ax, ay, bx, by, cx, cy, c)
  local r, g, b, a = c[1], c[2], c[3], c[4] or 1
  v[#v + 1] = { ax, ay, 0, 0, r, g, b, a }
  v[#v + 1] = { bx, by, 0, 0, r, g, b, a }
  v[#v + 1] = { cx, cy, 0, 0, r, g, b, a }
end

-- Points on a jittered hex lattice inside the outline, back to front.
local function scatter(o, spacing, margin, keep)
  local pts = {}
  local r = o.r
  local rowH = spacing * 0.866
  local row = 0
  for y = -r, r, rowH do
    row = row + 1
    local shift = (row % 2) * spacing / 2
    for x = -r + shift, r, spacing do
      local jx = (hash(o.x + x, o.y + y, 3) - 0.5) * spacing * 0.7
      local jy = (hash(o.x + x, o.y + y, 4) - 0.5) * spacing * 0.7
      local px, py = x + jx, y + jy
      local d = math.sqrt(px * px + py * py)
      local t = math.atan2 and math.atan2(py, px) or math.atan(py, px)
      local limit = r * edgeAt(o, t) - margin
      if d <= limit and (not keep or keep(px, py, d / math.max(1, limit))) then
        pts[#pts + 1] = { x = px, y = py, h = hash(o.x + px, o.y + py, 5), k = hash(o.x - px, o.y - py, 6) }
      end
    end
  end
  table.sort(pts, function(a, b) return a.y < b.y end)
  return pts
end

--------------------------------------------------------------------------------
-- Tree sprites
--
-- Painted once into an atlas with mipmaps, so a tree is still a tree at four
-- pixels wide and does not shimmer as the camera pulls back.
--------------------------------------------------------------------------------

-- A canvas is painted on and then copied into an Image. A canvas can lose its
-- contents when the window mode changes (going fullscreen, a new display), and
-- an image cannot, so every tree would otherwise vanish on the first resize.
local function bake(canvas)
  local image = lg.newImage(canvas:newImageData(), { mipmaps = true, dpiscale = canvas:getDPIScale() })
  canvas:release()
  image:setFilter("linear", "linear")
  image:setMipmapFilter("linear")
  return image
end

local CELL, CANOPY = 128, 40 -- atlas cell, canopy radius inside it
local atlas, quads

local BROADLEAF = {
  { { 0.10, 0.24, 0.15 }, { 0.17, 0.36, 0.21 }, { 0.27, 0.50, 0.29 } },
  { { 0.11, 0.26, 0.14 }, { 0.20, 0.40, 0.21 }, { 0.33, 0.55, 0.28 } },
  { { 0.09, 0.22, 0.16 }, { 0.15, 0.33, 0.23 }, { 0.24, 0.46, 0.31 } },
  -- A few turning, so a forest is never one flat green.
  { { 0.22, 0.21, 0.11 }, { 0.36, 0.33, 0.15 }, { 0.52, 0.46, 0.21 } },
}
local CONIFER = {
  { { 0.07, 0.18, 0.14 }, { 0.12, 0.29, 0.21 } },
  { { 0.08, 0.20, 0.13 }, { 0.14, 0.32, 0.19 } },
}

local function paintBroadleaf(cx, cy, pal, seed)
  local d, m, l = pal[1], pal[2], pal[3]
  -- Shadow cast down and to the right, onto the ground.
  lg.setColor(0, 0, 0, 0.30)
  lg.ellipse("fill", cx + 8, cy + 26, CANOPY * 0.95, CANOPY * 0.5)
  lg.setColor(0.24, 0.17, 0.11)
  lg.rectangle("fill", cx - 3, cy + 6, 6, 26, 2)
  local lobes = {}
  for i = 0, 5 do
    local a = i / 6 * math.pi * 2 + seed
    lobes[#lobes + 1] = { cx + math.cos(a) * CANOPY * 0.42, cy + math.sin(a) * CANOPY * 0.36, CANOPY * (0.55 + 0.08 * math.sin(i * 2.3 + seed)) }
  end
  lg.setColor(d)
  for _, b in ipairs(lobes) do lg.circle("fill", b[1], b[2] + 3, b[3]) end
  lg.circle("fill", cx, cy + 2, CANOPY * 0.7)
  lg.setColor(m)
  for _, b in ipairs(lobes) do lg.circle("fill", b[1] - 3, b[2] - 2, b[3] * 0.82) end
  lg.setColor(l)
  lg.circle("fill", cx - CANOPY * 0.28, cy - CANOPY * 0.30, CANOPY * 0.34)
  lg.circle("fill", cx + CANOPY * 0.06, cy - CANOPY * 0.42, CANOPY * 0.22)
  lg.setColor(l[1] * 1.25, l[2] * 1.2, l[3] * 1.15, 0.8)
  lg.circle("fill", cx - CANOPY * 0.34, cy - CANOPY * 0.38, CANOPY * 0.14)
end

local function paintConifer(cx, cy, pal)
  local d, l = pal[1], pal[2]
  lg.setColor(0, 0, 0, 0.30)
  lg.ellipse("fill", cx + 10, cy + 30, CANOPY * 0.7, CANOPY * 0.34)
  lg.setColor(0.22, 0.15, 0.10)
  lg.rectangle("fill", cx - 3, cy + 18, 6, 14, 2)
  -- Three tiers, each a dark full triangle with its sunlit left half on top.
  for i = 0, 2 do
    local w = CANOPY * (0.95 - i * 0.24)
    local base = cy + 24 - i * 22
    local top = base - CANOPY * (0.95 - i * 0.12)
    lg.setColor(d); lg.polygon("fill", cx - w, base, cx, top, cx + w, base)
    lg.setColor(l); lg.polygon("fill", cx - w, base, cx, top, cx + w * 0.05, base - 4)
  end
end

local function buildAtlas()
  local count = #BROADLEAF + #CONIFER
  local canvas = lg.newCanvas(CELL * count, CELL)
  lg.push("all")
  lg.origin()
  lg.setScissor()
  lg.setCanvas(canvas)
  lg.clear(0, 0, 0, 0)
  lg.setBlendMode("alpha")
  quads = { broad = {}, conifer = {} }
  local i = 0
  for k, pal in ipairs(BROADLEAF) do
    paintBroadleaf(i * CELL + CELL / 2, CELL / 2, pal, k * 1.3)
    quads.broad[k] = lg.newQuad(i * CELL, 0, CELL, CELL, canvas:getDimensions())
    i = i + 1
  end
  for k, pal in ipairs(CONIFER) do
    paintConifer(i * CELL + CELL / 2, CELL / 2, pal)
    quads.conifer[k] = lg.newQuad(i * CELL, 0, CELL, CELL, canvas:getDimensions())
    i = i + 1
  end
  lg.pop()
  atlas = bake(canvas)
end

--------------------------------------------------------------------------------
-- Terrain builders, one per kind
--------------------------------------------------------------------------------

local function buildForest(o, clearings)
  if not atlas then buildAtlas() end
  local v = {}
  groundBlob(v, o, { 0.15, 0.26, 0.16, 0.95 }, { 0.09, 0.17, 0.13, 0.9 }, 0.08)
  local spacing = o.massive and 26 or 22
  local a1, a2 = hash(o.x, o.y, 7) * 6.28, hash(o.x, o.y, 8) * 6.28
  local trees = scatter(o, spacing, spacing * 0.35, function(px, py, edge)
    -- Glades in a big forest, and a ragged treeline at every edge.
    -- Glades are small and kept to the interior, so the treeline is always
    -- trees and a forest never reads as an empty patch of grass.
    if o.r > 160 and edge < 0.72 then
      local n = math.sin(px / 170 + a1) + math.sin(py / 150 + a2) + math.sin((px + py) / 95 + a1)
      if n < -1.9 then return false end
    end
    for _, c in ipairs(clearings or {}) do
      if (px - c[1]) ^ 2 + (py - c[2]) ^ 2 < c[3] * c[3] then return false end
    end
    return edge < 0.82 or hash(o.x + px, o.y + py, 9) < (1 - edge) * 5
  end)
  local batch = lg.newSpriteBatch(atlas, math.max(1, #trees), "static")
  local conifers = 0.22 + 0.35 * hash(o.x, o.y, 10)
  for _, t in ipairs(trees) do
    local size = 0.82 + t.k * 0.45
    local quad
    if t.h < conifers then
      quad = quads.conifer[1 + math.floor(t.k * #CONIFER) % #CONIFER]
    else
      local pick = t.k < 0.06 and #BROADLEAF or 1 + math.floor(t.h * 97) % (#BROADLEAF - 1)
      quad = quads.broad[pick]
    end
    local s = spacing * 0.78 * size / CANOPY
    local shade = 0.86 + 0.18 * hash(o.x + t.x, o.y + t.y, 11)
    batch:setColor(shade, shade, shade, 1)
    batch:add(quad, t.x, t.y, 0, s, s, CELL / 2, CELL / 2 + 6)
  end
  return { ground = lg.newMesh(v, "triangles", "static"), batch = batch, trees = #trees }
end

-- A vertex-coloured triangle: each corner its own colour, so a peak can shade
-- from rock at the top into the colour of the ground at its foot.
local function triC(v, ax, ay, ca, bx, by, cb, cx, cy, cc)
  v[#v + 1] = { ax, ay, 0, 0, ca[1], ca[2], ca[3], ca[4] or 1 }
  v[#v + 1] = { bx, by, 0, 0, cb[1], cb[2], cb[3], cb[4] or 1 }
  v[#v + 1] = { cx, cy, 0, 0, cc[1], cc[2], cc[3], cc[4] or 1 }
end

local function mix(a, b, t, alpha)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, alpha or 1 }
end

-- A range rises out of the ground rather than sitting on it: grassy foothills
-- in the plot's own colour at the rim, scree and low humps further in, and
-- only the heart carries tall peaks with snow. Pines climb the lower slopes.
local FOOT = { 0.13, 0.19, 0.16 }
local SCREE = { 0.19, 0.19, 0.20 }
local function buildRange(o, clearings)
  if not atlas then buildAtlas() end
  local v = {}
  groundBlob(v, o, { FOOT[1] + 0.02, FOOT[2] + 0.01, FOOT[3], 0.9 }, { FOOT[1], FOOT[2], FOOT[3], 0.6 }, 0.3, 1.0)
  groundBlob(v, o, { 0.20, 0.20, 0.21, 0.9 }, { 0.16, 0.18, 0.17, 0.5 }, 0.45, 0.8)
  groundBlob(v, o, { 0.23, 0.22, 0.24, 0.9 }, { 0.19, 0.19, 0.21, 0.4 }, 0.5, 0.58)
  local spacing = o.massive and 84 or math.max(30, math.min(64, o.r * 0.5))
  local a1, a2 = hash(o.x, o.y, 7) * 6.28, hash(o.x, o.y, 8) * 6.28
  local function ridge(px, py)
    local n = math.sin(px / o.r * 3.3 + a1) * 0.6 + math.sin(py / o.r * 2.7 + a2) * 0.6 + math.sin((px - py) / o.r * 5.9 + a1) * 0.4
    return math.max(0, math.min(1, 0.5 + n / 3.2))
  end
  local function clear(px, py, pad)
    for _, c in ipairs(clearings or {}) do
      if (px - c[1]) ^ 2 + (py - c[2]) ^ 2 < (c[3] + pad) ^ 2 then return false end
    end
    return true
  end
  -- Pebbles over the scree.
  for i = 1, math.floor(o.r * o.r / 700) do
    local a, d = hash(o.x, o.y, 20 + i) * 6.28, math.sqrt(hash(o.x, o.y, 40 + i)) * o.r * edgeAt(o, hash(o.x, o.y, 20 + i) * 6.28) * 0.95
    local x, y, sz = math.cos(a) * d, math.sin(a) * d, 1.5 + hash(o.x, o.y, 60 + i) * 3.5
    local c = hash(o.x, o.y, 80 + i) * 0.08
    tri(v, x - sz, y + sz * 0.5, x - sz * 0.2, y - sz * 0.7, x + sz, y + sz * 0.5, { 0.30 + c, 0.29 + c, 0.32 + c, 0.75 })
  end
  local peaks = scatter(o, spacing * 0.8, spacing * 0.25, function(px, py, edge)
    if not clear(px, py, spacing * 0.4) then return false end
    local rg = ridge(px, py)
    return rg > 0.25 or hash(o.x + px, o.y + py, 12) < rg * 1.8
  end)
  local pines = scatter(o, 24, 6, function(px, py, edge)
    if not clear(px, py, 10) then return false end
    return edge > 0.5 and hash(o.x + px, o.y + py, 13) < (edge - 0.5) * 1.3
  end)
  -- Peaks and pines go down together, back to front, so a pine in front of
  -- a slope hides its foot and one behind it is hidden.
  local items = {}
  for _, p in ipairs(peaks) do
    local depth = math.sqrt(p.x * p.x + p.y * p.y) / (o.r * edgeAt(o, math.atan2 and math.atan2(p.y, p.x) or math.atan(p.y, p.x)))
    p.lift = math.max(0, 1 - depth) ^ 0.75 * (0.55 + 0.45 * ridge(p.x, p.y))
    if p.lift > 0.06 then items[#items + 1] = p end
  end
  for _, t in ipairs(pines) do t.pine = true; items[#items + 1] = t end
  table.sort(items, function(a, b) return a.y < b.y end)
  local run = v
  for _, p in ipairs(items) do
    if p.pine then
      -- A pine in the same mesh as the rock, so it takes its place in the
      -- back-to-front order: three tiers, each dark with a sunlit left half.
      local sz = 8 * (0.8 + p.k * 0.5)
      local pal = CONIFER[1 + math.floor(p.k * #CONIFER) % #CONIFER]
      local shade = 0.8 + 0.25 * p.h
      local d, l = mix(pal[1], pal[1], 0, 1), mix(pal[2], pal[2], 0, 1)
      for c = 1, 3 do d[c] = d[c] * shade; l[c] = l[c] * shade end
      tri(run, p.x - sz * 0.2, p.y + sz * 0.9, p.x + sz * 1.3, p.y + sz * 0.9, p.x + sz * 0.6, p.y + sz * 0.3, { 0, 0, 0, 0.25 })
      for i = 0, 2 do
        local wdt = sz * (0.95 - i * 0.24)
        local base = p.y + sz * 0.6 - i * sz * 0.55
        local top = base - sz * (0.95 - i * 0.12)
        tri(run, p.x - wdt, base, p.x, top, p.x + wdt, base, d)
        tri(run, p.x - wdt, base, p.x, top, p.x + wdt * 0.05, base - sz * 0.1, l)
      end
    else
      local lift = p.lift
      local w = spacing * (0.55 + lift * 1.35 + p.k * 0.3)
      local h = w * (0.35 + lift * 0.55 + p.h * 0.15)
      local x, y = p.x, p.y + h * 0.3
      local lean = (p.h - 0.5) * w * 0.18
      local ax, ay = x + lean, y - h
      local lsx, lsy = x - w * 0.29, y - h * (0.5 + p.k * 0.12)
      local rsx, rsy = x + w * 0.27, y - h * (0.46 + p.h * 0.1)
      local rbx = x + w * 0.06
      local tone = 0.88 + p.k * 0.2
      local lit = { 0.43 * tone, 0.42 * tone, 0.46 * tone, 1 }
      local dark = { 0.23 * tone, 0.22 * tone, 0.27 * tone, 1 }
      local crease = { 0.36 * tone, 0.35 * tone, 0.40 * tone, 1 }
      -- The foot of every face fades into the ground it stands on.
      local ground = lift < 0.35 and FOOT or SCREE
      local litFoot, darkFoot = mix(lit, ground, 0.8), mix(dark, ground, 0.7)
      triC(run, x - w * 0.6, y + 1, { 0, 0, 0, 0 }, x + w * 0.65, y + 1, { 0, 0, 0, 0 }, x + w * 0.12, y - h * 0.2, { 0, 0, 0, 0.22 })
      triC(run, rbx, y, litFoot, x - w / 2, y, litFoot, lsx, lsy, mix(lit, ground, 0.3))
      triC(run, rbx, y, litFoot, lsx, lsy, mix(lit, ground, 0.3), ax, ay, lit)
      triC(run, rbx, y, darkFoot, ax, ay, dark, rsx, rsy, mix(dark, ground, 0.25))
      triC(run, rbx, y, darkFoot, rsx, rsy, mix(dark, ground, 0.25), x + w / 2, y, darkFoot)
      triC(run, rbx, y, mix(crease, ground, 0.8), lsx, lsy, mix(crease, ground, 0.3), x - w * 0.12, y - h * 0.42, crease)
      if lift > 0.55 and h > spacing * 0.75 then
        local f = 0.24 + p.h * 0.08
        local lx, ly = ax + (lsx - ax) * f * 1.6, ay + (lsy - ay) * f * 1.6
        local rx, ry = ax + (rsx - ax) * f * 1.5, ay + (rsy - ay) * f * 1.5
        local mx, my = ax + (rbx - ax) * f * 0.9, ay + (y - ay) * f * 0.9
        local snowL, snowD = { 0.80, 0.83, 0.88, 1 }, { 0.54, 0.58, 0.67, 1 }
        tri(run, ax, ay, lx, ly, (lx + mx) / 2, (ly + my) / 2 - h * 0.04, snowL)
        tri(run, ax, ay, (lx + mx) / 2, (ly + my) / 2 - h * 0.04, mx, my, snowL)
        tri(run, ax, ay, mx, my, (mx + rx) / 2, (my + ry) / 2 - h * 0.05, snowD)
        tri(run, ax, ay, (mx + rx) / 2, (my + ry) / 2 - h * 0.05, rx, ry, snowD)
      end
    end
  end
  return { ground = lg.newMesh(v, "triangles", "static"), trees = #pines }
end

local function buildPond(o)
  local v = {}
  groundBlob(v, o, { 0.20, 0.36, 0.52, 1 }, { 0.12, 0.24, 0.38, 0.95 }, 0.12)
  return { ground = lg.newMesh(v, "triangles", "static"), pond = true }
end

local cache = setmetatable({}, { __mode = "k" })

local function built(o, clearings)
  local b = cache[o]
  if not b then
    b = o.kind == "park" and buildForest(o, clearings and clearings()) or o.kind == "bedrock" and buildRange(o, clearings and clearings()) or buildPond(o)
    cache[o] = b
  end
  return b
end

-- Draws one piece of terrain at screen position x, y with the camera's scale.
-- `dim` is how much of it to show: ground the company does not hold is drawn
-- quieter so what is for sale is still readable.
-- `clearings`, if given, is called once when the forest is first built and
-- returns spots to keep free of trees, as {dx, dy, radius} from its centre.
function Scenery.draw(o, x, y, scale, t, dim, clearings)
  local b = built(o, clearings)
  dim = dim or 1
  lg.setColor(1, 1, 1, dim)
  lg.draw(b.ground, x, y, 0, scale, scale)
  for _, layer in ipairs(b.layers or {}) do lg.draw(layer.mesh, x, y, 0, scale, scale) end
  if b.batch then
    -- The atlas was painted onto a clear canvas, so it holds premultiplied
    -- colour and is drawn that way; the fade is premultiplied to match.
    lg.setBlendMode("alpha", "premultiplied")
    lg.setColor(dim, dim, dim, dim)
    lg.draw(b.batch, x, y, 0, scale, scale)
    lg.setBlendMode("alpha")
  end
  if b.pond then
    -- Ripples drifting outward from the middle.
    lg.setLineWidth(math.max(1, 1.4 * scale))
    for i = 0, 2 do
      local ph = ((t or 0) * 0.12 + i / 3) % 1
      lg.setColor(0.55, 0.72, 0.90, 0.35 * (1 - ph) * dim)
      lg.ellipse("line", x, y, o.r * scale * (0.2 + 0.6 * ph), o.r * scale * (0.12 + 0.36 * ph))
    end
  end
end

-- The outline where crossing charges start: dashed, so it reads as a survey
-- line and not as a wall.
function Scenery.boundary(o, x, y, scale, color, alpha)
  local r = o.r * scale
  local segs = 2 * math.max(12, math.min(160, math.floor(math.pi * r / 14)))
  lg.setColor(color[1], color[2], color[3], alpha)
  lg.setLineWidth(1)
  local shaped = o.kind ~= nil
  for i = 0, segs - 1, 2 do
    local a0, a1 = i / segs * math.pi * 2, (i + 1) / segs * math.pi * 2
    local f0, f1 = shaped and edgeAt(o, a0) or 1, shaped and edgeAt(o, a1) or 1
    lg.line(x + math.cos(a0) * r * f0, y + math.sin(a0) * r * f0, x + math.cos(a1) * r * f1, y + math.sin(a1) * r * f1)
  end
end

--------------------------------------------------------------------------------
-- Plot ground
--
-- One tile of mottled grass, repeated across every plot and pinned to world
-- coordinates so it does not slide as the camera pans.
--------------------------------------------------------------------------------

local TILE, TILE_WORLD = 256, 640
local grass, grassQuad

local function buildGrass()
  local canvas = lg.newCanvas(TILE, TILE)
  lg.push("all")
  lg.origin(); lg.setScissor(); lg.setCanvas(canvas)
  lg.clear(0, 0, 0, 0)
  -- Blobs are drawn nine times, shifted a tile each way, so the tile wraps
  -- without a seam.
  local function blob(x, y, r, a, light)
    lg.setColor(light and 1 or 0, light and 1 or 0, light and 1 or 0, a)
    for dx = -1, 1 do for dy = -1, 1 do lg.circle("fill", x + dx * TILE, y + dy * TILE, r) end end
  end
  -- Broad patches, each a stack of shrinking discs so its edge is soft.
  for i = 1, 40 do
    local x, y, r, light = hash(i, 1) * TILE, hash(i, 2) * TILE, 18 + hash(i, 3) * 40, hash(i, 4) > 0.5
    for k = 1, 4 do blob(x, y, r * (1 - (k - 1) * 0.22), 0.007, light) end
  end
  -- Tufts.
  for i = 1, 220 do
    blob(hash(i, 5) * TILE, hash(i, 6) * TILE, 0.8 + hash(i, 7) * 1.6, 0.06, hash(i, 8) > 0.45)
  end
  lg.pop()
  grass = bake(canvas)
  grass:setWrap("repeat", "repeat")
  grassQuad = lg.newQuad(0, 0, TILE, TILE, TILE, TILE)
end

-- Mottles a plot. wx, wy, ww, wh are the plot in world units, sx, sy where its
-- corner lands on screen.
function Scenery.grass(wx, wy, ww, wh, sx, sy, scale, alpha)
  if not grass then buildGrass() end
  local k = TILE / TILE_WORLD
  grassQuad:setViewport(wx * k, wy * k, ww * k, wh * k, TILE, TILE)
  alpha = alpha or 1
  lg.setBlendMode("alpha", "premultiplied")
  lg.setColor(alpha, alpha, alpha, alpha)
  lg.draw(grass, grassQuad, sx, sy, 0, scale / k, scale / k)
  lg.setBlendMode("alpha")
end

-- How many trees a forest was built with; used by the checks.
function Scenery.treeCount(o)
  return built(o).trees or 0
end

return Scenery
