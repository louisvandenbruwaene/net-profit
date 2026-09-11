# AUGMENT

A roguelike about growing a flow network that survives its own minimum cut.

You start as a single source. Terminals appear across the field, each demanding
its own supply every wave. You buy nodes and lay links to reach them. Then an
adversary computes your minimum cut and severs it.

That last part is the game. Your maximum flow equals the capacity of your
minimum cut, so whatever is cheapest to cut is exactly what limits you, and the
adversary attacks precisely there. One thick trunk is a cut of width one: lose
it and you lose everything. Five thin disjoint routes are a cut of width five:
lose one and you keep four fifths. Redundancy is not caution, it is survival.

Fail to meet demand and the run ends. You keep the theorems you unlocked.

## Running

Needs [LÖVE](https://love2d.org) 11.x (`pacman -S love`).

    make run          # play
    make test         # graph algorithm unit tests (lua5.4, headless)
    make smoke        # input layer driven through the real love callbacks
    make sim          # balance telemetry from the reference bot
    make tune         # parameter sweep over the economy
    make dist         # build dist/augment.love

## Controls

| | |
|---|---|
| `1` `2` `3` | arm relay / hub / conduit, then click the field to place |
| drag node to node | lay a link |
| click | inspect a node or link |
| `U` | upgrade the selection (link capacity, node throughput) |
| `X` | demolish the selection, for a partial refund |
| `space` | resolve the wave |
| right-drag, wheel | pan, zoom |
| `C` `T` | centre on source, cycle terminals |
| `H` `M` | help, theorems |

## Reading the field

- **Link thickness** is capacity: what it could carry.
- **Moving dots** are flow: what it does carry.
- **The ring** around a node is its ports, one tick per link it can hold.
- **A node's inner fill** is how close it is to its throughput limit.
- **The red pulse** is the minimum cut, and it is where the next strike lands.

## The graph theory, and where it lives

Nothing here is decorative. Each mechanic is a theorem you have to act on.

| Concept | How you meet it |
|---|---|
| Max-flow min-cut | Delivery is a max flow; the adversary strikes the min cut |
| Menger's theorem | Surviving *k* strikes requires *k+1* disjoint routes |
| Degree constraints | Ports cap how many links a node can hold |
| Vertex capacities | Node throughput, modelled by splitting each node in two |
| Vertex connectivity | From wave 8 the adversary destroys nodes, not just links |
| Articulation points | Cut vertices are flagged live; each one is a single point of failure |
| Connectivity | A terminal severed from the source is served nothing |

## Layout

    main.lua            love callbacks, input, camera, screenshot and smoke modes
    conf.lua            window config
    src/graph.lua       graph structure, Dinic max flow, min cut, Tarjan, stats
    src/game.lua        run state, economy, wave pacing, the adversary
    src/render.lua      the field: links, nodes, flow, cut, effects
    src/ui.lua          sidebar, inspector, overlays
    src/meta.lua        persistence and the theorem unlocks
    src/camera.lua      pan and zoom
    src/palette.lua     every colour, in one place
    test/test_graph.lua unit tests with hand-computed expectations
    test/bot.lua        reference player, shared by sim and tune
    test/sim.lua        balance telemetry
    test/tune.lua       parameter sweep

`src/graph.lua` and `src/game.lua` have no LÖVE dependency, which is why the
rules and the algorithms can be tested headless with `lua5.4`.

## Design notes

The economy was tuned by simulation rather than by feel. `test/bot.lua` plays
the strategy the game means to teach, `test/tune.lua` sweeps the constants, and
the target was a median around the mid-teens for that bot, leaving a thinking
player real headroom. Current numbers: median wave 13, range 9 to 24 over 40
runs.

Three findings from that process shaped the design, and each is worth knowing
before changing the balance:

1. **Strikes must be capped.** Redundancy is bounded above by ports, so a strike
   count that grows without limit eventually exceeds any achievable cut width
   and kills even perfect play. Pressure comes from the economy of rebuilding.
2. **Demand is per terminal and scales with that terminal's own age.** Pooled
   demand made expansion optional; demand at full current value made a new
   terminal cost more in one wave than the whole network earned.
3. **Delivery and capacity are different flows.** Delivery caps each terminal at
   its demand and decides survival. Capacity ignores those caps and yields the
   cut the adversary attacks. Without the split, meeting demand exactly left the
   minimum cut empty and made the player untouchable.

If you run it under a tiling window manager, floating the window suits it
better. For Hyprland:

    windowrulev2 = float, class:^(love)$
