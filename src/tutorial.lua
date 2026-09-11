-- tutorial.lua -- a guided first contract.
--
-- Action steps watch the player's real network and complete when it satisfies
-- them. The order follows the order in which each idea becomes the thing in the
-- way: deliver first, discover that delivering is not surviving, then fix it.
local T = {}

T.active = false
T.step = 1
T.finished = false

-- A fixed site, not a generated one: both routes must be laid with a single
-- relay each, and a random map cannot promise that.
T.SPEC = {
  index = 0,
  bounds = { x = 0, y = 0, w = 1100, h = 800 },
  source = { x = 300, y = 400 },
  -- 270 apart: inside the 300 link range, so step 3 is a single drag.
  terminals = { { x = 570, y = 400, demand = 2 } },
  obstacles = {},
  threat = { kind = "edge", count = 1 },
  tools = { relay = true },
  budget = 200,
  par = 56,
}

local function liveEdges(ct)
  local n = 0
  for _, e in ipairs(ct.g.edges) do if e.alive then n = n + 1 end end
  return n
end

local function terminal(ct) return ct.terminals[1] end

T.steps = {
  {
    kind = "explain",
    title = "A contract, not a wave",
    body = "One site, one budget, no income. The green node supplies, the orange one demands 2. " ..
           "Spend the budget well enough and the contract holds.",
    focus = terminal,
  },
  {
    kind = "explain",
    title = "The adversary is declared up front",
    body = "The sidebar says it severs 1 link. It is not random and it does not wait: " ..
           "it takes whichever single link hurts you most, the moment you commit.",
  },
  {
    kind = "action",
    title = "Lay a link",
    body = "Drag from the source onto the terminal.",
    focus = terminal,
    done = function(ct) return liveEdges(ct) >= 1 end,
  },
  {
    kind = "action",
    title = "Widen it until you deliver 2",
    body = "Click the link, then press U. Watch the small line under AFTER THE STRIKE: it reads how much you deliver right now.",
    done = function(ct) return ct.flow >= ct.demand end,
  },
  {
    kind = "explain",
    title = "You deliver 2, and you survive 0",
    body = "Look at the big number: AFTER THE STRIKE is zero. Your only link is marked red, " ..
           "because losing it loses everything. Capacity is not resilience.",
  },
  {
    kind = "action",
    title = "Build a second route",
    body = "Press 1 and place a relay below the straight line, link source to relay and relay to terminal, " ..
           "then widen those two links as well. The step completes when AFTER THE STRIKE reads 2.",
    done = function(ct) return ct:resilience() >= ct.demand end,
  },
  {
    kind = "explain",
    title = "Now it holds",
    body = "Two routes sharing no link. The adversary can still take one, and the other carries the demand. " ..
           "That is the whole game: not more capacity, but capacity the cut cannot reach.",
  },
  {
    kind = "action",
    title = "Commit",
    body = "Press the COMMIT button, or Enter. The adversary takes exactly what the red marks promised.",
    done = function(ct) return ct.committed end,
  },
  {
    kind = "explain",
    title = "Budget and par",
    body = "Par is the cost of a known good solution. Beating it is the real game once you can hold a contract at all. " ..
           "Demolition refunds in full, so re-laying the whole site is free: use it.",
  },
}

function T.start() T.active, T.finished, T.step = true, false, 1 end
function T.stop() T.active, T.finished = false, true end
function T.current() return T.active and T.steps[T.step] or nil end

function T.isExplain()
  local s = T.current()
  return s ~= nil and s.kind == "explain"
end

function T.advance()
  if not T.active then return false end
  if T.step >= #T.steps then T.stop() else T.step = T.step + 1 end
  return true
end

function T.update(ct)
  local s = T.current()
  if not s or s.kind ~= "action" then return false end
  if s.done and s.done(ct) then
    if T.step >= #T.steps then T.stop() else T.step = T.step + 1 end
    return true
  end
  return false
end

function T.focusPoint(ct)
  local s = T.current()
  if not s or not s.focus then return nil end
  local ok, node = pcall(s.focus, ct)
  if not ok or not node then return nil end
  return node.x, node.y
end

return T
