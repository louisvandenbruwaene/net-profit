# September ideas: implementation and play guide

`ideas.rtf` is the design source for this update. This guide records the resulting rules, controls, save behavior and checks. It supersedes older balance examples in the README and roadmap.

## Water network

| Equipment | Connections | Behavior |
| --- | ---: | --- |
| Well | 1 | Starts at 20; upgrades to 30, 40 and 50. Upgrade prices are $140, $252 and $454. |
| T split | 3 | Divides routes and changes between pipe sizes. |
| Hub | 6 | The former “Pipe hub”; accepts different pipe sizes on its connections. |
| Pump | 2 | Raises design head from 30 to 95 m and permits links up to 950 m. |
| Filter | 2 | Protects the downstream water network against further mineral accumulation. |
| Binder | 6 initially | Short attachments to equipment; supports two identical parallel mains. |
| Valve | 2 | Sets branch throughput from 0 to 100, including full isolation. Reserve scarce supply for other branches without demolishing pipes. |
| Depot | 3 | Stores 100 units. Inspector and map badge show fullness; the map also shows the stored amount. |

Small, medium and large pipes have purchased capacities of **10, 30 and 50**. The late-game massive main carries 100. Purchase controls show capacity with the commodity symbol; electrical controls show amperes instead. A pipe's usable hydraulic flow can be lower than its purchased capacity when its length, diameter, pressure or mineral buildup constrains it.

Binder equipment attachments reach 95 m. The trunk between two binders uses the normal pipe range. Parallel mains must use the same size and lining; every lane is a separate paid asset and consumes real source supply. Upgrades to 3, 4 and 5 lanes cost $1,800, $5,000 and $12,000, at 12, 20 and 30 signed customers. Adding parallel lanes to one bundled connection does not consume extra outlets on the well.

### Filtration, mineral deposits and maintenance

Each untreated water main gains one mineral-deposit point per day. At 100 points, added leak risk begins; above 100, usable hydraulic capacity also declines. Filtration stops future accumulation but does not dissolve deposits already present. Repairs and replacement reset the affected pipe's accumulation.

Depots fill in batches when empty. Their intake is solved after customer and factory demand, using residual network capacity, so storage cannot steal a customer's delivery or receive water from a disconnected well. Stored supply is available the following day and deducted when delivered.

Treatment is determined from the actual supplied network. A filter does not protect its incoming raw-water main. A raw-water bypass into the downstream network defeats its clean status. Removing the bypass restores protection; removing the filter removes it. Disconnected filters provide no protection. These rules also apply to existing installed mains, so rebuilding every downstream main is unnecessary.

The obsolete Treat structure has been removed from the build and conversion tools. Existing treatment structures become filters on migration. Existing connected structures retain enough connections to avoid deleting their routes.

Maintenance crews repair already damaged mains. Engineers intervene when the daily wear step would start a new leak, replace the threatened main before capacity is lost, and charge its replacement quote after salvage. They cannot perform unfunded work. The day report records the number and cost of preventive replacements.

### Saltwater and purification

The water toolbar places purification beside the well controls and provides a shortcut to the seawater pump.

1. Own a coastal region.
2. Build the $1,600 seawater pump on sea water within 220 m of that owned coastline. It produces up to 50 saltwater per day and costs $18/day.
3. Connect it through a filter. Every saltwater main requires Armoured or Sealed lining; downgrading below Armoured is refused.
4. Connect the filter to a purification centre on suitable owned land. The centre no longer needs to stand on the coast.
5. Pipe its clean water to the water network and transport its salt to production facilities.

The $2,600 centre processes up to 16 saltwater per day into **16 clean water and 16 salt**, with $24/day upkeep. Actual output is limited by incoming saltwater. Losing the feed stops both outputs. Both products participate in the normal flow solver; salt is available to factories instead of requiring imports. Existing salt imports remain an alternative.

Saltwater uses a droplet with a horizontal bar; salt uses a circle with a horizontal bar. Saltwater's corrosion risk is eight times the ordinary base risk, reduced by filtration and lining. Salinity and mineral scaling are distinct mechanics.

## Electricity

Generation includes nuclear plants, river turbines, wind parks and solar arrays. River turbines must be within 100 m of a river. Solar construction consumes 12 imported panels, available through the commodity freight and storage system.

Generators provide high voltage. The network keeps high-voltage towers, standard towers and low-voltage poles as distinct electrical structures. Water fittings cannot carry power. Current ratings, resistance, voltage, span and booster spacing govern electrical delivery.

| Voltage | Cable span | Distance between generation, transformation or boosting |
| --- | ---: | ---: |
| 110 kV | 300 m | 2,500 m |
| 11 kV | 200 m | 1,000 m |
| 0.4 kV | 150 m | 300 m |

A standalone $260 transformer has six connections, accepts all three voltages, and has a 95 m attachment range. Tower-mounted transformers remain available. Homes receive low voltage; industrial facilities receive medium voltage. Cables with degraded insulation lose usable capacity and require maintenance.

Three-phase cable capacity uses `sqrt(3) × kV × A`; daily energy multiplies power by 24 hours. Resistance loss depends on conductor size and length. The two separate info buttons explain voltage and cable current rating. Their explanations stay collapsed until requested.

Offshore wind needs no island: it can stand in the sea within 220 m of owned coastline. Offshore installation costs 60% more and upkeep 50% more. Wind built on an owned island produces 50% more electricity than the base park.

The engineering model uses daily averages and conservative design limits rather than a full AC or hydraulic network simulation. The physical distinctions follow the [DOE electricity delivery explanation](https://afdc.energy.gov/fuels/electricity-production) and [DOE pumping sourcebook](https://www.energy.gov/sites/prod/files/2014/05/f16/pump.pdf). Game equipment sizes and prices are balance choices.

## Oil, environment and farming

Oil lost from a leaking pipe pollutes affected regions in proportion to actual supply lost. Shipping accidents also remove cargo from delivery and distribute pollution along the affected route. A large shipment can therefore cause substantially more damage than a small pipe leak. Active oil rigs add background pollution.

Environmental labs clean their own region and its eight neighbors. Each lab removes up to eight pollution points per covered region per day and costs $24/day. Natural recovery removes 0.3/day. At 30 pollution points, natural water extraction and farming stop. Production resumes when the land and water recover below that threshold. Inspectors and region overlays show the problem and the recovery.

Crop and livestock farms reserve a 280 × 280 m plot. Their water, oil, power and feed inputs limit output; farmland cannot overlap other buildings. Crops supply wheat. Dairy supplies milk, poultry eggs/chicken, pigs pork, and cattle beef. Livestock products are labeled by farm type and share the food commodity for transport and sale.

## Investments and staffing

An investment matures after seven days. At settlement, its return is drawn from a normal distribution with:

- Base expected return: 10%.
- Standard deviation: `0.01 × (company day − 1)`, starting at zero and stopping where a total loss is four standard deviations below the mean — 0.275 with no analysts, reached around day 29. Without that cap the payout floor at zero clipped the left tail and quietly paid the player for it. At the cap a settlement loses money 36% of the time; one analyst carries the mean to 20% against a 0.30 spread and loses 25% of the time, and earns its $175-a-cycle wage on $1,750 invested.
- Analyst contribution: +10 percentage points per employed analyst, plus +1 percentage point per completed week that individual has worked for the company.

For example, an analyst with one completed week changes the expected return from 10% to 21%. Hiring another analyst changes it to 31%. Each analyst costs $1,000 to recruit. Initial salary is $25/day and compounds by 1% each completed week of that analyst's service. Each worker's hiring day persists in the save. Dismissing a worker removes one analyst, with the newest dismissed first. Analyst headcount has no fixed cap.

Returns can be negative. Payout is floored at zero, so an investment can lose its entire principal but cannot create a debt beyond the amount invested. Consequently the extreme tail is clipped; the underlying return draw remains normal. The Company panel shows current expected return and standard deviation.

Workers have compact symbols and counts, each distinct from the others: a yellow hard hat for maintenance crews, a spanner for engineers, a signal reaching outward for dispatchers, a level on its tripod for surveyors, a house for estates, and a graduate's cap over a rising line for analysts. Hovering a hiring control identifies the role, recruitment price, daily wage and function. Clicking the hiring control adds one worker; Stop dismisses one.

Dispatchers reveal one neighboring ring each, up to four. Ownership remains visible, including disconnected holdings. Hidden neighboring terrain is generated ahead of construction so future mountain generation cannot appear on top of an established network. Dispatchers leave contract acceptance to the player.

### Land discounts and estates

Every region receives one stable offer for the current day:

| Discount | Daily probability |
| --- | ---: |
| 50% | 1% |
| 40% | 2% |
| 30% | 3% |
| 20% | 4% |
| 10% | 5% |
| None | 85% |

Prices do not reroll when the player opens an inspector, reloads or discovers a region. Day and region coordinates determine the seeded offer. The map price and land inspector display the discount.

Players may buy nonadjacent regions. Islands still require a harbor. Estates staff buy qualifying offers subject to the player's **minimum discount**, **maximum purchase price** and **cash reserve**. They favor the cheapest eligible region, buy at most one region per staff member per day, and can acquire disconnected holdings.

## Requests and compact controls

The top bar now has five windows: cash, estimated daily profit, supplied customers, client request, and fix all pipes. The request window shows one request, ranked by percentage above its base selling price. Accepting or rejecting it immediately exposes the next. Its info button opens the inspector. Fix All repairs the damaged lines for the displayed total.

The two windows that hold a decision hold the same control: one size, centred between the lines that bound the window, with the whole of the decision on its face. Client request carries the offer's percentage above or below the going rate — green above, red below, plain at it — and pressing it opens that contract, selects the house and brings the map in closer than it was. Fix All carries the repair price alone, in red, with the number of damaged lines in its tooltip. Headings and figures are measured against the width of their window, which matters at the 1100-point minimum.

Buying the power license gives existing water houses an electricity request without silently changing an already signed water contract. Accepting adds electricity demand and its own agreed rate. Declining leaves water service intact. Eligible existing houses make follow-up electricity requests at three times the ordinary request probability, capped at 100%, with a seven-day delay after a rejection.

Every structure the company has unlocked is on the panel; the More/Fewer buildings toggle is gone. A structure tile puts its icon on the left and centres its name and price in what the icon leaves. The sea pump and the purification centre are structures in that same grid, marked with the brine drop and the same drop with the sparkle of having been cleaned, and the purifier is no longer listed again under Works. Pipe capacity is headed with the commodity symbol and `/ day`, and lining with a shield. Roads gain a corner: a two-port node for bending a road, $30, taking offroads and normal roads. The build instructions sit behind the inline info button. Supply and maintenance totals use a compact expandable row. Commodity quantities use shared pictograms across the map and panels. Pipe choices favor numerical capacity over size names. Resource shortage messages use the same resource symbols.

The former People category is represented by the Roads symbol. Roads carry passenger traffic and commodity trucks; the existing physical road/path rules remain shared by both. Commodity freight includes solar panels, harvested resources and salt.

## Terrain and extraction

The nine starting regions retain manageable terrain. Distant ordinary terrain varies from small patches to broad obstacles. Massive woodland and mountain features have radii from 400 to 850 m and can span multiple regions. They stay clear of the opening area. River flow strokes use smooth interpolation along bends.

Click owned ground to open its region inspector. Woodland can be harvested and mountains demolished once the matching permit and all land covered by the feature are owned.

- Resource yield: `floor(radius² / 100)` timber or rock.
- Woodland clearing: $4 per unit yielded.
- Mountain demolition: $35 per unit yielded.
- Mountain gem chance: 5%; a successful find yields `max(1, floor(resource yield / 100))` gems.

Clearing removes the obstacle and credits the resources once. A depot's **Load from inventory** action moves harvested resources into physical storage for shipping; it deducts them from inventory. The $8,000 jeweler processes up to two gems into jewelry per day, using electricity. Jewelry delivered to a freight yard sells for $900 per unit. Existing forestry and quarry extraction buildings remain available.

## Temporary autoplay

Open **Stats**, choose 1–120 minutes, then press **Autoplay**. Press the same button to stop. Switching companies clears the timer. The timer itself is session state and does not restart from a save.

The assistant builds and expands water service, accepts contracts it can actually fulfill, repairs damage, upgrades wells and constrained mains, adds wells, expands distribution connections, buys affordable nearby land and advances days. All purchases use normal game cash and validation. A failed construction plan is discarded in full. The assistant pauses if it cannot establish an affordable opening or the company stops trading. Its simulation actions do not grant free resources or unlocks.

Autoplay is deliberately isolated in `src/autoplay.lua` and a small application/UI integration so it can be removed later. Automated verification uses test companies, never the player's slots.

## Branding and existing companies

The supplied `assets/net-profit.png` is the primary app logo. The alternative `net-profit2.png` and older `net-profit4` assets are retained. The macOS `.icns` is packaged from the primary PNG at standard icon sizes. Linux and portable exports use the primary PNG.

Save files retain company money, inventory, loans, investments, staff tenure, mineral accumulation and equipment state. Older wells migrate to the 20/30/40/50 progression; storage increases to at least 100. Existing connected wells keep enough outlets to preserve their routes. Obsolete Treat structures become filters. Old power cable migrations continue preserving working installed routes. Existing purification centres now require a saltwater feed.

## Implementation and checks

- `src/data/`: pipe capacities, well progression, depot size, production recipes and terrain ranges.
- `src/ideas.lua`: staff, investments, discounts, filtration, saltwater validation, electricity requests, clearing, inventory transfer and migrations.
- `src/infrastructure.lua`: water and electrical design limits, transformer support, environment and farms.
- `src/city.lua` and `src/graph.lua`: production dependencies, both purification products, daily wear and settlement.
- `src/company_ui.lua` and `src/company_render.lua`: controls, symbols, map status and river strokes.
- `src/symbols.lua` and `src/symbol_font.lua`: consistent portable pictograms, independent of installed emoji fonts. Carrying drawn symbols inside ordinary text requires an image font, because LÖVE refuses fallbacks between font types, so the glyph sheets are cut at the density of the screen in use and handed to `love.font.newImageRasterizer`. Metrics stay in points and no panel moves; the pixels behind them match the display. The window declares `highdpi`, and the sheets are cut again if the window moves to a screen of a different density.
- `src/autoplay.lua`: temporary gameplay assistant.
- `test/test_ideas.lua` and `src/ideas_walkthrough.lua`: new simulation and real-input regression coverage.

Run `make test`, `make smoke` and `make soak`. The smoke suite captures the new controls at the minimum 1100 × 700 window size, exercises actual input callbacks, and checks that every pictogram exists at every font size. The soak suite advances more than 60 days and checks save round trips. Separate autoplay runs exercise real budgets across more than 100 days.
