extends GdUnitTestSuite
## The perf arena holds the screen in landscape while it is open (plan P63b, ADR 0015; Michael,
## 2026-10-22: "Perf arena låser skærmen til liggende format, mens den er åben, så testen altid
## måles ens"), headless, through the three injectable seams `orientation_feature`,
## `orientation_source` and `orientation_sink`, whose spies log what the arena asks of the display
## server. Where the display server has the feature (the APK), entering reads the orientation it
## finds and sets sensor landscape, and leaving puts the found one back; where it has none (the web
## preview and headless), neither the source nor the sink is called. The rule of the card for a
## portrait view that the preview cannot lock is test_perf_hud_portrait.gd's and
## test_perf_arena_portrait.gd's. The frame cap and the screen kept on: test_perf_arena.gd.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
## project.godot's `window/handheld/orientation=4` (sensor_landscape) is this value.
const SENSOR_LANDSCAPE: int = DisplayServer.SCREEN_SENSOR_LANDSCAPE
## What a phone can be in when the arena opens (the engine's whole enum).
const FOUND: Array[int] = [
	DisplayServer.SCREEN_LANDSCAPE,
	DisplayServer.SCREEN_PORTRAIT,
	DisplayServer.SCREEN_REVERSE_LANDSCAPE,
	DisplayServer.SCREEN_REVERSE_PORTRAIT,
	DisplayServer.SCREEN_SENSOR_LANDSCAPE,
	DisplayServer.SCREEN_SENSOR_PORTRAIT,
	DisplayServer.SCREEN_SENSOR,
]

var _calls: Array[String] = []
var _arenas: Array[Node2D] = []
## What the spies answer, and what they were asked in order.
var _has_feature: bool = true
var _found: int = DisplayServer.SCREEN_LANDSCAPE
var _log: Array[String] = []
var _max_fps_before: int = 0


func before_test() -> void:
	_max_fps_before = Engine.max_fps
	_has_feature = true
	_found = DisplayServer.SCREEN_LANDSCAPE
	CommandQueue.clear()


## Every arena is freed (which restores the frame cap), the last one in first.
func after_test() -> void:
	_arenas.reverse()
	for arena: Node2D in _arenas:
		if is_instance_valid(arena):
			Rig.close(self, arena)
	_arenas.clear()
	_calls.clear()
	_log.clear()
	assert_int(Engine.max_fps).is_equal(_max_fps_before)
	CommandQueue.clear()


func test_entering_sets_sensor_landscape_and_leaving_puts_the_found_orientation_back() -> void:
	assert_int(SENSOR_LANDSCAPE).is_equal(4)
	for found: int in FOUND:
		_log.clear()
		_found = found
		var arena: Node2D = _make()
		assert_array(_log).override_failure_message("before the tree").is_empty()
		add_child(arena)
		var label: String = "found %d" % found
		assert_array(_log).override_failure_message(label).is_equal(
			["feature", "source", "sink %d" % SENSOR_LANDSCAPE]
		)
		remove_child(arena)
		assert_array(_log).override_failure_message(label).is_equal(
			["feature", "source", "sink %d" % SENSOR_LANDSCAPE, "sink %d" % found]
		)
		arena.free()


func test_the_arena_stays_locked_while_it_lives_and_asks_nothing_more() -> void:
	_found = DisplayServer.SCREEN_PORTRAIT
	var arena: Node2D = _make()
	add_child(arena)
	var on_entry: Array[String] = _log.duplicate()
	await await_idle_frame()
	await await_idle_frame()
	arena.runner.run_ticks(3)
	(arena.layers_button as Button).pressed.emit()  # A new run is no new entry.
	assert_array(_log).is_equal(on_entry)
	remove_child(arena)
	assert_array(_log).is_equal(on_entry + ["sink %d" % DisplayServer.SCREEN_PORTRAIT])
	arena.free()


func test_without_the_feature_neither_the_source_nor_the_sink_is_called() -> void:
	_has_feature = false
	_found = DisplayServer.SCREEN_PORTRAIT
	var arena: Node2D = _make()
	add_child(arena)
	assert_array(_log).is_equal(["feature"])
	await await_idle_frame()
	remove_child(arena)
	assert_array(_log).is_equal(["feature"])  # Leaving puts back what entry did not touch.
	arena.free()


func test_leaving_puts_back_only_what_entry_set_whatever_the_feature_says_by_then() -> void:
	var arena: Node2D = _make()
	add_child(arena)
	_has_feature = false  # Gone by the time the arena leaves: entry set it, so leaving unsets it.
	remove_child(arena)
	assert_array(_log).is_equal(
		[
			"feature",
			"source",
			"sink %d" % SENSOR_LANDSCAPE,
			"sink %d" % DisplayServer.SCREEN_LANDSCAPE
		]
	)
	arena.free()
	_log.clear()
	_has_feature = false
	var bare: Node2D = _make()
	add_child(bare)
	_has_feature = true  # Appears by the time it leaves: entry set nothing, so leaving sets nothing.
	remove_child(bare)
	assert_array(_log).is_equal(["feature"])
	bare.free()


func test_a_second_visit_finds_the_restored_orientation_and_locks_again() -> void:
	_found = DisplayServer.SCREEN_PORTRAIT
	var arena: Node2D = _make()
	add_child(arena)
	remove_child(arena)
	_log.clear()
	_found = DisplayServer.SCREEN_REVERSE_LANDSCAPE  # The phone was turned in the dev menu.
	add_child(arena)
	assert_array(_log).is_equal(["feature", "source", "sink %d" % SENSOR_LANDSCAPE])
	remove_child(arena)
	assert_array(_log).is_equal(
		[
			"feature",
			"source",
			"sink %d" % SENSOR_LANDSCAPE,
			"sink %d" % DisplayServer.SCREEN_REVERSE_LANDSCAPE
		]
	)
	arena.free()


## The default seams are the display server's own, so the APK reaches it. Headless has no
## orientation feature (`has_feature` answers false for every feature) and setting an orientation
## is a silent no-op there, so what the defaults do cannot be seen from their effect: the case
## pins which method each Callable is and which feature the check asks for (a check bound to
## another feature would drop the lock on the phone and pass every spy case). That nothing is
## asked where the feature is missing is
## `test_without_the_feature_neither_the_source_nor_the_sink_is_called`.
func test_the_defaults_are_the_display_servers_and_the_check_asks_for_the_orientation_feature(
) -> void:
	var arena: Node2D = Rig.make(_calls)
	_arenas.append(arena)
	assert_bool(arena.orientation_feature.is_valid()).is_true()
	assert_str(arena.orientation_feature.get_method()).is_equal("has_feature")
	assert_array(arena.orientation_feature.get_bound_arguments()).is_equal(
		[DisplayServer.FEATURE_ORIENTATION]
	)
	assert_str(arena.orientation_source.get_method()).is_equal("screen_get_orientation")
	assert_str(arena.orientation_sink.get_method()).is_equal("screen_set_orientation")


## An arena outside the tree whose orientation seams answer `_has_feature` and `_found` and log
## into `_log`; freed with the case.
func _make() -> Node2D:
	var arena: Node2D = Rig.make(_calls)
	arena.orientation_feature = func() -> bool:
		_log.append("feature")
		return _has_feature
	arena.orientation_source = func() -> int:
		_log.append("source")
		return _found
	arena.orientation_sink = func(orientation: int) -> void: _log.append("sink %d" % orientation)
	_arenas.append(arena)
	return arena
