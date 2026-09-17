-- Shared "lay this out efficiently" builder: given a target node and a
-- reach, find the nearest existing fitting with room and spare supply, and
-- hop a chain of T splits from it to the target, exactly the way a careful
-- person extends a network by hand. Written once for the autoplay test
-- player and reused by the hub, which runs the same builder against the
-- player's own network so a hub's coverage is a real, paid-for pipe run
-- instead of an invisible radius.
local N = {}

function N.dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Somewhere free to stand near a point, on owned ground.
function N.spot(c, x, y, ok, reach)
  for r = 0, reach or 120, 12 do
    for i = 0, (r == 0 and 0 or 15) do
      local a = i * math.pi / 8
      local px, py = x + math.cos(a) * r, y + math.sin(a) * r
      if not c:placementError(px, py) and (not ok or ok(px, py)) then return px, py end
    end
  end
end
function N.place(c, kind, x, y, extra, ok, reach)
  local px, py = N.spot(c, x, y, ok, reach)
  if not px then return nil end
  return c:build(px, py, kind, extra) or nil
end

-- Whether a main or a freight line carries a trade.
function N.carries(e, commodity) return e.commodity == commodity or (e.wagons and e.wagons[commodity]) end

-- Everything one network reaches over live mains of one trade.
function N.component(c, start, commodity)
  local seen, queue = { [start] = true }, { start }
  for _, id in ipairs(queue) do
    for _, e in ipairs(c.g:edgesAt(id)) do
      if e.alive and N.carries(e, commodity) and e.cap > 0 then
        local other = e.a == id and e.b or e.a
        if not seen[other] then seen[other] = true; queue[#queue + 1] = other end
      end
    end
  end
  return seen
end

N.FITTING = { junction = true, manifold = true, pump = true }
function N.freePort(c, n) return c:connectionPorts(n.id) < (n.ports or 1) end

-- Unused output of the wells feeding a network, or plenty if a haven feeds it:
-- the outside world does not run out.
function N.headroom(c, seen, commodity)
  local spare = 0
  for id in pairs(seen) do
    local n = c.g.nodes[id]
    if n.kind == "terminal" then return math.huge end
    if n.kind == "source" and n.commodity == commodity then
      spare = spare + math.max(0, (n.effectiveOutput or n.output or 0) - (c.produced[n.id] or 0))
    end
  end
  return spare
end

-- A chain of T splits from a fitting towards a building, finishing with a main
-- into it. True only if every link went in.
function N.chain(c, from, target, commodity, last, mid)
  local hops = math.max(1, math.ceil(N.dist(from, target) / 240))
  if hops > 6 then return false end
  local start = from
  for i = 1, hops - 1 do
    local t = i / hops
    local x, y = N.spot(c, start.x + (target.x - start.x) * t, start.y + (target.y - start.y) * t,
      function(px, py) return N.dist(from, { x = px, y = py }) < 290 end)
    local n = x and c:build(x, y, "junction")
    if not n or not c:layPipe(from.id, n.id, commodity, mid or "medium", nil, c.lining) then return false end
    from = n
  end
  return c:layPipe(from.id, target.id, commodity, last or "small", nil, c.lining) ~= nil
end

-- The nearest existing fitting (or freight yard, for anything but water) that
-- already reaches this commodity's network with room to spare, chained on to
-- the target. This is what makes the result efficient without any real
-- pathfinding: later targets naturally reuse whatever earlier ones built.
function N.connectPipe(c, target, want, commodity, last, mid)
  local best
  for _, n in ipairs(c.g:aliveNodes()) do
    if (N.FITTING[n.kind] or n.kind == "dc" and commodity ~= "water") and n.id ~= target.id
      and not c:pipeBetween(n.id, target.id, commodity)
      and N.dist(n, target) < 1400 and (not best or N.dist(n, target) < N.dist(best, target))
      and (N.freePort(c, n) or n.kind == "junction" and N.dist(n, target) < 500)
      and N.headroom(c, N.component(c, n.id, commodity), commodity) >= want then best = n end
  end
  if not best then return false end
  -- A full T split becomes a hub, which is what a person does when one runs out of room.
  if not N.freePort(c, best) and not c:convertNode(best.id, "manifold", commodity) then return false end
  return N.chain(c, best, target, commodity, last, mid)
end

return N
