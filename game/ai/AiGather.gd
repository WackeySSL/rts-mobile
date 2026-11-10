class_name AiGather
extends RefCounted
## The assembly of a wave and the tally of the squads (plan row P197, ADR 0030 section 6, *Army*):
## static helpers of `AiArmy`. A wave first walks to a point `gather_tiles` before its target, out
## of the reach of the base's guns, and goes on together when `gather_percent` of its units stand
## there (or `gather_ticks` after the launch), so the fast units do not arrive alone. The state is
## the wave's goal cell: the assembly point while it gathers, the target once it goes on. From the
## all-in the home squad joins a wave that is on its way in batches (`reinforce`), not one by one.


## The assembly point in tiles: on the line from the target to the staging point, `gather_tiles`
## from the target; (NONE, NONE) when the level has none, the target or staging point is unknown or
## the staging point is no farther than that.
static func point(army: AiArmy, memory: AiMemory) -> Vector2i:
	var none: Vector2i = Vector2i(AiMemory.NONE, AiMemory.NONE)
	if army.gather_tiles <= 0 or not memory.has_base_estimate() or not memory.has_staging():
		return none
	var target: Vector2i = Vector2i(memory.base_x, memory.base_y)
	var along: Vector2i = Vector2i(memory.staging_x, memory.staging_y) - target
	var length: int = FixedMath.isqrt(along.x * along.x + along.y * along.y)
	if length <= army.gather_tiles:
		return none
	return target + along * army.gather_tiles / length


## Where a launched wave goes first: the assembly point, else the target (tiles).
static func goal(army: AiArmy, memory: AiMemory) -> Vector2i:
	var at: Vector2i = point(army, memory)
	if at.x < 0:
		return Vector2i(memory.base_x, memory.base_y)
	return at


## Whether the wave still gathers: its goal is the assembly point, fewer than `gather_percent` of
## its units stand within half the defence radius of it and `gather_ticks` have not passed.
static func holding(army: AiArmy, view: PlayerView, wave_goal: Vector2i) -> bool:
	if army._gather_at.x < 0 or wave_goal != army._gather_at:
		return false
	if view.tick - army._launched_at >= army.gather_ticks:
		return false
	return army._gather_in * 100 < army._wave_units * army.gather_percent


## Whether the home squad waits for a batch: the all-in sends it to a wave that is past its assembly
## (a wave that gathers takes every unit at once) only when it is worth `reinforce` percent of the
## first wave's strength.
static func batching(army: AiArmy, wave_goal: Vector2i) -> bool:
	if army.reinforce <= 0 or wave_goal == army._gather_at:
		return false
	return army._home_value * 100 < army.wave_first_strength * army.reinforce


## Sums the home squad's value (`_home_value`, and `_ready_value` without the withdrawn units) and
## the wave's value, centre, units and idle units, the wave unit nearest the target and the wave
## units at the assembly point, over the members (a loop over the memory's list, not the view's
## rows).
static func tally(army: AiArmy, view: PlayerView, memory: AiMemory) -> void:
	army._home_value = 0
	army._ready_value = 0
	army._wave_value = 0
	army._wave_units = 0
	army._wave_idle = 0
	army._gather_in = 0
	army._gather_at = point(army, memory)
	var sum: Vector2i = Vector2i.ZERO
	var target: Vector2i = Vector2i.ZERO
	if memory.has_base_estimate():
		target = AiArmy._at(Vector2i(memory.base_x, memory.base_y))
	var gather: Vector2i = AiArmy._at(army._gather_at)
	var reach: int = army.defend_radius / 2
	var least: int = -1
	for at: int in memory.member_id.size():
		var row: int = view.row_of(memory.member_id[at])
		if row < 0:
			continue
		if memory.member_squad[at] == AiArmy.HOME:
			var value: int = AiIntel.value_of(view, row)
			army._home_value += value
			if not army._withdrawn(memory, memory.member_id[at]):
				army._ready_value += value
		elif memory.member_squad[at] == AiArmy.WAVE:
			var here: Vector2i = view.row_pos(row)
			army._wave_value += AiIntel.value_of(view, row)
			army._wave_units += 1
			sum += here
			if view.row_order(row) == PlayerView.Order.IDLE:
				army._wave_idle += 1
			var gap: Vector2i = here - target
			if least < 0 or gap.x * gap.x + gap.y * gap.y < least:
				least = gap.x * gap.x + gap.y * gap.y
				army._wave_front = here
			gap = here - gather
			if army._gather_at.x >= 0 and gap.x * gap.x + gap.y * gap.y <= reach * reach:
				army._gather_in += 1
	if army._wave_units > 0:
		@warning_ignore("integer_division")
		army._wave_at = sum / army._wave_units
