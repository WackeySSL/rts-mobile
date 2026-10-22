extends RefCounted
## The player's units of up to six types, for the HUD suites that need a mixed selection (plan
## P61). Not a suite. The six are the MVP units of docs/GDD.md, in its order: rifle squad, rocket
## squad and light tank are the data's definitions; heavy tank, artillery and harvester are made
## here (a type id and a display name), because the data has none of them yet.
## `select()` points a SelectionPanel at a paused match of these units and selects all of them, so
## a test gets the panel's mixed rows without a UnitLayer that would look for art that is not there.

const DATA: Array[String] = [
	"res://data/units/rifle_squad.tres",
	"res://data/units/rocket_squad.tres",
	"res://data/units/light_tank.tres",
]
const MADE: Dictionary[StringName, String] = {
	&"heavy_tank": "Heavy Tank", &"artillery": "Artillery", &"harvester": "Harvester"
}
const COLUMNS: int = 12
const SPACING: int = 800  ## Milli-tiles between neighbours: a block of 150 is 10 tiles by 13.


## The six definitions, in the order of the GDD table.
static func defs() -> Array[UnitDef]:
	var out: Array[UnitDef] = []
	for path: String in DATA:
		out.append(load(path))
	for type_id: StringName in MADE:
		var def: UnitDef = UnitDef.new()
		def.type_id = type_id
		def.display_name = MADE[type_id]
		out.append(def)
	return out


## A scenario with `counts[i]` units of type i for player 1 (a type with a count of 0 is left
## out). Units 1.. are numbered in that order: the first type's block first.
static func scenario(counts: Array[int]) -> ScenarioDef:
	var out: ScenarioDef = ScenarioDef.new()
	out.map_size_tiles = Vector2i(48, 48)
	var types: Array[UnitDef] = defs()
	for index: int in mini(counts.size(), types.size()):
		if counts[index] <= 0:
			continue
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = 1
		spawn.unit = types[index]
		spawn.count = counts[index]
		spawn.origin_tile = Vector2i(2 + 14 * (index % 3), 2 + 20 * (index / 3))
		spawn.columns = COLUMNS
		spawn.spacing = SPACING
		out.spawns.append(spawn)
	return out


## Shows all of `counts` selected in `panel`: a paused match of those units (owned by `suite`) is
## the panel's runner, and the panel is handed every unit id. Returns the runner.
static func select(
	suite: GdUnitTestSuite, panel: SelectionPanel, counts: Array[int]
) -> MatchRunner:
	var runner: MatchRunner = suite.auto_free(MatchRunner.new())
	runner.scenario = scenario(counts)
	runner.paused = true
	suite.add_child(runner)
	panel.runner = runner
	var total: int = 0
	for count: int in counts:
		total += maxi(count, 0)
	panel.set_selected(PackedInt32Array(range(1, total + 1)))
	return runner
