extends GdUnitTestSuite
## Picker.pick_building (plan P115b, ADR 0023 section 3) on hand-built snapshots: the silhouette
## (the footprint's diamond plus the rectangle between its side corners up to the picture's top),
## the box a shape under 48 dp grows to, the building drawn in front wins an overlap, and with own
## units selected an enemy building wins over an own one. The shapes are those of the real layer in
## test_building_picking.gd. A 3x3 Headquarters at zoom 1 is half 96 x 48 and 140 px tall above the
## corners, so its box is 192 wide and 188 high; MIN is a tenth of that, which grows nothing.

const MIN: float = 10.0
const HQ_HALF: Vector2 = Vector2(96, 48)
const HQ_RISE: float = 140.0
const AT: Vector2 = Vector2(500, 400)


func test_a_point_is_in_the_diamond_or_in_the_rectangle_above_its_side_corners() -> void:
	var snap: PickSnapshot = _snap([_hq(1, 1, AT, 400.0)])
	var hits: Array[Vector2] = [
		AT,
		AT + Vector2(0, 47),  # Just above the bottom corner.
		AT + Vector2(95, 0),  # Just inside a side corner.
		AT + Vector2(60, 15),  # Under the corners' line, inside the diamond's lower edge.
		AT + Vector2(-95, -139),  # The top corner of the rectangle: not a footprint cell.
		AT + Vector2(90, -100),
		AT + Vector2(0, -139),
	]
	var misses: Array[Vector2] = [
		AT + Vector2(0, 49),  # Under the bottom corner.
		AT + Vector2(97, 0),  # Beside a side corner.
		AT + Vector2(60, 25),  # Under the corners' line, outside the diamond's lower edge.
		AT + Vector2(-60, 25),
		AT + Vector2(0, -141),  # Over the picture's top.
		AT + Vector2(97, -100),  # Beside the rectangle.
		Vector2(0, 0),
	]
	for point: Vector2 in hits:
		(
			assert_int(Picker.pick_building(snap, point, 1, false, MIN))
			. override_failure_message(str(point - AT))
			. is_equal(0)
		)
	for point: Vector2 in misses:
		(
			assert_int(Picker.pick_building(snap, point, 1, false, MIN))
			. override_failure_message(str(point - AT))
			. is_equal(-1)
		)


func test_the_silhouette_is_not_the_footprint_box() -> void:
	# A tap on the overhang, in the rectangle and outside the footprint's cells, picks the building;
	# a tap in the corner of the footprint's bounding box, outside the diamond, does not.
	var snap: PickSnapshot = _snap([_hq(1, 1, AT, 400.0)])
	assert_int(Picker.pick_building(snap, AT + Vector2(0, -120), 1, false, MIN)).is_equal(0)
	assert_int(Picker.pick_building(snap, AT + Vector2(80, 30), 1, false, MIN)).is_equal(-1)
	assert_int(Picker.pick_building(snap, AT + Vector2(-80, 30), 1, false, MIN)).is_equal(-1)


func test_a_snapshot_with_no_building_picks_none() -> void:
	assert_int(Picker.pick_building(PickSnapshot.new(), AT, 1, true, MIN)).is_equal(-1)
	assert_int(PickSnapshot.new().building_count()).is_equal(0)


func test_a_shape_under_48_dp_grows_to_the_box_of_that_size_about_its_middle() -> void:
	# A 1x1 defence at zoom 0.75 on a 1.75 px per dp phone: half 24 x 12, 30 px of picture above
	# the corners. Its box is 48 wide and 42 high, under the 84 px that 48 dp make.
	var small: PickSnapshot = _snap([_row(1, 1, AT, Vector2(24, 12), 30.0, 100.0)])
	var m: float = 42.0
	# Middle of the shape's own box: (12 - 30) / 2 = 9 px above the centre; the box is 84 x 84.
	assert_int(Picker.pick_building(small, AT + Vector2(41, -9 + 41), 1, false, m)).is_equal(0)
	assert_int(Picker.pick_building(small, AT + Vector2(-41, -9 - 41), 1, false, m)).is_equal(0)
	assert_int(Picker.pick_building(small, AT + Vector2(43, -9), 1, false, m)).is_equal(-1)
	assert_int(Picker.pick_building(small, AT + Vector2(0, -9 + 43), 1, false, m)).is_equal(-1)
	assert_int(Picker.pick_building(small, AT + Vector2(0, -9 - 43), 1, false, m)).is_equal(-1)
	# One side short is enough: a building 200 wide and 30 high grows in height only.
	var flat: PickSnapshot = _snap([_row(1, 1, AT, Vector2(100, 15), 15.0, 100.0)])
	assert_int(Picker.pick_building(flat, AT + Vector2(99, 41), 1, false, m)).is_equal(0)
	assert_int(Picker.pick_building(flat, AT + Vector2(99, 43), 1, false, m)).is_equal(-1)
	assert_int(Picker.pick_building(flat, AT + Vector2(101, 0), 1, false, m)).is_equal(-1)


func test_a_building_drawn_in_front_wins_where_two_overlap_whatever_the_order_listed() -> void:
	var back: Array = _hq(4, 1, AT, 380.0)
	var front: Array = _hq(9, 1, AT + Vector2(60, 40), 420.0)
	for order: Array in [[back, front], [front, back]]:
		var snap: PickSnapshot = _snap(order)
		var both: Vector2 = AT + Vector2(50, 20)  # Inside both silhouettes.
		assert_int(snap.building_ids[Picker.pick_building(snap, both, 1, false, MIN)]).is_equal(9)
		var back_only: Vector2 = AT + Vector2(-80, -100)
		(
			assert_int(snap.building_ids[Picker.pick_building(snap, back_only, 1, false, MIN)])
			. is_equal(4)
		)
	# The same sort key: the later one in the tree, the higher id, is in front.
	for order: Array in [
		[_hq(4, 1, AT, 400.0), _hq(9, 1, AT, 400.0)], [_hq(9, 1, AT, 400.0), _hq(4, 1, AT, 400.0)]
	]:
		var snap: PickSnapshot = _snap(order)
		assert_int(snap.building_ids[Picker.pick_building(snap, AT, 1, false, MIN)]).is_equal(9)


func test_the_front_building_wins_even_when_it_is_an_enemy_unless_own_units_are_selected() -> void:
	var back_enemy: Array = _hq(4, 2, AT, 380.0)
	var front_own: Array = _hq(9, 1, AT + Vector2(60, 40), 420.0)
	var snap: PickSnapshot = _snap([back_enemy, front_own])
	var both: Vector2 = AT + Vector2(50, 20)
	# Nothing selected: what is drawn in front is what the finger gets (the enemy one for its info).
	assert_int(snap.building_ids[Picker.pick_building(snap, both, 1, false, MIN)]).is_equal(9)
	# Own units selected: an enemy building wins over an own one, to be attacked.
	assert_int(snap.building_ids[Picker.pick_building(snap, both, 1, true, MIN)]).is_equal(4)
	# Two enemy buildings with units selected: the front one again.
	var two: PickSnapshot = _snap([_hq(4, 2, AT, 380.0), _hq(9, 2, AT + Vector2(60, 40), 420.0)])
	assert_int(two.building_ids[Picker.pick_building(two, both, 1, true, MIN)]).is_equal(9)
	# An enemy building alone is a hit with nothing selected: the caller decides it is for info.
	var lone: PickSnapshot = _snap([back_enemy])
	assert_int(Picker.pick_building(lone, AT, 1, false, MIN)).is_equal(0)
	assert_int(Picker.pick_building(lone, AT, 2, false, MIN)).is_equal(0)  # Player 2's own.


## A 3x3 Headquarters row: id, owner, centre and sort key.
func _hq(id: int, owner_id: int, centre: Vector2, key: float) -> Array:
	return _row(id, owner_id, centre, HQ_HALF, HQ_RISE, key)


func _row(id: int, owner_id: int, centre: Vector2, half: Vector2, rise: float, key: float) -> Array:
	return [id, owner_id, centre, half, rise, key]


func _snap(rows: Array) -> PickSnapshot:
	var snap: PickSnapshot = PickSnapshot.new()
	for row: Array in rows:
		snap.building_ids.append(row[0])
		snap.building_owners.append(row[1])
		snap.building_centres.append(row[2])
		snap.building_half.append(row[3])
		snap.building_rise.append(row[4])
		snap.building_keys.append(row[5])
	return snap
