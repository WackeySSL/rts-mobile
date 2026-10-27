extends RefCounted
## Fixtures of the strike suites (plan P112). Not a test suite. `world()` is 24 x 16 open tiles with
## the shipped Derrick League and Lumen Accord strike buildings, two players and these rows, in this
## order (ids from 1), all placed at tick 0: player 1's two Deep Bores `BORE_A` and `BORE_B` (3x3 at
## tiles (2, 2) and (6, 2)), its Blackout Array `ARRAY` (3x3 at (10, 2)) and its Headquarters `HQ`
## (3x3 at (2, 10)); player 2's Deep Bore `ENEMY_BORE` (3x3 at (18, 10)). Every number a case needs
## (the charge, the radius) is read from the World's tables, never written here.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const COLS: int = 24
const ROWS: int = 16
const BORE_A: int = 1
const BORE_B: int = 2
const ARRAY: int = 3
const HQ: int = 4
const ENEMY_BORE: int = 5
const IDS: Array[String] = ["headquarters", "fossil_strike", "renew_strike"]


static func world() -> World:
	var made: World = Worlds.open(COLS, ROWS, IDS)
	made.add_building(1, type_of(made, "fossil_strike"), 2, 2)
	made.add_building(1, type_of(made, "fossil_strike"), 6, 2)
	made.add_building(1, type_of(made, "renew_strike"), 10, 2)
	made.add_building(1, type_of(made, "headquarters"), 2, 10)
	made.add_building(2, type_of(made, "fossil_strike"), 18, 10)
	return made


static func type_of(made: World, id: String) -> int:
	return Worlds.type_of(made, id)


## The tick at which a SUPERWEAPON of building `id` is first accepted, as the sim reads it: the
## stamp (`tick + 1`) reaches `ready_tick`.
static func fire_tick(made: World, id: int) -> int:
	return made.ready_tick[made.index_of(id)] - 1


## The snapshot of `made` as it stands; another `serial` is another match.
static func snapshot(made: World, serial: int = 0) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = serial
	snap.capture(made, null)
	return snap


## A runner that was never started, on a scenario whose local player is player 1, publishing `snap`.
static func runner(snap: MatchSnapshot) -> MatchRunner:
	var made: MatchRunner = MatchRunner.new()
	made.scenario = ScenarioDef.new()
	made.snapshot = snap
	return made
