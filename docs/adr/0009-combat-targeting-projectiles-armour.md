# ADR 0009: Combat (Phase 2 roster, targeting, weapons, projectiles, armour classes, death)

Status: accepted, 2026-10-12 (Michael). Proposed 2026-10-11 (revision 2 after the five-lens plan review, same day).

Status note (2026-10-20, P26y docs): after the merges of P41 (#112, acquisition) and P41b (#114,
engagement), §2 and §3 carry dated status notes on how `game/sim/Targeting.gd` realises them
(the scan's cell window in place of "5x5", the two meanings of "armed", the chase line's
trigger, the inclusive acquire-range guard and the counted line checks). No accepted text
changed.

## Context
ROADMAP Phase 2 asks for "combat with projectiles, armour classes and death". The GDD lists six
MVP units and four armour classes (infantry, light, heavy, building), and puts the damage
percentages per class in `data/`. `rts-sim-conventions` asks for:
- target acquisition every 5 ticks from a spatial hash;
- priority from data, with ties to the lower id;
- projectiles as sim entities with an integer flight time;
- rifles that may be hitscan;
- damage = base x armour percent.

Phase 1's "attack-move" moves without fighting (ADR 0003 §4), and a tap on an enemy attack-moves
to its position (ADR 0004 §5). Production, buildings, harvesters and artillery splash belong to
Phases 3 and 4.

The plan review found that straight chasing across rock deadlocks at a ridge: with rock covering
x in [30000, 34000), every rifle squad at the ridge edge acquires an enemy across it (acquire
5000 > 4001) that it can never shoot (range 4000), keeps it (stickiness), and slides along the
rock instead of using the gaps.

## Decision

### 1. Phase 2 roster: three unit types
Three types are enough to prove what the box asks for:
- two armour classes in play (infantry, light);
- hitscan and projectile weapons;
- two movement classes (foot, tracked);
- the GDD's counter triangle: rifle squads beat rocket squads, rocket squads beat light tanks,
  light tanks beat rifle squads, at equal cost.

| Unit | Armour | Move | HP | Speed (milli/tick) | Radius / selection / spacing | Sight / acquire | Weapon |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `light_tank` | LIGHT | TRACKED | 300 | 120 (1.8 t/s) | 400 / 500 / 1200 | 7000 / 5500 | `tank_cannon` |
| `rifle_squad` | INFANTRY | FOOT | 100 | 67 (1.0 t/s) | 300 / 350 / 900 | 6000 / 5000 | `rifle` |
| `rocket_squad` | INFANTRY | FOOT | 90 | 60 (0.9 t/s) | 300 / 350 / 900 | 6000 / 5500 | `rocket` |

| Weapon | Range | Min range | Damage | Cooldown (ticks) | Projectile speed (milli/tick) | vs infantry / light / heavy / building (%) |
| --- | --- | --- | --- | --- | --- | --- |
| `tank_cannon` | 4500 | 0 | 30 | 25 | 600 | 70 / 60 / 35 / 40 |
| `rifle` | 4000 | 0 | 12 | 15 | 0 (hitscan) | 100 / 10 / 5 / 5 |
| `rocket` | 5000 | 0 | 50 | 45 | 300 | 20 / 100 / 100 / 80 |

- Ranges, HP and speeds are the GDD's. Damage, cooldown, projectile speed and percentages are
  starting values, chosen so that the triangle holds by hand calculation:
  - 6 rifles against 1 tank leave the tank about half its HP (a rifle does 1 damage to light
    armour after truncation);
  - 2 rocket squads kill a tank in about 6 hits, before it lands the 5 shots that kill one squad;
  - 6 rifles wipe 2 rocket squads.

  The combat PR's triangle test is the judge. A value may change in that PR only with the test
  green and the plan table updated.
- A squad is one sim row. The art draws several soldiers in one sprite.
- HEAVY and BUILDING have percentage columns from day one. Tests prove them with a test-only
  `UnitDef` built in code. The heavy tank, artillery (which will use `min_range`), harvester and
  buildings arrive with production in Phase 3, through that phase's plan.
- `UnitDef` gains `display_name`, `max_hp` (script default 1, so a def built in a test never
  spawns dead), `armour` (`@export_enum`), `move_class`, `sight_range`, `acquire_range` and
  `weapon: WeaponDef` (null = unarmed). `WeaponDef` has `id`, `range`, `min_range`, `damage`,
  `cooldown_ticks`, `projectile_speed` and `vs_armour` (4 percents). A data test enforces:
  - `range <= acquire_range <= sight_range`;
  - speed 0 or at least 2 (ADR 0003 amendment);
  - every percent in 0..200 and `damage >= 1`;
  - cooldown at least 1;
  - unique `type_id` and weapon `id`.

### 2. Targeting
- Acquisition runs for a unit on the ticks where `(tick + id) % retarget_period == 0` (rules, 5).
  A fifth of the units scan each tick, so no tick holds all the scans.
- A unit scans only when it has a weapon and either has no valid target or its target is out of
  its current reach. Valid means the row exists, it is an enemy (owner is neither its own nor 0),
  and, from the fog-rules PR on, its cell is visible to the unit's owner (ADR 0010). Reach is the
  acquire range when attack-moving and the weapon range otherwise.
- **Candidates** come from the 4-tile targeting grid, from the cells that cover the reach (5x5
  for the Phase 2 ranges). A candidate must be a valid enemy with `d2 <= reach^2`,
  `d2 >= min_range^2` and a damage percent above 0 against its armour.
- **Priority:**
  1. highest damage percent against the candidate's armour (data-driven, so rocket squads
     prefer vehicles and rifles prefer infantry);
  2. then the smallest `d2`;
  3. then the lower id.
- **Stickiness:** a valid target within reach is kept. There is no switching for a better
  candidate, which avoids thrashing.
- **By order:**
  - `ATTACK_MOVE`: reach = acquire range, then engage (section 3).
  - `IDLE`: reach = weapon range. The unit fires but never moves on its own.
  - `MOVE`: no acquisition until arrival. The unit does not fire while moving.
  - `ATTACK`: the target is locked to `order_target` while it is valid. If it dies or goes out
    of sight, the order becomes `ATTACK_MOVE` to its last seen position.
- In Phase 2 an idle unit hit from beyond its weapon range does not react. The Phase 4 AI
  handles that.

Status note (2026-10-20, P26y docs, P41 as merged, #112, and P41b, #114; the text above stays as
accepted). `Targeting.run` is the TARGETING phase's acquisition pass, one pass over the rows in
ascending id order:
- **The cells.** "5x5 for the Phase 2 ranges" does not hold. The scan's cell window is computed
  from the reach: every row in the grid cells from `(pos - reach) / cell_milli` to
  `(pos + reach) / cell_milli` on each axis (integer division truncating toward zero, clamped to
  the grid), itself excepted. With the shipped ranges that is 3x3 to 4x4 cells, fewer at an edge.
- **The count.** `stats[TARGET_CANDIDATES]` adds every row the scan looks at, friends and neutral
  units included (only the scanning row itself is skipped). A kept target costs 0, because a row
  that keeps its target does not scan.
- **Ties.** The grid is visited cell by cell, not in id order, so the lower-id tie-break is an
  explicit comparison (`other < best` at an equal percent and `d2`).
- **Stickiness** as merged: a due row keeps its target while that unit exists, is an enemy and
  is still a candidate within reach (`min_range^2 <= d2 <= reach^2` and a percent above 0).
- **`MOVE`** rows drop their target on every tick, not only at acquisition.
- **`ATTACK`** (P41b): `target` is the row's `order_target` while that unit exists and is an
  enemy, and the row's goal is the target's position at the start of the tick. When the target
  is gone the order becomes `ATTACK_MOVE` to the goal it left (the target's last position),
  `order_target` and `target` are cleared, and the row goes through the same pass as an
  attack-moving row: it scans in that pass if it is due on that tick. "Goes out of sight" waits
  for the fog rules (P46b).
- **Two meanings of "armed".** `Targeting` treats a type whose weapon index is negative or past
  the weapon tables as unarmed: it acquires nothing and never holds or chases. `Sim._own_rows`,
  which validates an `ATTACK` command, asks only for an index of 0 or more. So on a hand-built
  World that names a weapon it has no table for, an `ATTACK` row locks its target and steers at
  it for good.
- **An empty map** (a grid with no cells): the `MOVE` clear and the `ATTACK` lock still run, and a
  due row that keeps no target writes 0 without a scan.
- **Owner 0.** The enemy test is "an owner that is neither the row's own nor 0", so an armed
  neutral row (owner 0) would acquire every player's units. No Phase 2 scenario arms a neutral
  unit; the plan records this as a design note for P42a, P44 (its rows P44a and P44b) and P46b,
  whose per-player vision lookup must handle owner 0.

### 3. Engagement
- With a valid target inside weapon range (`min_range <= d <= range`), the unit's `nav_mode` is
  `HOLD`: no movement intent, though separation still applies.
- With a valid target outside weapon range but inside reach:
  - **attack-move:** the unit chases it with `CHASE` (straight steering to the target's current
    position, with sliding) only while `FixedMath.line_clear` from the unit to the target holds
    for its class. The line is checked when the target is acquired and each time the unit enters
    a new tile (the same trigger as ADR 0008 §2). While the line is blocked, the unit keeps
    following its order's navigation (`DIRECT` or `FIELD` towards its slot) and fires as soon as
    the target comes into weapon range. Units therefore use the gaps instead of pressing into
    rock;
  - **attack (explicit target):** the unit uses `DIRECT` while the line is clear, else a flow
    field keyed on the target's tile (ADR 0008 §3, re-keyed after `attack_rekey_milli`).
- With no target, an attack-moving unit resumes its path to its slot (its line check runs
  again).
- There is no facing or turret turn time in the sim. The view turns turrets (ADR 0011).

Status note (2026-10-20, P26y docs, P41b as merged, #114; the text above stays as accepted).
Engagement is `Targeting._engage`, a second pass of the TARGETING phase after acquisition, on
every tick, from the positions at the start of the tick; it writes navigation state only through
`Movement.reset_row`, when a mode changes or an `ATTACK` unit's line must be checked again (a
`DIRECT` row reset to `DIRECT`, see `ATTACK` below). Where it differs from the text above:
- **The chase line's trigger.** The line is checked on the unit's line-check turn,
  `(tick + id) % line_check_period_ticks == 0`, not "when the target is acquired and each time
  the unit enters a new tile". With the shipped periods (both 5) that turn is also the unit's
  acquisition turn. The first clear line starts the chase and the first blocked one ends it, so a unit
  can stay in `CHASE` with a blocked line for up to `line_check_period_ticks` ticks (5),
  pinned by `MOST_BLOCKED_CHASE_TICKS` in `tests/sim/test_engagement_rock.gd`.
- **The acquire-range guard is inclusive**: an attack-moving unit tests the line only while
  `d2 <= acquire_range^2`.
- **Line checks are counted.** Each `FixedMath.line_clear` call of engagement adds 1 to
  `stats[LINE_CHECKS]`, added after its loop, as `Movement._check_line` counts its own.
- **`ATTACK`** never chases: its goal is the target's position, and its order's navigation takes
  it to weapon range (`DIRECT` while the line is clear, else a field keyed on the target's tile).
  Because that goal walks, on the unit's line-check turn a `DIRECT` unit whose line was marked
  clear tests it again, and a blocked line sends it back through `Movement.run`'s check, which
  takes the field on the same tick.
- **`HOLD`** is left again when the target is out of weapon range (it moved, or the unit was
  pushed). An idle unit holds too but never chases. A unit whose target is gone resumes its path:
  `DIRECT` with its line unchecked and no field (`NONE` for an idle unit).

### 4. Firing, projectiles and damage
- `cooldown` counts down by 1 per tick to 0. A unit with a target in weapon range and cooldown 0
  fires, and cooldown becomes `cooldown_ticks`. It fires on the first tick in range.
- **Hitscan** (projectile speed 0): the damage is applied at once in phase 10, and a `SHOT` event
  is written with the shooter's and the target's positions (ADR 0007 §10).
- **Projectile:**
  - It takes a slot (ADR 0007 §3) at the shooter's position, aimed at the target's position,
    with `proj_ticks = max(1, ceil(dist / speed))`. The distance is one `isqrt` per shot. A
    `SHOT` event is written too.
  - Each tick (phase 9): while the target exists, the aim follows the target's position (a
    homing shell, so no miss logic). Then `pos += (aim - pos) / proj_ticks` and
    `proj_ticks -= 1`.
  - At 0 it hits: the target, if it still exists, takes damage. An `IMPACT` event is written,
    and the slot is freed.
  - A projectile whose target has died flies to the last aim point and hits nothing.
- **Damage** = `max(1, damage * vs_armour[armour] / 100)` when the percent is above 0, else 0.
  `hp` may go below 0.
- **Death** in phase 11: rows with `hp <= 0` write `DIED` and are compacted (ADR 0007 §3). There
  is no wreck, kill credit or experience in Phase 2.
- **Splash** damage and **min range** use come with artillery in Phase 3/4. `min_range` already
  excludes candidates (section 2).

### 5. Proof
`tests/sim` proves:
- acquisition order (percent, distance, id), staggering and stickiness;
- `MOVE` never fires and idle units never move;
- chase then hold, and no chase through rock: two rifle squads on opposite sides of a 4-tile rock
  band keep following their path to the gap and never press into the band;
- hitscan damage is immediate, and projectile flight time equals `ceil(dist / speed)`;
- a hitscan kill's `SHOT` event carries the target's position;
- homing follows a moving target;
- a death mid-flight leads to an `IMPACT` with target 0;
- every armour percent, including heavy and building through a test-only def;
- a unit fires in the tick it dies;
- removal keeps id order;
- the counter triangle, with equal-cost duels on an open map, each run twice with the same
  final hash.

## Consequences
- The controls map's red light tanks now fire back. Tanks die, so the view must handle removed
  rows (and the selection must follow deaths) before this ADR's first death PR merges (ADR 0007
  Consequences).
- Hitscan rifles cost no projectile slots. A 75-versus-75 fight stays well under 512 slots:
  about 50 cannons and rockets in flight at peak. The perf test bounds the peak.
- Numbers will move in Phase 4 balance runs. Only the triangle and the GDD's ranges, HP and
  speeds are pinned as design intent.
- A tap on an enemy becomes an `ATTACK` Command (the `touch-ui-rules` "Attack it") instead of
  ADR 0004 §5's attack-move to its position. The `HOW_TO_PLAY` row changes in the same PR.
- Players cannot disengage in Phase 2: every ground tap is an attack-move, and `MOVE` has no
  gesture yet. This is a known limitation, recorded in `HOW_TO_PLAY.md`; a gesture for it is on
  the Phase 3 plan's agenda.
  Status note (2026-10-20, P43c): the limitation is lifted. A ground tap issues `MOVE` (Michael's
  decision of 2026-10-20), which drops the units' targets and holds their fire until they arrive
  and stand idle, where §2's idle reach (the weapon's range) applies; a tap on an enemy still
  issues `ATTACK`.
