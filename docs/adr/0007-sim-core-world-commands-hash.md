# ADR 0007: Simulation core (World v1, Command v1, tick pipeline, DetRandom, state hash, replays)

Status: proposed, 2026-10-11

## Context
Phase 2's first box asks for an ADR on the World data model, the Command format and the state
hash. Phase 1 shipped the v0 shapes of ADR 0003: a struct-of-arrays `World` that never removes a
unit, `Command` v0 with one type (`ATTACK_MOVE`), `Sim.step` and the Node-side `MatchRunner`
with `CommandQueue` API v0. ADR 0002 §1 left the `CommandQueue` API and the fate of the `DetRng`
factory to this ADR. Phase 2 adds removal (death), projectiles, fog, flow fields and
randomness, and it must prove that the same seed gives the same match. Phases 3 and 4 add
buildings, production and an AI that acts only through Commands.

Facts checked headless on Godot 4.7.2 (scratch project, 2026-10-11, Xeon 2.1 GHz cloud VM):
- `int` is 64-bit. `0x7FFFFFFFFFFFFFFF + 1` silently becomes the minimum value, and a 64-bit
  multiply silently wraps. In C++ that is undefined behaviour, so nothing may rely on it.
- `1 << 64 == 1`. A constant negative operand of `>>` is a parse error. At runtime `-8 >> 1`
  gives `-4` (arithmetic shift).
- A `PackedInt32Array` silently truncates a stored value to 32 bits (`2^31` is stored as
  `-2^31`). Squared distances in milli-tiles (up to about `8 * 10^9` on a 64x64 map) do not fit.
- `HashingContext` (a `RefCounted` engine class, not a Node) computes SHA-256 over 15 state arrays
  and a 4096-byte grid in 0.07 to 0.10 ms. The same data through a hand-written FNV loop in
  GDScript takes 0.3 to 0.5 ms.
- `var_to_bytes()` / `bytes_to_var()` round-trip a Dictionary holding a String, ints, a
  `PackedInt32Array` and a `PackedInt64Array` exactly.
- `FixedMath.isqrt` costs about 2 µs per call in GDScript.
- An array literal used inside a loop (`[1, -1, 0][k]`) allocates on every pass. A Dijkstra over
  64x64 cells took 17 to 20 ms written that way and 3 to 4 ms with constant offset arrays and a
  padded grid.

## Decision

### 1. Numeric rules (every file in `game/sim`)
- Sim state is `int`, `bool`, `StringName`/`String` (names only), `PackedInt32Array`,
  `PackedInt64Array` and `PackedByteArray`. No float anywhere (CLAUDE.md rule 2, enforced by
  `tests/project/test_sim_purity.gd`).
- **No expression may leave the int64 range.** Wrap-around is never used on purpose. Bit
  arithmetic (hashing, the generator) works on non-negative values below `2^48` and masks to
  32 bits.
- **Shift only non-negative values, by 0 to 62.**
- **A `PackedInt32Array` holds only values that fit in int32.** Positions, hit points, ids,
  ticks and plain distances fit. Squared distances, products and hashes stay in local `int`
  variables or in `PackedInt64Array`. Every PR that adds a stored quantity states its range in
  the field comment.
- Division truncates toward zero (ADR 0003). Positions are clamped to `[0, map - 1]`, so cell
  lookups divide only non-negative values. Any other division of a value that can be negative
  states its rounding in a comment.
- No `hash()`, no Dictionary or Array iteration whose order depends on anything but insertion
  in id order, and no constant arrays built inside loops (declare them as `const` outside).

### 2. World v1 layout (struct of arrays)
`World` stays one `RefCounted` with typed arrays, extended from v0 without renaming v0 fields.
It has these sections:

| Section | Contents | In the state hash |
| --- | --- | --- |
| Header | `tick`, `next_id`, `next_projectile_id`, `dropped_commands`, `projectile_overflow`, `player_count` (players are 1..player_count, 0 is neutral), `rng: DetRandom` | yes |
| Rules | ints copied from `data/rules.tres` (`RulesDef`, ADRs 0008-0010) | no (in `defs_hash()`) |
| Types | v0 arrays plus `type_names` (display names), `type_max_hp`, `type_armour`, `type_move_class`, `type_sight`, `type_acquire`, `type_weapon` (-1 = unarmed) | no (in `defs_hash()`) |
| Weapons | `weapon_ids`, `weapon_range`, `weapon_min_range`, `weapon_damage`, `weapon_cooldown`, `weapon_projectile_speed` (0 = hitscan), `weapon_vs_armour` (4 per weapon, percent) | no (in `defs_hash()`) |
| Map | `map_w`, `map_h` (milli), `map_cols`, `map_rows` (tiles), `terrain_ids`, `terrain` (`PackedByteArray`, terrain index per tile), `move_cost` (`PackedByteArray`, `class * cells + cell`, 0 = blocked), `map_version` | `terrain`, `move_cost`, `map_version` |
| Units, one row each, ascending id | v0 `unit_id`, `owner`, `type_index`, `pos_x`, `pos_y`, `goal_x`, `goal_y`, `order`, plus `hp`, `order_target`, `target`, `cooldown`, `nav_mode`, `field`, `nav_cell`, `best_dist`, `stall`, `fog_cell` | every array |
| Projectiles, fixed capacity `max_projectiles` | `proj_id` (0 = free slot), `proj_owner`, `proj_weapon`, `proj_target`, `proj_x`, `proj_y`, `proj_aim_x`, `proj_aim_y`, `proj_ticks`, and the free-slot stack `proj_free` | every array |
| Fog | `fog: FogGrid` with per-player `visible` counts and `explored` bytes (ADR 0010) | both arrays |
| Caches | `FlowCache`, two `SpatialGrid`s, sight masks (ADRs 0008-0010) | no (derived) |
| Events | `events: PackedInt32Array`, records of `EVENT_STRIDE = 6` ints (section 10) | no |
| View support | `rows_version` (bumped whenever rows are added or removed) | no |

- `World.Order` becomes `{ IDLE = 0, ATTACK_MOVE = 1, MOVE = 2, ATTACK = 3 }`. New enums:
  `Armour { INFANTRY = 0, LIGHT = 1, HEAVY = 2, BUILDING = 3 }`,
  `MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2 }`,
  `Event { SPAWNED = 1, DIED = 2, SHOT = 3, IMPACT = 4 }`.
- **All Phase 2 arrays are declared in the first World v1 PR**, even those that later PRs fill.
  Later sim PRs put their rules in their own files (`Movement.gd`, `Separation.gd`,
  `Targeting.gd`, `Combat.gd`, `FogUpdate.gd`) and add one call to `Sim.step`. Two sim lanes can
  then work in parallel without both editing `World.gd`.
- **Buildings (Phase 3) are rows of the same table.** They have hp, owner, armour, sight and a
  position, and they can be targeted, so targeting, damage, death and fog need no second code
  path. Building-only state (footprint, production queue, rally point) goes in side arrays added
  by the Phase 3 ADR. The `unit_` prefix stays, and "unit" in the sim means "row".
- Per-player economy (credits, power) arrives in Phase 3 as arrays indexed by player id.
- `World.from_scenario(scenario: ScenarioDef, rng: DetRandom = null) -> World` copies every
  Resource once (ADR 0003 §6 stays). A null `rng` means `DetRandom.create(0, DetRandom.STREAM_SIM)`,
  so Phase 1 callers keep working. `world.rng` is the sim's stream.

### 3. Ids, rows and removal
- Ids come from `next_id`, start at 1 and are never reused (ADR 0003). New rows are appended,
  and a new id is always the largest, so rows stay sorted by id and `index_of` stays a binary
  search.
- **Removal is a stable compaction at the end of the tick.** `World.remove_dead()` walks the rows
  once, keeps every row with `hp > 0` in its order and shrinks every per-unit array to the new
  count. No swap-remove: swapping would reorder rows and make iteration order depend on who died.
  It costs O(rows x arrays) only on ticks with a death.
- Before compaction each dead row writes a `DIED` event, releases its flow field and unstamps
  its fog. Other rows that point at a dead id (`target`, `order_target`, `proj_target`) are not
  rewritten. They see `index_of(id) == -1` the next time they look.
- `rows_version` increments on every append and every compaction, so the view and the runner
  can tell when rows moved.
- Projectiles use fixed slots, not compaction. A new projectile takes the slot on top of the
  `proj_free` stack (filled in descending order at start, so slot 0 is used first). An impact
  pushes its slot back. Slots are processed in ascending slot order. Any deterministic policy
  is deterministic, and this one never allocates. A shot with no free slot is applied as a
  hitscan and counted in `projectile_overflow`. The performance test requires that count to
  stay 0.

### 4. Tick pipeline (`Sim.step`)
In this order, each phase iterating rows in ascending id order unless noted:
1. Clear `events`.
2. Sort the commands with `Command.compare`. Apply those with `tick == world.tick` (section 5).
   Drop and count the rest.
3. Flow fields: advance pending integrations by at most `flow_cells_per_tick` cells (ADR 0008).
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

### 5. Command v1
`Command` keeps every v0 field and gains `payload: PackedInt32Array` (type-specific ints, empty
for Phase 2 types).

| Type | Value | Target | Phase 2 meaning |
| --- | --- | --- | --- |
| `NONE` | 0 | - | always dropped |
| `ATTACK_MOVE` | 1 | point (milli) | v0 meaning; units fight what they meet (ADR 0009) |
| `MOVE` | 2 | point (milli) | like attack-move, but no acquisition until arrival |
| `ATTACK` | 3 | `target_id` | chase and fire at that one enemy (ADR 0009) |
| `STOP` | 4 | - | order `IDLE`, goal = position, target cleared, field released |
| reserved | 10-19 | | Phase 3 economy and production (planned: place building, queue unit, cancel unit, set rally, harvest). The Phase 3 ADR fixes names and payloads |
| reserved | 20-29 | | match-level (planned: surrender) |

- Factories: `attack_move()` (v0), `move(player_id, unit_ids, x, y)`,
  `attack(player_id, unit_ids, target_id)`, `stop(player_id, unit_ids)`. Each copies `unit_ids`.
- **Validation** (in `Sim.step`; an invalid command is dropped and `dropped_commands` counted, no
  `push_error`, never a crash):
  - the command is not null, and `tick == world.tick`;
  - `type` is one of 1-4, and `player_id` is in 1..`player_count`;
  - `unit_ids.size()` is between 1 and `Command.MAX_UNITS = 256`, and `payload.size()` is at
    most `Command.MAX_PAYLOAD = 16`;
  - at least one id is valid: it exists, it belongs to `player_id`, and it has speed > 0 (for
    `ATTACK`, it must also have a weapon). Invalid ids and duplicates are filtered silently (v0
    rule);
  - `ATTACK`: `target_id` exists, its owner is neither `player_id` nor 0, and its cell is
    visible to `player_id` (from the fog PR on; ADR 0010). An AI can never attack what its
    player cannot see;
  - points are clamped to the map (v0 rule), then moved to the nearest passable tile for the
    group (ADR 0008).
- **Order:** ascending (tick, player_id, sequence), as in v0. `MatchRunner` stamps `tick` and a
  runner-wide unique `sequence`, so the unstable sort cannot reorder equal keys.
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
- **`MatchRunner` v1** keeps the v0 contract and adds:
  - `@export var match_seed: int` (0 to 2^31-1);
  - scenario orders submitted through the same stamping as queued commands (scripted Commands,
    not a side door);
  - a `Replay` recorded from tick 0;
  - a state-hash checkpoint every 15 ticks;
  - prev-position arrays re-aligned by id after rows change;
  - prev positions per projectile slot;
  - `last_tick_usec` for the performance HUD.

  The contract is in the plan.

### 7. DetRandom
- **Algorithm: xoshiro128\*\*** (32-bit words, period 2^128 - 1), written so that every
  intermediate value stays non-negative and below 2^48:
  - `mul32(a, b)` = the low 32 bits of `a * b`, as `(a * (b & 0xFFFF) + ((a * (b >> 16)) & 0xFFFF) << 16) & 0xFFFFFFFF`;
  - `rotl(x, k)` = `((x << k) | (x >> (32 - k))) & 0xFFFFFFFF`;
  - output = `mul32(rotl(mul32(s1, 5), 7), 9)`; the state update is the published reference.

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
  (0 when empty), `state() -> PackedInt32Array` and `set_state(words)`.
- The first outputs for seeds 0 and 42 are pinned in tests against an independent reference
  implementation (the published C code transcribed to a scratch Python script, not committed).

### 8. State hash
- `World.state_hash() -> int`: SHA-256 through `HashingContext` over the hashed arrays of the
  table in section 2, in declaration order. Each array is preceded by a section tag and its
  length. The header ints (with `STATE_FORMAT = 1` first) and `rng.state()` go first. The result
  is the first 8 digest bytes as a signed int64 (`decode_s64(0)`). For people it is shown as 16
  hex digits of those bytes.
- `to_byte_array()` is little-endian on every target (arm64 Android and iOS, x86_64, wasm32).
- **Coverage is enforced by a test.** It lists every `Packed*Array` property of `World` (through
  `get_property_list()`) and fails unless each one is named in exactly one of
  `World.HASHED_ARRAYS` and `World.UNHASHED_ARRAYS`. A new array cannot be forgotten.
- `World.defs_hash() -> int` hashes the type, weapon and rules tables the same way. It goes into
  the replay header, so a replay made with other data fails at once with a clear message
  instead of drifting.
- **Cadence:** `MatchRunner` hashes after every tick where `tick % 15 == 0` (once per second,
  about 0.1 ms), and tests compare those checkpoints. Nothing hashes inside `Sim.step`.

### 9. Replays
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
    with the logged commands and returns -1 when every checkpoint matches, or the first tick
    that differs.
- Loading the scenario Resource is the caller's job, outside the sim.
- **Storage:** Phase 2 keeps replays in memory (`MatchRunner.replay`) and in tests. Writing
  `user://replays/` comes with save data in Phase 5, or earlier through a new ADR if a bug report
  needs it.
- A replay is valid only for the code that recorded it. The data side is protected by
  `defs_hash`. Cross-version replays are not a goal before multiplayer.

### 10. Events
- `World.events` holds the events of the last tick. It is cleared in phase 1 and is not state.
- Records are `[kind, id, x, y, a, b]`:
  - `SPAWNED` (id, x, y, type, owner);
  - `DIED` (id, x, y, type, owner);
  - `SHOT` (shooter id, x, y, target id, weapon);
  - `IMPACT` (projectile id, x, y, target id or 0, weapon).
- `MatchRunner` emits `ticked` after every step, and view handlers read `runner.world.events`
  inside that signal. Up to 4 ticks per frame then lose no event.

## Consequences
- Supersedes ADR 0003 §2 (Command and World shapes) and §3 (application rules) where they
  differ: Command gains three types and `payload`, World gains removal and v1 arrays, and
  "Phase 1 never removes a unit" ends. ADR 0003 stays accepted for the rest. Phase 1 code and
  tests keep compiling, because v0 names, values and factories are unchanged.
- The view can no longer assume that row `i` stays unit `i` across ticks. `MatchRunner` re-aligns
  its prev arrays by id and `UnitLayer` maps rigs by id (ADR 0011). That view work must merge
  before the first sim PR that kills units.
- `rts-sim-conventions` needs these edits, approved by Michael before P26 merges:
  - xoshiro128\*\* instead of "PCG32 or xorshift64\*";
  - the payload line;
  - a 1-tile separation grid and a 4-tile targeting grid instead of "cell = 2 tiles";
  - fog staggered per player;
  - the int32 storage and no-overflow rules.
- The hash covers caches only indirectly. A divergence in a flow-field cache shows up as
  diverging positions, at most one second later. A Phase 5 save must store the flow-cache state
  or rebuild it at load. A resumed game is then not bit-identical to a replay from tick 0, which
  is acceptable for single player.
- SHA-256 relies on the engine's `HashingContext` (core, present in every official template).
  The gate compares hashes from Linux CI, the Android APK and the web build, which proves that
  assumption on all three.
