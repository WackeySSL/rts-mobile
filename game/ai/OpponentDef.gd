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
@export var defence_type: StringName = &"defence_turret"
@export var strike_type: StringName = &"fossil_strike"
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
## The building slots of `PlacementSpiral` round the Headquarters that the economy asks about
## (ring 1 first); the search wraps round them across thinks.
@export var spiral_slots: int = 64
@export var target_tests_max: int = 512
@export var goal_keys_max: int = 4
## The least enemy value a superweapon shot must hit (credits).
@export var strike_min_value: int = 3000


func _init() -> void:
	think_period = 5
	think_tick = 6


## The weight of `role` at `tier`; 0 outside the table.
func role_weight(tier: int, role: int) -> int:
	var at: int = tier * ROLES + role
	if tier < 0 or tier >= TIERS or role < 0 or role >= ROLES or at >= role_weights.size():
		return 0
	return role_weights[at]
