extends RefCounted
## A World with a flow cache, for the module tests of FlowField and FlowCache under both
## implementations (ADR 0013 section 3). The calls are the same on both: acquire() and invalidate()
## on the cache, recount() and advance() through FlowCache.run, whose dispatch hands them to C++
## when `impl` is NATIVE. A name the rig does not have reads through to the cache (`rig.status` is
## `rig.flow.status`). Not a test suite.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
## The unit rows that the `field` column of recount() points from.
const UNITS: int = 16

var world: World
var flow: FlowCache
## What SimImpls.use found wrong: the test asserts it is empty.
var problems: Array[String] = []


## A cols x rows map of open grass, `slots` cache slots and UNITS rows with no field. Returns self.
func setup(impl: int, cols: int, rows: int, slots: int) -> RefCounted:
	world = World.new()
	world.map_w = cols * World.MILLI_PER_TILE
	world.map_h = rows * World.MILLI_PER_TILE
	world.flow_cache_size = slots
	for _unit: int in UNITS:
		world.add_unit(1, 0, World.TILE_CENTRE, World.TILE_CENTRE)
	world.prepare()
	problems = SimImpls.use(world, impl)
	flow = world.flow
	return self


func acquire(goal_cell: int, move_class: int, map_version: int, tick: int) -> int:
	return flow.acquire(goal_cell, move_class, map_version, tick)


func invalidate(map_version: int) -> void:
	flow.invalidate(map_version)


func refs(slot: int) -> int:
	return flow.refs(slot)


func field(slot: int) -> FlowField:
	return flow.field(slot)


## The `field` column is the first `count` entries of `column`, and no field below that.
func recount(column: PackedInt32Array, count: int) -> void:
	var rows: PackedInt32Array = PackedInt32Array()
	rows.resize(UNITS)
	rows.fill(-1)
	for row: int in mini(mini(count, column.size()), UNITS):
		rows[row] = column[row]
	world.field = rows
	run(0)


## FlowCache.advance of the World's `costs`, as FlowCache.run does it: the settled cells.
func advance(costs: PackedByteArray, budget_cells: int) -> int:
	world.move_cost = costs
	return run(budget_cells)


## FlowCache.run (recount, then advance) and the cells it settled.
func run(budget_cells: int) -> int:
	world.stats.fill(0)
	FlowCache.run(world, budget_cells)
	return world.stats[World.Stat.FLOW_CELLS]


func _get(property: StringName) -> Variant:
	return flow.get(property)
