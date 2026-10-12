class_name RulesDef
extends Resource
## Every tuning int of the Phase 2 sim (ADRs 0007-0010). The instance is res://data/rules.tres,
## where all tuning happens; these defaults equal that file (a test pins both). World copies the
## ints under these names at match start. Times are ticks and distances are milli-tiles.

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
