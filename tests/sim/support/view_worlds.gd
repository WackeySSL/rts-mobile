extends RefCounted
## The crafted World of the PlayerView suites (plan row P78). Not a test suite.
##
## `crafted()` is 20 x 14 tiles of grass with one rock at tile (8, 2), two players, the fog real
## (every row is stamped with its sight disc, nothing else is visible) and the ids below, in this
## order. A sight disc covers the tiles whose centre-to-centre squared distance is at most the
## squared sight: a headquarters 7 tiles, a rifle squad 6, a harvester 5. The tile is the one that
## holds the row (a building: the tile of its footprint centre).
##
## | id | owner | what | tile | player 1 | player 2 |
## | HQ_1 | 1 | headquarters, 3x3 from (2, 2) | (3, 3) | own | hidden |
## | HQ_2 | 2 | headquarters, 3x3 from (14, 9) | (15, 10) | hidden | own |
## | RIFLE_1 | 1 | rifle squad | (1, 5) | own | hidden |
## | NEAR_FOE | 2 | rifle squad | (9, 5) | seen | own |
## | FAR_FOE | 2 | rifle squad | (16, 2) | hidden | own |
## | NEAR_HARVESTER | 2 | harvester | (6, 8) | seen | own |
## | NEAR_NEUTRAL | 0 | rifle squad | (3, 0) | seen | hidden |
## | FAR_NEUTRAL | 0 | rifle squad | (18, 12) | hidden | seen |
## | HARVESTER_1 | 1 | harvester | (1, 2) | own | hidden |
##
## Player 1's headquarters sees the three that it sees (squared distances 40, 34 and 9, of 49), and
## none of player 2's rows sees a row of player 1's (the nearest pair, NEAR_FOE and the
## headquarters, is 40 apart against its 36). Player 2's headquarters sees the far neutral (13).

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TargetingWorlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const IDS: Array[String] = [
	"rifle_squad", "harvester", "headquarters", "power_plant", "barracks", "refinery"
]
const COLS: int = 20
const ROWS: int = 14
const HQ_1: int = 1
const HQ_2: int = 2
const RIFLE_1: int = 3
const NEAR_FOE: int = 4
const FAR_FOE: int = 5
const NEAR_HARVESTER: int = 6
const NEAR_NEUTRAL: int = 7
const FAR_NEUTRAL: int = 8
const HARVESTER_1: int = 9


## The World described above, prepared and stamped.
static func crafted() -> World:
	var world: World = Worlds.world(GridWorld.grass(COLS, ROWS, [Vector2i(8, 2)]), IDS, false)
	world.prepare()
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	var harvester: int = Worlds.type_of(world, "harvester")
	var hq: int = Worlds.type_of(world, "headquarters")
	world.add_building(1, hq, 2, 2)
	world.add_building(2, hq, 14, 9)
	world.add_unit(1, rifle, 1500, 5500)
	world.add_unit(2, rifle, 9500, 5500)
	world.add_unit(2, rifle, 16500, 2500)
	world.add_unit(2, harvester, 6500, 8500)
	world.add_unit(0, rifle, 3500, 500)
	world.add_unit(0, rifle, 18500, 12500)
	world.add_unit(1, harvester, 1500, 2500)
	TargetingWorlds.stamp_fog(world)
	return world


## The rows of the units `ids`, in the order given.
static func rows(world: World, ids: Array[int]) -> Array[int]:
	var found: Array[int] = []
	for id: int in ids:
		found.append(world.index_of(id))
	return found
