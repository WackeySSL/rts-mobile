class_name AiSiege
extends RefCounted
## The siege and the press of a wave (plan row P197, ADR 0030 section 6, *Army*): static helpers of
## `AiArmy` that read its wave tally (`_wave_at`, `_wave_value`, `_wave_units`) and share its test
## cap (`tests`, `tests_max`). They add no state of their own: the focus target is the wave's
## `squad_focus` cell, and the early all-in is `AiArmy._pressed`.


## The seen enemy value near the wave's centre (`AiArmy._near`), read once a think.
static func foes(army: AiArmy, view: PlayerView, memory: AiMemory) -> int:
	if army._foes_tick != view.tick:
		army._foes_value = army._near(view, memory, army._wave_at)
		army._foes_tick = view.tick
	return army._foes_value


## The press: a wave at an enemy producer (within the defence radius of its centre) that is worth
## `press` percent of the seen enemy value near it launches the all-in now, for good. False when
## the read ran into the test cap (blind) or nothing qualifies. True from then on.
static func press(army: AiArmy, view: PlayerView, memory: AiMemory) -> bool:
	if army._wave_units == 0 or producer_near(army, view, memory) < 0:
		return false
	var near: int = foes(army, view, memory)
	if army.tests >= army.tests_max or army._wave_value * 100 < near * army.press:
		return false
	army._pressed = true
	return true


## The siege: a wave whose centre stands within the defence radius of a seen, finished enemy
## producer, with nothing armed near it, takes one `ATTACK` on the nearest of them (the buildings
## that decide the match, ahead of walls, power and units that are not shooting). Armed foes come
## first: the focus is dropped when one shows up, so the attack-move fights it. True while the
## target is held (sent, kept or refused), false when none is, which forgets an old one.
static func siege(army: AiArmy, view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	var best: int = producer_near(army, view, memory) if army.siege else -1
	if best >= 0 and (foes(army, view, memory) > 0 or army.tests >= army.tests_max):
		best = -1
	var kept: int = memory.squad_focus[AiArmy.WAVE]
	if best < 0:
		if army.siege and kept != AiMemory.NONE and _is_siege_target(view, kept):
			memory.squad_focus[AiArmy.WAVE] = AiMemory.NONE
			# The goal must differ from the target, or nothing re-sends the attack-move.
			memory.squad_goal_x[AiArmy.WAVE] = AiMemory.NONE
			memory.squad_goal_y[AiArmy.WAVE] = AiMemory.NONE
		return false
	var target: int = view.row_id(best)
	if target == kept:
		return true
	var tile: Vector2i = view.row_pos(best) / PlayerView.MILLI_PER_TILE
	var ids: PackedInt32Array = army._members(memory, true, AiArmy.WAVE)
	if not army._order(view, memory, out, ids, tile, AiMemory.Owner.ARMY, AiArmy._at(tile), target):
		return true
	memory.squad_focus[AiArmy.WAVE] = target
	memory.squad_goal_x[AiArmy.WAVE] = tile.x
	memory.squad_goal_y[AiArmy.WAVE] = tile.y
	army.focuses += 1
	return true


## The row of the nearest seen, finished enemy producer within the defence radius of the wave's
## centre (the lowest id on a tie), -1 for none; one test a producer, until the cap.
static func producer_near(army: AiArmy, view: PlayerView, memory: AiMemory) -> int:
	var found: int = -1
	var least: int = army.defend_radius * army.defend_radius + 1
	for id: int in memory.seen_site_id:
		if army.tests >= army.tests_max:
			break
		var row: int = view.row_of(id)
		if row < 0 or view.row_build_left(row) > 0:
			continue
		if not AiIntel.is_producer(view, view.row_type(row)):
			continue
		army.tests += 1
		var gap: Vector2i = view.row_pos(row) - army._wave_at
		if gap.x * gap.x + gap.y * gap.y < least:
			least = gap.x * gap.x + gap.y * gap.y
			found = row
	return found


## Whether the focus `id` is a siege target: gone, or a producer (a Hard unit focus is neither).
static func _is_siege_target(view: PlayerView, id: int) -> bool:
	var row: int = view.row_of(id)
	return row < 0 or AiIntel.is_producer(view, view.row_type(row))
