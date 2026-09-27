# Net Profit: the infinite city

A plan for turning a fixed twelve district map into an endless one, and a single
utility network into a distribution empire. Seven phases, each of which leaves a
game that is finished enough to play if the next one never happens.

**All seven are built.** What follows is the design that was implemented, with a
status line on each phase and a list at the end of every place the built thing
differs from the plan and why. `README.md` describes how to play it.

---

## 0. What the game becomes, and what must not change

Today you draw a pipe from a well to a house. At the end of this plan you place
a hub in a new town and it wires itself, you ship malt from a farm three hundred
kilometres away because your own maltings is cheaper than the port, and you sit
above a rule sheet that buys ground while you are looking somewhere else.

Four things hold across every phase, because they are what the game is:

1. **Everything is priced per unit and per metre.** Distance is the cost. That
   one rule already decides water against oil, and it will decide road against
   rail and against ship.
2. **The flow solver stays a max flow over a node split graph.** Structures that
   limit flow set `throughput`, structures that make it feed the super source.
   Every new building in this plan is one of those two things.
3. **Saves are versioned and migrated open, never broken.** A company at day 94
   must load on the day the sea appears.
4. **One file per system, and the game runs at sixty frames on a laptop.**

The economic spine stays: pay for capacity, get paid for delivery, pay again
when it rots.

---

## 1. Infinite ground

**Built.** `City:surveyCell`, `City:cellSeed`, `test/test_generation.lua`.

**What the player sees.** The map has no edge. Buy outward in any direction for
as long as the cheque clears. The further out you go, the richer the ground and
the more it costs to get there.

**How.**

The twelve authored districts stay exactly as they are and become the core,
which keeps the opening hand tuned and every existing save valid. Everything
beyond them is generated on demand.

```
districtKey(col, row) -> "col,row"
City:districtAtCell(col, row)      -- generates if absent, then caches
City:cellHash(col, row)            -- deterministic, order independent
```

The one technical rule that matters: **generation must never draw from
`City:random()`**. That is a single stream shared with leaks, offers and market
events, so anything generated from it depends on the order the player happened
to pan around in. Generation gets its own hash:

```lua
-- FNV style mix of the city seed and the cell, so a cell always generates the
-- same ground whoever looks at it first.
function City:cellHash(col, row)
  local h = 2166136261
  for _, v in ipairs({ self.seed, col * 73856093, row * 19349663 }) do
    h = (h ~ v) * 16777619 % 4294967296
  end
  return h
end
```

Every cell then seeds a small local LCG used for its name, its character, its
obstacles and its deposits.

**Rings.** `ring = max(abs(col - startCol), abs(row - startRow))`. The ring
drives four numbers at once, which is what makes expansion a decision rather
than a formality:

| Ring | Ground price | Water deposit cap | Oil deposit cap | Character |
|------|--------------|-------------------|-----------------|-----------|
| 0 | authored | 14 / day | 10 / day | the authored twelve |
| 1 | x1.6 | 18 | 14 | suburb, farmland appears |
| 2 | x2.4 | 24 | 20 | rural, forestry and quarry ground |
| 3 | x3.4 | 30 | 28 | frontier, ore appears |
| 4+ | x1.35 per ring | +6 per ring | +8 per ring | wilderness, the richest seams |

**Maximum daily output** is new and applies to every natural source. A well on a
ring 0 deposit gives 14 a day and no upgrade path takes it past that. Deepening
a well now means approaching its cap rather than passing it. This is the
pressure that makes an endless map necessary rather than decorative: the only
way to more water is more ground.

**Saves.** Format v3 stores the seed, a sparse table of cells that were touched,
and nothing else. A touched cell records only what the generator cannot
reproduce: owned, deposits taken, obstacles cleared by permit, buildings. A
thousand explored cells cost a few kilobytes.

**Camera and buying.** `districtAdjacent` already only allows next door, so
outward growth is free. The camera clamp becomes owned bounds plus two rings.
The map tab's list of twelve becomes a list of what you own plus what is for
sale next to it, sorted by distance from the yard.

**Files.** `city.lua` (generation, rings, caps), `company_save.lua` (v3 sparse),
`company_render.lua` (draw only visible cells), `company_ui.lua` (map tab list),
`camera.lua` (clamp).

**Test.** `test_generation.lua`: the same cell generated from two different
visit orders is identical, ring caps hold, and a v2 save loads with its twelve
districts intact.

---

## 2. The macro shift: hubs

**Built.** Keyed `exchange` in `Graph.KINDS`, because the archived contract game already owns `hub`.

**What the player sees.** Stop drawing a pipe to every house. Drop a hub in a
town, set the rate you will serve at, and every customer in range who pays that
much connects itself. The pipes you draw by hand are trunk mains between hubs,
works and sources.

**How.**

A hub is a structure with a radius (start at 700 m) and a price floor the player
sets. At every refresh it takes in every client inside its radius whose rate
clears the floor, and presents their summed demand to the network as one drain
per commodity.

The covered clients **leave the flow graph entirely**. This is the whole trick,
and it is what makes an endless map possible at all: a thousand houses become
one node with demand 3000 rather than a thousand nodes and a thousand edges.

```
hub.covered[commodity] = sum of demand of clients in radius over the floor
hub.lastMile          = one off fee per client + a daily fee per client
```

The last mile is charged, not modelled. A house connected by a hub costs a
connection fee and a daily fee and is never drawn as a pipe. That is honest: a
water company does not draw its service pipes on the strategy map either.

**Automatic upgrade** arrives here in its first form. A hub widens its own feed
when it runs above 90% for three days, charging the player the normal upgrade
price. It is a standing order with a wage, not a free lunch.

**Why this is the right moment for it.** Phase 1 makes the map endless. Without
hubs the player is handed a thousand pipes to draw and the game becomes
clerical. Phase 2 has to follow phase 1 immediately.

**Files.** `graph.lua` (hub aggregation in `buildNetwork`), `city.lua` (hub
rules, coverage, fees), `company_ui.lua` (hub inspector with the rate floor
slider), `company_render.lua` (coverage circle, covered clients drawn as dots).

**Test.** Coverage is exact, a client below the floor is refused, hub demand
equals the sum of covered demand, and a thousand client company solves in under
16 ms.

---

## 3. The sea, the coast and the islands

**Built.** The coast came forward into phase 1, because an endless map needs to know which way is north before anything else does.

**What the player sees.** Above y = 0 there is sea, and it does not end. Islands
sit out in it, buyable like ground. Wind parks stand on them. Harbours have to
be on the coast, which is now a real place rather than a strip of the map edge.

**How.**

The sea replaces the estuary band that phase 0 of today's game draws on the west
side. Cells above row 0 are sea cells. A sea cell generates either open water or
an island (roughly one in seven, more further out). Islands are small, cost more
than land, and are bought without the adjacency rule as long as you already hold
one coastal cell, because ships do not care what is next door.

The coastline is the row 0 boundary. A harbour must stand within 150 m of it,
which is the rule the current havens already use, now attached to something the
player can see the shape of.

**What islands are for.**

| Island use | Why you would |
|------------|---------------|
| Wind park | electricity with no fuel and no uranium, and no neighbours to object |
| Deep water harbour | the cheapest import prices in the game, but every unit needs a ship |
| Dredging | sand, which is glass and concrete |
| Desalination | water where there is no deposit, expensive per unit and unlimited |

Wind is the clean endgame: a wind park costs steel and concrete you had to make
or import, and then produces forever with no input at all.

**Files.** `city.lua` (sea cells, islands, coast test), `company_render.lua`
(water, islands, coastline), `company_ui.lua` (island purchase).

---

## 4. The freight layer

**Built.** `City.MODES`, wagons on the edge, the depot yard as the inland freight terminal.

**What the player sees.** A second network, drawn over the first. Distribution
centres, rail yards, harbours and airports, joined by lines that move anything
in bulk. Expensive to lay, expensive to run, and they move amounts a pipe cannot.

**How.**

Two layers, and the difference between them is the design:

- **Last mile.** One commodity per line. Cheap per metre, short range, fine
  grained. Pipes, cables, conveyors.
- **Bulk.** Any commodity, in wagons or holds. Enormous capex, enormous
  capacity, cheap per unit per metre once it exists. Rail, road, sea, air.

A bulk line terminates only at a bulk node: a distribution centre, a rail yard,
a harbour or an airport. A distribution centre is the interchange between the
two layers, and it is the new building the whole phase hangs off.

**The modes, and the niche each one owns:**

| Mode | Carries | Capex | Per unit per km | Capacity | Range | Notes |
|------|---------|-------|-----------------|----------|-------|-------|
| Road | anything | low | high | 40 | 400 km | drivers' wages and diesel, per unit |
| Rail | anything, in wagons | very high | very low | 600 | 2000 km | one wagon per commodity, assign each |
| Ship | bulk solids and liquids only | high | lowest | 4000 | unlimited coastal | port to port and island only |
| Air | one class per aircraft | high | highest | 20 | unlimited | tanker, freighter or reefer, pick per route |

A train is one line with a wagon list. Eight wagons means up to eight
commodities at once, each capped at the wagon's share. That is his requirement
answered directly: beer, oil and water cannot share a pipe, they share a train.

Aircraft split by class because a tanker cannot carry ore. That is the reason
air freight is a decision and not just a faster ship.

**Diesel becomes an operating cost, not only cash.** Road and ship burn diesel
per unit per km. Early you buy it at the port at import price. Later you refine
it from your own crude and your haulage bill halves. That is the first real
synergy between the two halves of the game.

**Files.** new `freight.lua` (bulk graph, modes, wagons, haulage), `graph.lua`
(the interchange node), `city.lua` (pricing), `company_render.lua` (bulk lines
drawn heavier and under the pipes), `company_ui.lua` (route builder).

---

## 5. Commodities and recipes

**Built.** Eighteen commodities, nine works, `City.SOLVE_ORDER`.

**What the player sees.** Beer stops being a thing you buy and becomes a thing
you make out of water, malt and electricity. Everything the city needs has a
chain behind it, and every link of the chain is somewhere on the map.

**How.**

Every commodity has exactly one role, which is what keeps eighteen of them
legible:

- **Utility.** Sold to clients, per unit per day. Water, power, beer, oil, food.
- **Feedstock.** Consumed by works. Wheat, malt, timber, ore, coke, sand, rock,
  cement, crude, uranium, diesel.
- **Material.** Spent on construction. Steel, planks, concrete, glass.

**Where raw things come from:**

| Commodity | Source | Import |
|-----------|--------|--------|
| Water | well on a deposit, capped | yes |
| Crude | rig on a deposit, capped | yes |
| Wheat | farmland, outer rings | yes |
| Timber | forestry on woodland, which is what the parkland permit is really for | yes |
| Iron ore | mine on a deposit, ring 3 and out | yes |
| Rock | quarry on bedrock, which is what the blasting licence is really for | no |
| Sand | coastal quarry or island dredging | yes |
| Coke | none | yes, port only |
| Uranium | none | yes, port only, licence |

Two of those are the payoff for permits that already exist. Parkland stops being
an obstacle and becomes a forest. Bedrock stops being a wall and becomes a
quarry. Nothing new has to be explained to the player for either.

**The recipes.** One output each, because multiple outputs double the interface
and add nothing the player will thank you for:

| Works | In | Out |
|-------|----|-----|
| Refinery | 2 crude, 1 power | 1 diesel |
| Maltings | 1 wheat, 1 water, 1 power | 1 malt |
| Brewery | 1 malt, 2 water, 1 power | 1 beer |
| Foodworks | 2 wheat, 1 water, 1 power | 1 food |
| Sawmill | 2 timber, 1 power | 1 planks |
| Steelworks | 2 ore, 1 coke, 3 power | 1 steel |
| Glassworks | 2 sand, 2 power | 1 glass |
| Cement works | 2 rock, 2 power | 1 cement |
| Concrete plant | 1 cement, 2 sand, 1 water | 1 concrete |
| Reactor | 1 uranium, 4 water | 40 power |
| Wind park | nothing | 8 power per turbine |

**Solving production without breaking the solver.** This is the one genuinely
new problem in the whole plan.

The recipes form a directed graph. Keep it acyclic by one rule: **a well, a mine
and a quarry never need power.** With that, the graph has a topological order,
and a refresh becomes:

```
for each commodity in topological order of the recipe graph:
    solve that commodity's network      (exactly today's maxflow)
    for each works consuming it:
        record what actually arrived
for each works:
    output = min over inputs of (arrived / required) * rated output
```

Wind bootstraps power with no inputs, so the order always has a start. One pass
is correct because nothing downstream can feed anything upstream. A works is a
drain on its input networks and a feed on its output network, which are both
things the solver already does.

**Files.** `recipes.lua` (the table and the topological order), `graph.lua`
(works as drain and feed), `city.lua` (refresh in order), UI for a works.

---

## 6. Building out of what you make

**Built.** `City.MATERIALS`, stock held in the yards.

**What the player sees.** A hub costs money and steel. A rail line costs money,
steel and concrete. When your own steelworks is running, expansion gets cheaper.

**How.** Every structure gains a bill of materials alongside its price. Materials
come out of the network at the build site, which means the distribution network
has to reach the place you want to build before you can build there. Early on
you have no steelworks, so you buy steel at the port and haul it, which is
exactly the tutorial for the freight layer.

| Structure | Cash | Materials |
|-----------|------|-----------|
| Junction, valve | as now | none |
| Hub | 1400 | 20 steel |
| Works | 2000 to 9000 | 40 steel, 30 concrete |
| Rail line, per km | 600 | 12 steel |
| Harbour | 6000 | 120 steel, 200 concrete |
| Reactor | 12000 | 300 steel, 500 concrete |
| Wind turbine | 2200 | 60 steel, 40 concrete |

This is the loop the whole plan exists to close: the network carries the
materials that extend the network.

---

## 7. The automation ladder

**Built.** `City.ORDERS`, four departments.

**What the player sees.** The company stops being a thing you operate and starts
being a thing you run. Each rung is bought once and then paid for daily.

| Rung | Buys you | Wage |
|------|----------|------|
| Crews | repair the worst main every close (exists today) | 14 / day |
| Surveyors | deposits revealed the moment ground is bought | 20 / day |
| Dispatchers | sign any offer over a rate you set | 30 / day |
| Engineers | widen any main over 90% for three days | 45 / day |
| Estates | buy adjacent ground when cash is over a reserve you set | 60 / day |
| Operations | the whole rule sheet, and a daily report instead of a day | 140 / day |

Every rung is a rule the player writes rather than a thing that happens to them.
The wage is the point: automation is a cost centre that beats the alternative
only at scale, which is exactly when it unlocks.

---

## 8. The performance budget

An endless map is a promise about frame time. Targets for a company with 5000
clients, 400 hubs and 18 commodities:

| Measure | Budget |
|---------|--------|
| Nodes actually solved | under 2500, because hubs absorb clients |
| Full resolve, all commodities | under 16 ms |
| Day close | under 40 ms |
| Save file at 1000 explored cells | under 400 kB |

Four things keep it there:

1. **Hub aggregation.** Clients are summed, not solved.
2. **Dirty commodities.** Solve only the networks a change touched. Laying a
   beer main does not resolve water.
3. **Component partition.** Solve each connected component separately. Early on
   a company is four unrelated islands of pipe.
4. **Solve on change, not per frame.** Already true today and must stay true.

Add `test/bench_flow.lua` in phase 1 and run it in CI from then on, so the
number is watched rather than remembered.

---

## 9. Build order

Each phase ships. If the next one never happens, the game is still whole.

| Phase | Ships | Depends on |
|-------|-------|------------|
| 1 | Infinite ground, output caps, sparse saves | nothing |
| 2 | Hubs, auto connect, auto widen | 1 |
| 3 | Sea, coast, islands, wind | 1 |
| 4 | Freight layer, distribution centres, wagons, diesel as a cost | 2, 3 |
| 5 | Commodities, works, the recipe solve | 4 |
| 6 | Bills of materials | 5 |
| 7 | The automation ladder | 2, 5 |

Phase 1 alone is worth having: today's game, endless, with wells that cap. Phase
2 alone changes what the game is about. Everything after that is the empire.

---

## 10. Risks, and what to cut first

- **Eighteen commodities is a lot of sidebar.** The trade row is four buttons
  today. If it stops being readable, ship only water, power, oil, beer, wheat,
  malt, steel, uranium and cut the rest to imports.
- **The recipe solve is the only new algorithm.** If the topological order turns
  out to have a cycle in practice, the answer is to remove the cycle from the
  recipes, never to iterate to a fixed point.
- **Perishable food and reefer aircraft.** Cut unless air freight needs a second
  reason to exist.
- **Animated trucks and trains.** They are eye candy and they are cheap eye
  candy, but they are not a mechanic. Draw a moving dot, not a simulation.
- **Multi output refineries.** Cut. One output per works.
- **Save size.** If sparse cells still grow without bound, cap the explored set
  and regenerate anything untouched.

## 13. The rebalance, and what it changed underneath

Two passes after the seven phases, both of them about what the game asks of a
player rather than what it contains.

The first made every trade reachable: the licence, one building and water. It
also made wide mains cheap, ground cheapest at the coast, and nothing visible
before it can be used.

The second undid one of its own answers. Giving every works a base recipe and
optional boosts meant a brewery could make beer out of water, which made the
chain an optimisation rather than the game. Recipes are strict again: a works
missing any input makes nothing. What replaced the boosts is the order trades
arrive in. Power needs only water and everything else needs power, so it comes
first; oil is a rig on marked ground; food needs a farm and a haven for salt,
which nobody mines here; beer needs malt, and malt needs wheat, so it is last.
The balance suite now checks that property directly: every input of every trade
is water, or something an earlier trade reached, or something a haven lands.

Mains stopped being a number. Three sizes, nothing widens, and the lining is
whatever the company knew how to lay on the day the main went in. That is one
rule doing three jobs: it makes the size decision matter when it is made, it
gives an old network a real weakness rather than a cosmetic one, and it gives
the player a reason to go back and dig up mains that are working perfectly well.

## 12. Where the built thing differs from the plan

Seven places, each of them a thing the plan could not have known:

- **The coast is fixed and the other two havens are not.** The plan had three
  gateways on three map edges. An endless map has no edges to put them on, so
  the sea sits north of row one forever and a harbour belongs on that coastline,
  while a road head and an air freight apron became buildings the company sites
  wherever it holds ground, each dearer than the last of its kind.
- **The hub was keyed `exchange`.** The archived contract game owned `hub`
  in `Graph.KINDS` at the time (both are gone now; old `exchange` nodes
  migrate to level-4 manifolds).
- **Uranium is gone and coke took its job.** Making the reactor eat imported
  fuel would have broken every saved company that already had a power station,
  so the reactor keeps paying for its fuel in cash. Coke is the port-only import
  that gates a chain instead, and it gates steel.
- **A highway takes no materials.** Rail is steel by the kilometre, and a
  company with no steel could never build the line that brings it steel. Tarmac
  breaks the deadlock and gives the early game its bulk mode.
- **Diesel is a fleet discount, not a flow.** Working out how much diesel the
  haulage needs requires knowing the haulage, which requires the flow, which
  requires the diesel. A company with spare diesel runs its own fleet on it and
  the bill drops; that is all it does.
- **The performance work was not where the plan expected.** Hub aggregation
  mattered far less than two things nobody had listed: the coverage scan was
  quadratic, and `buildNetwork` was giving four arcs to every node in the
  company whether anything was tied into it or not. Solving only the commodities
  that have both a feed and a want did the rest.
- **Solving a works needed no fixed point.** Keeping wells, mines and quarries
  free of a power requirement leaves the recipe graph acyclic, so one pass in
  topological order is exact.

## 11. Numbers to start from

Import prices stay at roughly a third of resale, as they are today. New ones in
the same spirit, per unit landed at a sea port:

| Commodity | Import | Sells or values at |
|-----------|--------|--------------------|
| Wheat | 0.9 | feedstock |
| Timber | 1.1 | feedstock |
| Sand | 0.6 | feedstock |
| Coke | 2.4 | feedstock |
| Iron ore | 1.8 | feedstock |
| Uranium | 90 | 40 power per unit |
| Steel | 7.0 | material |
| Planks | 3.2 | material |
| Glass | 5.5 | material |
| Concrete | 2.8 | material |
| Diesel | 4.0 | burnt by road and sea |
| Food | 3.0 | sells to houses at 9 |

Haulage, per unit per km: road 0.9, rail 0.12, ship 0.03, air 6.0. Those four
numbers are the whole freight game, and they are the first thing to tune.

---

## 14. People, and the businesses that move them

**Built.** Every phase below shipped together, in `src/people.lua` and the
structures, trades and screens around it, with the two open questions decided
as the plan recommended: population grows on its own, and the internet is a
wired fifth utility. The sections keep their original shape as the design
record, and where the build differs from the sketch the difference is noted in
place. `test/test_people.lua` covers every phase.

The reason this needs its own section rather than three lines in phase 4: a
person is not a commodity. Water flows through a pipe and is gone; a person
takes a trip and comes back tomorrow. Reusing the max-flow network for people
would be modelling the wrong thing. What follows is a second, smaller system
built next to the first one, sharing roads and money with it and nothing else.

### 14.0 The one new primitive: population and trips

A **city** is not a building, it is a property of a district: a population
count that grows on its own once a district has enough customers signed to
count as settled, the same way today's game already tells suburb from
frontier by what a district generates. Population is not solved by the flow
graph. It is a number per district, updated once a day, the same cadence as
rent and rot.

```
district.population        -- grows toward a ceiling the district's ring sets
district.tripsPerCapita     -- how often someone here wants to go somewhere
```

Every day, each populated district rolls up a handful of **trip demands**:
`{ from = district, to = another district or a resort, purpose = "work" |
"leisure", willingness = $ }`. A trip is satisfied the same way a customer is
served today: by whatever route across whatever mode gets them there, priced
per km per mode exactly like freight is. An unsatisfied trip is exactly like
an unsupplied customer — nobody starves, the company just does not get paid,
and the report says so.

This is the load-bearing decision in the whole plan: **trips are priced and
routed like freight, not simulated like a person.** No car is drawn taking a
particular road. The company owns capacity on routes, trips consume it, money
changes hands. This is what keeps it a max-flow-and-money game instead of a
different game.

**Decided: population grows on its own.** A district with at least three signed
customers counts as settled and grows toward what they can house, seventy
people each and capped by a ceiling its ring sets, as fast as their supply is
reliable. It loses people for the share of them that went short, and ground
nobody lives on empties out. Trips are a gravity model: commuters go to the
three nearest populated districts, weighted by how many people live there, and
a resort in reach takes a third of a district's trips as day trips.

### 14.1 Roads and tolls

**What the player sees.** Highways stop being a bulk-freight-only mode between
two depot yards. A road is now also something you can lay between any two
owned districts and charge a toll on, and every trip crossing it pays that
toll to whoever built it — you, almost always, since nobody else builds them.

**How.** `City.MODES.highway` already exists and already prices per km; what
is new is that a highway edge can exist without a `dc` at both ends, and it
carries a `toll` field the player sets (a rate slider, exactly like a hub's
floor). Freight still uses it as it does today. Trips use it and pay the toll
into the same ledger a hub's `perClient` fee lands in.

**As built.** A road laid for people is its own link between any two places
people board (a stop, a filling station, a resort, a yard or a haven), kept
beside the pipe graph rather than inside it, because the flow solver has no use
for a trip. Every freight highway carries trips as well and is tolled the same
way, so one road serves both. A road carries 400 trips a day.

**Files.** `city.lua` (highway edges between districts, toll field, trip
routing reuses `rangeBetween`/`crossingCost`), `company_ui.lua` (toll slider on
a highway edge), `company_render.lua` (draw tolled roads distinctly from bulk
freight lines, which are drawn heavier already).

**Unlock.** Hidden until a district first reaches enough population to
generate a trip at all — nothing to toll before then, so nothing is shown.

### 14.2 A gasoline business, and cars

**What the player sees.** Refined diesel already exists for your own trucks.
Gasoline is diesel's twin for the population: a new commodity, sold at a
filling station (a small structure on a road, cheap, unlicensed once
population exists) rather than piped to a house. People who own cars buy it
by the trip; people who do not use your buses instead.

**How.** A new commodity `gasoline`, role `utility`, form `liquid` — but sold
at a **station**, not by a main to a house, because nobody pipes fuel to a
driveway. A station is a small structure (closer to a depot than a works)
that a road passes through; it draws gasoline off the network like a client
and sells it per trip that uses that road, at a margin you set. Refining
gasoline from oil reuses `City.RECIPES` exactly (a second recipe off the
refinery, or a new "petrol works" if you want the two kept apart for
licensing reasons).

**Car ownership** is not a fleet the player manages trip by trip. It is a
population trait: some fraction of a district's population "owns a car",
meaning their trips prefer roads and consume gasoline rather than a bus seat,
and that fraction rises if you also build...

**Car manufacturing**, a new works chain (steel + glass + rubber\* → cars),
whose output is sold in bulk to a district (raising its car-owning fraction
over time, priced the way a district's amenities already are) rather than
tracked as individual vehicles. \*Rubber does not exist yet; simplest is to
make it an import-only feedstock like coke, so the chain has a haven
dependency the way food already does through salt.

**Files.** `graph.lua` (gasoline commodity), `city.lua` (station structure,
car-owning fraction per district, the manufacturing recipe), `company_ui.lua`
(station inspector, margin slider).

**Unlock.** Behind population (14.0) and a road network (14.1) both existing.

### 14.3 Buses, boats and planes for people

**What the player sees.** The same three bulk modes that already move freight
— road, sea, air — now also run scheduled passenger routes, each its own
small business: a bus company, a ferry company, an airline. You buy a route
between two places, set a fare, and every trip that prefers it over driving
pays you the fare instead of paying a filling station.

**How.** This is the smallest phase in the plan, because it reuses `freight.lua`\-
style bulk edges almost as they are: a passenger route is a bulk edge with
`wagons = seats` instead of tonnes, a `fare` instead of nothing, and no
material commodity riding it — the "cargo" is trip count. A trip picks
whichever available route (drive, bus, boat, flight) is cheapest for its
willingness-to-pay and gets there fastest, the same comparison `E.offerPreview`
already runs for customers picking a water source.

**Files.** `city.lua` (passenger routes as a bulk variant, route picking per
trip), `company_ui.lua` (route builder, fare slider), `company_render.lua`
(passenger routes drawn a third way, distinct from freight and toll roads).

**Unlock.** Behind 14.1. Air and sea routes specifically wait on the existing
haven/airfield/harbour unlocks, which already gate freight versions of the
same thing.

### 14.4 Destinations: growing cities and resorts

**What the player sees.** Later regions are not just richer ground, they are
new cities: districts that arrive already populated instead of empty, the way
today's frontier already arrives already rich in deposits. A vacation resort
is a structure you build (on the coast, on an island, or beside a lake if
14.x adds one) that manufactures leisure trip demand toward itself from every
populated district within its pull, the way a hub manufactures coverage.

**How.** A city is a district whose `spec` sets a starting population instead
of zero, generated the same deterministic way a frontier district already
rolls its archetype. A resort is a structure (closest existing analogue: a
haven — it has no throughput ceiling and mostly exists to be a destination)
that adds `{ from = every district in range, to = here, purpose = "leisure",
willingness = $$ }` trip demand each day, scaled by distance and by how good
the resort is (a level, like a well's, bought with money and materials).

**Files.** `city.lua` (city districts, resort structure and its trip
generation), `company_ui.lua` (resort inspector, upgrade levels).

**Unlock.** Deep. Resorts specifically should not appear in any list, hint, or
unlock-hint string until a company already has a working passenger network —
this is the clearest case in the whole plan for "hidden until almost
reachable", because a resort with no way to reach it is not a destination.

### 14.5 Data centres and the internet

**What the player sees.** A data centre is the single most expensive thing you
can build, drinks water and power by the tanker-load, and pays for itself
slowly out of a income line with no visible customer behind it — "online
business", the same way a haven's freight bill is real without a truck ever
being drawn.

**How.** Mechanically this is the *simplest* addition in the whole plan: it is
another `works`-shaped structure, like a turbine hall, except its recipe has
no material output at all — its "product" is a daily cash income proportional
to how much water and power it actually got, the same `worksOutput` starvation
logic already used for every other works (no power, no income; half the
water it wants, half the income). No new commodity is required for this half.

**Decided: internet as a commodity**, sold to the population rather than only
implied. The clean version, given
`role = utility` already means "sold to a client by the day": houses gain
internet as a fifth utility, sold and piped (well, cabled) exactly like power,
and a data centre's income scales with how many houses you actually serve
rather than being a flat number — which turns internet from flavour text into
a real reason to have wired a neighbourhood for it, and ties the whole phase
back into the network the rest of the game is about. That is what shipped: a
proper new trade with its own licence, subscribers as its customers, fibre as
its conduit, and its own place in the sidebar next to water, power, beer and
oil. The data centre is a works that turns water and power into internet.

**Files.** `city.lua` (data centre recipe, income-only works), `graph.lua`
(internet commodity, if wired), `company_ui.lua`.

**Unlock.** The deepest in the plan. Nothing about data centres or internet
should be visible — not a greyed button, not an unlock hint — until a company
already has a mature electricity network (a reactor built, not just licensed),
matching "almost reachable" as literally as the unlock system allows.

### 14.6 Build order and what stands alone

| Phase | Ships | Depends on |
|-------|-------|------------|
| 14.0 | Population and trip demand, no way to serve it yet | nothing new; reuses today's client/service-quality numbers |
| 14.1 | Tolled roads | 14.0 |
| 14.2 | Gasoline, filling stations, cars, car manufacturing | 14.0, 14.1 |
| 14.3 | Bus, ferry and airline routes | 14.1 |
| 14.4 | Cities in later regions, vacation resorts | 14.0, 14.3 |
| 14.5 | Data centres, internet as a fifth utility | nothing above; only needs a mature power network |

14.5 is deliberately independent of everything else in this section — it can
ship first, on its own, if you would rather see one small, self-contained
thing land before the bigger passenger system. Everything else builds in the
order listed: there is no reasonable way to have a filling station, a bus
route or a resort before there is anyone to use it.

### 14.7 What is deliberately not in this plan

- **Individual cars or people drawn on the map.** A moving dot is fine, a
  simulated commute is a different, much larger game. Trips are numbers.
- **A construction industry for houses.** Population grows itself; the player
  is not asked to zone or build housing. If that turns out to be wrong for
  the "create cities" feeling you want, it is a straightforward addition on
  top of 14.4 rather than a rework of it.
- **Insurance, loans against future toll revenue, or other financial products
  for the passenger side.** The existing credit system already covers it.
