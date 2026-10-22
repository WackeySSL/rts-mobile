class_name RulesDef
extends Resource
## Every tuning int of the sim (Phase 2: ADRs 0007-0010, Phase 3: ADR 0018). The instance is
## res://data/rules.tres, where all tuning happens; these defaults equal that file (a test pins
## both). World copies the ints under these names at match start. Times are ticks and distances are
## milli-tiles.

## Targeting: a unit scans for a target when (tick + id) % retarget_period_ticks == 0.
@export var retarget_period_ticks: int = 5
## Fog: each player's fog updates once per this many ticks.
@export var fog_period_ticks: int = 3
## Movement: a unit checks the straight line to its goal every this many ticks.
@export var line_check_period_ticks: int = 5
## Flow fields: cells settled per tick, and the number of cached fields.
@export var flow_cells_per_tick: int = 512
@export var flow_cache_size: int = 8
## Separation: overlapping neighbours used, units looked at, the share (percent) of a push that
## an idle unit takes next to a moving one, the push cap per axis and the divisor of the
## near-coincident distance.
@export var separation_neighbours: int = 8
@export var separation_scan: int = 16
@export var separation_idle_share: int = 75
@export var separation_push_max: int = 60
@export var separation_coincident_divisor: int = 4
## Stall: ticks without progress, within this many formation spacings of the goal, before a unit
## goes idle where it stands.
@export var stall_ticks: int = 15
@export var stall_range_spacings: int = 2
## An attack field is re-keyed when the target moves this far (milli-tiles) from its goal.
@export var attack_rekey_milli: int = 4000
## Capacities: projectile slots and unit rows.
@export var max_projectiles: int = 512
@export var max_rows: int = 256

## Phase 3 economy, production and building rules (ADR 0018 section 9). World copies them like the
## ints above (World.RULE_SCALARS, plan row P70); the rules that read them come with plan rows P73
## to P77.
## Credits: a player starts with start_credits.
@export var start_credits: int = 2000
## Ore fields: every ore cell starts with ore_start units, holds at most ore_cell_max and gains
## one unit on each tick with tick % ore_regrow_ticks == 0.
@export var ore_start: int = 20
@export var ore_cell_max: int = 20
@export var ore_regrow_ticks: int = 150
## One unit of ore is worth this many credits.
@export var credits_per_ore: int = 25
## Harvesters: ticks per unit mined and per unit unloaded (staggered by id), the distance (milli-
## tiles) from an ore cell's centre and from a dock within which a harvester has arrived, the wait
## before it looks for ore again, the wait before an idle one resumes (0 = never), and how far
## from a HARVEST point it takes an ore cell.
@export var harvest_ticks_per_ore: int = 3
@export var unload_ticks_per_ore: int = 1
@export var harvest_reach_milli: int = 1200
@export var dock_reach_milli: int = 1500
@export var harvest_retry_ticks: int = 15
@export var harvest_resume_ticks: int = 75
@export var harvest_pick_milli: int = 3000
## Power: a queue advances at this percent of its rate while a player uses more than it makes.
@export var low_power_percent: int = 50
## Production and building: items per queue, how far (tiles) from an own building a new one may
## stand, and the caps of mobile rows, building rows and last-seen building records per player.
@export var queue_slots: int = 5
@export var build_reach_tiles: int = 4
@export var unit_cap: int = 75
@export var building_cap: int = 40
@export var ghost_cap: int = 40
