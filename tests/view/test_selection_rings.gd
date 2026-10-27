extends GdUnitTestSuite
## The selection rings (plan P114b, ADR 0023 sections 1 to 3) in both scenes at the six sizes (the
## three landscape sizes and their portrait twins): a ring is the 2:1 ground ellipse
## `ui/selection_ellipse.svg` at the absolute z 3, under the sorted sprites and over the shadows,
## sized by one scale of the texture whose horizontal centre-line semi-axis is 72 px, so that its
## horizontal semi-axis is the larger of the selection radius's ellipse (`IsoProjection.ellipse_px`,
## padded 50 milli) and 18 dp on the screen, and its vertical one is half of it. The circle texture
## of the top-down view is not used by the layer any more. Sizes and dp are those of the window
## (`UiScale`), which a turn of the window changes.

const ArenaRig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ELLIPSE: String = "res://assets/art/svg/ui/selection_ellipse.svg"
const TEX_RX_PX: float = 72.0  ## The ellipse's horizontal centre-line semi-axis, STYLE.md.
const TEX_RY_PX: float = 36.0  ## And its vertical one: 2:1.
const RING_MIN_DP: float = 18.0
const PAD_MILLI: int = 50

var _window_size_before: Vector2i
var _calls: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	CommandQueue.clear()
	_calls.clear()


func test_a_ring_is_the_ground_ellipse_at_z_3_in_the_main_scene_at_every_size() -> void:
	var main: Node2D = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	add_child(main)
	await await_idle_frame()
	(main.get_node("MatchRunner") as MatchRunner).paused = true
	await _check_sizes(main.get_node("UnitLayer"), main.get_node("Camera"))


func test_a_ring_is_the_ground_ellipse_at_z_3_in_the_perf_arena_at_every_size() -> void:
	var arena: Node2D = ArenaRig.open(self, _calls)
	await await_idle_frame()
	await _check_sizes(arena.unit_layer, arena.camera)
	ArenaRig.close(self, arena)


func test_the_circle_texture_is_no_longer_the_layers() -> void:
	assert_str(UnitLayer.RING_ART).is_equal(ELLIPSE)
	assert_float(UnitLayer.RING_TEX_RX_PX).is_equal(TEX_RX_PX)
	assert_bool("RING_TEX_RADIUS_PX" in UnitLayer).is_false()
	var source: String = FileAccess.get_file_as_string("res://game/view/UnitLayer.gd")
	assert_bool(source.contains("selection_ring")).is_false()


## At each size the layer's first unit is selected and its ring is read back.
func _check_sizes(layer: UnitLayer, camera: RtsCamera) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		camera.zoom = Vector2.ONE
		layer.sync_rows()
		var snap: MatchSnapshot = layer.runner.snapshot
		var row: int = 0
		while layer.rig(row) == null:
			row += 1
		layer.set_selected(PackedInt32Array([snap.unit_id[row]]))
		for zoom: float in [0.75, 1.0, 1.5]:
			camera.zoom = Vector2(zoom, zoom)
			layer._process(0.0)
			_assert_ellipse(layer, row, zoom, "%s at zoom %s" % [size, zoom])
		layer.set_selected(PackedInt32Array())


func _assert_ellipse(layer: UnitLayer, row: int, zoom: float, note: String) -> void:
	var snap: MatchSnapshot = layer.runner.snapshot
	var rig: Node2D = layer.rig(row)
	var ring: Sprite2D = rig.get_node("Ring")
	assert_str(ring.texture.resource_path).override_failure_message(note).is_equal(ELLIPSE)
	assert_int(ring.z_index).override_failure_message(note).is_equal(WorldSort.Z_RING)
	assert_int(ring.z_index).is_equal(3)
	assert_bool(ring.z_as_relative).override_failure_message(note).is_false()
	assert_bool(layer.is_ringed(row)).override_failure_message(note).is_true()
	assert_that(ring.position).is_equal(Vector2.ZERO)  # On the unit's ground point.
	# One scale for the texture: 72 px across from the centre is `radius`, 36 px down is half of it.
	assert_float(ring.scale.y).override_failure_message(note).is_equal(ring.scale.x)
	assert_float(ring.scale.x * TEX_RX_PX).override_failure_message(note).is_equal_approx(
		ring.radius, 0.001
	)
	assert_float(ring.scale.y * TEX_RY_PX).override_failure_message(note).is_equal_approx(
		ring.radius * 0.5, 0.001
	)
	# The larger of the selection radius's ellipse and the 18 dp minimum (dp / zoom in world px).
	var semi: float = (
		IsoProjection.ellipse_px(snap.type_selection_radius[snap.type_index[row]] + PAD_MILLI).x
	)
	var least: float = RING_MIN_DP * UiScale.base_px_per_dp() / zoom
	assert_float(ring.radius).override_failure_message(note).is_equal_approx(
		maxf(semi, least), 0.001
	)
	assert_float(ring.radius * zoom).override_failure_message(note).is_greater_equal(
		UiScale.dp(RING_MIN_DP) - 0.001
	)
	# Over the shadow and under the sprites in the rig, and under the sorted world in z.
	assert_int(ring.get_index()).is_equal(1 if rig.has_node("Shadow") else 0)
	assert_int(ring.z_index).is_less(WorldSort.Z_SORT)
	assert_int(ring.z_index).is_greater(WorldSort.Z_SHADOW)
