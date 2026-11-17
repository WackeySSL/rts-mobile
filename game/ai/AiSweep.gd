class_name AiSweep
extends RefCounted
## The close-out search (plan row P250c): once no enemy producer is seen or remembered and the
## mirror estimate of the enemy Headquarters has been explored, the base estimate moves on to the
## sector of the enemy half, nearest to that point, whose centre the player has not explored, so the
## wave walks on and looks (the view's ghosts forget a building seen gone, so nothing stale is
## visited). Reads only `PlayerView.is_explored` and the sector grid of `AiIntel`; no Command and no
## draw (ties go to the lower sector). A sector the wave has not explored within `hold_ticks` of
## the pick (unreachable, or the wave went elsewhere) is skipped for good. 0 = off.

## Copied from the level when the manager is made.
var hold_ticks: int = 0
## Sweep goals picked over the match, for the suites.
var picks: int = 0


static func create(level: AiDifficultyDef) -> AiSweep:
	var sweep: AiSweep = AiSweep.new()
	sweep.hold_ticks = maxi(level.sweep_hold_ticks, 0)
	return sweep


## The tile the base estimate takes in place of the mirror estimate, (-1, -1) for "keep the mirror".
func target(view: PlayerView, memory: AiMemory, home: Vector2i, side: int, across: int) -> Vector2i:
	if hold_ticks <= 0 or home.x < 0 or side < 1 or across < 1:
		return Vector2i(-1, -1)
	var mirror: Vector2i = AiMemory.mirror(home, view.map_cols, view.map_rows)
	if not view.is_explored(mirror.y * view.map_cols + mirror.x):
		return Vector2i(-1, -1)
	var current: int = memory.sweep_sector
	if current >= 0:
		var at: Vector2i = _centre(view, current, side, across)
		if not view.is_explored(at.y * view.map_cols + at.x):
			if view.tick - memory.sweep_tick < hold_ticks:
				return at
			memory.sweep_skipped[current] = 1
		memory.sweep_sector = AiMemory.NONE
	var best: int = -1
	var best_distance: int = 0
	for sector: int in mini(memory.sweep_skipped.size(), across * _span(view.map_rows, side)):
		if memory.sweep_skipped[sector] != 0:
			continue
		var centre: Vector2i = _centre(view, sector, side, across)
		if view.is_explored(centre.y * view.map_cols + centre.x):
			continue
		var distance: int = AiIntel._distance(centre, mirror)
		if distance >= AiIntel._distance(centre, home):
			continue
		if best < 0 or distance < best_distance:
			best = sector
			best_distance = distance
	if best < 0:
		return Vector2i(-1, -1)
	memory.sweep_sector = best
	memory.sweep_tick = view.tick
	picks += 1
	return _centre(view, best, side, across)


@warning_ignore("integer_division")
static func _centre(view: PlayerView, sector: int, side: int, across: int) -> Vector2i:
	var col: int = sector % across * side + side / 2
	var line: int = sector / across * side + side / 2
	return Vector2i(mini(col, view.map_cols - 1), mini(line, view.map_rows - 1))


@warning_ignore("integer_division")
static func _span(length: int, side: int) -> int:
	return (length + side - 1) / side
