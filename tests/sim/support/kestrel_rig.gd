extends RefCounted
## What the Kestrel Flats suites share (plan row P79): the data paths, the World of a scenario made
## the way the runner makes it, the ore fields of a World, the start tile of a base and the reach of
## a finished flow field. Not a test suite.

const MAP_PATH: String = "res://data/maps/kestrel_flats.tres"
const SKIRMISH_PATH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const MIRRORED_PATH: String = "res://data/scenarios/skirmish_kestrel_flats_mirrored.tres"
const PATHS: Array[String] = [SKIRMISH_PATH, MIRRORED_PATH]
const SEED: int = 42
## Per faction id: the power plant, the refinery, a rifle squad and a tank, one item for each of
## the production tabs a start can use.
const POWER: Dictionary[StringName, StringName] = {
	&"fossil": &"power_plant", &"renew": &"renew_power"
}
const REFINERY: Dictionary[StringName, StringName] = {
	&"fossil": &"refinery", &"renew": &"renew_refinery"
}
const RIFLE: Dictionary[StringName, StringName] = {
	&"fossil": &"rifle_squad", &"renew": &"renew_rifle"
}
const TANK: Dictionary[StringName, StringName] = {&"fossil": &"heavy_tank", &"renew": &"renew_tank"}
## The map is 64 x 64 tiles; a half turn sends tile (x, y) to (63 - x, 63 - y).
const SIZE: int = 64
## A budget no field needs: one call settles every cell.
const BIG: int = 1000000
const CLASSES: Array[int] = [World.MoveClass.FOOT, World.MoveClass.WHEELED, World.MoveClass.TRACKED]


## The World the runner makes of the scenario at `path`: the jitter stream is seeded from SEED.
static func world(path: String) -> World:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))


## The ore fields of `world`: the groups of ore tiles joined side to side or corner to corner, each
## as its cells ascending, numbered by the lowest cell (the order `ore_cell` lists them in, and the
## order of `MapDef.field_kinds`).
@warning_ignore("integer_division")
static func ore_fields(world: World) -> Array[PackedInt32Array]:
	var cols: int = world.map_cols
	var lines: int = world.map_rows
	var state: PackedByteArray = PackedByteArray()
	state.resize(cols * lines)
	for cell: int in world.ore_cell:
		state[cell] = 1
	var found: Array[PackedInt32Array] = []
	for first: int in world.ore_cell:
		if state[first] != 1:
			continue
		var group: PackedInt32Array = PackedInt32Array()
		var open: Array[int] = [first]
		state[first] = 2
		while not open.is_empty():
			var cell: int = open.pop_back()
			group.append(cell)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var x: int = cell % cols + dx
					var y: int = cell / cols + dy
					if x < 0 or y < 0 or x >= cols or y >= lines:
						continue
					if state[y * cols + x] == 1:
						state[y * cols + x] = 2
						open.append(y * cols + x)
		group.sort()
		found.append(group)
	return found


## The building rows of `player`, ascending.
static func building_rows(world: World, player: int) -> PackedInt32Array:
	var rows: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_foot_w[world.type_index[row]] > 0:
			rows.append(row)
	return rows


## The ids of the mobile rows of `player`, ascending.
static func mobile_ids(world: World, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_speed[world.type_index[row]] > 0:
			ids.append(world.unit_id[row])
	return ids


## The tile south of the middle of `player`'s first building, the one a unit leaves a base by.
@warning_ignore("integer_division")
static func start_tile(world: World, player: int) -> Vector2i:
	var row: int = building_rows(world, player)[0]
	var type: int = world.type_index[row]
	var origin: Vector2i = world.footprint_origin(row)
	return Vector2i(origin.x + world.type_foot_w[type] / 2, origin.y + world.type_foot_h[type])


## A finished flow field from `goal` for `move_class` over `costs`, the World's own `move_cost` when
## none is given.
static func field(
	world: World, goal: Vector2i, move_class: int, costs: PackedByteArray = PackedByteArray()
) -> FlowField:
	var flow: FlowField = FlowField.new()
	var used: PackedByteArray = world.move_cost if costs.is_empty() else costs
	flow.begin(goal.y * world.map_cols + goal.x, move_class, used, world.map_cols, world.map_rows)
	flow.advance(BIG)
	return flow


## Whether the finished field `flow` reaches `tile` of a map `cols` wide.
static func reaches(flow: FlowField, cols: int, tile: Vector2i) -> bool:
	return flow.cost[(tile.y + 1) * (cols + FlowField.PAD) + tile.x + 1] != FlowField.UNREACHED
