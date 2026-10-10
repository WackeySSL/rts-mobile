# ADR 0003: Phase 1 simulation skeleton (Command v0, World v0, 15 Hz runner, unit and scenario data)

Status: proposed, 2026-10-10

## Context
Phase 1 (`docs/ROADMAP.md`) must show 30 tanks that move when the player gives orders. The
simulation core (World data model, Command format, state hash, flow fields, combat, fog) is
Phase 2, and Phase 2's first box is an ADR for the World model, the Command format and the
state hash. The CLAUDE.md hard rules apply in Phase 1 anyway: humans act only through Commands,
the sim is integer fixed-point at 15 Hz, `game/sim` has no Node, randomness only through a
seeded generator, and balance numbers live in `data/*.tres`.

Options considered:
1. **View-only movement** (tweens on Node2D). Breaks rules 1, 2 and 4 and is thrown away in
   Phase 2. Rejected.
2. **The full Phase 2 core now** (state hash, replay, flow fields, separation). Doubles Phase 1,
   delays the go/no-go on controls, and fixes Phase 2 decisions before Phase 2 is planned.
   Rejected.
3. **A minimal real sim that Phase 2 extends.** Chosen.

Facts that shaped it (Godot 4.7.2, checked headless in a scratch project on 2026-10-10): no
engine class is named `Command`, `World`, `Sim`, `FixedMath`, `Formation`, `UnitDef`,
`SpawnDef`, `ScenarioDef` or `MatchRunner`, and no `class_name` in `addons/` or `game/` uses
those names. GDScript `int` is 64-bit, and integer division truncates toward zero (`-7 / 2 == -3`).
`InputEvent` has no timestamp.

## Decision
1. **Scope pulled forward from Phase 2.** Phase 1 adds only these sim parts: the 15 Hz tick, a
   `Command` v0 with one type (attack-move), a struct-of-arrays `World` v0, straight-line integer
   movement to formation slots, `FixedMath.isqrt`, the unit and scenario definitions, and a
   Node-side runner that feeds Commands into ticks. Phase 1 adds **no** state hash, replay,
   command log, flow fields, separation, passability, combat, death, facing or fog. The Phase 2
   World/Command ADR adopts or supersedes these v0 shapes. The v0 shapes are kept small so that
   Phase 2 can extend them without breaking Phase 1 code.
2. **Classes** (all `extends RefCounted` unless noted, PascalCase files per ADR 0002 §2):
   - `game/sim/Sim.gd` `class_name Sim`: `const TICK_RATE: int = 15`,
     `const MILLI_PER_TILE: int = 1000`, and `static func step(world: World, commands: Array[Command]) -> void`.
     Applies the commands, then moves units, then increments `world.tick`.
   - `game/sim/Command.gd` `class_name Command`: `tick`, `player_id`, `sequence`, `type`
     (`enum Type { NONE = 0, ATTACK_MOVE = 1 }`), `unit_ids: PackedInt32Array`, `target_x`,
     `target_y` (milli-tiles), `target_id` (0 = none, unused in Phase 1). The target is a
     **point in milli-tiles**, not a cell: formation slots are centred on the tapped point, and
     snapping it to a tile centre would put the move marker up to half a tile from the finger.
     `rts-sim-conventions` says "target cell"; the lead asks Michael to update that line (see the plan).
   - `game/sim/World.gd` `class_name World`: map size in milli-tiles, per-type stat arrays, and
     per-unit `PackedInt32Array`s (id, owner, type index, position, goal, order). Unit ids come
     from a counter that starts at 1 and are never reused. Phase 1 never removes a unit.
   - `game/sim/FixedMath.gd`: `static func isqrt(n: int) -> int` (floor square root, integers
     only). Phase 2 adds the sine table and `dir_to`.
   - `game/sim/Formation.gd`: formation slots (rule 4).
   - `game/sim/defs/UnitDef.gd`, `SpawnDef.gd`, `ScenarioDef.gd` (`extends Resource`, integer
     and `Vector2i` fields only).
3. **Command application** (at the start of the tick that equals `command.tick`):
   - `Sim.step` sorts the list in place by (tick, player_id, sequence).
   - A command whose tick is not `world.tick`, whose type is unknown, or that has no valid unit
     left is dropped, and `world.dropped_commands` is incremented.
   - A unit id is valid when it exists, belongs to `player_id` and has speed > 0. Invalid ids
     and duplicates are filtered out silently.
   - The target point is clamped to the map, inset by the largest radius in the group.
   - Nothing in the sim calls `push_error`. An invalid command never crashes the sim.
4. **Attack-move and spread.** Each valid unit gets order `ATTACK_MOVE` and a goal on a
   formation slot:
   - Slot spacing is the largest `formation_spacing` in the group.
   - Candidates are the lattice points `target + spacing * (i, j)`. Ring r holds the points
     with `max(|i|, |j|) == r`. They are generated row by row (`j` from -r to r, then `i` from
     -r to r), keeping only ring-r points. Candidates outside the map inset by the group's
     largest radius are skipped.
   - K is the smallest ring such that rings 0..K hold at least n in-map candidates (n = group
     size). Candidates from every ring r with `r * r <= 2 * K * K` are collected, so no point
     outside ring K that is closer than ring K's corners is missed.
   - The candidates are sorted by squared distance to the target, with ties in generation
     order. The first n are the slots.
   - If the map cannot hold n slots, the units left over get the clamped target point. This
     never happens with the Phase 1 map and group sizes.
   - Assignment is greedy and centre-out. Each slot takes the nearest unassigned unit by squared
     distance; ties go to the lower id.
   - All of this is integer arithmetic, and it runs once per command, not per tick.
   - With no combat in Phase 1, `ATTACK_MOVE` moves like a plain move. Phase 2 adds target
     acquisition to the same order, so commands issued by Phase 1 code keep their meaning.
5. **Movement.** Each tick, units with an order are processed in ascending id order:
   - Compute `d2 = dx*dx + dy*dy` to the goal.
   - If `d2 <= speed*speed`, the unit snaps to the goal and becomes `IDLE`.
   - Otherwise `d = FixedMath.isqrt(d2)`, and the unit moves by `dx*speed/d` and `dy*speed/d`.
     Division truncates toward zero.
   - There is no collision or separation in Phase 1, so units may overlap while moving. They
     end on distinct slots.
6. **Data.**
   - `data/units/light_tank.tres` (`UnitDef`): `type_id = &"light_tank"`, `speed = 120`
     milli-tiles per tick (1.8 tiles/s from the GDD), `radius = 400`, `selection_radius = 500`,
     `formation_spacing = 1200`.
   - `data/scenarios/controls_test.tres` (`ScenarioDef`): `map_size_tiles = Vector2i(48, 48)`,
     `local_player = 1` and `camera_start_tile`, plus `spawns`. Each `SpawnDef` has `owner`,
     `unit`, `count`, `origin_tile`, `columns` and `spacing` (milli-tiles). The 30 player tanks
     and the 10 enemy targets are counts in this file. The targets are light tanks owned by
     player 2. They are static because Phase 1 has no player-2 controller, not because of a
     special unit type.
   - Unit art is found by convention from `type_id`
     (`res://assets/art/svg/units/<type_id>_{hull,team,turret}.svg`). The sim definitions hold
     no view references.
   - Resources are read once in `World.from_scenario()` at match start, never during a tick.
7. **Node side (`game/core/`, not sim):**
   - **`CommandQueue` autoload API v0.** This pulls the API that ADR 0002 §1 left for Phase 2
     forward into Phase 1:
     - `submit(command: Command) -> void`
     - `drain_into(out: Array[Command]) -> int`, which keeps submission order
     - `clear() -> void`
     - `pending() -> int`
   - **`game/core/MatchRunner.gd`** (`class_name MatchRunner extends Node`):
     - Builds the `World` from its exported `ScenarioDef`.
     - Accumulates frame delta into 15 Hz ticks, with at most `max_catch_up_ticks` (4) per
       frame. The excess backlog is dropped.
     - Each tick it drains `CommandQueue` and stamps each command with `tick = world.tick` and a
       runner-wide increasing `sequence`, then calls `Sim.step`.
     - Before each step it copies the positions into reused `prev_pos_x/y` arrays (no allocation).
     - It exposes `alpha()` for view interpolation and `run_ticks(n)`, which steps synchronously
       for tests.
   - Frame delta lives only here. The sim never sees time.
8. **Selection is not sim state.** Selection and control groups 1-3 are local to the player
   (`game/input/SelectionModel.gd`). They do not change the game, so they are not Commands. Only
   orders are Commands. This matches lockstep RTS practice and keeps replays small.
9. **Randomness.** Phase 1 sim code uses none, so it needs neither `DetRandom` nor the `DetRng`
   factory. The open docs issue #2 (DetRandom naming) therefore does not block Phase 1. It still
   blocks the Phase 2 plan.
10. **Determinism boundary.** Input converts float screen positions to integer milli-tiles once,
    when it builds a Command (`roundi`). From the Command on, everything is integer. The
    Command, not the touch, is what a replay records.

## Consequences
- `tests/project/test_sim_purity.gd` stops being vacuous: the first real `game/sim` code must
  pass it (no float, Vector2, Node, autoload or engine time).
- Phase 2 starts from working code with tests. Its ADR decides whether `Command` gains
  `payload`, cell targets or more types, whether `World` keeps SoA `PackedInt32Array`s, and how
  removal and the state hash work. Any of those may change v0 through a new ADR. Phase 1 tests
  pin behaviour (positions per tick, slots, drop rules), not storage layout, so they survive a
  layout change.
- Units overlap while moving until Phase 2 adds separation. Michael's gate judges group
  movement with this limit. If overlap blocks the gate, separation moves forward through a new ADR.
- `ROADMAP` Phase 2 box 2 (tick, Command queue) is partly done early but stays unticked until
  Phase 2 adds the state hash and replay test.
- Phase 1 view code interpolates between `prev_pos` and the current positions with
  `MatchRunner.alpha()`, which pulls part of Phase 2's "View interpolation" box forward.
  Without it, 15 Hz steps would look jerky and would bias the controls gate. That Phase 2 box
  is ticked only with its 150-unit check.
- Per command, slot generation and assignment are O(n^2) in the group size. That is 22 500
  comparisons for 150 units, run once per order, never per tick.
