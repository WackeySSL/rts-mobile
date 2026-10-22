extends GdUnitTestSuite
## A turn runs every `size_changed` handler twice (ADR 0015 sections 2 and 3: the UiOrientation
## autoload sets the content scale size inside the first emission, and that setter emits again), so
## every handler must end in the state a fresh scene has at the end size (plan P59). Each case opens
## a scene, turns the window and turns it back, and compares what the handlers made of the dp with
## a scene opened at that size; the middle step is compared with a fresh scene too. The handlers
## are the ones of main.tscn (DpMinSize, SafeAreaMargin, HudTheme, TouchInput, ArmyBar,
## SelectionPanel, UnitLayer's rings, HealthBarLayer, EffectsLayer and RtsCamera), of the touch
## probe and of the perf arena (PerfHud and the arena's own). A handler that a later row rewrites
## extends its case there (P61 SelectionPanel and ArmyBar, P62 RtsCamera and TouchInput, P63 the
## touch probe). The engine's own metrics are used, no override: the stretch has to follow.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
## Rifle squads (units 41 and 42) and rocket squads (43 and 44) join the tanks, so the main scene's
## SelectionPanel has a mixed selection to lay out in both orientations (P61).
const EXTRA_UNITS: Array[String] = [
	"res://data/units/rifle_squad.tres", "res://data/units/rocket_squad.tres"
]
const MIXED: Array[int] = [1, 2, 41, 42, 43, 44]
const PROBE_SCENE: String = "res://scenes/dev/touch_probe.tscn"
const RUN_TICKS: int = 15

var _window_size_before: Vector2i
var _calls: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	_calls.clear()
	CommandQueue.clear()
	HudLayout.bottom_zone_dp = 0.0


func test_the_main_scene_handlers_end_in_the_state_of_a_fresh_scene() -> void:
	await _check_flips(&"main")


## The ArmyBar's lift above a bottom zone is part of the main scene's state (P61): a stand-in band
## height makes the bar's band margin differ between the two orientations.
func test_the_army_bar_lift_ends_in_the_state_of_a_fresh_scene_with_a_bottom_zone() -> void:
	HudLayout.bottom_zone_dp = 200.0
	await _check_flips(&"main")


func test_the_touch_probe_ends_in_the_state_of_a_fresh_scene() -> void:
	await _check_flips(&"probe")


func test_the_perf_arena_ends_in_the_state_of_a_fresh_scene() -> void:
	await _check_flips(&"arena")


## The camera's turn rule (ADR 0015 section 4, P62) runs once per turn: the first run of a flip's
## two rescales the zoom (the web phone's toolbar takes another share of the screen in each
## orientation) and clamps the kept position to the new view, a further run only clamps, and
## turning back starts from the clamped position (no memory) with the zoom rescaled back.
func test_the_camera_turns_once_and_a_further_run_only_clamps() -> void:
	await _resize(_web_phone())  # Landscape: stretch 1.2945, half the view is 927 by 360 world px.
	var main: Node = await _open(&"main")
	var camera: RtsCamera = main.get_node("Camera")
	camera.zoom = Vector2.ONE
	camera.position = Vector2(1000, 400)
	var landscape: float = UiScale.base_px_per_dp()
	await _resize(_web_phone_portrait())  # Portrait: 720 base px wide, stretch 1.5.
	var factor: float = UiScale.base_px_per_dp() / landscape
	assert_float(factor).is_between(0.86, 0.87)  # The turn rescales, so this is not vacuous.
	assert_float(camera.zoom.x).is_equal_approx(factor, 0.000001)
	# The map's top edge stops the view: the centre is half the visible rect over the zoom.
	var half: Vector2 = get_window().get_visible_rect().size * 0.5 / camera.zoom
	var clamped: Vector2 = Vector2(1000.0, half.y)
	assert_that(camera.position).is_equal(clamped)
	var turned: Vector2 = camera.zoom
	get_tree().root.size_changed.emit()  # A third run, as after a flip's two.
	assert_that(camera.zoom).is_equal(turned)
	assert_that(camera.position).is_equal(clamped)
	await _resize(_web_phone())
	assert_float(camera.zoom.x).is_equal_approx(1.0, 0.000001)
	assert_that(camera.position).is_equal(clamped)
	_close(main)


## TouchInput ends a gesture in flight once per turn (ADR 0015 section 3, P62), through its own
## last orientation: the first run of the flip's two does it, so the second and a third find the
## orientation in place and leave a gesture that began after the first alone. The zoom is between
## levels and the turn is the 6-inch phone's, so a CAMERA_END that reached the camera would show
## as a snap.
func test_touch_input_ends_a_gesture_once_per_turn_and_a_further_run_leaves_the_next_alone(
) -> void:
	await _resize(ScreenSizes.LANDSCAPE[1])
	var main: Node = await _open(&"main")
	var touch: TouchInput = main.get_node("TouchInput")
	var camera: RtsCamera = main.get_node("Camera")
	camera.zoom = Vector2(1.2, 1.2)
	touch._recognizer.touch_down(0, Vector2(300, 400), 0)
	touch._recognizer.touch_move(0, Vector2(400, 400), 10)
	assert_int(touch._recognizer.state()).is_equal(GestureRecognizer.State.PAN)
	await _resize(ScreenSizes.PORTRAIT[1])
	assert_int(touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	assert_that(camera.zoom).is_equal(Vector2(1.2, 1.2))
	assert_object(camera._snap).is_null()  # A CAMERA_END would have started the snap to 1.0.
	touch._recognizer.touch_down(1, Vector2(300, 400), 0)
	touch._recognizer.touch_move(1, Vector2(400, 400), 10)
	get_tree().root.size_changed.emit()  # A further run of the same turn.
	assert_int(touch._recognizer.state()).is_equal(GestureRecognizer.State.PAN)
	await _resize(ScreenSizes.LANDSCAPE[1])  # Turning back is a turn again.
	assert_int(touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	assert_object(camera._snap).is_null()
	_close(main)


## [start, other]: the flip of the plan (the 6-inch phone, the stretch is 1.5 both ways), and a
## phone browser whose toolbar takes height in landscape (1.2945 to 1.5), where the state differs
## between the two.
func _flips() -> Array[Array]:
	return [
		[ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1]],
		[_web_phone(), _web_phone_portrait()],
	]


## The scenario of the main scene with two more types of the player's units after the tanks.
func _mixed_scenario() -> ScenarioDef:
	var scenario: ScenarioDef = (load(SCENARIO) as ScenarioDef).duplicate()
	scenario.spawns = scenario.spawns.duplicate()
	for index: int in EXTRA_UNITS.size():
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = 1
		spawn.unit = load(EXTRA_UNITS[index])
		spawn.count = 2
		spawn.origin_tile = Vector2i(8 + 4 * index, 14)
		scenario.spawns.append(spawn)
	return scenario


func _web_phone() -> Vector2i:
	return UiProfiles.by_name(&"web_phone").window_size


func _web_phone_portrait() -> Vector2i:
	return UiProfiles.by_name(&"web_phone_portrait").window_size


## Each pair of sizes: the scene turned and turned back equals a fresh scene at the start size,
## the scene turned equals a fresh one at the other size, and where the stretch differs the two
## states differ from each other (so the comparison is not between two equal constants).
func _check_flips(kind: StringName) -> void:
	var flips: Array[Array] = _flips()
	for flip: Array in flips:
		var start: Vector2i = flip[0]
		var other: Vector2i = flip[1]
		var label: String = "%s %s -> %s -> %s" % [kind, start, other, start]
		await _resize(start)
		var scene: Node = await _open(kind)
		await _resize(other)
		var turned: Dictionary = _read(kind, scene)
		var turned_zoom: float = _zoom_of(kind, scene)
		await _resize(start)
		var back: Dictionary = _read(kind, scene)
		var back_zoom: float = _zoom_of(kind, scene)
		_close(scene)
		var fresh_start: Dictionary = await _fresh(kind, back_zoom)
		await _resize(other)
		var fresh_other: Dictionary = await _fresh(kind, turned_zoom)
		assert_dict(back).override_failure_message(label + " back").is_equal(fresh_start)
		assert_dict(turned).override_failure_message(label + " turned").is_equal(fresh_other)
		if flip == flips[1]:
			assert_dict(turned).override_failure_message(label + " vacuous").is_not_equal(back)


func _resize(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()


## `kind` in the tree and settled, with a selection where the scene shows one.
func _open(kind: StringName) -> Node:
	var scene: Node = null
	match kind:
		&"main":
			scene = (load(MAIN_SCENE) as PackedScene).instantiate()
			scene.get_node("MatchRunner").scenario = _mixed_scenario()
			add_child(scene)
			await await_idle_frame()
			(scene.get_node("UnitLayer") as UnitLayer).set_selected(PackedInt32Array([2, 40]))
			var panel: SelectionPanel = scene.get_node("Hud/SafeArea/SelectionBand/SelectionPanel")
			panel.set_selected(PackedInt32Array(MIXED))
		&"probe":
			scene = (load(PROBE_SCENE) as PackedScene).instantiate()
			add_child(scene)
		&"arena":
			scene = Rig.open(self, _calls, RUN_TICKS)
			await await_idle_frame()
	await await_idle_frame()
	return scene


## The zoom of a main scene's camera, which a turn rescales (ADR 0015 section 4, P62); 1 for the
## scenes without one.
func _zoom_of(kind: StringName, scene: Node) -> float:
	return (scene.get_node("Camera") as RtsCamera).zoom.x if kind == &"main" else 1.0


## A scene opened at the current window size, its camera (a main scene's) at `zoom`: what a turn
## makes of the zoom is the camera's own case, so the rest is compared at the turned scene's zoom.
## Read and freed.
func _fresh(kind: StringName, zoom: float) -> Dictionary:
	var scene: Node = await _open(kind)
	if kind == &"main":
		(scene.get_node("Camera") as RtsCamera).zoom = Vector2(zoom, zoom)
		await await_idle_frame()  # The rings follow the zoom on the next frame.
	var state: Dictionary = _read(kind, scene)
	_close(scene)
	return state


## One scene at a time: two probes alive together restore `quit_on_go_back` in the wrong order.
func _close(scene: Node) -> void:
	remove_child(scene)
	scene.free()


func _read(kind: StringName, scene: Node) -> Dictionary:
	match kind:
		&"main":
			return _read_main(scene)
		&"probe":
			return _read_probe(scene)
	return _read_arena(scene as Node2D)


func _read_main(main: Node) -> Dictionary:
	var safe: Control = main.get_node("Hud/SafeArea")
	var army: Control = main.get_node("Hud/SafeArea/ArmyBand/ArmyBar")
	var band: Control = main.get_node("Hud/SafeArea/SelectionBand")
	var panel: SelectionPanel = main.get_node("Hud/SafeArea/SelectionBand/SelectionPanel")
	var recognizer: GestureRecognizer = (main.get_node("TouchInput") as TouchInput)._recognizer
	var rings: Array[Array] = []
	for row: int in [1, 39]:
		var ring: Sprite2D = main.get_node("UnitLayer").get_child(row).get_node("Ring")
		rings.append([ring.unit, ring.radius, ring.scale])
	var button_sizes: Array[Vector2] = [main.get_node("Hud/SafeArea/DevButton").custom_minimum_size]
	for child: Node in army.get_children():
		button_sizes.append((child as Button).custom_minimum_size)
	return {
		"button_sizes": button_sizes,
		"safe_margins": _margins(safe),
		"army_gap": army.get_theme_constant("separation"),
		"band_margins":
		[band.get_theme_constant("margin_left"), band.get_theme_constant("margin_right")],
		"panel_gap": panel._list.get_theme_constant("separation"),
		"panel_line": _panel_line(panel),
		"army_lift": army.get_parent().get_theme_constant("margin_bottom"),
		"font_size": army.get_node("AllArmy").get_theme_font_size("font_size"),
		"slops": [recognizer._slop_px, recognizer._double_tap_slop_px, recognizer._min_pinch_px],
		"rings": rings,
		"bar_dp": main.get_node("HealthBarLayer")._dp_px,
		"effects_dp": main.get_node("EffectsLayer")._dp_px,
	}


## How the SelectionPanel is laid out: the column or the line, its fit level and what shows, its
## size flags and the "+N" chip. The rects are the layout's to settle, so what is read is the
## state the handler sets.
func _panel_line(panel: SelectionPanel) -> Dictionary:
	var shown: Array[bool] = []
	for row: SelectionPanel.Row in panel._rows:
		shown.append(row.visible and row.title.visible)
	return {
		"vertical": panel._list.vertical,
		"level": panel._level,
		"names": shown,
		"total": panel._total.visible,
		"chip": "" if panel._chip == null or not panel._chip.visible else panel._chip.text,
		"flags": [panel.size_flags_horizontal, panel.size_flags_vertical],
	}


func _read_probe(probe: Control) -> Dictionary:
	var square: Control = probe.find_child("Square", true, false)
	var label: Label = probe.find_child("MetricsLabel", true, false)
	var recognizer: GestureRecognizer = probe._recognizer
	return {
		"square": square.size,
		"metrics": label.text,
		"font_size": label.get_theme_font_size("font_size"),
		"gap": probe.find_child("Column", true, false).get_theme_constant("separation"),
		"margins": _margins(probe.find_child("Margin", true, false)),
		"slop": recognizer._slop_px,
	}


func _read_arena(arena: Node2D) -> Dictionary:
	return {
		"layout_gap": arena.layout.get_theme_constant("separation"),
		"bar_gap": arena.bar.get_theme_constant("separation"),
		"hud_column_gap": arena.hud._column.get_theme_constant("separation"),
		"hud_buttons_gap": arena.hud._buttons.get_theme_constant("separation"),
		"safe_margins": _margins(arena.get_node("Hud/SafeArea")),
		"bar_dp": arena.bar_layer._dp_px,
		"effects_dp": arena.effects_layer._dp_px,
	}


func _margins(container: Control) -> Array[int]:
	var out: Array[int] = []
	for side: String in ["left", "top", "right", "bottom"]:
		out.append(container.get_theme_constant("margin_" + side))
	return out
