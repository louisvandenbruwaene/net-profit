# Net Profit: the infinite city

A plan for turning a fixed twelve district map into an endless one, and a single
utility network into a distribution empire. Seven phases, each of which leaves a
game that is finished enough to play if the next one never happens.

Nothing here is built yet. `README.md` describes the game as it is today.

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
