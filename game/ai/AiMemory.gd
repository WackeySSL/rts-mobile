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
## The owners of a goal key: the staging point (rally, retreat), the army goal and the scout's way.
enum Owner { STAGING, ARMY, SCOUT }
## The value of a point, an id or a tick that is not set.
const NONE: int = -1

## The caps, from the def and the first view (`unit_cap` is 0 until a think has set it).
var squads_max: int = 0
var sectors_max: int = 0
var goal_keys_max: int = 0
var unit_cap: int = 0

## The Commands this think may still send. `OpponentAi.think` sets it to the level's
## `commands_per_think_max` before the managers run. Every manager checks `can_send` BEFORE it
## appends a Command and before it records "sent" in this memory or in a counter, then calls
## `spent`; so the cut after the think (`commands_cut`) stays 0.
var commands_left: int = 0
## The credits production must leave this think (writer: AiEconomy, P176; reader: AiProduction,
## P178, which spends `maxi(view.credits - reserve_credits, 0)`): what the economy queued in it plus
## the price of the structure or tanker it keeps credits for. 0 = none.
var reserve_credits: int = 0

## Army: the staging point and the enemy base estimate, in tiles, (NONE, NONE) when not set.
var staging_x: int = NONE
var staging_y: int = NONE
var base_x: int = NONE
var base_y: int = NONE
## Squads, `squads_max` of each (a squad is used while its `squad_role` is not NONE): role, state,
## goal point in tiles, and the army value at launch. `squad_role` is AiArmy's role code (P179) and
## `squad_state` a `SquadState`. Their members are the pairs of `member_id`
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
## first and last tick it was seen (NONE: never). Empty until AiIntel (P177) sizes them to the
## view's type count and fills the ticks with NONE.
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
## class, at most `goal_keys_max`, and who uses each: a mask of `1 << Owner` bits (AiArmy writes
## STAGING and ARMY, AiIntel SCOUT). The army goal is one cell at a time: AiArmy releases its key
## before it adds the next. The scout's key is added only while the army goal is free or
## single-class.
var goal_x: PackedInt32Array = PackedInt32Array()
var goal_y: PackedInt32Array = PackedInt32Array()
var goal_class: PackedInt32Array = PackedInt32Array()
var goal_owner: PackedInt32Array = PackedInt32Array()
## Economy: where the placement spiral resumes (a slot index) and the staging point of the order it
## belongs to ((NONE, NONE): the plain spiral).
var spiral_resume: int = 0
var spiral_for_x: int = NONE
var spiral_for_y: int = NONE


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


## Adds `owner`'s bit to the key (tile, move class), making the key when it is not live; a key two
## owners use keeps both bits. False when the key is new and the cap is reached.
func add_goal_key(x: int, y: int, move_class: int, owner: int) -> bool:
	for at: int in goal_x.size():
		if goal_x[at] == x and goal_y[at] == y and goal_class[at] == move_class:
			goal_owner[at] |= 1 << owner
			return true
	if goal_x.size() >= goal_keys_max:
		return false
	goal_x.append(x)
	goal_y.append(y)
	goal_class.append(move_class)
	goal_owner.append(1 << owner)
	return true


## Clears `owner`'s bit of the key at index `key` (0 to `goal_keys() - 1`) and removes the key,
## in every parallel array and keeping the later keys' order, only when no owner is left.
func release_goal_key(key: int, owner: int) -> void:
	if key < 0 or key >= goal_x.size():
		return
	goal_owner[key] &= ~(1 << owner)
	if goal_owner[key] != 0:
		return
	goal_x.remove_at(key)
	goal_y.remove_at(key)
	goal_class.remove_at(key)
	goal_owner.remove_at(key)


## How many live keys `owner` uses.
func goal_keys_of(owner: int) -> int:
	var found: int = 0
	for mask: int in goal_owner:
		if mask & (1 << owner) != 0:
			found += 1
	return found


func clear_goal_keys() -> void:
	goal_x.clear()
	goal_y.clear()
	goal_class.clear()
	goal_owner.clear()


## Whether `count` more Commands fit in this think's budget.
func can_send(count: int = 1) -> bool:
	return commands_left >= count


## Takes `count` (not negative) Commands off the budget; an overspend leaves 0, never less.
func spent(count: int = 1) -> void:
	assert(count >= 0)
	commands_left = maxi(commands_left - count, 0)
