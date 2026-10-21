class_name FogUpdate
extends RefCounted
## The fog update, the FOG phase of Sim.step (ADR 0007 section 4 step 12, ADR 0010 section 1).
## Player p updates on the ticks where `tick % fog_period_ticks == (p - 1) % fog_period_ticks`, so
## with two players the work is spread over two ticks of every three. An update re-stamps a row
## only when its cell changed, and stamps the new disc (+1) before it unstamps the old one (-1):
## only the cells that really flip are listed in the dirty list (the status note of 2026-10-13 in
## ADR 0010 section 1; the final counts and `explored` are the same in either order). A dying row
## is unstamped by World.remove_dead before this phase. Integers only, no allocation. A mask id is
## the type index, or `type_sight.size()`, the pad mask (sight 0) that prepare() adds after one mask
## per type, for a type with no entry; and `fog_cell` is the cell last stamped.
##
## `run` has a C++ twin, the FOG kernel (native/sim_kernels, core/fog.cpp, ADR 0013 section 5):
## it hands the whole phase to it when the World's mask has its bit, and a change to `run`,
## `_covered` or `FogGrid.stamp` edits both and passes the kernel's tests. `begin`, the unstamp of
## World.remove_dead and the initial stamp of World.prepare stay GDScript and call `FogGrid.stamp`
## themselves, which is why that function stays the reference.


## Empties the dirty list of every player whose turn it is this tick. Sim.step calls it before
## World.remove_dead, so the cells a dying row's unstamp flips on the owner's own update tick stay
## in the list that the update then adds to. Nothing here changes a count.
static func begin(world: World) -> void:
	var fog: FogGrid = world.fog
	var period: int = maxi(world.fog_period_ticks, 1)
	var tick: int = world.tick
	for player: int in range(1, fog.player_count + 1):
		if (tick - player + 1) % period == 0:
			fog.begin_update(player)


## One FOG phase: the rows of the players whose turn it is move their disc from `fog_cell` to the
## cell of their position (a row not stamped yet, -1, only stamps), and stats[FOG_CELLS] grows by
## the cells those stamps cover, clipped to the map. A row of owner 0 or past player_count has no
## fog, and a grid with no cells or sides that do not make its cells has none at all.
## The cell is World.cell_of inlined.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	if ((world.native_phases >> SimProbe.Phase.FOG) & 1) == 1:
		world.kernels.fog(world)
		return
	var fog: FogGrid = world.fog
	var cols: int = fog.cols
	var map_rows: int = fog.rows
	var players: int = fog.player_count
	# No fog: no map, or sides that do not make the cells (configure() always does; the kernel
	# cannot divide by a side of 0, so both versions take the same test).
	if cols < 1 or map_rows < 1 or fog.cells % cols != 0 or fog.cells / cols != map_rows:
		return
	var period: int = maxi(world.fog_period_ticks, 1)
	var tick: int = world.tick
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var xs: PackedInt32Array = world.pos_x
	var ys: PackedInt32Array = world.pos_y
	var stamped: PackedInt32Array = world.fog_cell
	var starts: PackedInt32Array = fog.mask_start
	var radii: PackedInt32Array = fog.mask_radius
	var half: PackedInt32Array = fog.mask_half
	var pad: int = world.type_sight.size()
	var covered: int = 0
	for row: int in owners.size():
		var player: int = owners[row]
		if player < 1 or player > players or (tick - player + 1) % period != 0:
			continue
		var cell: int = (
			clampi(ys[row] / World.MILLI_PER_TILE, 0, map_rows - 1) * cols
			+ clampi(xs[row] / World.MILLI_PER_TILE, 0, cols - 1)
		)
		var old: int = stamped[row]
		if cell == old:
			continue
		var mask: int = mini(types[row], pad)
		var radius: int = radii[mask]
		var first: int = starts[mask] + radius
		fog.stamp(player, cell, mask, 1)
		covered += _covered(cell, cols, map_rows, radius, first, half)
		if old >= 0:
			fog.stamp(player, old, mask, -1)
			covered += _covered(old, cols, map_rows, radius, first, half)
		stamped[row] = cell
	world.stats[World.Stat.FOG_CELLS] += covered


## The cells of a mask centred on `cell` that lie in the map: what FogGrid.stamp walks. `radius` is
## the mask's, `first` its `mask_start` plus the radius, and `half` is `FogGrid.mask_half`.
@warning_ignore("integer_division")
static func _covered(
	cell: int, width: int, map_rows: int, radius: int, first: int, half: PackedInt32Array
) -> int:
	var centre_x: int = cell % width
	var centre_y: int = cell / width
	var spans: int = first - centre_y
	var total: int = 0
	for y: int in range(maxi(centre_y - radius, 0), mini(centre_y + radius, map_rows - 1) + 1):
		var reach: int = half[spans + y]
		total += mini(centre_x + reach, width - 1) - maxi(centre_x - reach, 0) + 1
	return total
