# AUGMENT

A puzzle roguelike about building networks that survive their own minimum cut.

Each **contract** is one site, one fixed budget and one declared threat: *the
adversary severs 2 links*. You build from scratch, and the network must still
meet every terminal's demand **after** it cuts. A run is twelve contracts of
rising difficulty.

The threat is not a surprise. The red marks on the field show exactly what will
be taken if you commit right now, recomputed against your network every time you
change it. So committing is never a gamble, and the whole game is the question
the budget asks: *what is the cheapest network that the cut cannot break?*

## Start here

Press **TUTORIAL** on the title screen. It takes about two minutes and teaches on
your own graph, one idea at a time: deliver, discover that delivering is not
surviving, then fix it.

## Running

Needs [LÖVE](https://love2d.org) 11.x (`pacman -S love`).

    make run          # play
    make test         # graph algorithms and contract rules, headless
    make smoke        # input paths through the real love callbacks
    make soak         # a whole campaign solved and committed, every screen drawn
    make tutorial     # every tutorial step walked through the real callbacks
    make audio        # peak and RMS of every synthesised sound
    make dist         # build dist/augment.love

## Controls

| | |
|---|---|
| `1` `2` `3` | arm relay / hub / conduit, then click the site to place |
| drag node to node | lay a link |
| click | inspect a node or link |
| `U` | add capacity to the selected link |
| `X` | demolish, refunded in full |
| `Enter` | commit the contract |
| `R` `F` | clear the site, refit the camera |
| drag empty space, wheel | pan, zoom |
| `H` `S` | help, mute |

## The tension the puzzle is built on

Capacity is cheap and fragile. Routes are expensive and robust.

With `r` disjoint routes against a threat that takes `k`, you keep `r-k` of them,
so each needs `demand/(r-k)` capacity. Total capacity bought is
`r*ceil(demand/(r-k))`, which **falls** as you add routes, while structural cost
**rises**. There is a cheapest `r` somewhere in the middle, and it moves with the
geometry, the obstacles and the threat. Finding it is the game.

When the threat destroys **nodes** rather than links, routes that share a relay
die together: you need routes that share no vertex, not merely no edge. That is
Menger's theorem, and it is the difference between two contracts that otherwise
look identical.

## Every puzzle is provably solvable

Generation is not hope-based. A candidate map is handed to the reference solver
before the player ever sees it; if the solver cannot finish it, the map is
thrown away. The cost of the solution it finds becomes **par**, and the budget is
par plus slack that tightens as the run goes on.

This is only possible because the whole game runs on exact max-flow and min-cut,
so a generated contract can never turn out to be impossible, and "beat par" is a
real target rather than a guess.

## Layout

    main.lua             love callbacks, input, camera, the test modes
    src/graph.lua        graph structure, Dinic max flow, min cut, worst-case removals
    src/contract.lua     one puzzle: budget, geometry, build rules, commit
    src/campaign.lua     a run of twelve contracts
    src/generate.lua     procedural maps, verified solvable, priced against par
    src/solver.lua       reference builder: proves solvability, sets par, powers the soak
    src/render.lua       the field: obstacles, links, nodes, flow, the doomed set
    src/ui.lua           sidebar, inspector, overlays
    src/tutorial.lua     the guided first contract
    src/audio.lua        procedural synthesis; no audio files ship
    src/meta.lua         persistence
    src/camera.lua       pan and zoom
    src/palette.lua      every colour, in one place
    test/test_graph.lua    46 assertions on the algorithms
    test/test_contract.lua 215 assertions on the rules and on generation

`graph.lua`, `contract.lua`, `solver.lua` and `generate.lua` carry no LÖVE
dependency, which is why the rules, the generator and the solver can all be
tested headless with `lua5.4`.

## State

Complete and playable: title, tutorial, twelve contracts, commit and reveal, run
summary. Verified by 46 graph assertions, 215 contract assertions, 23 input
assertions, a soak that solves and commits a whole campaign, and an audio report.
A normal launch writes nothing to stdout or stderr.

Not done, roughly in order of what would add most:

- No upgrade draft between contracts. The tools unlock on a fixed schedule
  (hub at 3, conduit at 5) rather than being chosen.
- No daily seed, though generation is already deterministic in one, so it is
  mostly a menu.
- One adversary behaviour. Variants that prefer articulation points, or that
  announce a specific target, would use the machinery that is already here.
- No music, and the mute state is not saved between sessions.
- Obstacles are circles. Walls and corridors would shape routes far more.
- Mouse and keyboard only.

## Running under a tiling WM

Floating the window suits it better. For Hyprland:

    windowrulev2 = float, class:^(love)$
