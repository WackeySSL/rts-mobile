---
name: rts-sim-conventions
description: Rules and patterns for the deterministic RTS simulation of rts-mobile - 15 Hz fixed tick, fixed-point integers, DetRng, the Command queue, entity storage, flow-field pathfinding, targeting, fog of war, state hashing and replays. Use whenever writing, reviewing or debugging code in game/sim, game/ai, data or tests/sim, even for small changes.
paths:
  - "game/sim/**"
  - "game/ai/**"
  - "data/**"
  - "tests/sim/**"
---

# RTS simulation conventions

The simulation is a pure function of (initial state, seed, ordered command list). Every rule
below protects that, because it gives reproducible tests, AI-vs-AI balance runs, replays and a
path to multiplayer.

## Time and units
- 15 ticks per second (`Sim.TICK_RATE = 15`). Durations in data are stored in ticks.
- Positions are integers in milli-tiles: 1 tile = 1000. Speeds are milli-tiles per tick, rounded
  in data and never at runtime (1.4 tiles/s = 93 per tick).
- Directions are 0-255 (0 = +x, 64 = +y, which is down on screen). `game/sim/FixedMath.gd` holds
  a 256-entry sine table scaled by 1024 and an integer `dir_to(dx, dy)`.
- No `sin`, `cos`, `atan2`, `sqrt` or any float in sim state. Compare squared distances with
  squared ranges.
- Health, damage, credits and power are plain ints.

## Randomness
- `DetRng` (PCG32 or xorshift64*) is owned by the match and passed explicitly. Never global,
  never `randi()` or `randf()`.
- Each AI player draws from its own stream seeded from (match seed, player index), so AI changes
  do not shift combat rolls.

## Commands
- `Command`: tick, player_id, type, unit_ids (PackedInt32Array), target cell or target_id, payload.
- Applied at the start of their tick in (tick, player_id, sequence) order. Invalid commands are
  dropped and counted; they never crash the sim.
- Input and AI never touch entities directly.

## Entities
- Integer IDs from a monotonic counter, never reused within a match.
- Stored as data in `World` (struct-of-arrays or typed arrays of RefCounted records), not as Nodes.
- Iterate in ascending ID order. Remove dead entities at the end of the tick.
- No allocation in hot loops: reuse PackedInt32Arrays and pool projectiles.

## Movement and pathfinding
- Tile grid with passability per movement class (foot, wheeled, tracked).
- Flow fields per (target cell, movement class): integer Dijkstra or BFS, cached, invalidated
  when buildings are placed or destroyed. A group move shares one field.
- Separation through a spatial hash (cell = 2 tiles), processed in ID order.

## Targeting and combat
- Spatial hash for range queries; target acquisition every 5 ticks, not every tick.
- Priority from data (can attack, threat, distance); ties broken by the lower entity ID.
- Projectiles are sim entities with an integer flight time. Rifles may be hitscan.
- Damage = base x armour-modifier percent from `data/`.

## Fog of war
- Per player `visible` and `explored` bit grids, updated every 3 ticks from precomputed sight masks.
- Easy and Normal AI read only their own player's visibility.

## Determinism checks
- `World.state_hash()` hashes all entity fields in ID order plus credits and tick.
- Tests run the same seed and commands twice and compare hashes every 15 ticks.
- Replay = seed + command log; `tests/sim/test_replay.gd` must reproduce the final hash.

## Data
- Units, buildings, weapons and AI profiles are custom Resources in `data/`. Load them once at
  match start into plain arrays. Never read Resources inside the tick loop.
