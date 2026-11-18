class_name AiSearch
extends RefCounted
## The close-out search (plan row P250c): once no enemy producer is seen or remembered and the
## mirror estimate of the enemy Headquarters has been explored, the base estimate moves on to the
## sector of the enemy half, nearest to that point, whose centre the player has not explored, so the
## wave walks on and looks. A remembered building that died out of sight stays remembered until the
## spot is seen again (`LastSeen`), so the visit also clears it. Reads only `PlayerView.is_explored`
## and the sector grid of `AiIntel`; no Command and no draw.
##
## Both seats choose mirrored sectors: halves and distances compare the true sector centres in
## doubled tile units (the integer goal tile is only where the wave walks), and a tie goes to the
## sector with the lower offset from the mirror point, taken toward the own side, a rule the point
## mirror keeps. A sector the wave has not explored after `hold_ticks` of marching since the pick
## (unreachable, or the wave is elsewhere) is skipped for good: the clock runs only while the wave
## squad is out. 0 = off.

## Copied from the level when the manager is made.
var hold_ticks: int = 0
## Search goals picked over the match, for the suites.
var picks: int = 0


static func create(level: AiDifficultyDef) -> AiSearch:
	var search: AiSearch = AiSearch.new()
	search.hold_ticks = maxi(level.search_hold_ticks, 0)
	return search


## The tile the base estimate takes in place of the mirror estimate, (-1, -1) for "keep the mirror".
func target(view: PlayerView, memory: AiMemory, home: Vector2i, intel: AiIntel) -> Vector2i:
	var side: int = intel.sector_side
	if hold_ticks <= 0 or home.x < 0 or side < 1:
		return Vector2i(-1, -1)
	var mirror: Vector2i = AiMemory.mirror(home, view.map_cols, view.map_rows)
	if not view.is_explored(mirror.y * view.map_cols + mirror.x):
		return Vector2i(-1, -1)
	var marching: bool = (
		memory.squad_role.size() > AiArmy.WAVE
		and memory.squad_role[AiArmy.WAVE] != AiMemory.NONE
		and memory.squad_state[AiArmy.WAVE] == AiMemory.SquadState.WAVE
	)
	if marching and memory.search_last != AiMemory.NONE:
		memory.search_spent += maxi(view.tick - memory.search_last, 0)
	memory.search_last = view.tick
	var current: int = memory.search_sector
	if current >= 0:
		var at: Vector2i = intel.centre_of(view, current)
		if not view.is_explored(at.y * view.map_cols + at.x):
			if memory.search_spent < hold_ticks:
				return at
			memory.search_skipped[current] = 1
		memory.search_sector = AiMemory.NONE
	var best: int = _pick(view, memory, home, mirror, intel)
	if best < 0:
		return Vector2i(-1, -1)
	memory.search_sector = best
	memory.search_spent = 0
	picks += 1
	return intel.centre_of(view, best)


## The unexplored, not skipped sector on the enemy side (strictly nearer the mirror point than the
## own Headquarters) whose true centre is nearest the mirror point; -1 for none.
func _pick(
	view: PlayerView, memory: AiMemory, home: Vector2i, mirror: Vector2i, intel: AiIntel
) -> int:
	var side: int = intel.sector_side
	var away: Vector2i = Vector2i(signi(mirror.x - home.x), signi(mirror.y - home.y))
	var best: int = -1
	var best_distance: int = 0
	var best_key: Vector2i = Vector2i.ZERO
	for sector: int in mini(memory.search_skipped.size(), intel.sector_count()):
		if memory.search_skipped[sector] != 0:
			continue
		var tile: Vector2i = intel.centre_of(view, sector)
		if view.is_explored(tile.y * view.map_cols + tile.x):
			continue
		var origin_col: int = sector % intel.sector_cols * side
		var origin_line: int = sector / intel.sector_cols * side
		var doubled: Vector2i = Vector2i(
			2 * origin_col + mini(side, view.map_cols - origin_col) - 1,
			2 * origin_line + mini(side, view.map_rows - origin_line) - 1
		)
		var distance: int = AiIntel._distance(doubled, 2 * mirror)
		if distance >= AiIntel._distance(doubled, 2 * home):
			continue
		var key: Vector2i = (doubled - 2 * mirror) * away
		if (
			best < 0
			or distance < best_distance
			or (distance == best_distance and _before(key, best_key))
		):
			best = sector
			best_distance = distance
			best_key = key
	return best


static func _before(key: Vector2i, other: Vector2i) -> bool:
	return key.x < other.x or (key.x == other.x and key.y < other.y)
