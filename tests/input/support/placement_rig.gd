extends RefCounted
## Fixtures of the placement suites (plan P86). Not a test suite. A 32 x 32 match on open ground
## with two players, the local one player 1: player 1's Headquarters `HQ` (3x3 at tiles 6-8 by 6-8)
## and player 2's Lumen Accord Headquarters far away, and the Derrick League's power plant (2x2)
## and barracks in the roster; the plant is the structure whose card turns READY. `make_ready`
## finishes it in the published snapshot, the way a finished queue head looks to the sidebar.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const HQ: int = 1
const PLANT: StringName = &"power_plant"
const FOOT: Vector2i = Vector2i(2, 2)  ## The power plant's footprint.
## A 2x2 origin tile that fits (the Headquarters' neighbour, in reach and explored) and ones that
## do not, with the reason each gets.
const FITS: Vector2i = Vector2i(10, 6)
const TOO_FAR: Vector2i = Vector2i(20, 6)
const ON_THE_HQ: Vector2i = Vector2i(7, 7)
const OFF_THE_MAP: Vector2i = Vector2i(-1, 6)


static func scenario() -> ScenarioDef:
	return scenario_for(1, "headquarters", [], ["power_plant", "barracks"])


## The same map for `local` (1 or 2), whose Headquarters `hq` (a file of data/units) stands at tiles
## 6-8 by 6-8 and the other player's, of the other faction, far away. `more` are further buildings
## of the local player as [unit, x, y] (what a structure in `roster` requires); `roster` lists the
## files of the units and structures the match knows.
static func scenario_for(local: int, hq: String, more: Array, roster: Array) -> ScenarioDef:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(local, hq, 6, 6),
		Rig.spawn(3 - local, "renew_hq" if hq == "headquarters" else "headquarters", 24, 24),
	]
	for entry: Array in more:
		spawns.append(Rig.spawn(local, entry[0], entry[1], entry[2]))
	var made: ScenarioDef = Rig.scenario(spawns)
	made.local_player = local
	for unit: String in roster:
		made.roster.append(load("res://data/units/%s.tres" % unit) as UnitDef)
	return made


## The type index of the power plant in `snap`.
static func plant(snap: MatchSnapshot) -> int:
	return snap.type_ids.find(PLANT)


## Player 1's STRUCTURES queue holds one finished structure in `snap`: the power plant, or `of_type`
## (a type index) when given. Only the published snapshot changes, not the World behind it.
@warning_ignore("integer_division")
static func make_ready(snap: MatchSnapshot, of_type: int = -1) -> void:
	var slots: int = snap.queue_type.size() / (snap.credits.size() * World.TABS)
	var queue: int = 1 * World.TABS + World.Tab.STRUCTURES
	var type: int = plant(snap) if of_type < 0 else of_type
	snap.queue_type[queue * slots] = type
	snap.queue_count[queue] = 1
	snap.queue_progress[queue] = snap.type_build_ticks[type] * Production.PROGRESS_PER_TICK


## Makes every tile of the map explored by player 1 in `snap`, so only the other rules decide.
static func explore(snap: MatchSnapshot) -> void:
	var fog: FogGrid = snap.fog
	for cell: int in fog.cells:
		fog.explored[cell] = 1
