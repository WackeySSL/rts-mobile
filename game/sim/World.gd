class_name World
extends RefCounted
## Simulation state v0 (ADR 0003 section 2): struct-of-arrays, integers only. Positions are
## milli-tiles (1 tile = 1000). Units are rows in the per-unit arrays, ascending by id. Ids come
## from a counter that starts at 1 and are never reused. Phase 1 never removes a unit, so an id
## is found by binary search. The view and input read a World and never write to it.

enum Order { IDLE = 0, ATTACK_MOVE = 1 }

## Same value as Sim.MILLI_PER_TILE, which P3 adds. World cannot read it from Sim (Sim reads World).
const MILLI_PER_TILE: int = 1000
const TILE_CENTRE: int = 500

var tick: int = 0
## Map size in milli-tiles.
var map_w: int = 0
var map_h: int = 0
var next_id: int = 1
## Commands Sim.step rejected (wrong tick, unknown type, no valid unit).
var dropped_commands: int = 0

## Per type. The index is the order of first appearance in the scenario's spawns.
var type_ids: Array[StringName] = []
var type_speed: PackedInt32Array = PackedInt32Array()
var type_radius: PackedInt32Array = PackedInt32Array()
var type_selection_radius: PackedInt32Array = PackedInt32Array()
var type_spacing: PackedInt32Array = PackedInt32Array()

## Per unit, ascending by id.
var unit_id: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
var pos_x: PackedInt32Array = PackedInt32Array()
var pos_y: PackedInt32Array = PackedInt32Array()
var goal_x: PackedInt32Array = PackedInt32Array()
var goal_y: PackedInt32Array = PackedInt32Array()
var order: PackedInt32Array = PackedInt32Array()


## Reads the scenario and its unit definitions once. A null scenario gives an empty world.
## A spawn without a unit is skipped.
static func from_scenario(scenario: ScenarioDef) -> World:
	var world: World = World.new()
	if scenario == null:
		return world
	world.map_w = scenario.map_size_tiles.x * MILLI_PER_TILE
	world.map_h = scenario.map_size_tiles.y * MILLI_PER_TILE
	for spawn: SpawnDef in scenario.spawns:
		if spawn == null or spawn.unit == null:
			continue
		var type: int = world._type_for(spawn.unit)
		var columns: int = maxi(spawn.columns, 1)
		var start_x: int = spawn.origin_tile.x * MILLI_PER_TILE + TILE_CENTRE
		var start_y: int = spawn.origin_tile.y * MILLI_PER_TILE + TILE_CENTRE
		var column: int = 0
		var row: int = 0
		for _slot: int in spawn.count:
			var x: int = start_x + column * spawn.spacing
			var y: int = start_y + row * spawn.spacing
			world.add_unit(spawn.owner, type, x, y)
			column += 1
			if column == columns:
				column = 0
				row += 1
	return world


func unit_count() -> int:
	return unit_id.size()


## The row of unit `id`, or -1 when no unit has that id.
func index_of(id: int) -> int:
	var index: int = unit_id.bsearch(id)
	if index < unit_id.size() and unit_id[index] == id:
		return index
	return -1


## Appends an idle unit at (x, y) with its goal on its position and returns its new id.
## `type_index` must be an index into type_ids. The parameters keep the contract's names, so
## they shadow the arrays of the same name.
@warning_ignore("shadowed_variable")
func add_unit(owner: int, type_index: int, x: int, y: int) -> int:
	var id: int = next_id
	next_id += 1
	unit_id.append(id)
	self.owner.append(owner)
	self.type_index.append(type_index)
	pos_x.append(x)
	pos_y.append(y)
	goal_x.append(x)
	goal_y.append(y)
	order.append(Order.IDLE)
	return id


## The type index for `unit`'s type_id. A type seen for the first time is copied in, so each
## definition is read once however many spawns use it.
func _type_for(unit: UnitDef) -> int:
	var found: int = type_ids.find(unit.type_id)
	if found >= 0:
		return found
	type_ids.append(unit.type_id)
	type_speed.append(unit.speed)
	type_radius.append(unit.radius)
	type_selection_radius.append(unit.selection_radius)
	type_spacing.append(unit.formation_spacing)
	return type_ids.size() - 1
