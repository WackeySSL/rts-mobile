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
const MAIN_SCENE: String = "res://scenes/main.tscn"
const PROBE_SCENE: String = "res://scenes/dev/touch_probe.tscn"
const RUN_TICKS: int = 15
## [start, other]: the flip of the plan (the stretch is 1.5 both ways), and a phone browser whose
## toolbar takes height in landscape (1.2945 to 1.5), where the state differs between the two.
const FLIPS: Array[Array] = [
	[Vector2i(2400, 1080), Vector2i(1080, 2400)],
	[Vector2i(2400, 932), Vector2i(1080, 2100)],
]

var _window_size_before: Vector2i
var _calls: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	_calls.clear()
	CommandQueue.clear()


func test_the_main_scene_handlers_end_in_the_state_of_a_fresh_scene() -> void:
	await _check_flips(&"main")


func test_the_touch_probe_ends_in_the_state_of_a_fresh_scene() -> void:
	await _check_flips(&"probe")


func test_the_perf_arena_ends_in_the_state_of_a_fresh_scene() -> void:
	await _check_flips(&"arena")


## The camera keeps today's rule on a turn: the position is clamped to the new view once, a
## further run of the handler changes nothing, and turning back starts from the clamped position
## (there is no memory, ADR 0015 section 4). P62 rewrites this case with the turn rule.
func test_the_camera_position_after_the_clamp_does_not_move_on_a_second_run() -> void:
	await _resize(Vector2i(2400, 932))  # Landscape: half the view is 927 by 360 world px.
	var main: Node = await _open(&"main")
	var camera: RtsCamera = main.get_node("Camera")
	camera.position = Vector2(1000, 400)
	await _resize(Vector2i(1080, 2100))  # Portrait: 720 base px wide, 1.5 wide as the stretch.
	# Half the height of the visible rect, whatever whole number of base px the engine floors to.
	var clamped: Vector2 = Vector2(1000.0, get_window().get_visible_rect().size.y * 0.5)
	assert_float(clamped.y).is_between(699.0, 700.0)
	assert_that(camera.position).is_equal(clamped)
	get_tree().root.size_changed.emit()  # A third run, as after a flip's two.
	assert_that(camera.position).is_equal(clamped)
	await _resize(Vector2i(2400, 932))
	assert_that(camera.position).is_equal(clamped)
	_close(main)


## Each pair of sizes: the scene turned and turned back equals a fresh scene at the start size,
## the scene turned equals a fresh one at the other size, and where the stretch differs the two
## states differ from each other (so the comparison is not between two equal constants).
func _check_flips(kind: StringName) -> void:
	for flip: Array in FLIPS:
		var start: Vector2i = flip[0]
		var other: Vector2i = flip[1]
		var label: String = "%s %s -> %s -> %s" % [kind, start, other, start]
		await _resize(start)
		var scene: Node = await _open(kind)
		await _resize(other)
		var turned: Dictionary = _read(kind, scene)
		await _resize(start)
		var back: Dictionary = _read(kind, scene)
		_close(scene)
		var fresh_start: Dictionary = await _fresh(kind)
		await _resize(other)
		var fresh_other: Dictionary = await _fresh(kind)
		assert_dict(back).override_failure_message(label + " back").is_equal(fresh_start)
		assert_dict(turned).override_failure_message(label + " turned").is_equal(fresh_other)
		if flip == FLIPS[1]:
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
			add_child(scene)
			await await_idle_frame()
			(scene.get_node("UnitLayer") as UnitLayer).set_selected(PackedInt32Array([2, 40]))
			var panel: SelectionPanel = scene.get_node("Hud/SafeArea/SelectionBand/SelectionPanel")
			panel.set_selected(PackedInt32Array([1, 2]))
		&"probe":
			scene = (load(PROBE_SCENE) as PackedScene).instantiate()
			add_child(scene)
		&"arena":
			scene = Rig.open(self, _calls, RUN_TICKS)
			await await_idle_frame()
	await await_idle_frame()
	return scene


## A scene opened at the current window size, read and freed.
func _fresh(kind: StringName) -> Dictionary:
	var scene: Node = await _open(kind)
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
	var army: Control = main.get_node("Hud/SafeArea/ArmyBar")
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
		"font_size": army.get_node("AllArmy").get_theme_font_size("font_size"),
		"slops": [recognizer._slop_px, recognizer._double_tap_slop_px, recognizer._min_pinch_px],
		"rings": rings,
		"bar_dp": main.get_node("HealthBarLayer")._dp_px,
		"effects_dp": main.get_node("EffectsLayer")._dp_px,
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
