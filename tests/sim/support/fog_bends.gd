extends RefCounted
## Fogs that `FogGrid.configure` never makes (P46b): a grid whose sides do not make its cells, or
## has no sides. Both versions of the vision rule (`Targeting.run` and `Targeting.sees`, and the
## TARGETING kernel's `has_cells`) take such a fog for no fog and see every cell, as FogUpdate.run's
## guard and the FOG kernel take it for no grid (tests/sim/native/test_fog_kernel.gd has its own
## list for the FOG phase). NAMES bend the fog of a 30 x 30 map and two players (900 cells). Not a
## test suite.

const SQUARE: int = 30
const NAMES: Array[String] = [
	"one column less",
	"one column more",
	"one row less",
	"one row more",
	"no columns",
	"no rows",
	"no rows, no cells",
	"sides of -30",
	"cells that 30 columns do not divide"
]


## Makes the grid of `fog` (30 x 30, 900 cells, two players) say what `how` (one of NAMES) says.
static func apply(fog: FogGrid, how: String) -> void:
	match how:
		"one column less":
			fog.cols = SQUARE - 1
		"one column more":
			fog.cols = SQUARE + 1
		"one row less":
			fog.rows = SQUARE - 1
		"one row more":
			fog.rows = SQUARE + 1
		"no columns":
			fog.cols = 0
		"no rows":
			fog.rows = 0
		"no rows, no cells":
			fog.configure(SQUARE, 0, fog.player_count)
		"cells that 30 columns do not divide":
			resize_blocks(fog, SQUARE * SQUARE + 5)
		_:
			fog.cols = -SQUARE
			fog.rows = -SQUARE


## Gives the grid `cells` cells with the arrays that its checked sizes ask for (player_count blocks
## of cells, and of a quarter of them for the dirty lists), whatever its sides are.
@warning_ignore("integer_division")
static func resize_blocks(fog: FogGrid, cells: int) -> void:
	fog.cells = cells
	fog.dirty_capacity = cells / 4
	fog.visible.resize(fog.player_count * cells)
	fog.explored.resize(fog.player_count * cells)
	fog.listed.resize(fog.player_count * cells)
	fog.dirty.resize(fog.player_count * fog.dirty_capacity)
