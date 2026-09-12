# Net Profit

A turn-based utility-company game about networks, cash, and promises.

Start with one water well, two houses, one district of a twelve-district city,
and $380. Build a network, sign new customers, keep the pipes flowing, buy the
ground you want to grow into, and decide how much of today's cash you can afford
to put into tomorrow's company. The map and company persist between days.

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

Your company is found either way. LÖVE gives a fused app a different save
directory from a game run out of a source folder, so the game looks in both and
mirrors each save into the other. Playing the app and running the checkout are
the same company, not two that drift apart.

To regenerate the app icon from `assets/net-profit.svg`, run `sh macos/make-icon.sh`.

On Linux, run `make install` to add the application-menu entry.

From a source checkout, install LÖVE 11.x and run:

```sh
make run
make install       # Linux app-menu entry, icon, and packaged game
```

The game opens directly into your company and automatically saves after each
decision and day close. Test modes use isolated companies and never overwrite
your normal save.

## Controls

| Action | Control |
| --- | --- |
| Lay a pipe or cable | Drag from one structure to another |
| Choose the trade | Water / Power / Beer / Oil in Network |
| Choose the bore | Minus / plus in Network before laying |
| Lay track instead of pipe | The PIPE / TRACK toggle, or T |
| Inspect | Click a structure, a customer, a main, or empty ground |
| Build a structure | Toolbar or keys 1-7, then place |
| Sink a well | Choose a trade, select New well, then place |
| Pan | Drag empty ground, or right / middle drag |
| Zoom / scroll sidebar | Mouse wheel |
| Fit the network | F, or the fit button |
| See the whole city | Open the Map tab |
| Widen a selected main | U |
| Line a selected main, deepen a selected well | E |
| Repair a selected main, or all of them | R |
| Jump to the worst leaking main | L |
| Demolish selection | Delete, or the inspector button |
| Undo a decision | Z, or the undo button |
| Close the day | Enter, or Close day |
| Cancel a tool or selection | Escape |
| Mute | M, or the sound button |

Hover over controls for prices and effects. Selecting anything on the map opens
the panel that can act on it and puts its most urgent control first, so clicking
a burst main lands on its Repair button rather than somewhere you have to scroll
from. "Build tools" returns. Undo works within the current session and day;
closing a day is final.

## What Things Cost

Nothing in the network has a flat price. A link is quoted the way a contractor
would quote it, and the quote is itemised on screen while you drag it:

- **Tie-ins**, charged once at each end, regardless of length. Connecting a house
  to a main that already runs past its door is still a day's work with a digger,
  so a zero-length connection still costs two tie-ins. A wellhead is the awkward
  end of the job and charges more; a manifold is a set of ports waiting for you
  and charges less.
- **Trench**, charged per metre, multiplied by the ground crossed.
- **Bore**, charged per extra unit of capacity both as fittings at the ends and
  as wider pipe over the whole run. A fat trunk main across the map is the most
  expensive thing you can build; a fat stub is nearly free.

Each trade prices all three differently. Water is cheap and thin-margined, power
sits just above it, beer is food-grade, and oil is pressurised and hazardous and
its prices say so - which is why a factory pays $26 a unit and a house pays $4.
Repairs, daily upkeep and lining are all priced off the same length and trade, so
a long oil trunk is a standing liability and a garden stub is not.

| | Water | Power | Beer | Oil |
| --- | --- | --- | --- | --- |
| Customer | House, Estate | Workshop | Pub | Factory |
| Pays | $4 - $6 / unit | $10 / unit | $16 / unit | $26 / unit |
| Tie-in, each end | $14 | $20 | $26 | $44 |
| Trench, per metre | $0.11 | $0.16 | $0.21 | $0.34 |
| Licence | held | $340 | $600 | $1500 |

## Company Decisions

- **Connections:** new customers appear as offers, and every one negotiates its
  own price. Early on the spread is almost nothing, so a small company cannot be
  killed by three unlucky draws; as the company grows the spread widens until a
  lowball house is worth refusing outright and a premium factory is worth
  rerouting the map for. Declining costs nothing. Offers expire after several
  days, and accepted customers have a visible patience clock.
- **Cash:** customers pay for delivered units. Wells earn wholesale that scales
  with their output. The expense line is itemised: office, wells, plant, mains,
  crews, imports and loan interest.
- **Failure:** a main has a daily chance to develop a leak. Once leaking it loses
  capacity every close until repaired. At zero it stays installed and repairable.
  Lost customers damage reputation.
- **Lining:** never required - a bare pipe carries exactly as much on the day it
  is laid. Lining cuts a main's leak risk to 45% and its repair bill to 70%, and
  armour takes those to 12% and 45% and halves the rate a leaking main bleeds
  capacity. The inspector states what each would save per day and how long it
  would take to pay for itself. On a short water stub that is a poor trade; on a
  long oil trunk it pays back in about a month, and it is the difference between
  playing the game and chasing burst mains around it.
- **Crews:** $340 to hire, $14 a day each, up to four. At every close each crew
  repairs the worst leaking main on the books and bills you for the work. The
  wage is the price of not clicking.
- **Wells:** deepen the one you have rather than sinking another. A deeper well
  needs no new route, no tie-in, no new ground and no second lot of upkeep, which
  makes it the cheap option until the levels get steep - and then it is not.
- **Ground:** the city is twelve districts and you start owning one. Districts
  are bought outward from what you already hold, each costing more than the last,
  and each has a character that decides who asks you for a connection: houses in
  Northgate, estates in Southfield, pubs in Brewers Row, factories in Docklands.
- **Forbidden ground:** parkland, rivers and bedrock block or tax every route.
  Three permits convert them from walls into tolls and let you build on them. The
  richest seams are under bedrock, which is what a blasting licence is really for.
- **Seams:** marked spots where a well costs less and yields half again as much.
  Some are buried under obstacles and need the matching permit first.
- **Gates:** a valve you set by hand. Tighten it to starve a cheap branch on
  purpose and send scarce supply to the customers who pay more.
- **Depots:** take in output the network could not sell today, up to 18 units,
  and feed it back the next morning - worth having when a market event doubles
  what a trade pays.
- **Havens:** the port, the airfield and the highway head are the only three
  places freight can arrive. A terminal there lands 24 units a day of one trade,
  far more than any well, but bills you for every unit that moves: supply bought
  rather than supply owned. **Track** runs it inland, up to 1400m, and never
  corrodes - there is no such thing as a leaking railway.
- **Credit:** the bank lends up to half of what the company owns, excluding cash,
  at a flat 10% a week charged daily. No variance at all, unlike the deposit
  fund. It is the instrument for buying a district today and paying for it out of
  the customers that district brings.
- **Investments:** deposits are locked for exactly seven closes. Return is
  normally distributed with mean 10% and standard deviation 5%; losses are possible.
- **Tenders:** the council asks for a delivery level you do not yet have, held
  for several closes. Nothing is lost by failing one, which is what makes taking
  an ambitious one a decision rather than a trap.
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

To move your company too, copy `company.lua` from the LÖVE save directory:

| Platform | Save folder |
| --- | --- |
| Linux | `~/.local/share/love/net-profit/` (or your XDG data directory) |
| Windows | `%APPDATA%\\LOVE\\net-profit\\` |
| macOS | `~/Library/Application Support/LOVE/net-profit/`, or `~/Library/Application Support/net-profit/` for the installed app |

The installer preserves saved companies. Simulation randomness is stored with
the company, so loading preserves future outcomes.

## Verification

```sh
make test          # graph, contracts, company rules, save locations, persistence and growth
make smoke         # real input callbacks, company screens, save checks
make soak          # 60+ rendered company days
make tutorial      # the opening input walkthrough
make shots         # exact 1440x880 and 1100x700 rendered screenshots
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
| `src/graph.lua` | Dinic max flow, finite source output, separate commodities |
| `src/company_app.lua` | Input, camera, action history and game lifecycle |
| `src/company_ui.lua` | Network inspector, treasury, clients, journal and report |
| `src/company_render.lua` | City map, districts, trade symbols, flowing pipes and track |
| `src/company_save.lua` | Versioned saves and random-state persistence |
| `src/company_walkthrough.lua` | Rendered input and screenshot checks |
| `test/test_company.lua` | Regression and multi-company economy tests |

The previous contract game is retained for comparison with
`love . --contracts`. Its graph and generation tests remain part of the suite.

This is a playable management prototype. Economy tuning and whether the choices
stay interesting over a long human playthrough still need playtesting; passing
the tests establishes mechanics and solvency, not how addictive it feels.
