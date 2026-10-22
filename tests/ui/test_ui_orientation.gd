extends GdUnitTestSuite
## The UiOrientation autoload (plan P59, ADR 0015 section 2): the root window's content scale size
## is the project's base size in a landscape window and its transpose in a portrait one, so the
## engine's stretch is the same number for the same device in both orientations and nothing
## shrinks when the phone turns. The flip of every `size_changed` handler is in
## test_ui_orientation_flip.gd.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const SERVICE: String = "res://game/ui/ui_orientation_service.gd"
## The project's base size and its transpose: the first window size of each list has stretch 1.
const LANDSCAPE_BASE: Vector2i = ScreenSizes.LANDSCAPE[0]
const PORTRAIT_BASE: Vector2i = ScreenSizes.PORTRAIT[0]
## Window, base size, stretch scale and the visible rect in base px: the six sizes of ADR 0015
## section 6 (the 6-inch phone, a 4:3 tablet and the base size, each in both orientations).
const SIZES: Array[Dictionary] = [
	{
		"window": ScreenSizes.LANDSCAPE[0],
		"base": LANDSCAPE_BASE,
		"stretch": 1.0,
		"visible": Vector2(1280, 720)
	},
	{
		"window": ScreenSizes.LANDSCAPE[1],
		"base": LANDSCAPE_BASE,
		"stretch": 1.5,
		"visible": Vector2(1600, 720)
	},
	{
		"window": ScreenSizes.LANDSCAPE[2],
		"base": LANDSCAPE_BASE,
		"stretch": 1.6,
		"visible": Vector2(1280, 960)
	},
	{
		"window": ScreenSizes.PORTRAIT[0],
		"base": PORTRAIT_BASE,
		"stretch": 1.0,
		"visible": Vector2(720, 1280)
	},
	{
		"window": ScreenSizes.PORTRAIT[1],
		"base": PORTRAIT_BASE,
		"stretch": 1.5,
		"visible": Vector2(720, 1600)
	},
	{
		"window": ScreenSizes.PORTRAIT[2],
		"base": PORTRAIT_BASE,
		"stretch": 1.6,
		"visible": Vector2(960, 1280)
	},
	# A square window is landscape: min(1000 / 1280, 1000 / 720) = 0.78125 and 1280 base px high.
	{
		"window": Vector2i(1000, 1000),
		"base": LANDSCAPE_BASE,
		"stretch": 0.78125,
		"visible": Vector2(1280, 1280)
	},
]

var _window_size_before: Vector2i
var _seen: Array[Dictionary] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_seen.clear()
	get_window().size = LANDSCAPE_BASE
	await await_idle_frame()


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


## At each size the engine's own stretch and visible rect are the ones of the orientation's base
## size: the visible rect turns and the stretch does not.
func test_the_content_scale_size_and_the_stretch_follow_the_window_at_every_size() -> void:
	for case: Dictionary in SIZES:
		var size: Vector2i = case["window"]
		get_window().size = size
		await await_idle_frame()
		var label: String = str(size)
		assert_that(get_window().content_scale_size).override_failure_message(label).is_equal(
			case["base"]
		)
		var stretch: float = get_window().get_stretch_transform().get_scale().x
		assert_float(stretch).override_failure_message(label).is_equal_approx(
			case["stretch"], 0.0001
		)
		assert_that(get_window().get_visible_rect().size).override_failure_message(label).is_equal(
			case["visible"]
		)
	var service: Node = get_tree().root.get_node_or_null("UiOrientation")
	assert_object(service).is_not_null()
	assert_str(service.get_script().resource_path).is_equal(SERVICE)


## The same phone has the same base px per dp in both orientations (ADR 0015 section 2), here with
## what the engine reports (no override): the stretch is the only part of it that turns.
func test_the_same_phone_has_the_same_base_px_per_dp_in_both_orientations() -> void:
	assert_bool(UiScale.has_override()).override_failure_message("override leaked").is_false()
	var twins: Array[Array] = [
		[ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1]],
		[ScreenSizes.LANDSCAPE[2], ScreenSizes.PORTRAIT[2]],
		[ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]],
	]
	for twin: Array in twins:
		var values: Array[float] = []
		for size: Vector2i in twin:
			get_window().size = size
			await await_idle_frame()
			values.append(UiScale.base_px_per_dp())
		assert_float(values[0]).override_failure_message(str(twin)).is_equal_approx(
			values[1], 0.0001
		)
	# A window that is not the exact transpose (a browser toolbar takes height in landscape) keeps
	# today's stretch, and the dp stays right through UiScale: 1080x2100 is 1.5, 2400x932 1.2945.
	get_window().size = UiProfiles.by_name(&"web_phone_portrait").window_size  # 1080x2100.
	await await_idle_frame()
	assert_float(get_window().get_stretch_transform().get_scale().x).is_equal_approx(1.5, 0.0001)
	get_window().size = UiProfiles.by_name(&"web_phone").window_size  # 2400x932.
	await await_idle_frame()
	assert_float(get_window().get_stretch_transform().get_scale().x).is_equal_approx(
		932.0 / 720.0, 0.0001
	)


## The base size is the project's and its transpose, not a second literal in the autoload.
func test_the_base_sizes_are_the_project_settings_and_their_transpose() -> void:
	var width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	assert_that(Vector2i(width, height)).is_equal(LANDSCAPE_BASE)
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	assert_that(get_window().content_scale_size).is_equal(Vector2i(width, height))
	get_window().size = ScreenSizes.PORTRAIT[1]
	await await_idle_frame()
	assert_that(get_window().content_scale_size).is_equal(Vector2i(height, width))
	# The mode and the aspect are the project's: only the size turns.
	assert_int(get_window().content_scale_mode).is_equal(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_int(get_window().content_scale_aspect).is_equal(Window.CONTENT_SCALE_ASPECT_EXPAND)


## The setter acts only when the value differs, and the emission it causes is the one nested
## `size_changed`: a resize within one orientation emits once, a turn twice, and an unchanged size
## not at all.
func test_the_content_scale_size_is_set_only_when_it_differs() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	var counter: Callable = _count_emissions
	get_tree().root.size_changed.connect(counter)
	var emissions: Array[int] = []
	for size: Vector2i in [
		ScreenSizes.LANDSCAPE[2],  # Landscape to landscape.
		ScreenSizes.LANDSCAPE[2],  # No change.
		ScreenSizes.PORTRAIT[1],  # A turn.
		ScreenSizes.PORTRAIT[2],  # Portrait to portrait.
		ScreenSizes.LANDSCAPE[1],  # A turn back.
	]:
		_seen.clear()
		get_window().size = size
		await await_idle_frame()
		emissions.append(_seen.size())
	get_tree().root.size_changed.disconnect(counter)
	assert_array(emissions).is_equal([1, 0, 2, 1, 2])


## A handler that connects after the autoload runs with the new base size and stretch in both runs
## of a turn (the setter is connected first), so it never sees a stretch of the old orientation.
func test_both_runs_of_a_turn_see_the_new_stretch() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	get_tree().root.size_changed.connect(_count_emissions)
	get_window().size = ScreenSizes.PORTRAIT[1]
	await await_idle_frame()
	get_tree().root.size_changed.disconnect(_count_emissions)
	assert_array(_seen).has_size(2)
	for seen: Dictionary in _seen:
		assert_that(seen["window"]).is_equal(ScreenSizes.PORTRAIT[1])
		assert_that(seen["base"]).is_equal(PORTRAIT_BASE)
		assert_float(seen["stretch"]).is_equal_approx(1.5, 0.0001)


## A window that is already portrait when the autoload enters the tree (the web preview opened on a
## phone held upright) gets the portrait base size from `_ready`, not only from the next resize.
func test_a_window_that_starts_in_portrait_gets_the_portrait_base_in_ready() -> void:
	var live: Node = get_tree().root.get_node("UiOrientation")
	var handler: Callable = Callable(live, &"_apply")
	get_tree().root.size_changed.disconnect(handler)  # The live node sleeps for this case.
	get_window().size = ScreenSizes.PORTRAIT[1]
	await await_idle_frame()
	assert_that(get_window().content_scale_size).is_equal(LANDSCAPE_BASE)  # Nothing turned it.
	var fresh: Node = (load(SERVICE) as GDScript).new()
	get_tree().root.add_child(fresh)
	assert_that(get_window().content_scale_size).is_equal(PORTRAIT_BASE)
	get_tree().root.remove_child(fresh)
	fresh.free()
	get_tree().root.size_changed.connect(handler)
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	assert_that(get_window().content_scale_size).is_equal(LANDSCAPE_BASE)


## In portrait the cutout is at the top and the gesture bar at the bottom: top and bottom both get
## the larger inset plus margin_dp, and so does a reverse portrait, where the cutout is at the
## bottom without a resize (ADR 0015 section 3). The 6-inch phone, 1080x2400, shows 720x1600 base
## px at stretch 1.5; 1 dp is 1.75 base px, so margin_dp 12 is 21.
func test_the_safe_area_margin_in_portrait_takes_the_larger_inset_on_both_sides() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	# A 100 px cutout at the top (66.67 base px, 67 rounded up) and 63 px of gesture bar below the
	# safe area (42 base px), then the turned phone with the two swapped.
	for safe_area: Rect2i in [Rect2i(0, 100, 1080, 2237), Rect2i(0, 63, 1080, 2237)]:
		UiScale.set_override(UiProfiles.with_safe_area(phone, safe_area))
		get_window().size = phone.window_size
		await await_idle_frame()
		assert_that(get_window().get_visible_rect().size).is_equal(Vector2(720, 1600))
		var margin: SafeAreaMargin = auto_free(SafeAreaMargin.new())
		add_child(margin)
		assert_that(margin.apply()).is_equal(Vector2i(21, 88))
		for side: String in ["top", "bottom"]:
			var value: int = margin.get_theme_constant("margin_" + side)
			assert_int(value).override_failure_message(str(safe_area)).is_equal(88)
		for side: String in ["left", "right"]:  # No inset on the long sides: only the gap.
			assert_int(margin.get_theme_constant("margin_" + side)).is_equal(21)
		remove_child(margin)
		margin.free()


func _count_emissions() -> void:
	(
		_seen
		. append(
			{
				"window": get_window().size,
				"base": get_window().content_scale_size,
				"stretch": get_window().get_stretch_transform().get_scale().x,
			}
		)
	)
