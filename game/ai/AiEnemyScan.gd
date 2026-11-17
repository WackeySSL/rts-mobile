class_name AiEnemyScan
extends RefCounted
## The army's two seen-enemy searches, moved out of `AiArmy` (P250): the value
## of the seen enemies near a point and the weakest seen enemy unit in reach. Static and stateless:
## the army passes its test counter and cap in and takes the used count back, in the `y` of the
## answer, so `AiArmy.tests` stays the one counter the suites read.


## The value of the rows of `list` within `radius` of `centre` (only armed, finished buildings when
## `sites`), one test each past the box, until the cap of `cap` tests, `used` of them spent already.
## `x` is the value, `y` the tests used afterwards.
static func value_in(
	view: PlayerView,
	list: PackedInt32Array,
	centre: Vector2i,
	radius: int,
	sites: bool,
	used: int,
	cap: int
) -> Vector2i:
	var found: int = 0
	var columns: Array[PackedInt32Array] = view.columns()
	var xs: PackedInt32Array = columns[PlayerView.Column.X]
	var ys: PackedInt32Array = columns[PlayerView.Column.Y]
	for id: int in list:
		if used >= cap:
			break
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var gap_x: int = xs[row] - centre.x
		var gap_y: int = ys[row] - centre.y
		if gap_x > radius or gap_x < -radius or gap_y > radius or gap_y < -radius:
			continue
		if sites and not armed(view, row):
			continue
		used += 1
		if gap_x * gap_x + gap_y * gap_y <= radius * radius:
			found += AiIntel.value_of(view, row)
	return Vector2i(found, used)


## Whether the building at `row` is finished (`build_left` 0) and has a weapon.
static func armed(view: PlayerView, row: int) -> bool:
	var type: int = view.row_type(row)
	return (
		view.row_build_left(row) == 0
		and type >= 0
		and type < view.type_weapon.size()
		and view.type_weapon[type] >= 0
	)


## The layers the weapon of `type` may hit (`weapon_targets`, a `PlayerView.Layer` mask): 0 for a
## type without a weapon, the ground for a weapon the view has no mask for.
static func hit_mask(view: PlayerView, type: int) -> int:
	var weapon: int = view.type_weapon[type]
	if weapon < 0:
		return 0
	return view.weapon_targets[weapon] if weapon < view.weapon_targets.size() else 1


## The row of the weakest (fewest hp, the first on a tie) unit of `list` within `radius` of
## `centre` that a weapon of `mask` can hit (the layer of its type, P250; a view without the layer
## table filters nothing), at most `cap` tests with `used` spent already. `x` is the row (-1 for
## none), `y` the tests used afterwards, `z` is 1 when the cap cut the search off.
static func weakest(
	view: PlayerView,
	list: PackedInt32Array,
	centre: Vector2i,
	radius: int,
	mask: int,
	used: int,
	cap: int
) -> Vector3i:
	var layers: PackedInt32Array = view.type_layer_bit
	var found: int = -1
	var least: int = 0
	var capped: int = 0
	for id: int in list:
		if used >= cap:
			capped = 1
			break
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var type: int = view.row_type(row)
		if type < layers.size() and layers[type] & mask == 0:
			continue
		var gap: Vector2i = view.row_pos(row) - centre
		if absi(gap.x) > radius or absi(gap.y) > radius:
			continue
		used += 1
		if gap.x * gap.x + gap.y * gap.y > radius * radius:
			continue
		if found < 0 or view.row_hp(row) < least:
			found = row
			least = view.row_hp(row)
	return Vector3i(found, used, capped)
