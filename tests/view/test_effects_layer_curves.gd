extends GdUnitTestSuite
## The look of each effect in time (plan P44b, assets/art/STYLE.md "Combat effects"): the alpha
## and the size of a flash, a tracer, a puff, a burst and a fade at their ages, the tracer's width
## in dp at every zoom on the three screens (1280x720, 2400x1080 and 2048x1536), and the atlas
## regions. The events and the ring are in test_effects_layer.gd. An effect is born at clock 0 and
## a case moves the fake clock to its age and plans a frame; the numbers are STYLE.md's, written
## out here and not read from the layer.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Rig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const ATLAS_PATH: String = "res://assets/art/svg/fx/effects_atlas.svg"
const ALPHA_TOL: float = 0.0001
const SIZE_TOL: float = 0.001
## The three screens, each with its profile and the base px of one dp on it.
const SCREENS: Array[Array] = [
	[Vector2i(1280, 720), &"desktop", 1.0],
	[Vector2i(2400, 1080), &"android_6in", 1.75],
	[Vector2i(2048, 1536), &"web_tablet", 1.25],
]
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]

var _window_size_before: Vector2i
var _now_ms: int = 0
var _runner: MatchRunner
var _layer: EffectsLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Rig.battle()
	_runner.start()
	_make_layer()


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_flash_holds_full_alpha_for_40_ms_then_fades_to_nothing_at_100_ms() -> void:
	_deliver(Rig.shot(Vector2i(5000, 5000), Vector2i(5000, 9000), _weapon(&"tank_cannon")))
	for case: Array in [[0, 1.0], [40, 1.0], [41, 59.0 / 60.0], [70, 0.5], [99, 1.0 / 60.0]]:
		_at(case[0])
		assert_int(_layer.quad_count()).is_equal(1)
		assert_float(_layer.quad_alpha(0)).is_equal_approx(case[1], ALPHA_TOL)
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(32.0, SIZE_TOL)  # No growth.
	_at(100)
	assert_int(_layer.quad_count()).is_equal(0)


func test_a_tracer_fades_colour_by_a_and_outline_by_a_squared_over_120_ms() -> void:
	_deliver(Rig.shot(Vector2i(5000, 5000), Vector2i(9000, 5000), _weapon(&"rifle")))
	_at(0)
	var width: float = _layer.line_width(1)
	for age: int in [0, 30, 60, 90, 119]:
		_at(age)
		var fade: float = 1.0 - age / 120.0  # a, from 1 to 0 over 120 ms.
		assert_int(_layer.line_count()).is_equal(2)
		assert_float(_layer.line_color(1).a).is_equal_approx(fade, ALPHA_TOL)
		assert_float(_layer.line_color(0).a).is_equal_approx(fade * fade, ALPHA_TOL)
		assert_float(_layer.line_color(1).r).is_equal_approx(Color("FFD84D").r, ALPHA_TOL)
		assert_float(_layer.line_color(0).r).is_equal_approx(Color("1C2127").r, ALPHA_TOL)
		assert_float(_layer.line_width(1)).is_equal_approx(width, SIZE_TOL)  # It fades, not thins.
	_at(120)
	assert_int(_layer.line_count()).is_equal(0)


func test_a_puff_grows_then_holds_150_ms_and_fades_by_350_ms() -> void:
	_deliver(Rig.impact(Vector2i(5000, 5000), _weapon(&"tank_cannon")))
	# Eased out over 150 ms (STYLE.md names no time for the growth): 1 - (1 - t)^2 is 0.75 at 75 ms.
	for case: Array in [[0, 24.0, 1.0], [75, 36.0, 1.0], [150, 40.0, 1.0], [250, 40.0, 0.5]]:
		_at(case[0])
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(case[1], SIZE_TOL)
		assert_float(_layer.quad_alpha(0)).is_equal_approx(case[2], ALPHA_TOL)
	_at(349)
	assert_float(_layer.quad_alpha(0)).is_equal_approx(1.0 / 200.0, ALPHA_TOL)
	_at(350)
	assert_int(_layer.quad_count()).is_equal(0)


func test_a_burst_grows_then_holds_350_ms_and_fades_by_600_ms() -> void:
	_deliver(Rig.died(Vector2i(5000, 5000), _type(&"light_tank")))
	for case: Array in [[0, 40.0, 1.0], [75, 70.0, 1.0], [150, 80.0, 1.0], [350, 80.0, 1.0]]:
		_at(case[0])
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(case[1], SIZE_TOL)
		assert_float(_layer.quad_alpha(0)).is_equal_approx(case[2], ALPHA_TOL)
	_at(475)
	assert_float(_layer.quad_alpha(0)).is_equal_approx(0.5, ALPHA_TOL)
	assert_float(_layer.quad_rect(0).size.x).is_equal_approx(80.0, SIZE_TOL)
	_at(599)
	assert_float(_layer.quad_alpha(0)).is_equal_approx(1.0 / 250.0, ALPHA_TOL)
	_at(600)
	assert_int(_layer.quad_count()).is_equal(0)


func test_an_infantry_fade_keeps_24_px_and_goes_from_0_7_to_nothing_over_700_ms() -> void:
	_deliver(Rig.died(Vector2i(5000, 5000), _type(&"rifle_squad")))
	for case: Array in [[0, 0.7], [350, 0.35], [525, 0.175], [699, 0.7 / 700.0]]:
		_at(case[0])
		assert_float(_layer.quad_alpha(0)).is_equal_approx(case[1], ALPHA_TOL)
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(24.0, SIZE_TOL)  # No growth.
	_at(700)
	assert_int(_layer.quad_count()).is_equal(0)


func test_a_flash_is_drawn_over_the_effects_that_are_older_than_it() -> void:
	# The plan is oldest first and a quad is painted over the ones before it.
	_deliver(Rig.died(Vector2i(5000, 5000), _type(&"light_tank")))
	_now_ms = 50
	_deliver(Rig.impact(Vector2i(5000, 5000), _weapon(&"rocket")))
	_now_ms = 80
	_deliver(Rig.shot(Vector2i(5000, 5000), Vector2i(5000, 9000), _weapon(&"tank_cannon")))
	_layer._process(0.0)
	assert_int(_layer.quad_count()).is_equal(3)
	assert_that(_layer.quad_region(0)).is_equal(Rect2(0, 0, 80, 80))  # The burst, the oldest.
	assert_that(_layer.quad_region(1)).is_equal(Rect2(84, 0, 56, 56))
	assert_that(_layer.quad_region(2)).is_equal(Rect2(144, 0, 32, 32))  # The flash, the newest.


func test_the_tracer_keeps_its_dp_width_at_every_zoom_on_every_screen() -> void:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	for screen: Array in SCREENS:
		get_window().size = screen[0]
		UiScale.set_override(UiProfiles.by_name(screen[1]))
		assert_float(UiScale.base_px_per_dp()).is_equal_approx(screen[2], ALPHA_TOL)
		_make_layer()  # It reads the dp that is in force when it enters the tree.
		for zoom: float in ZOOMS:
			camera.zoom = Vector2(zoom, zoom)
			await await_idle_frame()
			_now_ms += 1000
			_deliver(Rig.shot(Vector2i(5000, 5000), Vector2i(9000, 5000), _weapon(&"rifle")))
			_layer._process(0.0)
			var note: String = "%s zoom %s" % [screen[1], zoom]
			# 1.5 dp of colour over 3.5 dp of outline, in world px: a dp is px per dp over zoom.
			(
				assert_float(_layer.line_width(1) * zoom)
				. override_failure_message("colour pass, " + note)
				. is_equal_approx(1.5 * screen[2], SIZE_TOL)
			)
			(
				assert_float(_layer.line_width(0) * zoom)
				. override_failure_message("outline pass, " + note)
				. is_equal_approx(3.5 * screen[2], SIZE_TOL)
			)
			# The flash is 16 world px whatever the screen and the zoom: it grows with the map.
			assert_float(_layer.quad_rect(0).size.x).is_equal_approx(16.0, SIZE_TOL)


func test_the_regions_are_the_atlas_table_of_style_md_and_lie_inside_the_atlas() -> void:
	var atlas: Texture2D = load(ATLAS_PATH)
	assert_that(atlas.get_size()).is_equal(Vector2(176, 84))  # Import scale 0.5 of 352x168.
	var regions: Array[Rect2] = [Rect2(0, 0, 80, 80), Rect2(84, 0, 56, 56), Rect2(144, 0, 32, 32)]
	assert_array(EffectsLayer.REGIONS).is_equal(regions)
	assert_that(EffectsLayer.BURST).is_equal(regions[0])
	assert_that(EffectsLayer.PUFF).is_equal(regions[1])
	assert_that(EffectsLayer.FLASH).is_equal(regions[2])
	assert_that(EffectsLayer.ATLAS).is_equal(atlas)
	var image: Image = atlas.get_image()
	for region: Rect2 in regions:
		assert_bool(Rect2(Vector2.ZERO, atlas.get_size()).encloses(region)).is_true()
		var centre: Vector2i = Vector2i(region.get_center())
		assert_float(image.get_pixelv(centre).a).is_greater(0.9)  # Ink at the centre of a quad.


## A layer on the fake clock and out of the frame loop; the old one goes. It reads the dp that is
## in force now.
func _make_layer() -> void:
	if is_instance_valid(_layer):
		_layer.free()
	_now_ms = 0
	_layer = auto_free(EffectsLayer.new())
	_layer.runner = _runner
	_layer.clock = func() -> int: return _now_ms
	add_child(_layer)
	_layer.set_process(false)


## Delivers `events` as the events of a tick, the way the runner does.
func _deliver(events: PackedInt32Array) -> void:
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)


## The effects of the last tick `age` ms after they were born (at clock 0), planned.
func _at(age: int) -> void:
	_now_ms = age
	_layer._process(0.0)


func _weapon(weapon_id: StringName) -> int:
	return _runner.snapshot.weapon_ids.find(weapon_id)


func _type(type_id: StringName) -> int:
	return _runner.snapshot.type_ids.find(type_id)
