-- Headless validation of the endless map: luajit test/test_generation.lua
--
-- The one property everything else rests on is that ground is the same ground
-- whoever surveys it first. If generation ever drifts back onto the shared
-- random stream, these checks are what notices.
package.path = "src/?.lua;../src/?.lua;" .. package.path
local City = require("city")

local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then pass = pass + 1
  else fail = fail + 1
    print(string.format("  FAIL  %s: got %s want %s", name, tostring(got), tostring(want))) end
end
local function ok(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL  " .. name) end
end

-- Everything a cell is, as one string.
local function fingerprint(c, col, row)
  local d = c:cellAt(col, row)
  if not d then return nil end
  local parts = { d.name, d.ring, (d.spec and (d.spec.key or d.spec.name)) or "?" }
  for _, o in ipairs(c.obstacles) do
    if c:districtAt(o.x, o.y) == d then
      parts[#parts + 1] = string.format("%s:%.2f,%.2f,%.0f", o.kind, o.x, o.y, o.r)
    end
  end
  for _, dep in ipairs(c.deposits) do
    if c:districtAt(dep.x, dep.y) == d then
      parts[#parts + 1] = string.format("%s:%.2f,%.2f,%d", dep.commodity, dep.x, dep.y, dep.cap)
    end
  end
  return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
print("ground is generated the same whoever walks there first")
do
  local a, b = City.new({ seed = 4242 }), City.new({ seed = 4242 })
  a.money, b.money = 1e9, 1e9
  -- Two companies on the same seed take opposite routes out of the city.
  for _, cell in ipairs({ {3,2}, {4,2}, {5,2}, {5,3}, {5,4} }) do
    a:buyDistrict(a:cellAt(cell[1], cell[2]).id)
  end
  for _, cell in ipairs({ {2,3}, {3,3}, {4,3}, {5,3}, {5,2} }) do
    b:buyDistrict(b:cellAt(cell[1], cell[2]).id)
  end
  local shared, same = 0, 0
  for col = 0, 8 do
    for row = 1, 7 do
      local fa, fb = fingerprint(a, col, row), fingerprint(b, col, row)
      if fa and fb then
        shared = shared + 1
        if fa == fb then same = same + 1 end
      end
    end
  end
  ok("the two routes overlap at all", shared > 12)
  check("and every shared cell is identical", same, shared)

  local other = City.new({ seed = 4243 })
  ok("a different seed is a different city",
    fingerprint(other, 2, 1) ~= fingerprint(a, 2, 1))
end

--------------------------------------------------------------------------------
print("the map has no edge, and the sea is the one exception")
do
  local c = City.new({ seed = 11 })
  c.money = 1e9
  local col, row = 2, 2
  for step = 1, 8 do
    local d = c:cellAt(col + step, row)
    ok("ground keeps appearing to the east: step " .. step, d ~= nil)
    if not d then break end
    c:buyDistrict(d.id)
  end
  for step = 1, 3 do
    local d = c:cellAt(2, 2 + step)
    ok("and to the south: step " .. step, d ~= nil)
    if not d then break end
    c:buyDistrict(d.id)
  end
  check("but never above the coast", c:cellAt(2, 0), nil)
  check("nothing can be built out to sea", c:placementError(1200, -50), "that is the sea")
  ok("ground nobody has been near is not surveyed", c:cellAt(40, 40) == nil)
end

--------------------------------------------------------------------------------
print("distance is worth travelling for")
do
  local c = City.new({ seed = 77 })
  ok("water deposits cap higher further out",
    City.depositCap("water", 3) > City.depositCap("water", 0))
  ok("and so do oil deposits",
    City.depositCap("oil", 4) > City.depositCap("oil", 1))
  local near = c:districtCost(c:cellAt(2, 2))
  local far = c:districtCost({ ring = 4 })
  ok("and the ground out there costs more to buy", far > near * 2)

  -- A well cannot pass the ground it stands on, however deep it is sunk.
  c.money = 1e9
  local seam
  for _, d in ipairs(c.deposits) do
    local ground = c:districtAt(d.x, d.y)
    if not d.taken and d.commodity == "water" and ground and ground.owned
       and not c:placementError(d.x, d.y) then seam = d; break end
  end
  ok("there is water on the home ground", seam ~= nil)
  local well = c:buySource("water", seam.x, seam.y)
  ok("a well opens on it", well ~= nil)
  for _ = 1, City.sourceMaxLevel do c:upgradeSource(well.id) end
  check("and stops at what the ground gives", well.output, well.cap)
  ok("which is the deposit's own ceiling", well.cap == seam.cap)
  local why = select(2, c:upgradeSource(well.id))
  ok("with a reason the player can read", type(why) == "string" and why:find("no more"))
end

--------------------------------------------------------------------------------
print("a surveyed city saves and comes back the same")
do
  local Save = require("company_save")
  local c = City.new({ seed = 300 })
  c.money = 1e9
  for _, cell in ipairs({ {3,2}, {4,2}, {4,3} }) do c:buyDistrict(c:cellAt(cell[1], cell[2]).id) end
  local before, cells = {}, 0
  for _, d in ipairs(c.districts) do
    before[d.col .. "," .. d.row] = fingerprint(c, d.col, d.row)
    cells = cells + 1
  end
  local clone = assert(Save.unpack(Save.pack(c)))
  local matched = 0
  for key, print_ in pairs(before) do
    local col, row = key:match("(-?%d+),(-?%d+)")
    if fingerprint(clone, tonumber(col), tonumber(row)) == print_ then matched = matched + 1 end
  end
  check("every surveyed cell survives the round trip", matched, cells)
  ok("and the frontier is still open", #clone.districts >= #c.districts)
  ok("ground bought stays bought", #clone:ownedDistricts() == #c:ownedDistricts())
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
