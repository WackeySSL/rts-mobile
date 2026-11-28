extends GdUnitTestSuite
## `WallCover` (ADR 0053 amendment A7 and A8, plan P656d3), the GDScript twin of the silhouette
## shader's cover test: the three cells of a screen point against a brute-force prism sweep, the
## unit's sort key, `front_cell` and `ground_at` on tops, faces and flat ground, the near bytes.

const COLS: int = 12
const ROWS: int = 12
## '#' is a wall: a lone cell, a 2 x 2 block, a row of three and a diagonal pair.
const MAP: Array[String] = [
	"............",
	"..#.........",
	"............",
	"......##....",
	"......##....",
	"............",
	".###........",
	"............",
	"........#...",
	".........#..",
	"............",
	"............",
]


func test_the_rise_is_one_diamond_height() -> void:
	assert_int(TerrainKitDef.RISE_MAX).is_equal(2 * 2 * IsoProjection.HALF_H)


func test_the_three_cells_equal_a_brute_force_prism_sweep_at_four_samples_a_pixel() -> void:
	var raised: PackedByteArray = _raised()
	var checked: int = 0
	var hits: int = 0
	# Windows round the lone wall, the block, the row of three and the diagonal pair (cell centres
	# plus 48 px), each swept at a sample every half px on both axes (four to a px of area).
	for at: Vector2i in [Vector2i(2, 1), Vector2i(6, 3), Vector2i(2, 6), Vector2i(8, 8)]:
		var window: Rect2 = Rect2(
			IsoProjection.cell_centre_px(at.x, at.y) - Vector2(64, 80), Vector2(128, 128)
		)
		for iy: int in int(window.size.y) * 2:
			for ix: int in int(window.size.x) * 2:
				var p: Vector2 = window.position + Vector2(ix + 0.37, iy + 0.41) / 2.0
				var twin: bool = WallCover.covered(raised, COLS, p, -100000.0)
				assert_bool(twin).is_equal(_swept(raised, p))
				hits += 1 if twin else 0
				checked += 1
	assert_int(checked).is_greater(60000)
	assert_int(hits).is_greater(5000)


func test_a_cell_covers_only_a_unit_that_sorts_before_it() -> void:
	var raised: PackedByteArray = _raised()
	# The lone wall (2, 1): centre y (2 + 1 + 1) * 16 = 64. A unit above that line is covered by it.
	var p: Vector2 = IsoProjection.cell_centre_px(2, 1) + Vector2(0.0, -10.0)
	assert_bool(WallCover.covered(raised, COLS, p, 63.0)).is_true()
	assert_bool(WallCover.covered(raised, COLS, p, 64.0)).is_false()  # Equal keys: no cover.
	assert_bool(WallCover.covered(raised, COLS, p, 200.0)).is_false()


func test_ground_at_gives_the_wall_cell_on_a_top_and_on_a_face() -> void:
	var raised: PackedByteArray = _raised()
	var centre: Vector2 = IsoProjection.cell_centre_px(2, 1)
	# On the wall's top, 32 px up from its ground diamond.
	var top: Vector2 = centre + Vector2(0.0, -32.0)
	assert_that(WallCover.ground_at(raised, COLS, top)).is_equal(Vector2i(2500, 1500))
	# On its face, below the ground diamond's front edges (the face runs 32 px down from them).
	var face: Vector2 = centre + Vector2(10.0, 5.0)
	assert_that(WallCover.ground_at(raised, COLS, face)).is_equal(Vector2i(2500, 1500))
	# The ground the wall hides: behind its top, the flat inverse says a cell further back.
	assert_that(IsoProjection.px_to_ground(top)).is_not_equal(Vector2i(2500, 1500))


func test_ground_at_is_the_flat_inverse_away_from_walls() -> void:
	var raised: PackedByteArray = _raised()
	for p: Vector2 in [
		Vector2(0.0, 40.0), IsoProjection.cell_centre_px(9, 3), Vector2(-120.0, 200.0)
	]:
		assert_bool(WallCover.front_cell(raised, COLS, p) < 0).is_true()
		assert_that(WallCover.ground_at(raised, COLS, p)).is_equal(IsoProjection.px_to_ground(p))
	assert_that(WallCover.ground_at(PackedByteArray(), 0, Vector2(10.0, 90.0))).is_equal(
		IsoProjection.px_to_ground(Vector2(10.0, 90.0))
	)


func test_the_front_most_cell_wins_over_the_ones_behind_it() -> void:
	var raised: PackedByteArray = _raised()
	# The 2 x 2 block (6, 3) to (7, 4): the top of (6, 3) shows its own cell, and the ground diamond
	# of (6, 3) lies under the top of (7, 4), a tile down the diagonal, which sorts after it.
	var top: Vector2 = IsoProjection.cell_centre_px(6, 3) + Vector2(0.0, -32.0)
	assert_int(WallCover.front_cell(raised, COLS, top)).is_equal(3 * COLS + 6)
	var under: Vector2 = IsoProjection.cell_centre_px(6, 3)
	assert_int(WallCover.front_cell(raised, COLS, under)).is_equal(4 * COLS + 7)
	assert_that(WallCover.ground_at(raised, COLS, under)).is_equal(Vector2i(7500, 4500))


func test_the_near_wall_bytes_mark_a_cell_with_a_wall_at_one_of_seven_offsets() -> void:
	var raised: PackedByteArray = _raised()
	var near: PackedByteArray = WallCover.near_bytes(raised, COLS)
	assert_int(near.size()).is_equal(COLS * ROWS)
	# The lone wall at (2, 1) is the near-wall of the cells that have it at an offset of NEAR.
	var marked: Array[Vector2i] = []
	for offset: Vector2i in WallCover.NEAR:
		marked.append(Vector2i(2, 1) - offset)
	assert_int(WallCover.NEAR.size()).is_equal(7)
	for cell: Vector2i in marked:
		if cell.y >= 0:  # One of the seven is above the map's first row.
			assert_int(near[cell.y * COLS + cell.x]).is_equal(1)
	# A cell with no wall at any offset, and the wall's own cell (no offset is zero).
	assert_int(near[11 * COLS + 11]).is_equal(0)
	assert_int(near[10 * COLS + 10]).is_equal(0)
	assert_int(near[1 * COLS + 2]).is_equal(0)  # (2, 1) itself, alone: nothing at an offset.
	# And brute force, for every cell.
	for row: int in ROWS:
		for col: int in COLS:
			var want: bool = false
			for offset: Vector2i in WallCover.NEAR:
				want = want or WallKit.is_raised(raised, COLS, col + offset.x, row + offset.y)
			assert_int(near[row * COLS + col]).is_equal(1 if want else 0)


## Whether a prism of the map covers `p`, found without the twin's three cells: some height h in
## 0 to one rise puts `p` plus h px down inside a raised cell's ground diamond, which is the
## vertical segment from `p` down by the rise meeting the diamond.
@warning_ignore("integer_division")
func _swept(raised: PackedByteArray, p: Vector2) -> bool:
	for cell: int in raised.size():
		if raised[cell] == 0:
			continue
		var centre: Vector2 = IsoProjection.cell_centre_px(cell % COLS, cell / COLS)
		var reach: float = 1.0 - absf(p.x - centre.x) / IsoProjection.HALF_W
		if reach <= 0.0:
			continue
		var low: float = centre.y - IsoProjection.HALF_H * reach
		var high: float = centre.y + IsoProjection.HALF_H * reach
		if p.y <= high and p.y + IsoProjection.HALF_H * 2.0 >= low:
			return true
	return false


func _raised() -> PackedByteArray:
	var raised: PackedByteArray = PackedByteArray()
	raised.resize(COLS * ROWS)
	for row: int in ROWS:
		for col: int in COLS:
			raised[row * COLS + col] = 1 if MAP[row][col] == "#" else 0
	return raised


func test_look_b_keeps_the_team_hue_lowers_the_alpha_and_hatches_every_fourth_diagonal() -> void:
	var team: Color = Color8(255, 148, 70)
	var grey: Color = Color8(128, 128, 128)
	var off_line: Vector2 = Vector2(10.5, 11.5)  # x + y = 22: not a hatch line.
	var on_line: Vector2 = Vector2(10.5, 9.5)  # x + y = 20, a multiple of 4: a hatch line.
	var a: Color = WallCover.silhouette_colour(team, WallCover.LOOK_A, off_line)
	var b: Color = WallCover.silhouette_colour(team, WallCover.LOOK_B, off_line)
	var hatched: Color = WallCover.silhouette_colour(team, WallCover.LOOK_B, on_line)
	assert_float(b.h).is_equal_approx(team.h, 0.001)  # The hue of the team texel survives.
	assert_float(b.s).is_equal_approx(team.s, 0.001)
	assert_that(Vector3(b.r, b.g, b.b)).is_equal(Vector3(team.r, team.g, team.b))
	assert_float(a.a).is_equal_approx(WallCover.ALPHA_A, 0.001)
	assert_float(b.a).is_equal_approx(0.55, 0.001)
	assert_float(b.a).is_less(a.a)
	assert_float(hatched.a).is_equal_approx(0.25, 0.001)
	# One line in four: the diagonals x + y = 20 .. 23 carry exactly one hatch line.
	var lines: int = 0
	for sum: int in range(20, 24):
		var texel: Color = WallCover.silhouette_colour(team, WallCover.LOOK_B, Vector2(sum, 0.0))
		lines += 1 if texel.a == WallCover.HATCH_ALPHA else 0
	assert_int(lines).is_equal(1)
	# Any other texel is the dark body colour at the same alphas; look A has no hatch.
	var body: Color = WallCover.silhouette_colour(grey, WallCover.LOOK_B, off_line)
	assert_that(Vector3(body.r, body.g, body.b)).is_equal(
		Vector3(WallCover.BODY.r, WallCover.BODY.g, WallCover.BODY.b)
	)
	assert_float(body.a).is_equal_approx(0.55, 0.001)
	assert_float(WallCover.silhouette_colour(team, WallCover.LOOK_A, on_line).a).is_equal_approx(
		WallCover.ALPHA_A, 0.001
	)
	(
		assert_float(WallCover.silhouette_colour(Color(1, 0, 0, 0.5), WallCover.LOOK_B, off_line).a)
		. is_equal_approx(0.275, 0.001)
	)
