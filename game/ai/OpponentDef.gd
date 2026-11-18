class_name OpponentDef
extends AiDef
## The data of the opponent AI of one faction (ADR 0030 section 6, plan row P175):
## `data/ai/opponent_<faction>.tres`. It extends `AiDef` so the factory can tell it from the dummy's
## def. Used from the base: `id`, `hq_type`, `harvester_type`, `queue_target`, `place_stride_tiles`,
## `defend_radius_tiles`, `think_period` (5) and `think_tick` (6). Ignored by `OpponentAi` and held
## at their script defaults by a data test: `build_order`, `place_tries`, `harvesters_wanted`,
## `guard_offset_tiles` (replaced by `build_orders`, `place_tries_per_think`, the level's
## `harvesters_per_refinery` and the staging point). A def lists only its own faction's type ids.
## Script defaults equal the fossil file, but for `id` and `build_orders` (resources).

## The roles of the army's mix, in the order of `role_weights`.
enum Role { ANTI_INFANTRY, ANTI_VEHICLE, TANK, ARTILLERY }
const ROLES: int = 4
## The difficulty tiers (`AiDifficultyDef.build_order_tier`).
const TIERS: int = 3

## The role table (type ids). The scout is the one unit sent to look; `anti_vehicle_types` may hold
## several types.
@export var scout_type: StringName = &"light_tank"
@export var anti_infantry_type: StringName = &"rifle_squad"
@export var anti_vehicle_types: Array[StringName] = [&"rocket_squad"]
@export var tank_type: StringName = &"heavy_tank"
@export var artillery_type: StringName = &"artillery"
## The types Normal and Hard set to hold position when they join a wave (ADR 0037 section 15): the
## artillery, which has a minimum range and should not chase into it. A type id of this faction.
@export var hold_types: Array[StringName] = [&"artillery"]
@export var defence_type: StringName = &"defence_turret"
@export var strike_type: StringName = &"fossil_strike"
## The air and tech types (ADR 0036 section 14, plan row P250): the anti-air building the economy
## builds against seen aircraft, and the two aircraft the production draws from. An empty id or a
## type the roster lacks turns that part off.
@export var aa_type: StringName = &""
@export var fighter_type: StringName = &""
@export var bomber_type: StringName = &""
## The weights of the aircraft draw, flat `tier * 2 + (0 bomber, 1 fighter)`. `fighter_seen_weight`
## adds to the fighter's weight for each enemy aircraft the AI has seen at once (its most). These
## default to off (no type, weight 0) like the level's air fields, so a def that names none (the
## `perf_ai` frozen files) plays as before; the shipped files set them.
@export var air_weights: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
@export var fighter_seen_weight: int = 0
## The weights of the draw among the roles whose type can be queued, flat: `tier * ROLES + role`.
## Artillery needs the radar, which the weak tier never builds, so its weight there is 0.
@export var role_weights: PackedInt32Array = PackedInt32Array(
	[50, 40, 10, 0, 35, 30, 25, 10, 20, 25, 35, 20]
)
## The build orders, indexed by tier.
@export var build_orders: Array[AiBuildOrderDef] = []
## The power surplus kept before a consumer is queued.
@export var power_margin: int = 20
## The staging point's distance from the Headquarters toward the base estimate, and how far a unit
## hit by something unseen shifts its squad's goal toward it, in tiles.
@export var staging_offset_tiles: int = 6
@export var unseen_hit_shift_tiles: int = 4
## The sector map: tiles per sector side and the most sectors kept.
@export var sector_tiles: int = 8
@export var sectors_max: int = 64
## The most squads, `placement` calls per think (the spiral resumes where it stopped), candidate
## tests per slot, and live flow-cache keys of the AI (a key is a goal cell and a move class).
@export var squads_max: int = 4
@export var place_tries_per_think: int = 8
@export var target_tests_max: int = 512
@export var goal_keys_max: int = 4
## The building slots of `PlacementSpiral` round the Headquarters that the economy asks about
## (ring 1 first); the search wraps round them across thinks.
@export var spiral_slots: int = 64
## The mines (ADR 0037 section 8, plan row P295): the faction's minelayer type (an empty id
## turns `AiMines` off, so a def that names none, the frozen files, plays as before), the tiles
## between two mines on the route, how far from the route a known enemy mine is still swept, and
## the tiles between two waypoints of the scout layer.
@export var mine_layer_type: StringName = &""
@export var mine_spacing_tiles: int = 4
@export var mine_sweep_reach_tiles: int = 4
@export var mine_scout_leg_tiles: int = 8
## The least enemy value a superweapon shot must hit (credits).
@export var strike_min_value: int = 3000


func _init() -> void:
	think_period = 5
	think_tick = 6


## The weight of the aircraft draw at `tier`: `fighter` picks the fighter's, else the bomber's; 0
## outside the table.
func air_weight(tier: int, fighter: bool) -> int:
	var at: int = tier * 2 + (1 if fighter else 0)
	return air_weights[at] if tier >= 0 and tier < TIERS and at < air_weights.size() else 0


## The weight of `role` at `tier`; 0 outside the table.
func role_weight(tier: int, role: int) -> int:
	var at: int = tier * ROLES + role
	if tier < 0 or tier >= TIERS or role < 0 or role >= ROLES or at >= role_weights.size():
		return 0
	return role_weights[at]
