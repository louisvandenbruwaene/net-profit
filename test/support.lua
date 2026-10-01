-- Shared by the headless suites. Two ways of counting: `check` stops at the
-- first failure, and `ok`/`same` keep going and report every failure before
-- `finish` sets the exit code. And the sandbox company most suites build on.
package.path = "src/?.lua;../src/?.lua;" .. package.path
local City = require("city")

local T = { checks = 0, pass = 0, fail = 0 }

function T.check(value, message)
  assert(value, message)
  T.checks = T.checks + 1
end

function T.ok(name, cond, detail)
  if cond then T.pass = T.pass + 1
  else
    T.fail = T.fail + 1
    print("  FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

function T.same(name, got, want)
  T.ok(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

function T.finish()
  print(string.format("\n%d passed, %d failed", T.pass, T.fail))
  os.exit(T.fail == 0 and 0 or 1)
end

-- A company with the map out of the way: cash, every district owned, every
-- permit and no terrain. `everything` adds every licence and a stock of
-- materials.
function T.sandbox(seed, everything)
  local c = City.new({ seed = seed, obstacles = 0 })
  c.money = 1000000; c.obstacles = {}
  for _, d in ipairs(c.districts) do d.owned = true end
  c.permits = { park = true, bedrock = true, river = true }
  if everything then
    c.stock = { steel = 1000, concrete = 1000, panels = 100 }
    c.licences = { water = true, power = true, oil = true, food = true, beer = true, internet = true }
  end
  return c
end

-- A building put straight into the graph, past the rules, for a fixture.
function T.node(c, kind, x, y, commodity, output)
  local n = c.g:addNode(x, y, kind); n.commodity = commodity
  if output then n.output = output; n.cap = output end
  return n
end

-- Works and plants built of materials go up overnight and run from the next
-- day. A fixture that is about the running building, not the wait, says they
-- were built yesterday.
function T.commission(c, ...)
  for _, n in ipairs({ ... }) do n.assembling = nil end
  c:refresh()
end

return T
