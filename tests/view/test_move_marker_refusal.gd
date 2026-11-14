extends GdUnitTestSuite
## The two marks of P244 on `MoveMarkerLayer`: the diamond of an attack on a building rings its
## footprint (a bomber's target) and is never smaller than the plain diamond, and the diamond of a
## refused tap (an enemy none of the selected units can hit) shakes sideways, settles on its point
## and fades with the others.

var _markers: MoveMarkerLayer


func before_test() -> void:
	_markers = auto_free(MoveMarkerLayer.new())
	_markers.clock = func() -> int: return 0
	add_child(_markers)


func test_the_ring_is_as_wide_as_the_footprint_and_never_smaller_than_the_plain_diamond() -> void:
	_markers.show_target(Vector2.ZERO)
	var plain: MoveMarkerLayer.Mark = _markers.get_child(0) as MoveMarkerLayer.Mark
	assert_float(_half(plain)).is_equal_approx(MoveMarkerLayer.DIAMOND_PX, 0.01)
	_markers.show_ring(Vector2.ZERO, 96.0)
	var ring: MoveMarkerLayer.Mark = _markers.get_child(1) as MoveMarkerLayer.Mark
	assert_float(_half(ring)).is_equal_approx(96.0, 0.01)
	_markers.show_ring(Vector2.ZERO, 10.0)  # A small building: the plain size.
	assert_float(_half(_markers.get_child(2) as MoveMarkerLayer.Mark)).is_equal_approx(
		MoveMarkerLayer.DIAMOND_PX, 0.01
	)


func test_a_refused_mark_swings_off_its_point_and_comes_back_while_a_plain_one_stands_still(
) -> void:
	var at: Vector2 = Vector2(50.0, 80.0)
	_markers.show_refused(at)
	var mark: MoveMarkerLayer.Mark = _markers.get_child(0) as MoveMarkerLayer.Mark
	assert_bool(mark.visible).is_true()
	mark.pose(MoveMarkerLayer.SHAKE_MS * 0.25, 1000.0, 1.0)  # A quarter swing: the far point.
	var dp: float = UiScale.base_px_per_dp()
	assert_float(mark.position.x - at.x).is_greater(0.5 * MoveMarkerLayer.SHAKE_DP * dp)
	assert_float(mark.position.y).is_equal(at.y)
	mark.pose(MoveMarkerLayer.SHAKE_MS * 0.75, 1000.0, 1.0)  # And back past it the other way.
	assert_float(mark.position.x - at.x).is_less(0.0)
	mark.pose(1000.0, 1000.0, 1.0)  # Over: settled.
	assert_vector(mark.position).is_equal_approx(at, Vector2(0.01, 0.01))
	_markers.show_target(at)
	var plain: MoveMarkerLayer.Mark = _markers.get_child(1) as MoveMarkerLayer.Mark
	plain.pose(MoveMarkerLayer.SHAKE_MS * 0.25, 1000.0, 1.0)
	assert_vector(plain.position).is_equal(at)


## Half the diamond's width in world px, once it has settled.
func _half(mark: MoveMarkerLayer.Mark) -> float:
	mark.pose(10000.0, 100000.0, 1.0)
	var flash: Line2D = mark.get_child(4) as Line2D
	return flash.get_point_position(0).x * mark.scale.x
