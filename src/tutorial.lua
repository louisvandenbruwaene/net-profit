-- tutorial.lua -- a guided first run.
--
-- It is not a text dump and it does not script the world: every action step
-- watches the player's real graph and completes when the graph satisfies it.
-- The order is chosen so each idea arrives at the moment it is the thing
-- standing in the player's way, which is the only time a definition sticks.
local Graph = require("graph")

local T = {}

T.active = false
T.step = 1
T.finished = false

local function source(run) return run.g.nodes[run.source.id] end
local function terminal(run) return run.g:nodesOfKind("sink")[1] end

local function liveEdges(run)
  local n = 0
  for _, e in ipairs(run.g.edges) do
    if e.alive then n = n + 1 end
  end
  return n
end

-- kind "explain" waits for the player to press on. kind "action" waits for the
-- graph to satisfy `done`.
T.steps = {
  {
    kind = "explain",
    title = "This is your source",
    body = "The green node supplies the network. Every unit of flow in the game starts here.",
    focus = source,
  },
  {
    kind = "explain",
    title = "This is a terminal",
    body = "The orange node demands supply. The number under it reads delivered / demanded. " ..
           "Every wave it wants more, and if any terminal goes unsupplied the run ends.",
    focus = terminal,
  },
  {
    kind = "action",
    title = "Lay your first link",
    body = "Press and drag from the source onto the terminal.",
    focus = terminal,
    done = function(run) return liveEdges(run) >= 1 end,
  },
  {
    kind = "explain",
    title = "Capacity and flow are different things",
    body = "The link's thickness is its capacity, what it could carry. The moving dots are " ..
           "the flow, what it actually carries. A new link has capacity 1, and the terminal asks for 2.",
    focus = terminal,
  },
  {
    kind = "action",
    title = "Widen the link",
    body = "Click the link to select it, then press U to add capacity. Watch DELIVERY in the sidebar reach the number it needs.",
    done = function(run) return run.flow >= run.demand end,
  },
  {
    kind = "action",
    title = "Resolve the wave",
    body = "Delivery now meets demand. Press SPACE, or the button at the bottom right.",
    done = function(run) return run.wave > 1 end,
  },
  {
    kind = "explain",
    title = "That red line is your minimum cut",
    body = "It marks the cheapest set of links that would separate supply from demand. Its total " ..
           "capacity is exactly your maximum flow, so nothing you build elsewhere raises delivery " ..
           "until the cut itself gets wider.",
    focus = function(run)
      for _, c in ipairs(run.cut or {}) do
        if c.kind == "edge" then
          local e = run.g.edges[c.id]
          if e and e.alive then
            local a, b = run.g.nodes[e.a], run.g.nodes[e.b]
            return { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2 }
          end
        end
      end
      return terminal(run)
    end,
  },
  {
    kind = "explain",
    title = "The adversary cuts exactly there",
    body = "Every wave from now on it severs a link from that cut. Your cut is one link wide, " ..
           "so one strike takes everything. Capacity alone will not save you.",
  },
  {
    kind = "action",
    title = "Place a relay",
    body = "Press 1, then click an empty spot to one side of the straight line between source and terminal.",
    done = function(run) return #run.g:aliveNodes() >= 3 end,
  },
  {
    kind = "action",
    title = "Route around",
    body = "Drag source to relay, then relay to terminal. That gives you a second path that shares no link with the first.",
    done = function(run) return #(run.cut or {}) >= 2 end,
  },
  {
    kind = "explain",
    title = "Now the cut is two wide",
    body = "A strike costs you half your throughput instead of all of it. This is the whole game: " ..
           "keep delivery at or above demand, and keep the cut wider than the number of strikes. " ..
           "The sidebar tells you both numbers every wave.",
  },
  {
    kind = "explain",
    title = "You have it",
    body = "1 2 3 pick a node and click to place. Drag node to node to link. U upgrades, X demolishes. " ..
           "SPACE resolves. H reopens the full reference. The line at the bottom always names your next problem.",
  },
}

function T.start()
  T.active = true
  T.finished = false
  T.step = 1
end

function T.stop()
  T.active = false
  T.finished = true
end

function T.current()
  if not T.active then return nil end
  return T.steps[T.step]
end

function T.isExplain()
  local s = T.current()
  return s ~= nil and s.kind == "explain"
end

-- Advance an explain step. Action steps ignore this.
function T.advance()
  if not T.active then return false end
  if T.step >= #T.steps then
    T.stop()
    return true
  end
  T.step = T.step + 1
  return true
end

-- Called every frame: completes action steps when the graph satisfies them.
function T.update(run)
  local s = T.current()
  if not s or s.kind ~= "action" then return false end
  if s.done and s.done(run) then
    if T.step >= #T.steps then T.stop() else T.step = T.step + 1 end
    return true
  end
  return false
end

function T.focusPoint(run)
  local s = T.current()
  if not s or not s.focus then return nil end
  local ok, node = pcall(s.focus, run)
  if not ok or not node then return nil end
  return node.x, node.y
end

return T
