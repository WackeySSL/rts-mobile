class_name Combat
extends RefCounted
## The FIRE phase (ADR 0007 section 4 step 10, ADR 0009 section 4): cooldowns count down, and a
## unit with a target in reach and a ready weapon fires. Phase 2 part 1 (P42a) has hitscan only:
## the damage is applied at once and a `SHOT` event is written. Part 2 (P42b) adds the projectile
## slots and the `PROJECTILES` phase before this one; until then a weapon with a projectile speed
## also applies its damage on the tick it fires (its flight time is not read).
##
## `fire` walks the rows in ascending id order, from the positions as `Movement.integrate` left
## them. For each row:
## - `cooldown` drops by 1 when it is above 0, whether or not the unit has a target;
## - the unit fires when its cooldown is 0 after that, its type names a weapon (an index of 0 or
##   more inside the weapon tables, the "armed" of `Targeting`: a hand-built World may name a weapon
##   it has no table for, which is unarmed), and its `target` is a unit that still has a row, is an
##   enemy (an owner that is neither its own nor 0) and stands at `min_range^2 <= d2 <= range^2`.
##   The unit does not have to be in `HOLD`: a chasing unit fires on the first tick it is in range.
##   It fires on that first tick, and then every `cooldown_ticks`, because the cooldown is set to
##   `cooldown_ticks` by a shot and counts down on each of the following ticks;
## - a shot lowers the target's `hp` by `max(1, damage * percent / 100)`, `percent` being the
##   weapon's share against the target's armour class (0 when the percent is 0), writes
##   `[SHOT, shooter id, shooter x, shooter y, target id, weapon, target x, target y]` (ADR 0007
##   section 10, both positions read now, so a tracer can still be drawn after either unit is
##   removed) and sets the cooldown.
##
## Damage only lowers `hp` here and in the projectile phase; rows die in `World.remove_dead`, the
## next phase. A unit therefore fires in the tick it dies, whatever its id, and a target another
## shooter has already brought to 0 or less is still a target: its `hp` takes every hit of the tick,
## so the result does not depend on the order of the shooters. The target of a unit that fired at a
## row that was then removed is not rewritten (ADR 0007 section 3): the row looks it up again the
## next tick and finds nothing.
##
## Keep it portable (the C++ twin P42n is conditional on this phase's `PERF` line, ADR 0013 section
## 1): integers only, the World's arrays aliased into typed locals before the loop, no allocation
## apart from the event append, rows in ascending order. Every number comes from the World's weapon
## tables (data/). Range: positions are below 2^16, so a squared distance stays below 2^33 and the
## damage `damage * percent` (a percent is at most 200) stays far below 2^62 in an int64.

## The event kind this phase writes, as the World's int.
const SHOT: int = World.Event.SHOT
## A percent divides by this: structure, not balance.
const PERCENT: int = 100

## One FIRE phase over the World, as described above.
@warning_ignore("integer_division")
static func fire(world: World) -> void:
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var targets: PackedInt32Array = world.target
	var cooldowns: PackedInt32Array = world.cooldown
	var hit_points: PackedInt32Array = world.hp
	var type_armour: PackedInt32Array = world.type_armour
	var type_weapon: PackedInt32Array = world.type_weapon
	var weapon_range: PackedInt32Array = world.weapon_range
	var weapon_min_range: PackedInt32Array = world.weapon_min_range
	var weapon_damage: PackedInt32Array = world.weapon_damage
	var weapon_cooldown: PackedInt32Array = world.weapon_cooldown
	var weapon_vs: PackedInt32Array = world.weapon_vs_armour
	var events: PackedInt32Array = world.events
	var weapons: int = weapon_range.size()
	var armour_classes: int = World.Armour.size()
	var count: int = ids.size()
	for row: int in count:
		var wait: int = cooldowns[row]
		if wait > 0:
			wait -= 1
			cooldowns[row] = wait
		var held: int = targets[row]
		if wait > 0 or held == 0:
			continue
		var type: int = types[row]
		var weapon: int = type_weapon[type]
		if weapon < 0 or weapon >= weapons:
			continue
		var at: int = ids.bsearch(held)
		if at >= count or ids[at] != held or owners[at] == owners[row] or owners[at] == 0:
			continue
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		var dx: int = pos_x[at] - x
		var dy: int = pos_y[at] - y
		var d2: int = dx * dx + dy * dy
		var reach: int = weapon_range[weapon]
		var min_range: int = weapon_min_range[weapon]
		if d2 > reach * reach or d2 < min_range * min_range:
			continue
		var percent: int = weapon_vs[weapon * armour_classes + type_armour[types[at]]]
		if percent > 0:
			hit_points[at] -= maxi(1, weapon_damage[weapon] * percent / PERCENT)
		cooldowns[row] = weapon_cooldown[weapon]
		# The shot's record: the only array this phase grows (one event append per shot).
		var end: int = events.size()
		events.resize(end + World.EVENT_STRIDE)
		events[end] = SHOT
		events[end + 1] = ids[row]
		events[end + 2] = x
		events[end + 3] = y
		events[end + 4] = held
		events[end + 5] = weapon
		events[end + 6] = pos_x[at]
		events[end + 7] = pos_y[at]
