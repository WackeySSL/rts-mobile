extends GdUnitTestSuite
## BUILD (plan P120, ADR 0025 section 4) in the main scene: a 64 dp square at the safe rect's
## bottom right in both orientations, at the six sizes of ScreenSizes.ALL and at every profile, also
## with a cutout, where `HudCorners.place` puts it. The ring is the share of the queue head that
## finishes first (the least work left over the player's three queues), the badge the items in all
## of them; it redraws when either changes and not at rest; it hides while the drawer or the pause
## menu is open; a tap opens the drawer. Stalled and the Ready chip are P120c's.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 1.5
const BASE: Array[String] = ["headquarters", "power_plant", "barracks", "vehicle_factory"]

var _window_size_before: Vector2i
var _main: Node2D
var _button: BuildButton
var _feed: HudStateFeed
var _runner: MatchRunner


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func before_test() -> void:
	MenuRig.begin()


func test_build_is_64_dp_at_the_safe_rects_bottom_right_where_the_layout_puts_it() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		var rect: Rect2 = _button.get_global_rect()
		var side: float = UiScale.dp(64.0)
		var at: String = "%s: BUILD %s, safe %s" % [why, rect, safe]
		assert_bool(_button.visible).override_failure_message(at).is_true()
		assert_float(rect.size.x).override_failure_message(at).is_equal_approx(side, TOLERANCE_PX)
		assert_float(rect.size.y).override_failure_message(at).is_equal_approx(side, TOLERANCE_PX)
		assert_float(rect.end.x).override_failure_message(at).is_equal_approx(safe.end.x, 1.0)
		assert_float(rect.end.y).override_failure_message(at).is_equal_approx(safe.end.y, 1.0)
		assert_bool(safe.grow(TOLERANCE_PX).encloses(rect)).override_failure_message(at).is_true()
		for other: String in ["EconomyPill", "RadarScope"]:
			assert_bool(rect.intersects(_rect(other))).override_failure_message(at).is_false()


func test_the_ring_is_the_first_finishing_head_and_the_badge_counts_every_queue() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	assert_int(_button.count).is_equal(0)
	assert_float(_button.progress).is_equal(0.0)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var plant: int = Sw.type_of(world, "power_plant")
	var rifle: int = Sw.type_of(world, "rifle_squad")
	var plant_goal: int = world.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
	var rifle_goal: int = world.type_build_ticks[rifle] * Production.PROGRESS_PER_TICK
	# The plant is a fifth along; the rifle squads, with another queued behind, half way.
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], plant_goal / 5)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rifle_squad"], rifle_goal / 2)
	_publish(world, 1)
	var left_plant: int = plant_goal - plant_goal / 5
	var left_rifle: int = rifle_goal - rifle_goal / 2
	var expected: float = 0.2 if left_plant < left_rifle else 0.5
	assert_float(_button.progress).is_equal_approx(expected, 0.001)
	assert_int(_button.count).is_equal(3)
	# Now the plant is nearly done: it finishes first.
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], plant_goal - 10)
	_publish(world, 2)
	assert_float(_button.progress).is_equal_approx(float(plant_goal - 10) / plant_goal, 0.001)
	# Empty queues: no ring and no badge.
	Sw.enqueue(world, World.Tab.STRUCTURES, [])
	Sw.enqueue(world, World.Tab.INFANTRY, [])
	_publish(world, 3)
	assert_int(_button.count).is_equal(0)
	assert_float(_button.progress).is_equal(0.0)


func test_it_redraws_when_the_ring_or_the_badge_changes_and_not_at_rest() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_button.set_process(true)  # The game's frames read the published snapshot.
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_post(world, 1)
	await await_idle_frame()
	await await_idle_frame()
	var drawn: int = _button.draws
	assert_int(drawn).is_greater(0)
	for tick: int in 3:  # The same queue on later ticks and over idle frames: nothing to redraw.
		_post(world, 2 + tick)
		await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_button.draws).is_equal(drawn)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 600)
	_post(world, 9)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_button.draws).is_equal(drawn + 1)


## The badge is a HUD number: 18 sp at the least (touch-ui-rules, ADR 0025 section 13), in the
## theme's number face; the word is the theme's 14 dp caps.
func test_the_badge_is_an_18_sp_number_and_the_word_a_14_dp_caps_face_from_the_theme() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var dp: float = UiScale.dp(1.0)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_publish(world, 1)  # A count above 0: the badge is drawn.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_button.count).is_greater(0)
	assert_object(_button.badge_font).is_not_null()  # What _draw really used for the digits.
	assert_object(_button.badge_font).is_same(
		_button.get_theme_font(&"font", BuildButton.NUMBER_FONT)
	)
	assert_float(float(_button.badge_font_size)).is_greater_equal(roundf(18.0 * dp) - 0.5)
	var word: int = _button.get_theme_font_size(&"font_size", BuildButton.WORD_FONT)
	assert_float(float(word)).is_greater_equal(roundf(14.0 * dp) - 0.5)
	assert_object(_button.badge_font).is_not_same(
		_button.get_theme_font(&"font", BuildButton.WORD_FONT)
	)


func test_it_hides_under_the_drawer_and_the_pause_menu_and_a_tap_opens_the_drawer() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		var why: String = str(size)
		assert_bool(_button.visible).override_failure_message(why).is_true()
		var at: Vector2 = _button.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(_feed.state.current).override_failure_message(why).is_equal(
			HudState.Unfold.DRAWER
		)
		assert_bool(_button.visible).override_failure_message(why).is_false()
		_feed.state.close(HudState.Unfold.DRAWER)
		assert_bool(_button.visible).override_failure_message(why).is_true()
		_feed.state.open(HudState.Unfold.PAUSE)
		assert_bool(_button.visible).override_failure_message(why).is_false()
		_feed.state.close(HudState.Unfold.PAUSE)
		assert_bool(_button.visible).override_failure_message(why).is_true()
		assert_bool(_button.visible).is_true()


## The snapshot of `world` at `tick`, published to the runner the button reads (its own frames
## pick it up).
func _post(world: World, tick: int) -> void:
	var snap: MatchSnapshot = Sw.snapshot(world, 0)
	snap.tick = tick
	_runner.snapshot = snap


func _publish(world: World, tick: int) -> void:
	var snap: MatchSnapshot = Sw.snapshot(world, 0)
	snap.tick = tick
	_runner.snapshot = snap
	_button.refresh(snap)


func _rect(node_name: String) -> Rect2:
	return (_main.get_node("Hud").find_child(node_name, true, false) as Control).get_global_rect()


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}. Each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait).
func _screens() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append({"label": "size %s" % size, "size": size, "metrics": null})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, m.window_size.x - CUTOUT_PX, m.window_size.y)
		all.append({"label": str(profile_name), "size": m.window_size, "metrics": m})
		var with_cutout: UiMetrics = UiProfiles.with_safe_area(m, cut)
		all.append(
			{
				"label": "%s with a cutout" % profile_name,
				"size": m.window_size,
				"metrics": with_cutout
			}
		)
	return all


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, and BUILD reading a runner of its own (the snapshots a test publishes).
func _open(size: Vector2i, metrics: UiMetrics) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _main.get_node("MatchRunner").scenario
	_button = _main.get_node("Hud/BuildButton")
	_button.runner = _runner
	_feed = _main.get_node("Hud/HudStateFeed")
	await await_idle_frame()
