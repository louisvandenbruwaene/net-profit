# Net Profit

A turn-based utility-company game about networks, cash, and promises.

Start with one water source, two houses, and $300. Build a network, sign new
customers, keep the pipes flowing, and decide how much of today's cash you can
afford to put into tomorrow's company. The map and company persist between days.

## Play

On this device, open **Net Profit** from the application menu. No terminal opens.
The installed application is a snapshot: run `make install` after changing the
source to update it.

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
| Lay a pipe | Drag from a source or structure to another node |
| Choose pipe capacity | Minus / plus in Network before laying it |
| Inspect | Click a structure, customer, or pipe |
| Build junction / manifold / pump / treatment station | Toolbar or keys 1 / 2 / 3 / 4, then place |
| Add a source | Choose a trade, select New source, then place |
| Pan | Drag empty ground, or use right / middle drag |
| Zoom / scroll sidebar | Mouse wheel |
| Fit the entire network | F or the fit button |
| Upgrade / repair a selected pipe | U / R, or inspector buttons |
| Demolish selection | Delete, or inspector button |
| Undo a decision | Z or the undo button |
| Close the day | Enter or Close day |
| Cancel a tool / selection | Escape |
| Mute | M or sound button |

Hover over controls for prices and effects. Sidebar sections scroll in smaller
windows. Undo works within the current session and day; closing a day is final.

## Company Decisions

- **Connections:** new customers appear as offers. Sign when you can deliver;
  unsigned offers consume no supply and cause no reputation penalty. Offers
  expire after several days. Accepted customers have a visible patience clock.
- **Cash:** customers pay for delivered units. Each source earns $12 wholesale
  per day. Offices cost $8/day, each source $6, each built structure $1, and each
  installed pipe $0.50, rounded up on the daily expense total.
- **Failure:** a pipe has a daily chance to develop a leak. Once leaking, it
  loses one capacity every close until repaired, including on the first day.
  At zero it stays installed and repairable. Lost customers damage reputation.
- **Protection:** pipe lining halves local risk. Global treatment upgrades
  reduce base risk by 13 percentage points of its original value per grade.
  Treatment stations reduce risk by another 55% for mains whose midpoint is
  within 220m. Multiple stations do not stack.
- **Growth:** advertising increases enquiries for five closes. Pumps reach
  520m instead of 300m; manifolds have six ports instead of three.
- **Ground:** bedrock blocks construction and pipes. Park crossings cost twice
  the base route price, river crossings three times. Nodes cannot occupy either.
- **Premium trades:** beer and oil licences unlock separate networks, sources,
  and customer types. Pubs and factories pay much more and have shorter patience.
  Different commodities can share structures and routes without mixing.
- **Investments:** deposits are locked for exactly seven closes. Return is
  normally distributed with mean 10% and standard deviation 5%; losses are possible.
- **Milestones:** serving 2, 5, 10, and 20 customers at a day close earns one-time
  municipal grants. Continue building after the final milestone.
- **Insolvency:** negative cash with no outstanding investments ends the company.
  Outstanding investments allow a company to wait for maturity but do not fund
  construction while cash is negative.

Pipes can be laid at their intended capacity immediately. Client buildings are
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
| macOS | `~/Library/Application Support/LOVE/net-profit/` |

The installer preserves saved companies. Simulation randomness is stored with
the company, so loading preserves future outcomes.

## Verification

```sh
make test          # graph, archived contracts, company rules, persistence and growth
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
| `src/city.lua` | Company, construction, customers, daily economy and wear |
| `src/graph.lua` | Dinic max flow, finite source output, separate commodities |
| `src/company_app.lua` | Input, camera, action history and game lifecycle |
| `src/company_ui.lua` | Network inspector, treasury, clients, journal and report |
| `src/company_render.lua` | City map, flowing pipes and customer symbols |
| `src/company_save.lua` | Versioned saves and random-state persistence |
| `src/company_walkthrough.lua` | Rendered input and screenshot checks |
| `test/test_company.lua` | Regression and multi-company economy tests |

The previous contract game is retained for comparison with
`love . --contracts`. Its graph and generation tests remain part of the suite.

This is a playable management prototype. Economy tuning and whether the choices
stay interesting over a long human playthrough still need playtesting; passing
the tests establishes mechanics and solvency, not how addictive it feels.
