extends GdUnitTestSuite
## The selection ring and the health bar of a selected flyer (plan P244, ADR 0036 section 15):
## `AirLayer` rings a selected flyer on the ground under its shadow, as `UnitLayer` rings a ground
## unit, sized for the dp and the zoom; the ring goes with the selection; `HealthBarLayer` draws a
## selected flyer's bar above its lifted hull and none for one that is not selected. Own fighter:
## unit 3 (row 2) at tile (8, 8); enemy drone: unit 4.

const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")

var _runner: MatchRunner
var _layer: AirLayer
var _camera: RtsCamera
var _bars: HealthBarLayer


func before_test() -> void:
	_runner = auto_free(Air.runner())
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(Air.layer(self, _runner))
	_layer.reveal_enemies = true
	var units: UnitLayer = auto_free(UnitLayer.new())
	units.runner = _runner
	units.camera = _camera
	add_child(units)
	units.set_process(false)
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = units
	_bars.air_layer = _layer
	add_child(_bars)
	_bars.set_process(false)
	_layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_a_selected_flyer_wears_a_ring_on_the_ground_that_goes_with_the_selection() -> void:
	assert_bool(_layer.is_ringed(Air.FIGHTER_ID)).is_false()
	_layer.set_selected(PackedInt32Array([Air.FIGHTER_ID]))
	_layer._process(0.0)
	assert_bool(_layer.is_ringed(Air.FIGHTER_ID)).is_true()
	assert_bool(_layer.is_ringed(Air.DRONE_ID)).is_false()
	var rig: AirLayer.Rig = _layer.rig_of(Air.FIGHTER_ID)
	var ring: UnitLayer.Ring = rig.ring
	assert_vector(ring.global_position).is_equal_approx(rig.global_position, Vector2(0.01, 0.01))
	assert_int(ring.z_index).is_equal(WorldSort.Z_RING)
	assert_bool(ring.z_as_relative).is_false()
	var unit: float = UiScale.base_px_per_dp() / _layer.get_canvas_transform().get_scale().x
	assert_float(ring.radius).is_greater_equal(UnitLayer.RING_MIN_DP * unit - 0.01)
	assert_float(ring.scale.x * UnitLayer.RING_TEX_RX_PX).is_equal_approx(ring.radius, 0.01)
	_layer.set_selected(PackedInt32Array())
	assert_bool(_layer.is_ringed(Air.FIGHTER_ID)).is_false()


func test_the_ring_follows_a_flyer_that_arrives_in_the_selection_after_the_rows_changed() -> void:
	_layer.set_selected(PackedInt32Array([Air.FIGHTER_ID, Air.DRONE_ID]))
	_runner.snapshot.rows_version += 1  # A merge: the rigs are looked up again by id.
	_layer._process(0.0)
	assert_bool(_layer.is_ringed(Air.FIGHTER_ID)).is_true()
	assert_bool(_layer.is_ringed(Air.DRONE_ID)).is_true()


func test_a_selected_flyer_has_a_bar_above_its_hull_and_an_unselected_one_none() -> void:
	_runner.world.hp[2] -= 5
	_runner.run_ticks(1)
	Buildings.see(_runner.snapshot, 1, [Vector2i(8, 8)])
	_layer._process(0.0)
	_bars._process(0.0)
	assert_int(_bars.bar_count()).is_equal(0)  # Hurt, not selected: no bar for a flyer.
	_layer.set_selected(PackedInt32Array([Air.FIGHTER_ID]))
	_layer._process(0.0)
	_bars._process(0.0)
	assert_int(_bars.bar_count()).is_equal(1)
	assert_int(_bars.bar_row(0)).is_equal(2)
	var rig: AirLayer.Rig = _layer.rig_of(Air.FIGHTER_ID)
	var bar: Rect2 = _bars.rect_at(_bars.bar_first_rect(0))
	assert_float(bar.end.y).is_less(rig.position.y - rig.lift)  # Over the hull, not the ground.
	assert_float(_layer.bar_lift_px(2)).is_greater(rig.lift)
