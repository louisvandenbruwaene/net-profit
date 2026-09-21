-- Every panel, with content at the size it reaches in a long company.
--
-- The other walkthroughs play the game, so they draw what a short game draws:
-- small numbers, two customers, one well. Text runs into its neighbour at the
-- other end -- seven figures of cash, a company with a name, a works with four
-- inputs, sixty clients, an inspector for a building that took three days to
-- unlock. This builds one of those companies and opens everything on it.
--
-- Nothing here is checked by eye. It exists so `make layout` has something to
-- measure, and the assertions it does make are only that the panel drew at all.
local City = require("city")
local UI = require("company_ui")

return function(app, capture, click, scrollTo, check)
  local c = City.new({ seed = 24, obstacles = 0 })
  c.money = 9876543
  c.obstacles = {}
  c.companyName = "Vandenbruwaene Municipal Water & Power"
  c.reputation = 100
  c.guideDismissed = true
  c.lining = #City.GRADES
  c.crews = City.crewMax
  c.stock = { steel = 900, concrete = 900, glass = 400, panels = 60, timber = 400, rock = 400 }
  c.permits = { park = true, bedrock = true, river = true }
  for _, d in ipairs(c.districts) do d.owned = true; d.population = 900 end
  for name in pairs(c.licences) do c.licences[name] = true end
  -- Everything unlocked, so no panel is missing the half of itself that only
  -- appears late.
  c.unlocked = function() return true end
  c.history = {}
  for day = 1, 180 do
    c.history[day] = { day = day, revenue = 1200 + day * 37, expenses = 900 + day * 21 }
  end
  c.day = 181
  app.setTestCity(c)

  -- Somewhere to put a building, since the first choice is often occupied.
  local function place(kind, x, y, extra)
    for i = 0, 80 do
      local n = c:build(x + ((i * 137) % 420) - 210, y + ((i * 89) % 360) - 180, kind, extra)
      if n then return n end
    end
    return nil
  end

  local home = c.districts[City.MAP.start]
  local ox, oy = home.x + home.w / 2, home.y + home.h / 2
  local well
  for _, deposit in ipairs(c.deposits) do
    if not well and deposit.commodity == "water" then well = c:buySource("water", deposit.x, deposit.y) end
  end
  well = well or c.firstSource
  local plant = place("junction", ox + 500, oy - 400) and c:buySource("power", ox + 500, oy - 400, "nuclear")

  local built, placed = {}, 0
  for _, kind in ipairs({ "junction", "manifold", "pump", "gate", "depot", "filtration", "binder",
                          "tower", "lab", "exchange", "dc", "stop", "station", "resort",
                          "pole", "pylon", "hvtower", "corner", "roundabout", "interchange" }) do
    built[kind] = place(kind, ox + (placed % 5) * 240 - 400, oy + math.floor(placed / 5) * 240 - 300)
    placed = placed + 1
  end
  built.terminal = place("terminal", c:cellAt(home.col, home.row - 1).x + 200,
    c:cellAt(home.col, home.row - 1).y + 120, "port")
  built.works = place("works", ox - 700, oy + 500, "brewery")

  -- A network with something in it: a trunk out of the well, stubs off it, and
  -- customers of every kind, some signed, some still deciding.
  local hub = built.junction or place("junction", well.x + 200, well.y + 120)
  if hub then pcall(function() c:layPipe(well.id, hub.id, "water", "trunk") end) end
  for i = 1, 26 do
    local kind = ({ "house", "estate", "workshop", "pub", "factory", "market", "home", "subscriber" })[(i % 8) + 1]
    local client = c:addClient(kind, i % 4 == 0)
    if client and i % 4 ~= 0 then c:acceptClient(client.id) end
    if client and hub then pcall(function() c:layPipe(hub.id, client.id, client.commodity, "small") end) end
  end
  -- One of everything the inspector shows differently: a burst main, a client
  -- short of supply, a secure contract, a household on both utilities.
  local leak
  for _, e in ipairs(c.g.edges) do
    if e.alive and not leak then leak = e; e.leaking = true; e.cap = 0 end
  end
  for _, client in ipairs(c:clientList()) do
    if client.commodity == "water" and not client.secure then client.secure = true; break end
  end
  for _, client in ipairs(c:clientList()) do
    if client.commodity == "water" and not client.powerAccepted then
      client.powerAccepted = true
      client.utilityRates = { water = 4, power = 6 }
      break
    end
  end
  c:refresh()

  local sizes = { { 1100, 700 }, { 1440, 880 } }
  local shots = 0
  local function sweep(name, prepare)
    for _, size in ipairs(sizes) do
      prepare()
      -- Scrolled to the top and to the bottom: the foot of a long panel is
      -- where the crowding is, and it is never on screen at the top.
      for _, scroll in ipairs({ 0, 1 }) do
        app.state.scroll = scroll == 0 and 0 or (UI.maxScroll or 0)
        capture("net-profit-stress-" .. name .. "-" .. size[1] .. "-" .. scroll, app, size[1], size[2], true)
        shots = shots + 1
      end
    end
  end

  for _, tab in ipairs({ "network", "finance", "customers", "map", "stats", "ambitions", "ledger", "advisor" }) do
    sweep(tab, function()
      app.state.modal = nil; app.state.node = nil; app.state.edge = nil; app.state.link = nil
      app.state.tab = tab
    end)
  end
  -- The build panel with each trade in hand, and with its options open.
  for _, trade in ipairs({ "water", "power", "beer", "oil", "food", "internet", "steel" }) do
    sweep("build-" .. trade, function()
      app.state.modal = nil; app.state.node = nil; app.state.edge = nil
      app.state.tab = "network"; app.state.commodity = trade
      app.state.lineOptions = true; app.state.showSupply = true
      app.state.voltageHelp = true; app.state.ampereHelp = true; app.state.buildHelp = true
    end)
  end
  app.state.lineOptions = nil; app.state.voltageHelp = nil; app.state.ampereHelp = nil
  app.state.commodity = "water"
  -- Every inspector, on a real building of that kind.
  local seen = {}
  for _, n in ipairs(c.g:aliveNodes()) do
    local key = n.kind .. (n.clientType or "")
    if not seen[key] then
      seen[key] = true
      sweep("node-" .. key, function() app.action("focusNode", n.id) end)
    end
  end
  for _, e in ipairs(c.g.edges) do
    local key = e.commodity .. (e.leaking and "-leaking" or "")
    if e.alive and not seen[key] then
      seen[key] = true
      sweep("edge-" .. key, function() app.action("focusEdge", e.id) end)
    end
  end
  -- And the two panels that sit over the top of everything.
  c:endDay()
  sweep("report", function()
    app.state.node = nil; app.state.tab = "stats"
    app.state.modal = "report"; app.state.reportDetails = true
  end)
  sweep("slots", function() app.action("openSlots") end)
  app.state.modal = nil
  check(shots > 100, "the stress sweep drew every panel: " .. shots .. " screens")
end
