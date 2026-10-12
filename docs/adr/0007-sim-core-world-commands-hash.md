# ADR 0007: Simulation core (World v1, Command v1, tick pipeline, DetRandom, state hash, replays)

Status: accepted, 2026-10-12 (Michael). Proposed 2026-10-11 (revision 5 after the five-lens plan review and three completeness checks, same day).

Status note (2026-10-12): §6 partly superseded by ADR 0012 §1 and §3 (the runner's per-tick work
runs as a `TickJob`, on a worker thread on Android and desktop; prev positions live in the
`MatchSnapshot`); §10's last bullet superseded by ADR 0012 §3 (view handlers read
`runner.snapshot.events` inside `ticked`, not `runner.world.events`).

## Context
Phase 2's first box asks for an ADR on the World data model, the Command format and the state
hash. Phase 1 shipped the v0 shapes of ADR 0003: a struct-of-arrays `World` that never removes a
unit, `Command` v0 with one type (`ATTACK_MOVE`), `Sim.step` and the Node-side `MatchRunner`
with `CommandQueue` API v0. ADR 0002 §1 left the `CommandQueue` API and the fate of the `DetRng`
factory to this ADR. Phase 2 adds removal (death), projectiles, fog, flow fields and
randomness, and it must prove that the same seed gives the same match. Phases 3 and 4 add
buildings, production and an AI that acts only through Commands.

Facts checked headless on Godot 4.7.2 (scratch project, 2026-10-11, Xeon cloud VM):
- `int` is 64-bit. `0x7FFFFFFFFFFFFFFF + 1` silently becomes the minimum value, and a 64-bit
  multiply silently wraps. In C++ that is undefined behaviour, so nothing may rely on it.
- `1 << 64 == 1`. A constant negative operand of `>>` is a parse error. At runtime `-8 >> 1`
  gives `-4` (arithmetic shift). `+` binds tighter than `<<` (`a + b << 16` shifts the sum).
- A `PackedInt32Array` silently truncates a stored value to 32 bits (`2^31` is stored as
  `-2^31`, `0xFFFFFFFF` as `-1`). Squared distances in milli-tiles (up to about `8 * 10^9` on a
  64x64 map) do not fit. `PackedInt32Array` has no `pop_back()` (parse error).
- `HashingContext` (a `RefCounted` engine class, not a Node) computes SHA-256 over about 10 KB in
  0.07 to 0.10 ms. Over the real Phase 2 state (about 86-109 KB: fog counts per player,
  512 projectile slots x 10 arrays, terrain and move costs) it takes 0.34-0.38 ms (plan review).
  A hand-written FNV loop in GDScript is 3-5 times slower.
- `var_to_bytes()` / `bytes_to_var()` round-trip a Dictionary holding a String, ints, a
  `PackedInt32Array` and a `PackedInt64Array` exactly.
- `"%016x" % -2` gives `-000000000000002`. `encode_s64` plus `hex_encode()` always gives 16
  lower-case hex digits (the bytes in memory order).
- `FixedMath.isqrt` costs about 2 µs per call in GDScript.
- An array literal used inside a loop (`[1, -1, 0][k]`) allocates on every pass. A Dijkstra over
  64x64 cells took 17 to 20 ms written that way and 3 to 4 ms with constant offset arrays and a
  padded grid.
- Indexing `world.pos_x[row]` inside a 150-row loop costs 2.7 times as much as aliasing the
  array into a typed local first (writes through the alias reach the World). A per-element helper
  call (`fog.is_visible(p, world.cell_of(x, y))`) inside a loop costs 5.6 times an inline lookup
  on an aliased array (plan review benches).

## Decision

### 1. Numeric and coding rules (every file in `game/sim`)
- Sim state is `int`, `bool`, `StringName`/`String` (names only), `PackedInt32Array`,
  `PackedInt64Array` and `PackedByteArray`. No float anywhere (CLAUDE.md rule 2, enforced by
  `tests/project/test_sim_purity.gd`).
- **No expression may leave the int64 range.** Wrap-around is never used on purpose. Bit
  arithmetic (hashing, the generator) works on non-negative values below `2^49` and masks to
  32 bits. Shifts are parenthesised explicitly whenever they meet `+` or `-`.
- **Shift only non-negative values, by 0 to 62.**
- **A `PackedInt32Array` holds only values that fit in int32.** Positions, hit points, ids,
  ticks and plain distances fit. Squared distances, products, hashes and 32-bit unsigned words
  stay in local `int` variables or in `PackedInt64Array`. Every PR that adds a stored quantity
  states its range in the plan's column table and in the field comment.
- Division truncates toward zero (ADR 0003). Positions are clamped to `[0, map - 1]`, so cell
  lookups divide only non-negative values. Any other division of a value that can be negative
  states its rounding in a comment.
- No `hash()`, no Dictionary or Array iteration whose order depends on anything but insertion
  in id order.
- **Hot loops** (per row, per candidate, per cell):
  - no array or dictionary literal, `PackedInt32Array(...)`, `.duplicate()` or `.slice()` inside
    the loop body. `test_sim_purity` checks this by indentation, and a reviewed exception carries
    a trailing `# alloc-ok`;
  - World arrays are aliased into typed locals before the loop
    (`var pos_x: PackedInt32Array = world.pos_x`), and cell, passability and visibility lookups
    are inlined on those locals. Helper methods (`cell_of`, `is_passable`, `fog.is_visible`,
    `index_of`) are for code outside loops and for tests.
  - A loop may call a helper at **event cadence**, never on every row of every tick: when a row
    enters a new tile, gets a new order, or its staggered check comes due. The named cases are
    `FixedMath.line_clear` (line checks, ADR 0008 §2) and `FlowField.best_neighbour` (a `FIELD`
    unit entering a new tile or seeing its field complete, result stored in `nav_next`, ADR 0008
    §2). Any other case is named in the PR and reviewed.

### 2. World v1 layout (struct of arrays)
`World` stays one `RefCounted` with typed arrays, extended from v0 without renaming v0 fields.
It has these sections:

| Section | Contents | In the state hash |
| --- | --- | --- |
| Header | `tick`, `next_id`, `next_projectile_id`, `dropped_commands`, `projectile_overflow`, `spawn_refused`, `player_count` (players are 1..player_count, 0 is neutral), `proj_free_top`, `map_version` (last in `HASHED_SCALARS`, P29a2), `rng: DetRandom` | yes (`HASHED_SCALARS`, then `rng.state()`) |
| Rules | ints copied from `data/rules.tres` (`RulesDef`, ADRs 0008-0010), including `max_rows` and `max_projectiles` | no (in `defs_hash()`) |
| Types | v0 arrays plus `type_names` (display names), `type_max_hp`, `type_armour`, `type_move_class`, `type_sight`, `type_acquire`, `type_weapon` (-1 = unarmed) | no (in `defs_hash()`) |
| Weapons | `weapon_ids`, `weapon_range`, `weapon_min_range`, `weapon_damage`, `weapon_cooldown`, `weapon_projectile_speed` (0 = hitscan), `weapon_vs_armour` (4 per weapon, percent) | no (in `defs_hash()`) |
| Map | `map_w`, `map_h` (milli), `map_cols`, `map_rows` (tiles), `terrain_ids`, `terrain` (`PackedByteArray`, terrain index per tile), `move_cost` (`PackedByteArray`, `class * cells + cell`, 0 = blocked), `map_version`, `terrain_cost` (see the amendment in the next cell) | `map_version` (through `HASHED_SCALARS`, in the header section) plus a cached map digest of `terrain` and `move_cost` (the map section), recomputed only when `map_version` changes. Amendment (2026-10-12, P29b and P29c reviews): the Map section gains `terrain_cost`, declared in P29b (`PackedByteArray`, entry `terrain * 3 + class`, values 0..40, the per-terrain costs `set_terrain` copies into `move_cost`), written only by `from_scenario` and `prepare()` (open grass) and constant during a match; `MAP_ARRAYS` is `terrain`, `move_cost`, `terrain_cost`. The map digest covers every `MAP_ARRAYS` entry, `terrain_cost` included (no special case; it is not in `defs_hash()`). Open grass has `terrain_ids = [&"grass"]` (`World.GRASS_ID`), and a map size of 0 or less on either axis gives no map (0 x 0) |
| Units, one row each, ascending id | v0 `unit_id`, `owner`, `type_index`, `pos_x`, `pos_y`, `goal_x`, `goal_y`, `order`, plus `hp`, `order_target`, `target`, `cooldown`, `nav_mode`, `field`, `nav_cell`, `nav_next`, `best_dist`, `stall`, `fog_cell` | every array |
| Projectiles, fixed capacity `max_projectiles` | `proj_id` (0 = free slot), `proj_owner`, `proj_weapon`, `proj_target`, `proj_x`, `proj_y`, `proj_aim_x`, `proj_aim_y`, `proj_ticks`, and the free-slot stack `proj_free` with `proj_free_top` | live slots only (slot index plus its fields), then `proj_free[0, proj_free_top)` |
| Scratch, capacity `max_rows`, rewritten every tick (`SCRATCH_ARRAYS`) | `intent_x`, `intent_y`, `push_x`, `push_y` | no |
| Cost counters (`RUNTIME_ARRAYS`) | `stats: PackedInt32Array`, indexed by `enum Stat` (flow cells settled, line checks, separation pairs tested, targeting candidates tested, fog cells stamped, projectile steps, rows compacted), reset in phase 1 | no |
| Helper objects (wired in P31a) | `fog: FogGrid` (hashed through its own lists, ADR 0010), `flow: FlowCache`, `sep_grid: SpatialGrid`, `target_grid: SpatialGrid`, sight masks (derived) | `fog` only |
| Events (`RUNTIME_ARRAYS`) | `events: PackedInt32Array`, records of `EVENT_STRIDE = 8` ints (section 10) | no |
| View support | `rows_version` (bumped whenever rows are added or removed) | no |

- `World.Order` becomes `{ IDLE = 0, ATTACK_MOVE = 1, MOVE = 2, ATTACK = 3 }`. New enums:
  `Armour { INFANTRY = 0, LIGHT = 1, HEAVY = 2, BUILDING = 3 }`,
  `MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2 }`,
  `Event { SPAWNED = 1, DIED = 2, SHOT = 3, IMPACT = 4 }`,
  `NavMode { NONE = 0, DIRECT = 1, FIELD = 2, HOLD = 3, CHASE = 4 }`, `Stat { ... }`.
- **Shape registry.** `World` declares `const ROW_ARRAYS`, `TYPE_ARRAYS`, `WEAPON_ARRAYS`,
  `PROJECTILE_ARRAYS`, `MAP_ARRAYS`, `SCRATCH_ARRAYS`, `RUNTIME_ARRAYS` (`events` and `stats`:
  rewritten every tick, neither hashed nor compacted; all `Array[StringName]`), plus
  `HASHED_SCALARS` and `UNHASHED_SCALARS`. `remove_dead()` compacts exactly the `ROW_ARRAYS`
  (through `get(name)`, only on ticks with a death), and a test fails unless every `Packed*Array`
  property of `World` is in exactly one shape list and every `int` property in exactly one scalar
  list. A Phase 3 array therefore cannot be forgotten by the compaction or by the hash.
- **Who declares what.** The first two World v1 PRs (P29a, then P29a2; the plan lists which
  names each declares, so each stays under the PR size limit after `gdformat`) declare every
  World-level array, scalar, enum, scratch array and the `stats` counters, including those that
  later PRs fill.
  Each rule int keeps its `RulesDef` field name (`world.retarget_period_ticks`, ...), so data,
  code and tests use one name. Helper objects are separate classes from lane B (`FlowCache`,
  `SpatialGrid`, `FogGrid`). They become typed `World` members in P31a, after their classes
  exist, because a typed member of a missing class is a parse error. Later sim PRs put their rules in their own files (`Movement.gd`,
  `Separation.gd`, `Targeting.gd`, `Combat.gd`, `FogUpdate.gd`) and add one call to `Sim.step`.
  Two sim lanes can then work in parallel without both editing `World.gd`.
- **A hand-built `World.new()` is a valid open-grass world**, because Phase 1 tests and future AI
  unit tests build worlds that way:
  - the rule ints start at the `RulesDef` script defaults (`World._init()` copies
    `RulesDef.new()`; those defaults equal `data/rules.tres`, pinned by a test);
  - `World._init()` sets `rng = DetRandom.create(0, DetRandom.STREAM_SIM)`, the same default
    stream `from_scenario` uses for a null `rng`, so `state_hash()` (which hashes
    `rng.state()`) and spawn jitter never meet a null stream on a hand-built world (pinned by a
    test in the first World v1 PR);
  - `add_unit` raises `player_count` to `maxi(player_count, owner)` before the world is
    prepared, and uses hp 1 when the type has no `type_max_hp` entry (a type's stored max hp is
    `maxi(def.max_hp, 1)`);
  - `is_passable` is true and `cell_of` works while no map is loaded;
  - `prepare()` is idempotent (one bool check). It first **pads every `TYPE_ARRAYS` table to
    `type_ids.size()`** with named defaults, because Phase 1 tests append only the five v0 type
    arrays and the phase modules read the per-type tables inline and unguarded (section 1):
    `type_max_hp` 1, `type_armour` `INFANTRY`, `type_move_class` `TRACKED`, `type_sight` 0,
    `type_acquire` 0, `type_weapon` -1 (unarmed), `type_names` the type id as a capitalized String
    (`String(type_id).capitalize()`, the same rule `from_scenario` uses for a def whose
    `display_name` is empty, and the name the Phase 1 selection panel shows), and 0 for
    a missing v0 entry (`type_speed`, `type_radius`, `type_selection_radius`, `type_spacing`).
    The defaults are constants next to the shape lists (`TYPE_PAD_*`), not balance numbers: a
    padded type cannot fire, sees only its own tile and counts as tracked. Types are
    appended before the first step; a type appended after `prepare()` is not supported. When
    `map_cols == 0` it derives the tile grid from `map_w`/`map_h` (rounded up) as open grass.
    It (re)configures the helper objects to the World's size, players and `max_rows`, builds
    the sight masks, stamps the initial fog for every player and computes the map digest.
    `from_scenario` ends with `prepare()`, and `Sim.step` calls it first, so a hand-built world
    prepares on its first step.
  - After `prepare()`, `add_unit` refuses (returns 0 and counts `spawn_refused`) an owner above
    `player_count` or a row beyond `max_rows`.
- **Buildings (Phase 3) are rows of the same table.** They have hp, owner, armour, sight and a
  position, and they can be targeted, so targeting, damage, death and fog need no second code
  path. Building-only state (footprint, production queue, rally point) goes in side arrays added
  by the Phase 3 ADR and registered in the shape lists. The `unit_` prefix stays, and "unit" in
  the sim means "row".
- Per-player economy (credits, power) arrives in Phase 3 as arrays indexed by player id.
- `World.from_scenario(scenario: ScenarioDef, rng: DetRandom = null) -> World` copies every
  Resource once (ADR 0003 §6 stays). A null `rng` means `DetRandom.create(0, DetRandom.STREAM_SIM)`,
  so Phase 1 callers keep working. `world.rng` is the sim's stream. Types come from the spawns and
  from `ScenarioDef.roster` (extra types a later phase may produce). `player_count` comes from
  `ScenarioDef.player_count`, or the highest spawn owner when that is 0.
  Amendment (2026-10-12, P29c review): `player_count` is the scenario value (a negative value
  counts as 0) raised to the highest spawn owner, because spawns go through `add_unit` before
  `prepare()`; data keeps the spawn total within `max_rows` and the jitter in 0..8000.
- **Spawn jitter** draws exactly two values per unit (x then y) from `world.rng` if and only if
  the spawn's `jitter > 0`. A scenario with no jitter consumes no draws.

### 3. Ids, rows and removal
- Ids come from `next_id`, start at 1 and are never reused (ADR 0003). New rows are appended,
  and a new id is always the largest, so rows stay sorted by id and `index_of` stays a binary
  search.
- **Removal is a stable compaction at the end of the tick.** `World.remove_dead()` walks the rows
  once, keeps every row with `hp > 0` in its order and shrinks every `ROW_ARRAYS` array to the
  new count. No swap-remove: swapping would reorder rows and make iteration order depend on who
  died. It costs O(rows x arrays) only on ticks with a death.
- Before compaction each dead row writes a `DIED` event and unstamps its fog. Flow-field
  references need no release: the cache recounts them from the `field` column (ADR 0008 §3).
  Other rows that point at a dead id (`target`, `order_target`, `proj_target`) are not
  rewritten. They see `index_of(id) == -1` the next time they look.
- `rows_version` increments on every append and every compaction, so the view and the runner
  can tell when rows moved.
- Projectiles use fixed slots, not compaction. A new projectile takes the slot
  `proj_free[proj_free_top - 1]` and decrements the top (the stack is filled in descending order
  at start, so slot 0 is used first). An impact pushes its slot back. Slots are processed in
  ascending slot order. A shot with no free slot is applied as a hitscan and counted in
  `projectile_overflow`. The performance test requires that count to stay 0.

### 4. Tick pipeline (`Sim.step`)
`Sim.step(world: World, commands: Array[Command], probe: SimProbe = null) -> void`. In this
order, each phase iterating rows in ascending id order unless noted:
0. `world.prepare()` (a no-op after the first call).
1. Clear `events` and `stats`.
2. Sort the commands with `Command.compare`. Apply those with `tick == world.tick` (section 5).
   Drop and count the rest.
3. Flow fields: recount references, then advance pending integrations by at most
   `flow_cells_per_tick` cells (ADR 0008).
4. Rebuild both spatial grids from the positions at the start of the tick (ADR 0008).
5. Target acquisition, staggered by id (ADR 0009).
6. Movement intents: order, target, line check, flow field or straight steering (ADR 0008).
7. Separation pushes, accumulated from start-of-tick positions (ADR 0008).
8. Integrate: intent plus push, passability slide, clamp, arrival and stall (ADR 0008).
9. Projectiles advance in slot order, and those that arrive apply damage (ADR 0009).
10. Weapons: cooldowns, then fire, either hitscan damage or new projectiles (ADR 0009).
11. `remove_dead()` (section 3).
12. Fog update for the player whose turn it is (ADR 0010).
13. `tick += 1`.

Damage only lowers `hp` during phases 9 and 10. Rows die only in phase 11. A unit therefore
fires in the tick it dies, whatever its id, and no id has an advantage.

**Probe.** `game/sim/SimProbe.gd` is a `RefCounted` with `func begin() -> void` and
`func mark(phase: int) -> void`, both doing nothing, and the fixed phase ids:

```
enum Phase { COMMANDS = 0, FLOW = 1, GRIDS = 2, TARGETING = 3, INTENTS = 4, SEPARATION = 5,
	INTEGRATE = 6, PROJECTILES = 7, FIRE = 8, REMOVE = 9, FOG = 10, COUNT = 11 }
const PHASE_NAMES: Array[String] = ["commands", "flow", "grids", "targeting", "intents",
	"separation", "integrate", "projectiles", "fire", "remove", "fog"]
```

`COMMANDS` covers steps 0-2 above; `FLOW` to `FOG` are steps 3-12 in order; step 13 is not
timed. When a probe is passed, `Sim.step` calls `probe.begin()` first and
`probe.mark(Phase.X)` after each phase. Rules:
- The ids are fixed from the first pipeline PR on and never renumbered. A phase that does not
  exist yet is not marked and keeps its id, so per-phase numbers compare between PRs. A phase
  added in a later phase of the roadmap gets a new id through a new ADR.
- Marks come in ascending id order, each at most once per tick. Until the movement rewrite the
  Phase 1 movement is marked `INTEGRATE`.
- The `GRIDS` phase holds one rebuild line per spatial grid; no phase module rebuilds a grid.
- Consumers size by `Phase.COUNT` and label by `PHASE_NAMES`: the Node-side `TimingProbe`
  (`phase_usec`, zeroed by `begin()`, so an unmarked phase reads 0), the `PERF` line's
  `phases=` field and the perf card. The Node side
passes a subclass (`game/core/TimingProbe.gd`) that reads the clock, so the per-phase split is
measured without the sim ever referencing time. A probe never reads or writes the World. A test
proves that the hashes with and without a probe are equal.

### 5. Command v1
`Command` keeps every v0 field and gains `payload: PackedInt32Array` (type-specific ints, empty
for Phase 2 types).

| Type | Value | Target | Phase 2 meaning |
| --- | --- | --- | --- |
| `NONE` | 0 | - | always dropped |
| `ATTACK_MOVE` | 1 | point (milli) | v0 meaning; units fight what they meet (ADR 0009) |
| `MOVE` | 2 | point (milli) | like attack-move, but no acquisition until arrival |
| `ATTACK` | 3 | `target_id` | chase and fire at that one enemy (ADR 0009) |
| `STOP` | 4 | - | order `IDLE`, goal = position, target cleared, `field = -1` |
| reserved | 10-19 | | Phase 3 economy and production (planned: place building, queue unit, cancel unit, set rally, harvest) |
| reserved | 20-29 | | match-level (planned: surrender) |

- Factories: `attack_move()` (v0), `move(player_id, unit_ids, x, y)`,
  `attack(player_id, unit_ids, target_id)`, `stop(player_id, unit_ids)`. Each copies `unit_ids`.
- **Validation** (in `Sim.step`; an invalid command is dropped and `dropped_commands` counted, no
  `push_error`, never a crash). It is a `match command.type` with one `_valid_*` function per
  type and shared helpers (`_own_rows`, `_enemy_target`):
  - common to every type: the command is not null, `tick == world.tick`, `player_id` is in
    1..`player_count`, and `payload.size()` is at most `Command.MAX_PAYLOAD = 16`. Any type that
    has no branch (0, 5-9, the reserved ranges in Phase 2) is dropped as an unknown type before
    any id rule runs;
  - the unit-group types (`ATTACK_MOVE`, `MOVE`, `ATTACK`, `STOP`): `unit_ids.size()` is between
    1 and `Command.MAX_UNITS = 256`, and at least one id is valid: it exists, it belongs to
    `player_id`, and it has speed > 0 (for `ATTACK`, it must also have a weapon). Invalid ids and
    duplicates are filtered silently (v0 rule);
  - `ATTACK`: `target_id` exists, and its owner is neither `player_id` nor 0. From the fog-rules
    PR on (P46b), its cell must also be visible to `player_id` (ADR 0010). An AI can never attack
    what its player cannot see;
  - points are clamped to the map (v0 rule), then moved to the nearest passable tile for the
    group (ADR 0008).
  - Each later command type's id rules and payload layout are fixed by the ADR that adds it.
- **Order:** ascending (tick, player_id, sequence), as in v0. The match loop (section 9) stamps
  `tick` and a match-wide unique `sequence`, so the unstable sort cannot reorder equal keys.
- **Encoding** for replays: `encode(out: PackedInt32Array)` appends `tick, player_id, sequence,
  type, target_x, target_y, target_id, unit count, ids..., payload count, payload...`.
  `static func decode(data: PackedInt32Array, at: int, out: Command) -> int` returns the next
  offset, or -1 for malformed data (a count past the end, or a negative count).

### 6. Node-side services (`game/core`, ADR 0002 §1)
- **`CommandQueue` API v1 = v0, unchanged:** `submit`, `drain_into`, `clear`, `pending`. Input,
  and in Phase 4 the AI controllers, submit there. Nothing else does.
- **`DetRng` stays a stateless factory:** `func create(match_seed: int, stream_id: int) ->
  DetRandom`, which returns `DetRandom.create(match_seed, stream_id)`. The runner uses it for the
  sim stream, and AI controllers will use it for theirs. `game/sim` never references it.
- **`MatchRunner` v1** keeps the v0 contract and drives the match through a `MatchLoop`
  (section 9). Per tick it drains `CommandQueue`, calls `MatchLoop.step`, then does view
  bookkeeping (prev arrays re-aligned by id, prev positions per projectile slot, timing,
  `ticked`). It adds `@export var match_seed: int` (0 to 2^31-1), `match_serial` (incremented by
  every `start()`, so view layers detect a restart without comparing World identity) and the
  timing fields for the performance HUD. The contract is in the plan.

### 7. DetRandom
- **Algorithm: xoshiro128\*\*** (32-bit words, period 2^128 - 1), written so that every
  intermediate value stays non-negative and below 2^49:
  - `mul32(a, b)` = the low 32 bits of `a * b`, written with explicit parentheses:
    `(a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF`. (Without the inner
    parentheses `+` binds first and the whole sum is shifted, which is wrong and can pass 2^63.)
  - `rotl(x, k)` = `((x << k) & 0xFFFFFFFF) | (x >> (32 - k))`;
  - output = `mul32(rotl(mul32(s1, 5), 7), 9)`;
  - update (the published reference, with masks): `t = (s1 << 9) & 0xFFFFFFFF; s2 ^= s0;
    s3 ^= s1; s1 ^= s2; s0 ^= s3; s2 ^= t; s3 = rotl(s3, 11)`.

  The skill named PCG32 or xorshift64\*. Both need a 64-bit multiply modulo 2^64, which would
  rely on int64 wrap-around (section 1).
- **Seeding:**
  - `seed` is masked to 0..2^31-1, and `stream` is 0..65535.
  - Word `i` (0 to 3) is `mix32((seed + stream * 0x632BE5AB + i * 0x9E3779B9) & 0xFFFFFFFF)`,
    with `mix32` = lowbias32: `x ^= x >> 16; x = mul32(x, 0x7FEB352D); x ^= x >> 15; x = mul32(x, 0x846CA68B); x ^= x >> 16`.
  - An all-zero state sets word 0 to 1.
- **Streams:** `STREAM_SIM = 1` (owned by `World`, hashed with it) and `STREAM_AI_BASE = 100`,
  plus the player id (owned by each AI controller in Phase 4, so AI changes never shift sim
  rolls). Phase 2 sim uses its stream only for spawn jitter (`SpawnDef.jitter`), which makes
  different seeds give different matches.
- **API:** `static create(seed, stream)`, `next_u32()` (0 to 2^32-1), `next_int(n)` (0..n-1 for
  n in 1..2^31, unbiased by rejection; 0 for any other n), `range_int(lo, hi)` (inclusive),
  `shuffle(values: PackedInt32Array)` (Fisher-Yates from the end), `pick_random(values)`
  (0 when empty), `state() -> PackedInt64Array` (4 words, each 0..2^32-1) and
  `set_state(words: PackedInt64Array)` (masks every word to 32 bits).
- **Oracles in tests:**
  - the core generator: `set_state([1, 2, 3, 4])` then the first outputs equal the published
    reference, produced by compiling Vigna's public-domain `xoshiro128starstar.c` in a scratch
    folder (not committed);
  - the project's seeding (mix32, stream constants): literals from a Python transcription that
    is committed as `tests/sim/reference/det_random_ref.py`, so the literals can be regenerated
    and audited;
  - a state round-trip with high-bit words (above 2^31).

### 8. State hash
- `World.state_hash() -> int`: SHA-256 through `HashingContext`, in this order, each section
  preceded by a section tag and its length:
  - `STATE_FORMAT` (1), then `HASHED_SCALARS`, then `rng.state()`;
  - the map digest (8 bytes, cached; section 2);
  - every hashed row array;
  - live projectile slots (slot index and its fields), then `proj_free[0, proj_free_top)`;
  - `fog`'s hashed arrays (`FogGrid.HASHED`, ADR 0010).

  The result is the first 8 digest bytes as a signed int64 (`decode_s64(0)`).
- `static func hash_hex(h: int) -> String` is the only formatter for people:
  `encode_s64(0, h)` into 8 bytes, then `hex_encode()`. That is 16 lower-case hex digits, equal
  to the first 16 hex digits of the SHA-256 digest. The `PERF` line, the perf card, replay
  tools and gate issues use only this function.
- `to_byte_array()` is little-endian on every target (arm64 Android and iOS, x86_64, wasm32).
- **Coverage is enforced by a test.** Every `int` and `Packed*Array` property of `World` must be
  in exactly one of the shape lists and scalar lists (section 2), each list says hashed or not,
  and every helper object reachable from a World property declares its own `HASHED` and
  `UNHASHED` lists (dotted names such as `fog.visible`), checked the same way. A test changes one
  element of each hashed array and each hashed scalar and expects a different hash.
- `World.hash_parts() -> PackedInt64Array` returns one 8-byte digest prefix per section, in the
  order of `static func hash_section_names() -> PackedStringArray`: `"header"` (format, hashed
  scalars, `rng`), `"map"`, one name per `ROW_ARRAYS` entry, `"projectiles"`, `"fog"`. The
  determinism and replay tests print the names of the differing sections when hashes differ.
  It is computed only on failure.
- `World.defs_hash() -> int` hashes the type, weapon and rules tables the same way. It goes into
  the replay header, so a replay made with other data fails at once with a clear message
  instead of drifting.
- **Cadence:** the match loop hashes after every tick where `tick % 15 == 0` (once per second,
  measured at 0.34-0.38 ms before the live-slot and map-digest savings, so it is re-measured in
  P31b), and tests compare those checkpoints. Nothing hashes inside `Sim.step`.

### 9. Match loop and replays
- **`game/sim/MatchLoop.gd`** (pure `RefCounted`) is the one tick driver. It owns the sequence
  counter, `ScenarioOrders`, the `Replay`, a reused command list and the 15-tick checkpoints:
  `func step(world: World, queued: Array[Command], probe: SimProbe = null) -> void` collects the
  scenario orders for this tick, appends the queued commands, stamps tick and sequence, records
  each in the replay, calls `Sim.step`, and on `tick % 15 == 0` adds a checkpoint.
  `MatchRunner`, `Replay.play`, `tests/perf` and Phase 4's headless AI-vs-AI script all call it,
  so the phone and CI cannot drift through duplicated stamping code.
- A replay is `scenario_path + seed + defs_hash + the ordered command log + checkpoints`. The sim
  is a pure function of these (rts-sim-conventions).
- `game/sim/Replay.gd` (pure):
  - `record(command)` appends `Command.encode`, after stamping and before `Sim.step`;
  - `add_checkpoint(tick, hash)`;
  - `to_bytes()` is `var_to_bytes` of a Dictionary with `format = 1`, `scenario`, `seed`,
    `defs_hash`, `commands`, `checkpoint_ticks` (`PackedInt32Array`), `checkpoint_hashes`
    (`PackedInt64Array`), `final_tick` and `final_hash`;
  - `static from_bytes(bytes)` uses `bytes_to_var` (never `bytes_to_var_with_objects`) and
    returns null for a wrong format or a missing key;
  - `static func play(replay: Replay, world: World, until_tick: int) -> int` steps a fresh world
    with the logged commands and returns -1 when every checkpoint matches, the first tick that
    differs, or -2 when `defs_hash` differs.
- `MatchLoop.create(null, scenario_path, seed, world)` yields no scenario orders. `Replay.play`
  uses exactly that, because the log already holds the stamped scenario orders: it feeds each
  tick's logged commands to `step` as `queued`, in log order, so the re-stamped sequences equal
  the recorded ones.
- Loading the scenario Resource is the caller's job, outside the sim.
- **Storage:** Phase 2 keeps replays in memory (`MatchRunner.replay`) and in tests. Writing
  `user://replays/` comes with save data in Phase 5. Until then nothing is stored, so `FORMAT`
  may change freely (for example when Phase 3 adds per-match setup values).
- A replay is valid only for the code that recorded it. The data side is protected by
  `defs_hash`. Cross-version replays are not a goal before multiplayer.

### 10. Events
- `World.events` holds the events of the last tick. It is cleared in phase 1 and is not state.
- Records are `EVENT_STRIDE = 8` ints, unused fields 0:
  - `SPAWNED` `[1, id, x, y, type, owner, 0, 0]`;
  - `DIED` `[2, id, x, y, type, owner, 0, 0]`;
  - `SHOT` `[3, shooter id, shooter x, shooter y, target id, weapon, target x, target y]`, both
    positions read at fire time, so a tracer can be drawn after the target (or the shooter) has
    been removed in phase 11;
  - `IMPACT` `[4, projectile id, x, y, target id or 0, weapon, 0, 0]`.
- `MatchRunner` emits `ticked` after every step, and view handlers read `runner.world.events`
  inside that signal. Up to 4 ticks per frame then lose no event.

## Consequences
- Supersedes ADR 0003 §2 (Command and World shapes) and §3 (application rules) where they
  differ: Command gains three types and `payload`, World gains removal and v1 arrays, and
  "Phase 1 never removes a unit" ends. ADR 0003 stays accepted for the rest. Phase 1 code and
  tests keep compiling and stay green, because v0 names, values and factories are unchanged and
  a hand-built `World.new()` stays a valid world (section 2).
- The view can no longer assume that row `i` stays unit `i` across ticks. `MatchRunner` re-aligns
  its prev arrays by id and `UnitLayer` maps rigs by id (ADR 0011). That view work must merge
  before the first sim PR that kills units.
- Accepting this ADR makes the lead update `rts-sim-conventions` in P26 (complete list in the
  plan, "P26").
- The hash covers caches only indirectly. A divergence in a flow-field cache shows up as
  diverging positions, at most one second later. A Phase 5 save must store the flow-cache state
  or rebuild it at load. A resumed game is then not bit-identical to a replay from tick 0, which
  is acceptable for single player.
- SHA-256 relies on the engine's `HashingContext` (core, present in every official template).
  CI on x86_64 and arm64 Linux (if an official arm64 editor build exists, P51b), the Android APK
  and the web build compare golden hashes, which proves that assumption on every target.
