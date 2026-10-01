# Net Profit

A turn-based utility-company game about networks, cash, and promises.

The [September implementation guide](IDEAS-IMPLEMENTATION.md) documents every requirement from `ideas.rtf`, including water aging, saltwater purification, staffing, investments, land discounts and the new app logo. (Autoplay, Rounds mode and the automated departments have since been removed: the game is the one company again.)

The [infrastructure guide](INFRASTRUCTURE.md) covers electricity, water, farming and pollution, including the simplified simulation rules. It supersedes older engineering descriptions below.

For changing prices, production and progression, start with [EDITING.md](EDITING.md).
The [engine assessment](ENGINE-MIGRATION.md) describes a Godot migration designed around Inspector-editable values and reusable scenes.

You start with a marked spring, one household asking to be connected, one
district and $750. Sink the well, connect it through a junction to the house, sign the contract,
and close the day. After that: sign new customers, keep the mains sound, buy the
ground you want to grow into, and decide how much of today's cash you can
afford to put into tomorrow's company. The map and company persist between
days.

The city does not end. South, east and west it carries on for as long as you can
pay to go, generated as you survey it and richer the further out you get. North
is sea, with islands in it. What begins as one well and a pipe to a house
becomes a distribution business: hubs that wire a neighbourhood without a main
being drawn to any of it, works that turn wheat into malt into beer, railways
and shipping lanes moving materials in wagons, and departments that do the
clerical half of the job for a wage.

## Growing the network

Buildings are few and each one levels up in place, keeping every main tied in:

| Building | Level 1 | Level 2 | Level 3 | Level 4 |
| --- | --- | --- | --- | --- |
| Junction | T split | Hub | Large hub | **Distribution hub** |
| Tank | Tank | Cistern | Reservoir | Water tower |
| Pump | Pump | Booster pump | Pumping station | Main station |
| Tower | Basic | Standard | Reinforced | Grid node |

Wells deepen through six named levels, hand well to aquifer station. The **distribution hub** runs its neighbourhood: once a day, for every customer within 600 m who pays at least the minimum price you set on it, it signs the offer, lays a real connection (paid for at the normal price) and digs out the main that is starving them for the next size up. Droughts, grid faults and ground shifts test the network, and some customers offer a secure contract that pays more and refunds every short day. **Stats > Advisor** grades how much one failure would cost you and ranks the upgrades that earn the most. See [EDITING.md](EDITING.md) for the numbers.

## Chokes and growth

The loop is: sign customers, the network chokes, find the choke and fix it for less than it earns.

- **Chokes glow.** Whatever is leaving a customer short glows amber on the map: a full main, a well pumping flat out, or a valve at its setting. The more customers waiting behind it, the brighter it glows. Pointing at it says how many it starves.
- **Fixes are one click.** A glowing main leads its panel with *Widen $X · Nd back*. A glowing well offers to deepen, or, once it is as deep as its deposit allows, to sink a second well on the nearest free deposit, tied into the same network. The planned well and its main are drawn on the map. A glowing valve highlights *Open*.
- **The day says what chokes cost.** The pill after each close reads like `Day 12: +$240   -$42 short`. Clicking it goes to the worst choke.
- **Customers grow.** A customer you keep fully supplied wants one more unit every 30 days, up to half again what they signed for and never past what their own service main carries. The map shows *Wants +1*. A customer who grows out of their supply waits a week before their patience starts running down.
- **The Advisor looks ahead.** It lists only fixes that win back lost income, and warns when customers due to grow in the next ten days will outgrow the network. Clicking the warning goes to the limit they will hit.

## Play

On macOS, download the macOS build of LÖVE 11.x from [love2d.org](https://love2d.org/),
move `love.app` to `/Applications`, then run `make mac-install`. Open
**Net Profit** from Launchpad, Finder, or Spotlight.

The installer builds a self-contained app in `~/Applications`: a copy of LÖVE
with the game fused in as `Resources/game.love`, carrying its own icon and
bundle identity and signed ad-hoc. It reads nothing outside its own bundle, so
macOS never asks for permission to open your Documents folder, and it keeps
working if `love.app` is moved or removed. Re-run `make mac-install` after
changing the source, or use `make run` to play the checkout directly.

`make hooks` (once, per checkout) wires a git hook that reruns `make mac-install`
after every commit, so the app in `~/Applications` never drifts behind the
source without you noticing. A copy of the game already open would keep the old
code in memory, so the hook quits it first (the game saves on quit) and reopens
it in the background on the new build.

Your company is found either way. LÖVE gives a fused app a different save
directory from a game run out of a source folder, so the game looks in both and
mirrors each save into the other. Playing the app and running the checkout are
the same company, not two that drift apart.

To regenerate the app icon from `assets/net-profit.png`, run `sh macos/make-icon.sh`.

On Linux, run `make install` to add the application-menu entry.

From a source checkout, install LÖVE 11.x and run:

```sh
make run
make install       # Linux app-menu entry, icon, and packaged game
```

The game opens directly into whichever company you last played and saves after
every decision and day close. **Companies**, in the bottom bar, keeps six of them
side by side: switch between them, start another, or delete one. The company you
are leaving is always saved first, so switching can never cost you a day's work.
Test modes use isolated companies and never read or overwrite your saves.

## Menus

The screen is the map. One bar runs along the top: the four menus, your cash
and the day's profit, whatever is waiting on a decision (a new offer with what
you would keep a unit, a repair bill for burst mains, Undo) and End day. A
menu opens as a drawer over the left of the map and folds away again with its
tab, the `<` on its edge, Esc, B (Build) or Tab. Clicking anything on the map
opens the drawer on its inspector. Company and Stats are folded into sections;
only Money starts open.

The gear holds everything else: show all, undo, sound, hiding other networks,
hints, companies, and the **text size** (Normal, Large, Huge). The choice is
remembered in `settings.lua` beside the saves, apart from any company.

- **Build:** pipes, sources and buildings. Pipe options and More buildings open extra tools.
- **Company:** licences, staff, loans, upgrades and land permits.
- **Clients:** accept or decline requests. Check supply problems.
- **Stats:** day, clients, value, reputation, costs, goals and history.

Click land on the map to view it or buy it. Use the wheel to zoom and drag to pan.
**Show all** centres the view and zooms to show your buildings.

Declining a request costs 1 reputation. Letting it expire costs 2.
Every close where all signed customers are fully supplied adds 2 reputation. Losing a customer costs 12.
Requests grow with reputation: one a day up to 66%, rising in even steps to four a day at 100%, if there is room for them.
While the limit is one, odd days always bring a request and even days usually do. The first close always leaves a new house one pipe from your T split.
Requests expire after five days.

## Controls

| Action | Control |
| --- | --- |
| Lay a pipe or cable | Drag from one structure to another |
| Choose the trade | Water / Power / Beer / Oil in Build, or drag: two structures that only take one trade put it in hand themselves |
| Choose the size of main | Pipe options in Build; connections fit their endpoints automatically |
| Choose the lining | Pipe options → Bare / Lined / Armoured / Sealed, up to what the company can lay |
| Replace a main | Select it, then a size under "Replace pipe" - or U to go up one size |
| Choose how it is carried | MAIN / RAIL / HWY / SEA / AIR under the capacity row, or T |
| Inspect | Click a structure, a customer, a main, or empty ground |
| Build a structure | Toolbar or keys 1-9, then place |
| Sink a well or rig | Choose water or oil, select the supply button, then place it on a marked deposit |
| Build a power station | Choose Power, then Reactor on your ground or Wind park on an island |
| Build a works | More buildings, then any of the nine works, then place |
| Fit a wagon to a bulk line | Select the line, then the commodity under "Fit another wagon" |
| Set a distribution hub's minimum price | Select the hub, then minus / plus |
| Hire surveyors, scouts or analysts | Company tab, under the maintenance crews |
| Pan | Drag empty ground, or right / middle drag |
| Zoom / scroll sidebar | Mouse wheel |
| Show all buildings | F, or Show all |
| See the whole city | Scroll out on the map |
| Widen a selected main | U |
| Put a bigger main in place of a selected one, or grow a selected source | E |
| Repair a selected main, or all of them | R |
| Jump to the worst leaking main | L |
| Demolish selection | Delete, or the inspector button |
| Undo a decision | Z, or the undo button |
| Close the day | Enter, or End day |
| Switch or start a company | Companies, in the bottom bar |
| Cancel a tool or selection | Escape |
| Mute | M, or the sound button |
| Overview map (corner minimap; click it to jump) | O, or the gear menu |
| Filter the map by trade | All trades / Water / Power / Beer / Oil above the map |
| Show full or damaged mains and a selected customer's route | Supply overlay above the map |
| Return to construction from any panel | Build tools above the map |
| Choose a long-term ambition | Stats → Goals |
| Rename your company | Company → Rename; type, then Enter or Save name |

## A City Worth Growing

The opening guide walks through connecting the two houses and collecting the
first municipal grant. Everyday build tools stay near the top of Build;
**More buildings** reveals treatment, valves, storage and freight and stays collapsed until you open it. **Pipe options** reveals manual size and lining choices; automatic endpoint fitting keeps the opening straightforward. The guide can
be dismissed, and existing companies continue with their original saves.

Woods, mountain ranges and water give the map a sense of place, and two of them
are worth owning: parkland is where a forestry stands and bedrock is where a
quarry goes, so the permits that make them passable are an investment rather
than a toll. Woods are drawn as many trees and ranges as peaks rising out of
foothills, each with an irregular outline; that outline is exactly the ground
the rules charge for, so what you see is what a main pays to cross. Islands grow
groves at their ends and keep the middle clear for a wind park. Hover bare
ground to see what crossing it costs; while dragging a main, every wood and
range on the run lights up red (closed), amber (dearer) or green (open).

Zoomed in, customers, wells, works, towers, tanks, pumps, stops, stations,
resorts and depot yards stand as small buildings in the same footprint as their
disc (same click); zoomed out they return to flat icons that stay readable.
Plants spread over their sites (a turbine per wind row, a panel bank per solar
array, reactor domes beside a cooling tower, a headrace to the river), a
harbour runs a jetty to a moored ship, and road heads and airfields sit on
their own road and runway. Only badged structures and customers are
interactive. District landmarks and stories explain the character of each area.

The land view colours every plot by whether it can be bought now (green),
is next door but short of cash (amber) or is not reachable yet, and gives each
plot for sale a deed: type, price and discount, what stops you, and what is on
it. The panel lists the plots next door, cheapest first.

A power tower carries electricity and nothing else, so picking one up puts
electricity in hand whatever the panel had selected, and the preview, the price
and the main that gets laid all agree with it. The same happens when a drag
lands on a structure that leaves only one possible answer. Where two answers
would fit, the trade in hand is kept and the usual refusal says why.

While dragging a line, the quote shows the projected supply, change in daily net
income (including upkeep), and remaining cash. Offer inspectors estimate the
cheapest direct connection that could fully supply the customer, or explain
that a more involved route or more supply is needed. These are simulations of
the current network, not promises about future leaks or market changes. Shared
supply can reduce another customer's delivery; previews flag that risk.

End day starts the next day immediately. Stats shows the previous day’s results;
open Full day results for accounting, awards and events. Accounting expands on demand,
and enquiries and repair actions open the relevant inspector directly. Clients
can be sorted by urgency or potential daily income; Company includes a recent
operating-profit chart. The supply overlay marks full or damaged mains in amber
and traces a route from a selected customer to supply in blue. A full main is
not necessarily a service problem, and alternative routes may exist.

Goals also shows the next three equipment unlocks. Two later ambitions reward fully supplying four trades at once, or earning $250 net per day with at least twenty customers and no shortfalls.

Choose an optional ambition in Goals: hold twelve districts, maintain seven
consecutive closes of full service, or fully supply fifty customers. The selected ambition is evaluated at each day close and pays
its grant once. Progress and completed ambitions survive switching goals and
reloading. The service streak counts from play with this version; it resets on
a shortfall. Company names and guide dismissal also persist.

Hover over controls for prices and effects. Selecting anything on the map opens
the panel that can act on it and puts its most urgent control first, so clicking
a burst main lands on its Repair button rather than somewhere you have to scroll
from. "Build tools" returns. Undo works within the current session and day;
closing a day is final.

## The Second Half of the Game

- **Ground is cheapest towards the sea.** Every row further from the coast costs
  more, because the coast is where a harbour goes and a harbour is the door to
  everything the city cannot make for itself. The frontier costs more again, and
  gives more.
- **Five sizes, and the widest waits for a heart.** A TRUNK main carries 200,
  which is a whole treatment works' output in one trench, and it does not open
  for customers however many there are: it needs the works itself, because
  nothing else in the game can fill one. It is the last rung on a ladder where
  each size carries more cheaply per unit than the one below.
- **Mains branch because branching is cheaper.** The four sizes are priced on
  Murray's law, the rule a real vascular network follows: minimising the power
  spent pumping against the cost of maintaining the fluid gives `Q ~ r^3`, so a
  main's cross-section, and with it its dig, goes as `Q^(2/3)`. Doubling the
  flow costs 1.59 times the main, which is why one trunk that splits always
  beats two mains laid side by side, and why the network a company ends up with
  looks like a tree rather than a spiderweb. A trunk also runs further between
  pumps than a stub does, because pressure gradient falls as `Q^(-1/3)` at each
  size's design flow.
- **The network can be measured.** Stats prints the shape of your own water
  network the way a river system or a set of blood vessels is measured: a main
  into a building is order 1, and where two of the same order meet, the main
  carrying them both is one order higher. Under that are the three numbers that
  say whether the same shape repeats at every scale: how many mains feed each
  one below, how much more that one carries, and how much longer it runs.
  Capacity keeping up with branching is Murray's law holding. Length keeping up
  is the harder one, and the panel says plainly when it is not.
- **Ground has no edge.** Buy outward in any direction. Every district past the
  authored twelve is generated from the company seed and its own coordinates, so
  it is the same ground whoever surveys it first, and it is richer and dearer the
  further out it lies. Every natural deposit has a daily ceiling no amount of
  deepening passes, and the ceiling rises with distance, so more supply always
  means more map.
- **Distribution hubs.** A junction levelled four times becomes a distribution
  hub. Every close, for every customer inside 600 m paying at least its minimum
  price, it signs the offer, connects them with a real chain of T splits and
  mains, and widens the full main that is starving them, to a large main at
  most. Everything it lays is on the map and on the books. Customers below the
  minimum, and secure contracts, stay your decision.
- **The sea.** North of the first row is water that does not end. Islands in it
  are bought outright rather than next door, and need a harbour to reach. What
  they are for is the wind: a wind park burns nothing at all and will stand
  nowhere else.
- **Bulk freight.** A depot yard is the only thing inland a railway, a highway or
  a ship can terminate at. Rail is enormous to lay and nearly free to run;
  a highway is the opposite and is paid for in drivers and diesel; shipping is
  the cheapest freight there is and only calls at the coast; air costs more than
  most freight is worth and flies one aircraft type per route. Beer, oil and
  water need three different mains and share one train, each in its own wagon.
- **Mains have fixed sizes and nothing widens them.** Small carries 10, medium
  30, large 50; massive carries 100 and trunk 200, each once unlocked. If the small main you laid last year is too small now, it comes
  out of the ground and a bigger one goes in, and the old pipe is worth about a
  third of what it cost as scrap. One large main costs less than the four small
  ones it replaces, which is why a trunk into a hub beats a stub to every house.
- **Lining is decided when a main is laid, and never again.** The company buys
  the ability to lay bare, lined, armoured and finally sealed pipe, at $900,
  $3200 and $11000, and each grade costs more per metre than the last. Sealed
  pipe practically never fails and costs three times bare pipe to lay. Nothing
  improves a main already in the ground, so the cheap pipes at the centre of an
  old network stay the weakest thing you own until somebody digs them up.
- **Trades arrive one at a time,** in the order their chains can support:
  electricity, then oil, then food, then beer. Power needs nothing but water and
  a turbine hall, and everything else needs power. Oil is a rig on marked
  ground. Food needs wheat from a farm and salt, which nobody mines here, so a
  haven is part of the recipe. Beer needs malt, which needs wheat, and water and
  power besides: it is the longest chain in the game and it pays like it.
- **Works.** Ten of them, one output each, and a works missing any one of its
  inputs makes nothing at all. There is no half recipe. The inspector names
  whichever input is holding it back, which is the same question the game
  already answers for a short customer. That answer is one of six: a shut
  valve, nothing connected, a burst main to mend, a main to widen, a valve set
  lower than what wants through it, or wells already pumping flat out. It names a main that can actually be made wider,
  and where none can - a customer takes a small main and nothing else, however
  long the run of houses behind it - it says to put a fitting in the run
  instead.
- **Design is rewarded.** A main twice as wide is nothing like twice as dear to
  lay, so one big trunk into a hub with short spurs out of it beats a separate
  main to every house from about nine customers on, and beats it on upkeep from
  about seven. Below that, connecting directly is still the right answer.
- **Materials.** A hub is twenty steel, a works is forty steel and twenty
  concrete, a railway is twelve steel a kilometre, a solar array twelve panels.
  Materials are imported or made, taken in at the yards, and spent from there. A
  highway needs none, which is how the first steel ever reaches the city.
- **Importing.** Every haven has an import menu: pick a good and a quantity and
  pay the landed price now. The freighter (a ship at a harbour, lorries at a road
  head, a plane at an air apron) sets out at once and lands overnight. From there
  the load is hauled on to the nearest yard by the best way you have built: your
  own freight line, a semi along your roads, a barge on the river, a plane from
  an air apron, or a lorry overland. Haulage is billed at that mode's rate and the
  goods are in stock the morning after. Whatever a building is made of is driven
  out to its site, and a works or a power plant built of materials goes up from
  it overnight: it starts working the next day.
- **Land and roads.** Land is one continuous field; plots are survey lines, and
  woods and ranges may lie across them. There are no streets until you lay them:
  every road on the map is yours, and only a **bridge** crosses water. A bridge
  costs the road plus $3.20 a metre of water spanned and charges a toll you set.
- **Traffic is the company's own.** Cars, buses and lorries drive your roads as
  many as made trips on them today; trains, semis, ships and planes carry your
  freight; ships call only when cargo lands, ferries and airliners run only on
  routes that carried passengers. People live in the buildings on the map and
  walk the pavements of your roads, or their own gardens; there are more of them
  as a district grows.
- **Staff.** Surveyors report on ground you have not bought, scouts reveal the
  regions further out, analysts improve investment returns. They inform; none of
  them acts for you.

## People

- **People settle where the service is good.** A district with three signed
  customers counts as settled and grows toward seventy people for each of them,
  as fast as their supply is reliable. Customers left short cost it people. Out
  past the second ring some ground is already a town, full of people nobody
  moves.
- **People travel.** Every day they commute to the nearest populated districts
  and take day trips to resorts, and each trip has a price it is worth to them.
  Trips are routed like freight over whatever the company has built, the best
  paying first and the cheapest way first, and what does not fit waits.
- **Roads and tolls.** Once a district has people, stops and roads appear. Pick
  up Road and drag between two places people board, and every driver on it pays
  your toll. Freight highways carry drivers too, and are tolled the same way.
- **Buses, ferries and airlines.** Once a road exists, a bus route runs seats
  along it, a ferry calls at the coast, the river and the islands once there is
  a harbour, and an airline flies between two air freight aprons. A driver takes
  the car when that is cheaper, and everyone else takes the seats.
- **Petrol and cars.** A petrol works refines oil into gasoline, and a filling
  station on a road sells it to every driver passing at the price you set. A car
  works turns steel, glass, imported rubber and power into cars, which reach the
  yards and are sold at the close to the districts with room for more drivers.
- **Resorts.** Once a passenger route has carried somebody, a resort can stand on
  the coast, an island or the riverbank. It pulls day trips from every town in
  reach and takes their money when they arrive.
- **The internet.** Once a reactor is running, the internet licence opens. A data
  centre turns water and power into internet, and subscribers take it by fibre,
  the way a workshop takes power.

## What Things Cost

Nothing in the network has a flat price. A link is quoted the way a contractor
would quote it, and the quote is itemised on screen while you drag it:

- **Tie-ins**, charged once at each end, regardless of length. Connecting a house
  to a main that already runs past its door is still a day's work with a digger,
  so a zero-length connection still costs two tie-ins. A wellhead is the awkward
  end of the job and charges more; a manifold is a set of ports waiting for you
  and charges less.
- **Trench**, charged per metre, multiplied by the ground crossed.
- **Size**, which multiplies both. A medium main is about 1.7 times a small one
  and carries twice as much; a large one is about 2.9 times and carries four
  times as much. One large main is cheaper than the four small ones it replaces,
  which is the whole argument for a trunk into a hub.
- **Lining**, which adds 35%, 95% or 220% to the lot, depending on what the
  company can lay and what you choose for this main.

Each trade prices all of it differently. Water is cheap and thin-margined, power
sits just above it, beer is food-grade, and oil is pressurised and hazardous and
its prices say so - which is why a factory pays $26 a unit and a house pays $4.
Repairs and daily upkeep are priced off the same length and trade, so a long oil
trunk is a standing liability and a garden stub is not.

| | Water | Power | Beer | Oil |
| --- | --- | --- | --- | --- |
| Customer | House, Estate | Workshop | Pub | Factory |
| Pays | $4 - $6 / unit | $10 / unit | $16 / unit | $26 / unit |
| Tie-in, each end | $14 | $20 | $26 | $44 |
| Trench, per metre | $0.11 | $0.16 | $0.21 | $0.34 |
| Licence | held | $900 | $600 | $1500 |

A licence is priced against what the trade costs to enter rather than against
the paper it is written on, and the panel that sells one says what the rest of
the bill is: the cheapest generator, the well and its deposit, the works and
what it eats. Electricity was $340 in front of an $850 river turbine and a
transformer pole, which read as a cheap trinket and left companies holding a
licence they could not yet use.

## Company Decisions

- **Connections:** new customers appear as offers, and every one negotiates its
  own price. A household signs for one utility. Some houses and estates -- about
  a third of them, fixed per building -- also want electricity, and that arrives
  later as its own offer at its own rate. The rest are content with water, so a
  house is one contract unless it asks for two. Early on the spread is almost nothing, so a small company cannot be
  killed by three unlucky draws; as the company grows the spread widens until a
  lowball house is worth refusing outright and a premium factory is worth
  rerouting the map for. Declining costs nothing. Offers expire after several
  days, and accepted customers have a visible patience clock.
- **Cash:** customers pay for delivered units, and they are the only income. A
  well costs its upkeep a day and a pumping cost ($0.30 for water) for every unit
  it lifts. Every trade has an all-in cost a unit: sources, pumping and mains over
  the units delivered. The well, every customer, every offer, the header request
  and the Company tab show the price against that cost and what you keep, with an
  amber (cost) and green (margin) bar. More customers on the same mains make every
  unit cheaper. The expense line is itemised: office, wells, pumping, plant,
  mains, crews, imports and loan interest.
- **Failure:** a main has a daily chance to develop a leak. Once leaking it loses
  capacity every close until repaired. At zero it stays installed and repairable.
  Lost customers damage reputation.
- **Lining:** never required - a bare main carries exactly as much as a sealed
  one. Lined pipe cuts a main's leak risk to 45% and its repair bill to 70%,
  armoured to 12% and 45% while halving the rate a leaking main bleeds capacity,
  and sealed to 2% and 30%. What it is lined with is decided when it is laid, so
  improving an old main means digging it out. The inspector states what relaying
  would save per day and how long it would take to pay for itself.
- **Crews:** $340 to hire, $14 a day each, up to four. At every close each crew
  repairs the worst leaking main on the books and bills you for the work. The
  wage is the price of not clicking.
- **Wells and intakes:** grow the source you have rather than sinking another.
  Another stage needs no new route, no tie-in, no new ground and no second lot
  of upkeep, and it is priced below a second source at the margin in every
  trade, so a settled company runs one deep source and two or three shallow
  ones rather than a dozen identical wells. A well sunk on a field tops out at
  50 a day whatever you spend. A works standing on the river or the coast does
  not: it is an intake rather than a well, it costs three times as much to
  commission, and the channel's own width sets its ceiling. A broad estuary
  will carry a whole city through one building, and a headwater branch will
  carry about half of one.
- **Closing a well:** a well with mains tied into it is never simply deleted.
  Demolishing it caps the wellhead: production stops and part of the money comes
  back, but a connection chamber is built in its place, out of the refund,
  holding every main exactly where it was. That chamber is an ordinary structure
  afterwards.
- **Replacing a structure:** any structure can be swapped for another where it
  stands, paying only the difference, with every main left connected. Buying
  three more ports no longer means demolishing a junction and relaying
  everything by hand. A replacement is refused if the new structure has fewer
  ports than the mains already tied in.
- **Removing a structure:** every pipe hangs off a node at each end, so pulling
  one out cuts every main tied into it, and those mains are not recovered. The
  inspector says how many will be cut, what they cost, and how many customers
  would stop being supplied, before anything is pressed. With nothing standing
  there, no pipe can be connected or laid to that spot at all.
- **Ground:** the authored city is twelve districts and you start owning one,
  with generated ground in every direction past it. Districts are bought outward
  from what you already hold, each costing more than the last and more again the
  further out it is, and each has a character that decides who asks you for a
  connection: houses in Northgate, estates in Southfield, pubs in Brewers Row,
  factories in Docklands, and out past those, suburbs, farmland, woodland,
  quarries, industry and wilderness.
- **Forbidden ground:** parkland, rivers and bedrock block or tax every route.
  Three permits convert them from walls into tolls and let you build on them. The
  richest seams are under bedrock, which is what a blasting licence is really for.
- **Deposits:** oil comes out of the ground only where the survey marked it,
  and so does water away from the water's edge. A well or a rig goes on the
  mark and nowhere else, costs less than open ground would and yields half
  again as much. Running water is the exception and is its own deposit: an
  intake sinks no shaft, it stands on the bank and lifts what is already going
  past. Some are buried under
  obstacles and need the matching permit first. Everything else the city uses is
  landed at a haven.
- **Gates:** a valve you set by hand. Tighten it to starve a cheap branch on
  purpose and send scarce supply to the customers who pay more.
- **Depots:** take in output the network could not sell today, up to 18 units,
  and feed it back the next morning - worth having when a market event doubles
  what a trade pays.
- **Havens:** three things run along the edge of the map and stop at it - the
  estuary on the west, the trunk road across the north, the freight apron on the
  south. A haven is the door in that wall, so it can only stand on the strip of
  a district that touches one, and each of the three takes exactly one. What
  comes through it is unlimited: every trade but electricity, in any quantity,
  billed per unit as it moves. What it costs is the freight. Sea is the cheap way
  in at list price, road is x1.20, air is x1.55, and the cheap one is on the far
  side of the map from the dear one. **Track** runs the freight inland, up to
  1400m, never corrodes, and charges haulage by the unit and by the metre - which
  is why water is rarely worth importing across a city and oil almost always is.
  Nothing is piped straight out of a haven.
- **Electricity:** the one trade nobody can land. It is generated here or not at
  all, and a **nuclear plant** is what generates it: an enormous cheque, a large
  standing upkeep whether it runs or not, and fuel so cheap per unit that the
  next customer is nearly free. It needs no deposit, only ground you hold.
- **Beer:** nobody brews. A beer licence buys the right to lay beer mains, and
  the beer itself comes off a ship.
- **Credit:** the bank lends against the owner's own capital: up to twice the
  company's net worth (a new company's is its $750 founding stake), at a flat 1%
  a week charged daily. Borrowing moves cash and debt together, so it cannot raise
  its own limit. It is the instrument for buying a district today and paying for
  it out of the customers that district brings.
- **Investments:** deposits are locked for exactly seven closes. Return is
  normally distributed with mean 10% and standard deviation 5%; losses are possible.
- **Markets:** a heatwave, a beer festival or an excise rise moves what one trade
  pays for a few days. It is the only thing that changes a price without you
  touching anything, and it is what makes a full depot worth having.
- **Protection:** global treatment upgrades reduce base risk by 13 percentage
  points of its original value per grade. Treatment stations reduce risk by
  another 55% for mains whose midpoint is within 220m. Stations do not stack.
- **Growth:** advertising increases enquiries for five closes. Pumps reach 520m
  instead of 300m; manifolds have six ports instead of three.
- **Milestones:** serving 2, 5, 10, and 20 customers at a day close earns one-time
  municipal grants. Continue building after the final milestone.
- **Insolvency:** negative cash with no outstanding investments ends the company.

Every trade has a symbol and a colour and uses them everywhere: a blue droplet
for water, a violet bolt for electricity, an amber droplet for beer and a black
droplet for oil, beside the house, saw-tooth workshop, glass and chimney that
mark who buys them. Pipes can be laid at their intended capacity immediately.
Client buildings are
through-junctions: they draw up to their demand and pass remaining water onward.
The Customer supply toggle in the inspector closes only that customer's service
valve, so you can reserve scarce supply for customers farther downstream.
Denied customers still lose patience and leave; their through-pipes remain
installed when the account ends.
Source output is finite and shared between connected customers.

## Move To Another Device

```sh
make export
```

This produces:

- `dist/net-profit.love`: the game, runnable with LÖVE 11.x on Linux, Windows,
  or macOS. Install LÖVE on the destination, then open the file with it.
- `dist/net-profit-portable.zip`: the game, README, icon, and Linux installer.
  Extract it and run `sh install-linux.sh` once to add an app-menu entry.
- `dist/net-profit.bundle`: the committed source and complete Git history,
  requiring no hosting account or network access.

To work on the source on another device, sign in to GitHub with an account that
has access to the private repository, then clone it:

```sh
git clone https://github.com/louisvandenbruwaene/net-profit.git
cd net-profit
make run
```

For an offline transfer, use `git clone /path/to/net-profit.bundle net-profit`
instead. The bundle includes committed work only; commit before exporting.
The `origin` remote points to the private GitHub repository. Push committed
changes with `git push`; local edits and company saves do not sync automatically.
The runtime is not bundled; the export currently requires LÖVE to be installed.

To move your companies too, copy `company1.lua` through `company6.lua` and
`current.lua` from the LÖVE save directory. A company from before there were
slots is called `company.lua` and is picked up as the first slot:

| Platform | Save folder |
| --- | --- |
| Linux | `~/.local/share/love/net-profit/` (or your XDG data directory) |
| Windows | `%APPDATA%\\LOVE\\net-profit\\` |
| macOS | `~/Library/Application Support/LOVE/net-profit/`, or `~/Library/Application Support/net-profit/` for the installed app |

The installer preserves saved companies. Simulation randomness is stored with
the company, so loading preserves future outcomes.

## Verification

```sh
make test          # graph, company rules, save locations, persistence and growth
make smoke         # real input callbacks, company screens, save checks
make soak          # 60+ rendered company days
make tutorial      # the opening input walkthrough
make shots         # exact 1440x880 and 1100x700 rendered screenshots
make layout        # every string the interface draws, and any two that collide
make audio         # synthesized audio report
make dist          # package the game
```

Headless tests need Lua 5.4. Window tests need LÖVE and a display. All window test
targets have a timeout with forced termination. GitHub Actions runs the rules
and window tests under Xvfb and uploads the packaged game.

## Source Map

| File | Responsibility |
| --- | --- |
| `src/city.lua` | Company, prices, ground, construction, customers, daily economy and wear |
| `src/people.lua` | Population, trip demand and routing, roads, passenger routes, filling stations, resorts and cars |
| `src/graph.lua` | Dinic max flow, finite source output, separate commodities |
| `src/company_app.lua` | Input, camera, action history and game lifecycle |
| `src/company_ui.lua` | Network inspector, treasury, clients, journal and report |
| `src/company_render.lua` | City map, districts, trade symbols, flowing pipes and track, close-up buildings, land deeds |
| `src/scenery.lua` | Cached forests, mountain ranges, ponds, plot grass and cloud shadows |
| `src/terrain_shape.lua` | The lobed outline of woods and ranges, shared by the rules and the renderer |
| `src/company_save.lua` | Six save slots, versioned saves, random-state persistence |
| `src/experience.lua` | Isolated planning previews, ambitions, names, district stories and route overlays |
| `src/company_walkthrough.lua` | Rendered input and screenshot checks |
| `src/layout_audit.lua` | Records the box every drawn string occupies, and reports collisions |
| `src/stress_walkthrough.lua` | Every panel of a large company, drawn for `make layout` to measure |
| `test/test_company.lua` | Regression and multi-company economy tests |
| `test/test_people.lua` | Population, trips, tolls, routes, petrol, resorts, cars and the internet |
| `test/test_save_location.lua` | Save slots, and finding a company either build wrote |
| `src/distribution.lua` | The distribution hub: sign, connect and widen within its radius |
| `src/costs.lua` | Pumping bill, cost a unit per trade, and every customer's margin |
| `src/upgrades.lua` | Building levels (data in `src/data/upgrades.lua`) |

This is a playable management prototype. Economy tuning and whether the choices
stay interesting over a long human playthrough still need playtesting; passing
the tests establishes mechanics and solvency, not how addictive it feels.
