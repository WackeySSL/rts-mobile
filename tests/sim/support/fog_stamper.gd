extends RefCounted
## The stamp of a FogGrid through one of the two implementations (ADR 0013 section 3, plan P46n),
## for the cases of test_fog_grid.gd. There is no test-only bound entry (ADR 0013 section 2), so the
## C++ stamp is reached the way the sim reaches it: through the FOG kernel, from a row of a scratch
## World whose `fog` is the grid under test, which FogUpdate.run moves onto the cell. The GDScript
## implementation calls FogGrid.stamp itself, in the order FogUpdate.run uses. The only unstamp that
## the sim makes alone is World.remove_dead's, a GDScript call in both implementations; the C++ one
## is the second half of a re-stamp, so `move` is its entry. Not a test suite.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const FOG: int = SimProbe.Phase.FOG
const TILE: int = World.MILLI_PER_TILE

## The implementation asked for: SimImpls.Impl.GDSCRIPT or NATIVE.
var impl: int = SimImpls.Impl.GDSCRIPT
## What went wrong with the setup, empty when every call did what was asked: the library is not
## loaded, the phase did not run in the implementation asked for, or the kernel did not stamp the
## row. A test asserts that it is empty.
var problems: Array[String] = []
## The kernel calls so far; 0 for the GDScript implementation.
var runs: int = 0


func _init(which: int = SimImpls.Impl.GDSCRIPT) -> void:
	impl = which


## `grid.stamp(player, cell, mask, 1)`: the disc of `mask` at `cell` for the first time (a row not
## stamped yet).
func stamp(grid: FogGrid, player: int, cell: int, mask: int) -> void:
	if impl == SimImpls.Impl.GDSCRIPT:
		grid.stamp(player, cell, mask, 1)
	else:
		_run(grid, player, -1, cell, mask)


## A row moves from `old` (stamped) to `cell`: the new disc is stamped before the old one is
## unstamped, as FogUpdate.run does.
func move(grid: FogGrid, player: int, old: int, cell: int, mask: int) -> void:
	if impl == SimImpls.Impl.GDSCRIPT:
		grid.stamp(player, cell, mask, 1)
		grid.stamp(player, old, mask, -1)
	else:
		_run(grid, player, old, cell, mask)


## One FogUpdate.run on a scratch World that has one row of `player` standing on `cell`, last
## stamped on `old` (-1: not at all), over the grid, with every player's turn on every tick. The
## type index of the row is the mask id, and the table holds as many types as the grid has masks,
## so that the pad mask is none of the ids asked for.
@warning_ignore("integer_division")
func _run(grid: FogGrid, player: int, old: int, cell: int, mask: int) -> void:
	var world: World = World.new()
	world.map_w = grid.cols * TILE
	world.map_h = grid.rows * TILE
	world.player_count = grid.player_count
	world.fog_period_ticks = 1
	for index: int in grid.mask_start.size():
		world.type_ids.append(StringName("mask_%d" % index))
	world.prepare()
	world.fog = grid
	var x: int = (cell % grid.cols) * TILE + World.TILE_CENTRE
	var y: int = (cell / grid.cols) * TILE + World.TILE_CENTRE
	world.add_unit(player, mask, x, y)
	world.fog_cell[0] = old
	problems.append_array(SimImpls.attach(world, SimImpls.Impl.NATIVE, FOG))
	FogUpdate.run(world)
	runs += 1
	if world.fog_cell[0] != cell:
		problems.append("the kernel left the row at cell %d, not %d" % [world.fog_cell[0], cell])
