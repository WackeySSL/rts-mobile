class_name Combat
extends RefCounted
## The two weapon phases (ADR 0007 section 4 steps 9 and 10, ADR 0009 section 4).
## `advance_projectiles` (PROJECTILES) moves the shells in flight and lets those that arrive hit,
## then `fire` (FIRE) counts the cooldowns down and lets every unit with a target in reach and a
## ready weapon shoot. A weapon whose projectile speed is 0 is hitscan: its damage lands in the tick
## it fires (P42a). A weapon with a speed takes a slot of the World's projectile pool at the
## shooter's position (P42b), and its damage lands when the shell arrives, a flight time later.
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
## - an offline defence does not shoot (ADR 0018 section 4): a building row (`type_foot_w` above 0)
##   of a player whose `power_used` is above its `power_made` (`Power.is_low`'s rule, inlined over
##   the aliased totals) keeps its `target` and its cooldown counts down, but it skips the shot, so
##   it fires on the first FIRE after the totals stop being low, with no wind-up. TARGETING and its
##   kernel are unchanged, and a mobile row never goes offline;
## - a shot writes `[SHOT, shooter id, shooter x, shooter y, target id, weapon, target x, target y]`
##   (ADR 0007 section 10, both positions read now, so a tracer can still be drawn after either unit
##   is removed) and sets the cooldown, and then either
##   - hits at once (hitscan, speed 0): the target's `hp` drops by `max(1, damage * percent / 100)`,
##     `percent` being the weapon's share against the target's armour class (0 when it is 0);
##   - launches a shell (speed above 0, a slot free): the slot at `proj_free[proj_free_top - 1]`
##     (the top of the stack, which `prepare()` fills so that slot 0 comes first) takes the next
##     projectile id, the shooter's owner and weapon, the target's id, the shooter's position as its
##     position, the target's position as its aim and a flight time of `proj_ticks`, and the stack
##     shrinks by one. The flight time is the smallest number of ticks in which a shell of that
##     speed covers the distance, at least 1: `max(1, ceil(dist / speed))` with `dist` the real
##     distance. The distance is one `FixedMath.isqrt` per launch (a helper call at event cadence,
##     ADR 0007 section 1), raised by one when its square is below `d2`; ceil(ceil(dist) / speed)
##     is ceil(dist / speed) for a whole speed, so no float and no rounding error enter;
##   - with no slot free (the pool is full) applies the damage as hitscan and adds 1 to
##     `projectile_overflow`. The performance test requires that count to stay 0 (ADR 0007 section
##     3). The shot still writes its SHOT record and no IMPACT follows it: the damage landed in the
##     shot's tick, so a view that draws a hit from an IMPACT shows none for that shot.
##
## `advance_projectiles` walks the slots in ascending slot order (a slot's number says nothing
## about its age once slots are reused). For each live slot (`proj_id` not 0):
## - while the target still has a row, the aim follows its position as it stands now, after
##   `Movement.integrate` (a homing shell: there is no miss); a target that is gone leaves the aim
##   where it last was;
## - the shell moves `(aim - pos) / proj_ticks` on each axis (integer division truncating toward
##   zero) and `proj_ticks` drops by 1. The step with 1 left is the whole rest, so the shell is on
##   the aim point exactly when it arrives;
## - at 0 it arrives: a target that still has a row takes the damage of the shell's weapon (the same
##   percent rule as a hitscan shot; a row another shell has already brought to 0 or less in this
##   tick is still hit), `[IMPACT, projectile id, x, y, target id, weapon, 0, 0]` is written (the
##   target id is 0 when the target was gone: the shell hits nothing and the record shows where it
##   came down, ADR 0007 section 10), the slot's columns are zeroed and the slot goes back on top of
##   the free stack. The shell does not look at its shooter: it flies on when the shooter has died.
## - `stats[PROJ_STEPS]` gets the number of live slots stepped.
##
## Damage only lowers `hp` here and in `fire`; rows die in `World.remove_dead`, the next phase. A
## unit therefore fires in the tick it dies, whatever its id, and a target another shooter or shell
## has already brought to 0 or less is still a target: its `hp` takes every hit of the tick, so the
## result does not depend on the order of the shooters. The target of a unit that fired at a row
## that was then removed is not rewritten (ADR 0007 section 3): the row looks it up again the next
## tick and finds nothing. Neither is a shell's `proj_target`: it looks the id up each tick.
##
## Keep both portable (the C++ twins P42n are conditional on this phase's `PERF` line, ADR 0013
## section 1): integers only, the World's arrays aliased into typed locals before the loop and the
## scalars read once before it and written once after it, no allocation apart from the event
## appends, rows and slots in ascending order. Every number comes from the World's weapon tables
## (data/). Range: positions are below 2^16, so a squared distance stays below 2^33, a step
## `aim - pos` is below 2^16 and the damage `damage * percent` (a percent is at most 200) stays far
## below 2^62 in an int64; `proj_ticks` is at most `max(1, ceil(longest range / slowest speed))`
## (17 with the shipped data), and a projectile id is below 2^31 for any match.
## The twins grow `events` once per shot and once per impact, inside their loops. A port may not
## (ADR 0013 section 2: one resize per appending kernel, after its loop): it records the events
## first and resizes once. No decision here reads `events`, and none depends on an earlier shot or
## impact except through the arrays and scalars a kernel holds the same way: the free stack and its
## top, the next projectile id and `hp`. So only the order of the records and the ints written have
## to match. The first `events` writer of a tick is `advance_projectiles` (its IMPACTs), the second
## `fire` (its SHOTs).

## The event kinds the phases write, as the World's ints.
const SHOT: int = World.Event.SHOT
const IMPACT: int = World.Event.IMPACT
## A percent divides by this: structure, not balance.
const PERCENT: int = 100

## One PROJECTILES phase over the World, as described above.
@warning_ignore("integer_division")
static func advance_projectiles(world: World) -> void:
	var ids: PackedInt32Array = world.unit_id
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var hit_points: PackedInt32Array = world.hp
	var type_armour: PackedInt32Array = world.type_armour
	var weapon_damage: PackedInt32Array = world.weapon_damage
	var weapon_vs: PackedInt32Array = world.weapon_vs_armour
	var slot_ids: PackedInt32Array = world.proj_id
	var slot_owner: PackedInt32Array = world.proj_owner
	var slot_weapon: PackedInt32Array = world.proj_weapon
	var slot_target: PackedInt32Array = world.proj_target
	var slot_x: PackedInt32Array = world.proj_x
	var slot_y: PackedInt32Array = world.proj_y
	var slot_aim_x: PackedInt32Array = world.proj_aim_x
	var slot_aim_y: PackedInt32Array = world.proj_aim_y
	var slot_ticks: PackedInt32Array = world.proj_ticks
	var free_slots: PackedInt32Array = world.proj_free
	var events: PackedInt32Array = world.events
	var free_top: int = world.proj_free_top
	var armour_classes: int = World.Armour.size()
	var count: int = ids.size()
	var slots: int = slot_ids.size()
	var stepped: int = 0
	for slot: int in slots:
		var shell: int = slot_ids[slot]
		if shell == 0:
			continue
		stepped += 1
		var held: int = slot_target[slot]
		var at: int = -1
		if held != 0:
			at = ids.bsearch(held)
			if at >= count or ids[at] != held:
				at = -1
		if at >= 0:
			slot_aim_x[slot] = pos_x[at]
			slot_aim_y[slot] = pos_y[at]
		var aim_x: int = slot_aim_x[slot]
		var aim_y: int = slot_aim_y[slot]
		# The step truncates toward zero, as every division of a signed value in the sim.
		var left: int = maxi(slot_ticks[slot], 1)
		var x: int = slot_x[slot]
		var y: int = slot_y[slot]
		x += (aim_x - x) / left
		y += (aim_y - y) / left
		left -= 1
		if left > 0:
			slot_x[slot] = x
			slot_y[slot] = y
			slot_ticks[slot] = left
			continue
		var weapon: int = slot_weapon[slot]
		if at >= 0:
			var percent: int = weapon_vs[weapon * armour_classes + type_armour[types[at]]]
			if percent > 0:
				hit_points[at] -= maxi(1, weapon_damage[weapon] * percent / PERCENT)
		# The impact's record: with the shot's append, the only array growth of the phase.
		var end: int = events.size()
		events.resize(end + World.EVENT_STRIDE)
		events[end] = IMPACT
		events[end + 1] = shell
		events[end + 2] = x
		events[end + 3] = y
		events[end + 4] = held if at >= 0 else 0
		events[end + 5] = weapon
		events[end + 6] = 0
		events[end + 7] = 0
		slot_ids[slot] = 0
		slot_owner[slot] = 0
		slot_weapon[slot] = 0
		slot_target[slot] = 0
		slot_x[slot] = 0
		slot_y[slot] = 0
		slot_aim_x[slot] = 0
		slot_aim_y[slot] = 0
		slot_ticks[slot] = 0
		free_slots[free_top] = slot
		free_top += 1
	world.proj_free_top = free_top
	world.stats[World.Stat.PROJ_STEPS] += stepped


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
	var type_foot: PackedInt32Array = world.type_foot_w
	var power_made: PackedInt32Array = world.power_made
	var power_used: PackedInt32Array = world.power_used
	var weapon_range: PackedInt32Array = world.weapon_range
	var weapon_min_range: PackedInt32Array = world.weapon_min_range
	var weapon_damage: PackedInt32Array = world.weapon_damage
	var weapon_cooldown: PackedInt32Array = world.weapon_cooldown
	var weapon_speed: PackedInt32Array = world.weapon_projectile_speed
	var weapon_vs: PackedInt32Array = world.weapon_vs_armour
	var slot_ids: PackedInt32Array = world.proj_id
	var slot_owner: PackedInt32Array = world.proj_owner
	var slot_weapon: PackedInt32Array = world.proj_weapon
	var slot_target: PackedInt32Array = world.proj_target
	var slot_x: PackedInt32Array = world.proj_x
	var slot_y: PackedInt32Array = world.proj_y
	var slot_aim_x: PackedInt32Array = world.proj_aim_x
	var slot_aim_y: PackedInt32Array = world.proj_aim_y
	var slot_ticks: PackedInt32Array = world.proj_ticks
	var free_slots: PackedInt32Array = world.proj_free
	var events: PackedInt32Array = world.events
	var free_top: int = world.proj_free_top
	var next_shell: int = world.next_projectile_id
	var overflow: int = 0
	var weapons: int = weapon_range.size()
	var footprints: int = type_foot.size()
	var players: int = mini(power_made.size(), power_used.size())
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
		var side: int = owners[row]
		if type < footprints and type_foot[type] > 0 and side < players:
			if power_used[side] > power_made[side]:
				continue  # Offline: the target stays, the shot waits for power.
		var at: int = ids.bsearch(held)
		if at >= count or ids[at] != held or owners[at] == side or owners[at] == 0:
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
		var speed: int = weapon_speed[weapon]
		if speed > 0 and free_top > 0:
			# A shell: the top of the free stack, aimed at the target's position now.
			free_top -= 1
			var slot: int = free_slots[free_top]
			var dist: int = FixedMath.isqrt(d2)
			if dist * dist < d2:
				dist += 1
			slot_ids[slot] = next_shell
			next_shell += 1
			slot_owner[slot] = owners[row]
			slot_weapon[slot] = weapon
			slot_target[slot] = held
			slot_x[slot] = x
			slot_y[slot] = y
			slot_aim_x[slot] = pos_x[at]
			slot_aim_y[slot] = pos_y[at]
			slot_ticks[slot] = maxi(1, (dist + speed - 1) / speed)
		else:
			if speed > 0:
				overflow += 1
			var percent: int = weapon_vs[weapon * armour_classes + type_armour[types[at]]]
			if percent > 0:
				hit_points[at] -= maxi(1, weapon_damage[weapon] * percent / PERCENT)
		cooldowns[row] = weapon_cooldown[weapon]
		# The shot's record: the other array this phase grows (one event append per shot).
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
	world.proj_free_top = free_top
	world.next_projectile_id = next_shell
	world.projectile_overflow += overflow
