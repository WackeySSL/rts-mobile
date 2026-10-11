# ADR 0009: Combat (Phase 2 roster, targeting, weapons, projectiles, armour classes, death)

Status: proposed, 2026-10-11 (revision 2 after the five-lens plan review, same day)

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
