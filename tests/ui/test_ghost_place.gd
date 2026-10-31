extends GdUnitTestSuite
## The placement function of the check mark and the X (`GhostControls.place`, plan P86c, ADR 0024
## section 10) on crafted rects, without a scene: a column right of the silhouette box
## `ghost_grab_dp` + 8 dp out, left of it when the right does not fit, a row above it when neither
## does, never below, slid along its side to the nearest place inside the allowed rect and clear of
## the HUD, and the right column clamped into the allowed rect when nothing fits; it never covers
## the grab ring. The buttons in the main scene are tests/ui/test_ghost_controls.gd's.

## 2 px per dp, so a button is 128 px, the column 128 x 288 px (two buttons and 16 dp between) and
## the gap `ghost_grab_dp` + 8 dp = 64 px.
const DP: float = 2.0
const GRAB_DP: float = 24.0
const COLUMN: Vector2 = Vector2(128.0, 288.0)
const ROW: Vector2 = Vector2(288.0, 128.0)
const GAP: float = 64.0
const BOX: Rect2 = Rect2(400.0, 300.0, 200.0, 150.0)  ## Centre (500, 375).
const ROOM: Rect2 = Rect2(0.0, 0.0, 1000.0, 800.0)


func test_the_column_is_right_of_the_box_one_gap_out_and_centred_on_it() -> void:
	assert_float(GhostControls.ACTION_DP).is_equal(64.0)
	var group: Rect2 = GhostControls.place(BOX, ROOM, _none(), DP, GRAB_DP)
	assert_that(group).is_equal(Rect2(Vector2(BOX.end.x + GAP, 375.0 - 144.0), COLUMN))


func test_the_column_slides_along_the_side_to_stay_inside_the_allowed_rect() -> void:
	var high: Rect2 = Rect2(400.0, 20.0, 200.0, 40.0)
	var low: Rect2 = Rect2(400.0, 700.0, 200.0, 50.0)
	assert_that(GhostControls.place(high, ROOM, _none(), DP, GRAB_DP)).is_equal(
		Rect2(Vector2(high.end.x + GAP, 0.0), COLUMN)
	)
	assert_that(GhostControls.place(low, ROOM, _none(), DP, GRAB_DP)).is_equal(
		Rect2(Vector2(low.end.x + GAP, ROOM.end.y - COLUMN.y), COLUMN)
	)


func test_near_the_right_edge_the_column_flips_to_the_left() -> void:
	var box: Rect2 = Rect2(800.0, 300.0, 100.0, 100.0)
	var group: Rect2 = GhostControls.place(box, ROOM, _none(), DP, GRAB_DP)
	assert_that(group).is_equal(
		Rect2(Vector2(box.position.x - GAP - COLUMN.x, 350.0 - 144.0), COLUMN)
	)


func test_above_the_box_a_row_when_neither_side_fits() -> void:
	var narrow: Rect2 = Rect2(0.0, 0.0, 300.0, 800.0)  # A side needs 64 + 128 px and more.
	var box: Rect2 = Rect2(80.0, 400.0, 100.0, 100.0)
	var group: Rect2 = GhostControls.place(box, narrow, _none(), DP, GRAB_DP)
	# A row, the check mark left of the X; its bottom edge a gap above the box, slid inside.
	assert_that(group).is_equal(Rect2(Vector2(0.0, box.position.y - GAP - ROW.y), ROW))
	assert_float(group.size.x).is_greater(group.size.y)


func test_never_below_the_box_where_nothing_fits_the_right_column_is_clamped() -> void:
	# 260 px is less than the column's 288: no side fits; above needs 192 px over the box at the
	# top. Below the box would fit (a row from 84 to 212), and it is not a candidate.
	var short: Rect2 = Rect2(0.0, 0.0, 1000.0, 260.0)
	var box: Rect2 = Rect2(400.0, 0.0, 100.0, 20.0)
	var group: Rect2 = GhostControls.place(box, short, _none(), DP, GRAB_DP)
	assert_that(group).is_equal(Rect2(Vector2(box.end.x + GAP, 0.0), COLUMN))
	var corner: Rect2 = Rect2(900.0, 100.0, 80.0, 40.0)  # The clamp keeps it inside, too.
	var clamped: Rect2 = GhostControls.place(
		corner, Rect2(0.0, 0.0, 1000.0, 200.0), _none(), DP, 24.0
	)
	assert_that(clamped).is_equal(Rect2(Vector2(1000.0 - COLUMN.x, 0.0), COLUMN))


func test_a_hud_rect_on_the_column_slides_it_to_the_nearest_free_place() -> void:
	var over: Array[Rect2] = [Rect2(664.0, 200.0, 300.0, 100.0)]
	# The column wants y 231..519: above the rect there is no room (-88), below it from y 300.
	assert_that(GhostControls.place(BOX, ROOM, over, DP, GRAB_DP)).is_equal(
		Rect2(Vector2(664.0, 300.0), COLUMN)
	)
	var middle: Array[Rect2] = [Rect2(664.0, 400.0, 300.0, 50.0)]
	# Above it from y 112 (119 away), below it from y 450 (219 away): the nearer.
	assert_that(GhostControls.place(BOX, ROOM, middle, DP, GRAB_DP)).is_equal(
		Rect2(Vector2(664.0, 112.0), COLUMN)
	)
	# A rect that merely touches the column's edge is not in the way.
	var touching: Array[Rect2] = [Rect2(792.0, 231.0, 100.0, 288.0)]
	assert_that(GhostControls.place(BOX, ROOM, touching, DP, GRAB_DP).position).is_equal(
		Vector2(664.0, 231.0)
	)


func test_a_hud_that_covers_the_right_side_sends_the_column_left_and_both_sides_the_row_above(
) -> void:
	var right: Rect2 = Rect2(600.0, 0.0, 400.0, 800.0)
	var left: Rect2 = Rect2(0.0, 0.0, 300.0, 800.0)
	var one_side: Array[Rect2] = [right]
	assert_that(GhostControls.place(BOX, ROOM, one_side, DP, GRAB_DP)).is_equal(
		Rect2(Vector2(BOX.position.x - GAP - COLUMN.x, 231.0), COLUMN)
	)
	var both: Array[Rect2] = [Rect2(700.0, 0.0, 300.0, 800.0), left]
	assert_that(GhostControls.place(BOX, ROOM, both, DP, GRAB_DP)).is_equal(
		Rect2(Vector2(356.0, BOX.position.y - GAP - ROW.y), ROW)
	)
	# No HUD rect with an area counts: an empty rect is a hidden control.
	var hidden: Array[Rect2] = [Rect2(), Rect2(664.0, 300.0, 0.0, 0.0)]
	assert_that(GhostControls.place(BOX, ROOM, hidden, DP, GRAB_DP).position).is_equal(
		Vector2(BOX.end.x + GAP, 231.0)
	)


func test_the_group_never_covers_the_grab_ring_or_leaves_the_allowed_rect() -> void:
	var hud: Array[Rect2] = [Rect2(0.0, 0.0, 200.0, 120.0), Rect2(800.0, 700.0, 200.0, 100.0)]
	for x: float in range(60, 900, 120):
		for y: float in range(60, 700, 120):
			var box: Rect2 = Rect2(x, y, 120.0, 90.0)
			var group: Rect2 = GhostControls.place(box, ROOM, hud, DP, GRAB_DP)
			var note: String = "box %s, group %s" % [box, group]
			assert_bool(ROOM.encloses(group)).override_failure_message(note).is_true()
			var ring: Rect2 = box.grow(GRAB_DP * DP)
			assert_bool(group.intersects(ring)).override_failure_message(note).is_false()
			for part: Rect2 in hud:
				assert_bool(group.intersects(part)).override_failure_message(note).is_false()


func _none() -> Array[Rect2]:
	return []
