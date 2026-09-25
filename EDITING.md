# Editing Net Profit

Most everyday balance changes now live in `src/data/`. These files contain values and descriptions, without drawing, input, loading or saving code.

| What you want to change | File | Examples |
| --- | --- | --- |
| Money and running costs | `src/data/economy.lua` | `rules.startMoney`, `price.junction`, `trade.water.sourceBase`, loan interest, crew wages |
| Pipes and connections | `src/data/pipes.lua` | capacities, lining costs, leakage modifiers, endpoint size limits |
| Engineering, farms and environment | `src/data/infrastructure.lua` | tower spacing, booster distances, upgrade prices, customer voltages, amperage, pump head, filtration, pollution, cleanup and farm recipes |
| Terrain size and frequency | `src/data/terrain.lua` | park and mountain size ranges, massive obstacle chance and distance from the start |
| Customers | `src/data/customers.lua` | daily rates, demand ranges, patience, spawn weights, `DUAL` (how many households ever want a second utility) |
| Factories and sources | `src/data/production.lua` | recipes, inputs, output, construction cost, extractors and power plants |
| Freight and storage | `src/data/freight.lua` | transport modes, hubs, havens, material bills and warehouse limits |
| Unlocks and rewards | `src/data/progression.lua` | customer thresholds, municipal grants, staff and permits |
| Building levels | `src/data/upgrades.lua` | the four-level ladders, what each level gives, `DISTRIBUTION` (radius, default minimum price, upkeep, daily limit), `WELL_NAMES` |
| Unit costs | `src/data/economy.lua` | `extractPerUnit` (pumping cost a unit), `sourceUpkeep`; the display logic is `src/costs.lua` |
| Population and transport | `src/data/population.lua` | settlement, trips, fares and passenger routes |

For example, change `startMoney = 750` to `startMoney = 1000` in `economy.lua`. Restart with `make run` and create a company in an empty slot to try the new opening. An existing company's cash is saved, so changing starting money does not change its bank balance.

To make households pay more, change the `house` entry's `rate = 6` in `customers.lua`. Newly generated households use the new value; existing customers retain their saved contracts. Built pipes retain purchased capacities and sources retain their saved output. Factory recipe rates and inputs are read from the definitions, so those changes also affect existing factories after restarting. Use a new company for a clean balance comparison.

## The shape of a network

Four numbers decide whether a company grows a branching tree or a spiderweb of point-to-point mains, and they are worth understanding together before any of them is moved.

`trench` in `pipes.lua` follows **Murray's law**, the small-vessel half of the West/Brown/Enquist model of vascular networks. Minimising pumping power against the cost of maintaining the fluid gives `Q ~ r^3`, so cross-section, and with it the dig, goes as `Q^(2/3)`. Keeping the four sizes on that curve (1.00, 2.08, 2.92, 4.64) is what makes one trunk that splits cheaper than two mains laid side by side. Flatten the curve and every rung above SMALL becomes a trap. Steepen it and nobody lays a trunk at all.

`reach` in the same table is the other half of the physics. Pressure gradient goes as `Q/r^4`, so at each size's design flow it falls as `Q^(-1/3)`, and a trunk runs further between pumps than a stub does. These multipliers are checked against the Darcy-Weisbach model in `City:waterRating`, which throttles a main that is asked to carry its rating too far. Raise `reach` past the point where that model still delivers the full rating and mains will be legal to lay but quietly short on arrival.

`upgradeGrowth` in `economy.lua` sits **below** `sourceGrowth` in every trade. That inversion is what makes growing a source the cheaper unit of supply at the margin, and it is the reason a company settles on one deep source and two or three shallow ones rather than a dozen identical wells. Put `upgradeGrowth` back above `sourceGrowth` and the sprawl returns immediately.

`trunk` waits for the intake, not for customers. Forty customers drawn from wells will never open it, because a trunk main is sized for a source that can fill one and only a works on running water is. That is the one unlock in the game gated on a kind of building rather than a count, and `City:hasIntake` is what it asks.

`City.INTAKE` in `city.lua` is the heart. A water source standing within `reach` of the river or the coast is a treatment works rather than a well: its ceiling is `riverBase + riverPerHalf * halfWidth`, so a broad estuary hosts a city's whole supply and a headwater branch does not. It is finite, like every other source, and sized against what two MASSIVE mains can carry out of it. Ordinary wells stay capped at `wellCap` in `infrastructure.lua`, which is what keeps them accessory organs.

There are five rungs, and the fifth exists because the measurement asked for it. `make anatomy` reports capacity against branching: flow arriving at the widest mains was 3.6 times what the mains below carried, where the ladder stepped up only 1.9 times, and a quarter of the widest mains were running full. A 200 rung halved that saturation and served 17% more customers across nine seeded companies. If you change `cap` on the top rung, re-run `make anatomy` and look at `R_C` against `R_B`: the ladder is meant to keep up with the branching, and when it cannot, the trunks throttle everything under them.

The one thing the prices cannot buy is **self-similarity in space**. `make anatomy` measures what the networks actually come out as: Horton-Strahler orders, and the three ratios that describe a tree. Branching runs about 3.6 mains into each one below, and capacity follows it at about 70%, so Murray's law holds reasonably well. The length ratio is about 0.94, where a tree filling its ground would want `3.6^(1/3)` = 1.54. In other words the networks have a hierarchy of capacities laid over a geometry with a single length scale: a trunk is about as long as a stub, whatever it carries.

That is a property of how a network grows, not of what it costs. Each new customer joins the nearest fitting with a spare port, which builds a dense blob outward rather than a trunk to a distant district. A trunk only pays past about 850 m, and a growing company rarely has a reason to cross that much ground at once. The Stats panel prints the same numbers for the player's own network, so it is at least visible and aimable at.

Do not try to fix it in `N.chain`. The `240` in `src/network_builder.lua` is not a pipe length: it is how fast the network grows its own attachment points, and it has been measured. The comment there records what happens either side of it.

Plants follow the same rule through `unitBase`, `unitGrowth`, `unitStep` and `maxUnits` in `production.lua`: another reactor on a commissioned site reuses the grid connection, the cooling and the crew, so it is always cheaper per megawatt than a second site.

In recipes, `inputs` are **per output unit**: crop farm output `rate = 12` with `water = 3` consumes 36 water per day at full production. Costs are dollars; probabilities such as `leakBase = 0.07` mean 7%. Keep pipe sizes in ascending capacity order and recipe chains acyclic. Keep existing keys such as `water`, `house` and `turbine`: rules and old saves use those identifiers.

## What a licence is worth

`powerLicence` and the rest in `economy.lua` are free to type but not free to
choose. The panel that sells one quotes the rest of the bill beside it, from
`E.tradeEntry`: the cheapest generator, the well and its deposit, or the works
and what it eats. A licence priced far below that reads as a cheap trinket in
front of a bill the player cannot pay, which is what $340 in front of an $850
river turbine and a transformer pole was. Move a source price and the licence
in front of it is worth looking at again.

## Text that fits

`make layout` renders every panel and reports any two strings that land on the
same pixels. It is a measurement like `make anatomy`, not a test: it plays the
smoke walkthrough with `src/layout_audit.lua` recording the box every string
actually occupies, then does the same over a company built for the purpose in
`src/stress_walkthrough.lua` -- seven figures of cash, a long company name,
every building, every inspector, every tab, at both window sizes and scrolled
to both ends. Around 560 frames, and it reports three things:

- **overlapping pairs**, by region. `panel`, `header` and `footer` are layout
  faults. `map` is two labels on the city itself, which is what zoom is for.
- **squeezed**, a label drawn below full size because it did not fit the space
  it was given. `single` and `button` shrink rather than collide, so this is
  the same fault caught a moment earlier. Below about 0.85 it is worth fixing;
  a deliberately long company name sitting at 0.68 is the mechanism working.
- **broken words**, where a word too long for its column was cut in the middle
  rather than wrapped. "Automation hub" in a 64 point tile read "Automati / on
  hub" until the tile gave the name its full width.

Text hidden under an opaque panel is not reported, so a tooltip or a lesson
box over the map is not a finding. Run it after moving anything in a panel.

Run `make test` after an edit. Some tests deliberately assert the current balance, so an intentional balance change may require updating those expectations after checking its effect. `make smoke` exercises the real interface with isolated test companies. `make run` runs source edits immediately; the installed app requires `make mac-install` to rebuild it.

Colours live in `src/palette.lua` and commodity colours in `src/graph.lua`. Much of the current map art is drawn procedurally in `src/company_render.lua`; there is no individual building PNG to replace yet. This is one reason an engine migration should include reusable building scenes with external textures.

These files cover common balance edits, not every game rule. Adding an entirely new mechanic still needs simulation and interface changes. World generation settings remain in `src/city.lua`, and goals and presentation helpers live in `src/experience.lua`.

## September requirements

See [IDEAS-IMPLEMENTATION.md](IDEAS-IMPLEMENTATION.md) for the new rules and their controls. Staffing, daily land offers, saltwater validation and migration are in `src/ideas.lua`. The primary app logo is `assets/net-profit.png`; `assets/net-profit.icns` must be an actual macOS icon container, not a renamed PNG.

## Levels, shocks and secure contracts

**Levels** (`src/data/upgrades.lua`, logic in `src/upgrades.lua`). Junctions (T split, hub, large hub, distribution hub), towers, pumps and tanks (tank, cistern, reservoir, water tower) are one building each with four levels. A new one starts at level 1 and is grown in place: `ports`, `throughput`, `reach` (towers and pumps) `radius` (the distribution hub) and `store`/`fill` (tanks) per level, `cost` to reach it, and `clients` the company must have signed before it is allowed. A junction becomes a manifold (a six port hub) at level 2 and keeps every main tied in. Towers scale throughput by the voltage they carry (`TOWER_SCALE`). `LEGACY` is the level a building from an older save counts as. Saves need no migration because a level only ever adds to what a building already has, and reach only counts once a building has been upgraded. The old kinds (`manifold`, `pole`, `pylon`, `hvtower`) still exist in saves and tests; the build panel sells one Junction and one Tower, and the tower's voltage is chosen above the tools.

**Shocks** (`src/data/resilience.lua`, logic in `src/resilience.lua`). Droughts and grid faults hold a trade's sources to a fraction of their output for a few days; a ground shift cracks the mains around one point. Nothing lands before `SHOCK_CLIENTS` customers or day `SHOCK_FROM`, and never more often than `SHOCK_CHANCE` a day. Shocks are rolled from a hash of the seed and the day and never from `City:random()`, so they do not reshuffle a save's offers and leaks.

**Secure contracts.** `SECURE.share` percent of new offers pay `SECURE.rate` times the going rate, refund `SECURE.credit` times the missing revenue for every short day, and leave after `SECURE.patience` short days. Distribution hubs never sign them on the player's behalf.

**The Advisor** (Stats, then Advisor). *Check resilience* fails each loaded main and structure in turn on a copy of the company (`City:startResilience`, run a little each frame) and grades the worst single failure, A to F by `GRADES`. *Best next upgrades* (`experience.lua`, `E.advise`) does each candidate upgrade on a copy and ranks by payback. Neither changes the company. Upgrade buttons elsewhere quote what the upgrade would earn when pointed at.
