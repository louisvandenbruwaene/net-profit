# Editing Net Profit

Most everyday balance changes now live in `src/data/`. These files contain values and descriptions, without drawing, input, loading or saving code.

| What you want to change | File | Examples |
| --- | --- | --- |
| Money and running costs | `src/data/economy.lua` | `rules.startMoney`, `price.junction`, `trade.water.sourceBase`, loan interest, crew wages |
| Pipes and connections | `src/data/pipes.lua` | capacities, lining costs, leakage modifiers, endpoint size limits |
| Engineering, farms and environment | `src/data/infrastructure.lua` | tower spacing, booster distances, upgrade prices, customer voltages, amperage, pump head, filtration, pollution, cleanup and farm recipes |
| Terrain size and frequency | `src/data/terrain.lua` | park and mountain size ranges, massive obstacle chance and distance from the start |
| Customers | `src/data/customers.lua` | daily rates, demand ranges, patience, spawn weights |
| Factories and sources | `src/data/production.lua` | recipes, inputs, output, construction cost, extractors and power plants |
| Freight and storage | `src/data/freight.lua` | transport modes, hubs, havens, material bills and warehouse limits |
| Unlocks and rewards | `src/data/progression.lua` | customer thresholds, municipal grants, departments and permits |
| Population and transport | `src/data/population.lua` | settlement, trips, fares and passenger routes |

For example, change `startMoney = 750` to `startMoney = 1000` in `economy.lua`. Restart with `make run` and create a company in an empty slot to try the new opening. An existing company's cash is saved, so changing starting money does not change its bank balance.

To make households pay more, change the `house` entry's `rate = 4` in `customers.lua`. Newly generated households use the new value; existing customers retain their saved contracts. Built pipes retain purchased capacities and sources retain their saved output. Factory recipe rates and inputs are read from the definitions, so those changes also affect existing factories after restarting. Use a new company for a clean balance comparison.

In recipes, `inputs` are **per output unit**: crop farm output `rate = 12` with `water = 3` consumes 36 water per day at full production. Costs are dollars; probabilities such as `leakBase = 0.07` mean 7%. Keep pipe sizes in ascending capacity order and recipe chains acyclic. Keep existing keys such as `water`, `house` and `turbine`: rules and old saves use those identifiers.

Run `make test` after an edit. Some tests deliberately assert the current balance, so an intentional balance change may require updating those expectations after checking its effect. `make smoke` exercises the real interface with isolated test companies. `make run` runs source edits immediately; the installed app requires `make mac-install` to rebuild it.

Colours live in `src/palette.lua` and commodity colours in `src/graph.lua`. Much of the current map art is drawn procedurally in `src/company_render.lua`; there is no individual building PNG to replace yet. This is one reason an engine migration should include reusable building scenes with external textures.

These files cover common balance edits, not every game rule. Adding an entirely new mechanic still needs simulation and interface changes. World generation settings remain in `src/city.lua`, and goals and presentation helpers live in `src/experience.lua`.

## September requirements

See [IDEAS-IMPLEMENTATION.md](IDEAS-IMPLEMENTATION.md) for the new rules and their controls. Staffing, daily land offers, saltwater validation and migration are in `src/ideas.lua`. Temporary autoplay is in `src/autoplay.lua`; its regression tests use isolated companies. The primary app logo is `assets/net-profit.png`; `assets/net-profit.icns` must be an actual macOS icon container, not a renamed PNG.
