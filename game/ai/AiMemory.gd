class_name AiMemory
extends RefCounted
## Everything an `OpponentAi` keeps between thinks (ADR 0030 section 3, plan row P175): ints and
## packed int arrays only, so a later `to_ints` / `from_ints` is a small row. Ids, never rows (a row
## index is good for one tick), and never a copy of the enemy's buildings (the view's ghosts are the
## sim's). Not in the World and not hashed. Each manager writes its own part; every field another
## manager reads is declared here with a "none" value, so a manager can be built and tested before
## the one that fills the field. Bounded by the caps of `OpponentDef` and the rules' `unit_cap`.

## Squad states.
enum SquadState { HOME, WAVE, RETREAT }
## The value of a point, an id or a tick that is not set.
const NONE: int = -1

## The caps, from the def and the first view (`unit_cap` is 0 until a think has set it).
var squads_max: int = 0
var sectors_max: int = 0
var goal_keys_max: int = 0
var unit_cap: int = 0

## Army: the staging point and the enemy base estimate, in tiles, (NONE, NONE) when not set.
var staging_x: int = NONE
var staging_y: int = NONE
var base_x: int = NONE
var base_y: int = NONE
## Squads, `squads_max` of each (a squad is used while its `squad_role` is not NONE): role, state,
## goal point in tiles, and the army value at launch. Their members are the pairs of `member_id`
## (ascending, at most `unit_cap`) and `member_squad`.
var squad_role: PackedInt32Array = PackedInt32Array()
var squad_state: PackedInt32Array = PackedInt32Array()
var squad_goal_x: PackedInt32Array = PackedInt32Array()
var squad_goal_y: PackedInt32Array = PackedInt32Array()
var squad_launch_value: PackedInt32Array = PackedInt32Array()
var member_id: PackedInt32Array = PackedInt32Array()
var member_squad: PackedInt32Array = PackedInt32Array()
## The waves launched, the tick the next may start (NONE: not drawn yet) and the first tick of the
## threat now at the base (NONE: no threat).
var wave_count: int = 0
var wave_start_tick: int = NONE
var threat_first_tick: int = NONE
## Intel: the scout's unit id (NONE: none) and its waypoint index, the sector map's own and enemy
## value (`sectors_max` each) and, per type index of the view's roster, the count last seen and the
## first and last tick it was seen (NONE: never).
var scout_id: int = NONE
var scout_waypoint: int = 0
var sector_own: PackedInt32Array = PackedInt32Array()
var sector_enemy: PackedInt32Array = PackedInt32Array()
var seen_count: PackedInt32Array = PackedInt32Array()
var seen_first_tick: PackedInt32Array = PackedInt32Array()
var seen_last_tick: PackedInt32Array = PackedInt32Array()
## The hp each own unit had at the last ARMY slot ("hit by something unseen"), ids ascending.
var hp_id: PackedInt32Array = PackedInt32Array()
var hp_value: PackedInt32Array = PackedInt32Array()
## The live flow-cache keys of the AI's orders (ADR 0030 section 4): goal cell in tiles and move
## class, at most `goal_keys_max`.
var goal_x: PackedInt32Array = PackedInt32Array()
var goal_y: PackedInt32Array = PackedInt32Array()
var goal_class: PackedInt32Array = PackedInt32Array()
## Economy: where the placement spiral resumes (a slot index).
var spiral_resume: int = 0


## A memory with the caps of `def`, every field at its "none" value.
static func create(def: OpponentDef) -> AiMemory:
	var memory: AiMemory = AiMemory.new()
	memory.squads_max = def.squads_max
	memory.sectors_max = def.sectors_max
	memory.goal_keys_max = def.goal_keys_max
	memory.squad_role.resize(memory.squads_max)
	memory.squad_state.resize(memory.squads_max)
	memory.squad_goal_x.resize(memory.squads_max)
	memory.squad_goal_y.resize(memory.squads_max)
	memory.squad_launch_value.resize(memory.squads_max)
	memory.squad_role.fill(NONE)
	memory.squad_goal_x.fill(NONE)
	memory.squad_goal_y.fill(NONE)
	memory.sector_own.resize(memory.sectors_max)
	memory.sector_enemy.resize(memory.sectors_max)
	return memory


func has_staging() -> bool:
	return staging_x != NONE and staging_y != NONE


func has_base_estimate() -> bool:
	return base_x != NONE and base_y != NONE


## The number of live goal keys.
func goal_keys() -> int:
	return goal_x.size()


## Adds the key (tile, move class) unless it is live already; false when the cap is reached.
func add_goal_key(x: int, y: int, move_class: int) -> bool:
	for at: int in goal_x.size():
		if goal_x[at] == x and goal_y[at] == y and goal_class[at] == move_class:
			return true
	if goal_x.size() >= goal_keys_max:
		return false
	goal_x.append(x)
	goal_y.append(y)
	goal_class.append(move_class)
	return true


func clear_goal_keys() -> void:
	goal_x.clear()
	goal_y.clear()
	goal_class.clear()
