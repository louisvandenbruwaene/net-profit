-- Headless validation of the contract loop: lua5.4 test/test_contract.lua
-- Generation must never hand the player an impossible or trivial map, so every
-- contract is solved here before it could ever reach a screen.
package.path = "src/?.lua;../src/?.lua;" .. package.path
local C      = require("contract")
local Solver = require("solver")
local G      = require("generate")

local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then pass = pass + 1
  else
    fail = fail + 1
    print(string.format("  FAIL  %s: got %s want %s", name, tostring(got), tostring(want)))
  end
end
local function ok(name, cond)
  if cond then pass = pass + 1
  else fail = fail + 1; print("  FAIL  " .. name) end
end

local TOOLS = { relay = true, hub = true, conduit = true }

--------------------------------------------------------------------------------
print("a contract is only solved when it survives the threat")
do
  local spec = {
    index = 1,
    bounds = { x = 0, y = 0, w = 1000, h = 800 },
    source = { x = 200, y = 400 },
    terminals = { { x = 700, y = 400, demand = 2 } },
    obstacles = {},
    threat = { kind = "edge", count = 1 },
    tools = TOOLS,
    budget = 500,
  }
  local ct = C.new(spec)
  check("starts unsolved", ct:isSolved(), false)
  check("nothing spent", ct.spent, 0)

  -- One chain delivers, but does not survive a cut.
  local r = ct:buildNode(450, 250, "relay")
  ok("relay placed", r ~= nil)
  ct:buildLink(ct.source.id, r.id)
  ct:buildLink(r.id, ct.terminals[1].id)
  ct:upgradeLink(1); ct:upgradeLink(2)
  check("delivers 2 intact", ct.flow, 2)
  check("but nothing survives one cut", (ct:resilience()), 0)
  check("so it is not solved", ct:isSolved(), false)

  -- A second, disjoint route fixes it.
  local r2 = ct:buildNode(450, 550, "relay")
  ct:buildLink(ct.source.id, r2.id)
  ct:buildLink(r2.id, ct.terminals[1].id)
  ct:upgradeLink(3); ct:upgradeLink(4)
  ok("two disjoint routes survive the cut", ct:resilience() >= 2)
  check("now solved", ct:isSolved(), true)

  local spentBefore = ct.spent
  local refund = ct:demolishLink(4)
  ok("demolition refunds in full", ct.spent == spentBefore - refund)
  ct:buildLink(r2.id, ct.terminals[1].id)
  ct:upgradeLink(5)
  check("rebuilt to the same state", ct:isSolved(), true)
end

--------------------------------------------------------------------------------
print("obstacles block ground and links")
do
  local spec = {
    index = 1,
    bounds = { x = 0, y = 0, w = 1000, h = 800 },
    source = { x = 150, y = 400 },
    terminals = { { x = 850, y = 400, demand = 2 } },
    obstacles = { { x = 500, y = 400, r = 120 } },
    threat = { kind = "edge", count = 1 },
    tools = TOOLS,
    budget = 500,
  }
  local ct = C.new(spec)
  ok("cannot build on blocked ground", ct:buildNode(500, 400, "relay") == nil)
  local a = ct:buildNode(500, 250, "relay")
  ok("can build clear of it", a ~= nil)
  -- A link straight through the obstacle must be refused. Both ends are well
  -- inside link range, so the only possible reason is the blocked ground.
  local b = ct:buildNode(500, 550, "relay")
  ok("second relay placed", b ~= nil)
  ok("ends are within link range", ct:rangeBetween(a.id, b.id) >= 300)
  local e, why = ct:buildLink(a.id, b.id)
  ok("link through blocked ground refused", e == nil)
  check("and says why", why, "blocked ground")
end

--------------------------------------------------------------------------------
print("conduits reach further than relays")
do
  local spec = {
    index = 1,
    bounds = { x = 0, y = 0, w = 1200, h = 800 },
    source = { x = 100, y = 400 },
    terminals = { { x = 1100, y = 400, demand = 1 } },
    obstacles = {},
    threat = { kind = "edge", count = 1 },
    tools = TOOLS,
    budget = 500,
  }
  local ct = C.new(spec)
  local far = ct:buildNode(100 + 420, 400, "relay")
  ok("relay cannot span 420", ct:buildLink(ct.source.id, far.id) == nil)
  ct:demolishNode(far.id)
  local cond = ct:buildNode(100 + 420, 400, "conduit")
  ok("conduit can span 420", ct:buildLink(ct.source.id, cond.id) ~= nil)
end

--------------------------------------------------------------------------------
print("generated campaigns are solvable within budget")
do
  local t0 = os.clock()
  local seeds = { 1, 7, 42, 1234, 99999 }
  local totalContracts, hardest = 0, 0
  for _, seed in ipairs(seeds) do
    local camp, failedAt = G.campaign(seed, TOOLS)
    ok("campaign generated for seed " .. seed, camp ~= nil)
    if camp then
      check("run length", #camp, G.RUN_LENGTH)
      for i, spec in ipairs(camp) do
        totalContracts = totalContracts + 1
        ok(string.format("seed %d contract %d has a par", seed, i), spec.par and spec.par > 0)
        ok(string.format("seed %d contract %d budget covers par", seed, i),
           spec.budget >= spec.par)
        -- And the solution actually fits in the budget the player is given.
        local cost = Solver.solve(spec)
        ok(string.format("seed %d contract %d solvable within budget", seed, i),
           cost ~= nil and cost <= spec.budget)
        hardest = math.max(hardest, spec.par)
      end
    end
  end
  print(string.format("  %d contracts generated and solved in %.1fs (hardest par %d)",
    totalContracts, os.clock() - t0, hardest))
end

--------------------------------------------------------------------------------
print("committing runs the adversary the readout promised")
do
  local spec = G.contract(3, TOOLS, function() return 0.5 end)
  ok("contract 3 generated", spec ~= nil)
  if spec then
    local ct = C.new(spec)
    local built = Solver.autoBuild(ct)
    ok("the solver builds a solution", built)
    if built then
      ok("within budget", ct.spent <= ct.budget)
      ok("and solved", ct:isSolved())
      -- The readout is a promise: what it says will survive must be what does.
      local predicted = ct:resilience()
      local result = ct:commit()
      ok("commit succeeds", result.success)
      check("delivery matches the prediction exactly", result.delivered, predicted)
      check("removals match the declared threat", #result.removed, spec.threat.count)
    end
  end
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
