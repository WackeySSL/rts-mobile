extends RefCounted
## Fixtures of the air-view suites (plan P243). No aircraft art exists before P245, so two crafted
## sheets of 8-direction frames in `tests/view/fixtures/air/` stand in: a high fighter of the
## Derrick League (`fossil_fighter`, `FLY_PX`) and a low drone squad of the Lumen Accord
## (`renew_drone`, `LOW_FLY_PX`), both with a hull and a shadow. A scenario has one of each flyer
## beside a tank of each player, so both players have ground art. Not a test suite.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const FIXTURES: String = "res://tests/view/fixtures/air"
const FLY_PX: int = 30
const LOW_FLY_PX: int = 14
const FIGHTER: StringName = &"fossil_fighter"
const DRONE: StringName = &"renew_drone"
const FIGHTER_ID: int = 3  ## Unit ids of the two flyers of `runner`.
const DRONE_ID: int = 4


## The crafted sheet of `art_id` of `faction`: a hull and a shadow of 8 directions, 64 x 40 px.
static func sheet(art_id: StringName, faction: StringName, high: bool) -> IsoSheetDef:
	var made: IsoSheetDef = IsoSheetDef.new()
	made.art_id = art_id
	made.faction = faction
	made.root = FIXTURES
	made.parts = PackedStringArray(["hull", "shadow"])
	made.counts = PackedInt32Array([8, 8])
	made.sizes = PackedInt32Array([64, 40, 64, 40])
	made.anchors = PackedInt32Array([32, 30, 32, 30])
	made.fly_px = FLY_PX if high else 0
	made.low_fly_px = 0 if high else LOW_FLY_PX
	return made


static func sheets() -> Array[IsoSheetDef]:
	return [sheet(FIGHTER, &"fossil", true), sheet(DRONE, &"renew", false)]


## A runner on a scenario of the own fighter at tile (8, 8), the enemy drone at (20, 20) and a
## tank of each player; paused, started, not in the tree.
static func runner() -> MatchRunner:
	var spawns: Array[SpawnDef] = [
		Buildings.spawn(1, "light_tank", 4, 4),
		Buildings.spawn(2, "renew_tank", 24, 24),
		Buildings.spawn(1, String(FIGHTER), 8, 8),
		Buildings.spawn(2, String(DRONE), 20, 20),
	]
	return Buildings.runner(Buildings.scenario(spawns))


## An `AirLayer` over `runner` in `host`'s tree whose sorted world bakes the crafted sheets.
static func layer(host: Node, runner_in: MatchRunner) -> AirLayer:
	var made: AirLayer = AirLayer.new()
	made.runner = runner_in
	var sort: WorldSort = WorldSort.new()
	sort.runner = runner_in
	sort.extra_sheets = sheets()
	made.world_sort = sort
	made.add_child(sort)
	host.add_child(made)
	made.set_process(false)
	return made
