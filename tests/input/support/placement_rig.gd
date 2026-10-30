extends RefCounted
## Fixtures of the placement suites (plan P86). Not a test suite. A 32 x 32 match on open ground
## with two players, the local one player 1: player 1's Headquarters `HQ` (3x3 at tiles 6-8 by 6-8)
## and player 2's Lumen Accord Headquarters far away, and the Derrick League's power plant (2x2)
## and barracks in the roster; the plant is the structure whose card turns READY. `make_ready`
## finishes it in the published snapshot, the way a finished queue head looks to the sidebar.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const HQ: int = 1
const PLANT: StringName = &"power_plant"
const SPAWNS: Array[Array] = [[1, "headquarters", 6, 6], [2, "renew_hq", 24, 24]]
const FOOT: Vector2i = Vector2i(2, 2)  ## The power plant's footprint.
## A 2x2 origin tile that fits (the Headquarters' neighbour, in reach and explored) and ones that
## do not, with the reason each gets.
const FITS: Vector2i = Vector2i(10, 6)
const TOO_FAR: Vector2i = Vector2i(20, 6)
const ON_THE_HQ: Vector2i = Vector2i(7, 7)
const OFF_THE_MAP: Vector2i = Vector2i(-1, 6)


static func scenario() -> ScenarioDef:
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var made: ScenarioDef = Rig.scenario(spawns)
	made.roster = [
		load("res://data/units/power_plant.tres") as UnitDef,
		load("res://data/units/barracks.tres") as UnitDef,  # A card that is not ready.
	]
	return made


## The type index of the power plant in `snap`.
static func plant(snap: MatchSnapshot) -> int:
	return snap.type_ids.find(PLANT)


## Player 1's STRUCTURES queue holds one finished power plant in `snap`.
@warning_ignore("integer_division")
static func make_ready(snap: MatchSnapshot) -> void:
	var slots: int = snap.queue_type.size() / (snap.credits.size() * World.TABS)
	var queue: int = 1 * World.TABS + World.Tab.STRUCTURES
	var type: int = plant(snap)
	snap.queue_type[queue * slots] = type
	snap.queue_count[queue] = 1
	snap.queue_progress[queue] = snap.type_build_ticks[type] * Production.PROGRESS_PER_TICK


## Makes every tile of the map explored by player 1 in `snap`, so only the other rules decide.
static func explore(snap: MatchSnapshot) -> void:
	var fog: FogGrid = snap.fog
	for cell: int in fog.cells:
		fog.explored[cell] = 1
