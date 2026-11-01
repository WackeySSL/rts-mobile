extends GdUnitTestSuite
## EffectsLayer from the runner's side (plan P44b, ADR 0012 section 3): that every tick's events
## are read once when a frame plays several catch-up ticks, that a frame paints its plan and stops
## painting it when the last effect is gone, that frames make no object, that a record the tables
## do not know draws something sane, and the layer's place in the main scene (z 50, after the
## health bars, before the markers). The events themselves are in test_effects_layer.gd and the
## look in time in test_effects_layer_curves.gd (gdlint allows 20 public methods per file).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Rig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
const FLASH: Rect2 = Rect2(144, 0, 32, 32)
const PUFF: Rect2 = Rect2(84, 0, 56, 56)
const BURST: Rect2 = Rect2(0, 0, 80, 80)
const SCRIPT_PATH: String = "res://game/view/EffectsLayer.gd"
## What runs every frame or every tick, and the calls that make or grow an array or a container.
const FRAME_PATH: Array[String] = [
	"_process",
	"_plan",
	"_plan_effect",
	"_add_line",
	"_add_quad",
	"_draw",
	"_on_ticked",
	"_add_shot",
	"_add_impact",
	"_add_death",
	"_push",
	"_follow_match",
	"_empty",
]
const ALLOCATING: Array[String] = [
	"Array(",
	".new(",
	".append",
	".push_back(",
	".resize(",
	".duplicate(",
	".map(",
	".filter(",
	"func(",
	"{",
	"[]",  # An array made empty, or a literal, in any place an expression can stand.
	"= [",
	"([",
	", [",
	"return [",
	" in [",
	": Array",  # A local or a parameter that holds an array: there is no reason for one here.
	"Array[",
]

var _window_size_before: Vector2i
var _now_ms: int = 0
var _runner: MatchRunner
var _layer: EffectsLayer
## What each tick the runner plays should have given the layer, and the tick numbers it played.
var _expected: Array[int] = []
var _ticks: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	_now_ms = 0
	_expected.clear()
	_ticks.clear()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Rig.battle()
	_runner.start()
	_layer = _make_layer(128)


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_frame_that_plays_four_ticks_gives_the_layer_every_ticks_events_once() -> void:
	# The runner publishes a tick and emits ticked before it plays the next, so the snapshot that
	# a handler reads is that tick's. The ring is big enough for the match and the clock stands
	# still, so every effect that is born stays alive: they add up to what the events held.
	_layer = _make_layer(4096)
	_runner.ticked.connect(_note_tick)
	var busy_frames: int = 0
	var total: int = 0
	for _frame: int in 40:
		var before: int = _expected.size()
		_runner._process(4.0 / 15.0)  # Four ticks, the most a frame plays.
		assert_int(_expected.size() - before).is_equal(4)
		var busy_ticks: int = 0
		for index: int in range(before, _expected.size()):
			total += _expected[index]
			busy_ticks += int(_expected[index] > 0)
		busy_frames += int(busy_ticks >= 2)
		assert_int(_layer.active_count()).is_equal(total)
	assert_int(_ticks[0]).is_equal(1)
	assert_int(_ticks[159]).is_equal(160)
	assert_int(busy_frames).is_greater(5)  # Many frames held events of more than one tick.
	assert_int(total).is_greater(100)


func test_run_ticks_gives_the_layer_every_ticks_events_once_too() -> void:
	_layer = _make_layer(4096)
	_runner.ticked.connect(_note_tick)
	_runner.run_ticks(160)
	assert_int(_expected.size()).is_equal(160)
	assert_int(_layer.active_count()).is_equal(_expected.reduce(_sum, 0))
	_layer._process(0.0)  # A frame reads no events: it plans what the ticks left.
	assert_int(_layer.line_count() + _layer.quad_count()).is_greater(0)
	assert_int(_layer.active_count()).is_equal(_expected.reduce(_sum, 0))


func test_each_ticks_effects_are_born_at_the_clock_of_that_ticks_own_emission() -> void:
	# A frame that plays several ticks emits ticked once per tick, and the clock moves on between
	# the emissions by the cost of the tick that ran between them: the earlier tick is the older.
	var cannon: int = _weapon(&"tank_cannon")
	_now_ms = 1000
	_deliver(Rig.shot(Vector2i(5000, 5000), Vector2i(9000, 5000), cannon))
	_now_ms = 1060
	_deliver(Rig.shot(Vector2i(5000, 6000), Vector2i(9000, 6000), cannon))
	_layer._process(0.0)
	assert_int(_layer.quad_count()).is_equal(2)  # Oldest first.
	assert_float(_layer.quad_alpha(0)).is_equal_approx(40.0 / 60.0, 0.0001)  # 60 ms into its fade.
	assert_float(_layer.quad_alpha(1)).is_equal_approx(1.0, 0.0001)  # Born this instant.


func test_the_default_clock_is_the_engine_clock_in_ms_and_a_flash_expires_by_it() -> void:
	var layer: EffectsLayer = auto_free(EffectsLayer.new())  # Its clock is left at the default.
	layer.runner = _runner
	add_child(layer)
	layer.set_process(false)
	var before: int = Time.get_ticks_msec()
	_deliver(Rig.shot(Vector2i(5000, 5000), Vector2i(9000, 5000), _weapon(&"tank_cannon")))
	var after_tick: int = Time.get_ticks_msec()
	assert_int(layer._born[0]).is_between(before, after_tick)  # Not usec, not a frame count.
	OS.delay_msec(150)  # A flash lives 100 ms: a clock that stands still or counts otherwise keeps it.
	layer._process(0.0)
	assert_int(layer.active_count()).is_equal(0)
	assert_int(layer.quad_count()).is_equal(0)


func test_draw_paints_the_plan_and_paints_nothing_once_the_last_effect_is_gone() -> void:
	await await_idle_frame()
	assert_int(_layer.drawn_quads()).is_equal(0)
	_deliver(Rig.shot(Vector2i(5000, 5000), Vector2i(9000, 5000), _weapon(&"rifle")))
	_deliver(Rig.impact(Vector2i(6000, 6000), _weapon(&"tank_cannon")))
	_layer._process(0.0)
	await await_idle_frame()
	assert_int(_layer.drawn_lines()).is_equal(2)
	assert_int(_layer.drawn_quads()).is_equal(2)
	_now_ms = 120  # The tracer and the flash are gone, the puff is not.
	_layer._process(0.0)
	await await_idle_frame()
	assert_int(_layer.drawn_lines()).is_equal(0)
	assert_int(_layer.drawn_quads()).is_equal(1)
	_now_ms = 350  # The last one goes: a frame with nothing planned redraws too.
	_layer._process(0.0)
	await await_idle_frame()
	assert_int(_layer.drawn_lines() + _layer.drawn_quads()).is_equal(0)
	_deliver(Rig.died(Vector2i(5000, 5000), _type(&"light_tank")))  # And an effect can come back.
	_layer._process(0.0)
	await await_idle_frame()
	assert_int(_layer.drawn_quads()).is_equal(1)


func test_frames_that_make_and_expire_effects_leave_no_objects_behind() -> void:
	var events: Array[PackedInt32Array] = [
		Rig.shot(Vector2i(5000, 5000), Vector2i(9000, 5000), _weapon(&"rifle")),
		Rig.shot(Vector2i(5000, 5000), Vector2i(5000, 9000), _weapon(&"tank_cannon")),
		Rig.impact(Vector2i(6000, 6000), _weapon(&"rocket")),
		Rig.died(Vector2i(7000, 7000), _type(&"light_tank")),
		Rig.died(Vector2i(7000, 7000), _type(&"rifle_squad")),
	]
	for index: int in 20:  # Warm up: the first frames may make the engine's own objects.
		_now_ms += 17
		_deliver(events[index % events.size()])
		_layer._process(0.0)
	var before: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	for index: int in 400:  # More effects than the ring holds, and many of them expire.
		_now_ms += 17
		_deliver(events[index % events.size()])
		_layer._process(0.0)
	var after_frames: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	assert_int(after_frames).is_equal(before)
	assert_int(_layer.active_count()).is_greater(0)


func test_the_frame_path_makes_no_array_and_grows_none() -> void:
	# The object count above cannot see an array: Packed arrays, Arrays and Dictionaries are no
	# Objects. So the functions that run every frame or tick may not name a call that makes,
	# resizes or grows one, nor write an array literal or an Array local; the ring made its arrays
	# once, in `_make_ring`.
	for func_name: String in FRAME_PATH:
		var code: String = _code_of(func_name)
		assert_int(code.count("\n")).is_greater(2)  # The function and not its first line.
		for token: String in ALLOCATING:
			var note: String = "%s makes an array or grows one with %s" % [func_name, token]
			assert_bool(code.contains(token)).override_failure_message(note).is_false()


func test_draw_hands_every_field_of_the_plan_to_its_draw_call() -> void:
	# Pixels cannot be read headless, so this step is pinned in the source, spaces aside: a line is
	# painted from its two ends in its colour and width, a quad into its rect from its region with
	# its alpha as the tint. A tint without the alpha, a region fixed in the call, a white line or
	# a line that ends where it starts would each change this text.
	var code: String = _code_of("_draw").replace(" ", "").replace("\t", "").replace("\n", "")
	var line_args: String = "line_from(index),line_to(index),line_color(index),line_width(index),true"
	var quad_args: String = "ATLAS,quad_rect(index),quad_region(index),tint"
	assert_str(code).contains("draw_line(" + line_args + ")")
	assert_str(code).contains("draw_texture_rect_region(" + quad_args + ")")
	assert_str(code).contains("vartint:Color=Color(1.0,1.0,1.0,_quad_alpha[index])")


func test_records_the_tables_do_not_know_draw_something_sane_and_other_kinds_nothing() -> void:
	# A weapon past the snapshot's tables gets the default flash 13 px from its shooter and no
	# tracer, a puff of the default size, both at the default muzzle height of 14 px, and a type
	# past them bursts, centred 13 px up (half of the default vehicle frame of 26). A SPAWNED
	# record, or one of no kind, is ignored.
	var at: Vector2i = Vector2i(5000, 5000)
	var ground: Vector2 = IsoProjection.ground_to_px(at.x, at.y)
	var shooter: Vector2 = ground - Vector2(0.0, 14.0)
	for weapon: int in [99, -1]:
		_now_ms += 1000
		_deliver(Rig.shot(at, Vector2i(9000, 5000), weapon))
		_layer._process(0.0)
		assert_int(_layer.line_count()).is_equal(0)
		assert_int(_layer.quad_count()).is_equal(1)
		assert_that(_layer.quad_region(0)).is_equal(FLASH)
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(24.0, 0.001)
		var muzzle: Vector2 = _layer.quad_rect(0).get_center()
		assert_float(muzzle.distance_to(shooter)).is_equal_approx(13.0, 0.001)
		var towards: Vector2 = IsoProjection.ground_to_px(9000, 5000) - ground
		var offset: Vector2 = muzzle - shooter
		assert_vector(offset).is_equal_approx(towards.normalized() * 13.0, Vector2(0.001, 0.001))
		_now_ms += 1000
		_deliver(Rig.impact(at, weapon))
		_layer._process(0.0)
		assert_that(_layer.quad_region(0)).is_equal(PUFF)
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(40.0 * 0.6, 0.001)
		assert_vector(_layer.quad_rect(0).get_center()).is_equal_approx(
			shooter, Vector2(0.001, 0.001)
		)
	for type_index: int in [99, -1]:
		_now_ms += 1000
		_deliver(Rig.died(at, type_index))
		_layer._process(0.0)
		assert_that(_layer.quad_region(0)).is_equal(BURST)
		assert_vector(_layer.quad_rect(0).get_center()).is_equal_approx(
			ground - Vector2(0.0, 13.0), Vector2(0.001, 0.001)
		)
	_now_ms += 1000
	_deliver(
		PackedInt32Array([World.Event.SPAWNED, 1, 5000, 5000, 0, 1, 0, 0, 0, 1, 2, 3, 0, 0, 0, 0])
	)
	_layer._process(0.0)
	assert_int(_layer.active_count()).is_equal(0)
	_deliver(PackedInt32Array())  # A tick without events adds nothing.
	_layer._process(0.0)
	assert_int(_layer.active_count()).is_equal(0)


func test_a_weapon_of_minus_one_is_no_hitscan_weapon_even_when_the_last_one_is() -> void:
	# GDScript counts a negative index from the end of an array, so without the check on the
	# weapon, -1 would read the last row of the speed column. Make that row a hitscan weapon.
	var last: int = _runner.snapshot.weapon_projectile_speed.size() - 1
	_runner.snapshot.weapon_projectile_speed[last] = 0
	var at: Vector2i = Vector2i(5000, 5000)
	_deliver(Rig.shot(at, Vector2i(9000, 5000), last))
	_layer._process(0.0)
	assert_int(_layer.line_count()).is_equal(2)  # The fixture does what it says: a tracer.
	_now_ms += 1000
	_deliver(Rig.shot(at, Vector2i(9000, 5000), -1))
	_layer._process(0.0)
	assert_int(_layer.line_count()).is_equal(0)
	assert_int(_layer.quad_count()).is_equal(1)  # Its flash, no tracer.


func test_a_layer_without_a_runner_or_before_its_match_plans_nothing_and_raises_nothing() -> void:
	var bare: EffectsLayer = auto_free(EffectsLayer.new())
	add_child(bare)
	bare._process(0.0)
	assert_int(bare.active_count()).is_equal(0)
	var idle: MatchRunner = auto_free(MatchRunner.new())  # No scenario run: no snapshot yet.
	var waiting: EffectsLayer = auto_free(EffectsLayer.new())
	waiting.runner = idle
	add_child(waiting)
	waiting._process(0.0)
	assert_int(waiting.line_count() + waiting.quad_count()).is_equal(0)


func test_the_main_scene_has_the_layer_at_z_50_between_the_health_bars_and_the_markers() -> void:
	get_window().size = BASE_SIZE
	await await_idle_frame()
	var main: Node2D = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	add_child(main)
	await await_idle_frame()
	var runner: MatchRunner = main.get_node("MatchRunner")
	runner.paused = true
	var layer: EffectsLayer = main.get_node("EffectsLayer")
	layer.reveal_enemies = true  # Tile (5, 5) is in the dark at the start of the match.
	assert_int(layer.z_index).is_equal(50)  # ADR 0023 section 2.
	assert_bool(layer.z_as_relative).is_false()
	assert_object(layer.runner).is_same(runner)
	assert_int(layer.capacity).is_equal(128)
	# The fog lies on the ground at z 4, under every effect, so it cannot cover a tracer: the layer
	# clips one with a single end seen itself (ADR 0023 section 2, test_fog_hiding.gd).
	var fog: Node2D = main.get_node("FogLayer")
	assert_bool(fog.z_as_relative).is_false()
	assert_int(fog.z_index).is_less(layer.z_index)
	var order: Array[StringName] = []
	for child: Node in main.get_children():
		order.append(child.name)
	assert_int(order.find(&"EffectsLayer")).is_greater(order.find(&"HealthBarLayer"))
	assert_int(order.find(&"EffectsLayer")).is_less(order.find(&"MarkerLayer"))
	if order.has(&"ProjectileLayer"):  # P44a's layer, z 40, comes first.
		assert_int(order.find(&"EffectsLayer")).is_greater(order.find(&"ProjectileLayer"))
	# And it takes the events of the runner's ticks: this scene has tanks only.
	var cannon: int = runner.snapshot.weapon_ids.find(&"tank_cannon")
	runner.snapshot.events = Rig.shot(Vector2i(5000, 5000), Vector2i(9000, 5000), cannon)
	runner.ticked.emit(runner.snapshot.tick)
	assert_int(layer.active_count()).is_equal(1)
	layer._process(0.0)
	assert_int(layer.quad_count()).is_equal(1)
	assert_int(layer.line_count()).is_equal(0)


## An EffectsLayer of `slots` ring slots on the fake clock, out of the frame loop. The old one goes.
func _make_layer(slots: int) -> EffectsLayer:
	if is_instance_valid(_layer):
		_layer.free()
	var layer: EffectsLayer = auto_free(EffectsLayer.new())
	layer.capacity = slots
	layer.runner = _runner
	layer.clock = func() -> int: return _now_ms
	add_child(layer)
	layer.set_process(false)
	return layer


## Delivers `events` as the events of a tick, the way the runner does.
func _deliver(events: PackedInt32Array) -> void:
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)


## Notes the tick just published and how many effects its events make: a flash for a SHOT and
## a tracer too for a hitscan weapon, a puff for an IMPACT and a burst or fade for a DIED.
func _note_tick(tick: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var effects: int = 0
	for at: int in range(0, snap.events.size(), World.EVENT_STRIDE):
		var kind: int = snap.events[at]
		if kind == World.Event.SHOT:
			var hitscan: bool = snap.weapon_projectile_speed[snap.events[at + 5]] == 0
			effects += 2 if hitscan else 1
		elif kind == World.Event.IMPACT or kind == World.Event.DIED:
			effects += 1
	_expected.append(effects)
	_ticks.append(tick)


## The code of the function `func_name` of EffectsLayer.gd, without its comments.
func _code_of(func_name: String) -> String:
	var source: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	var start: int = source.find("func %s(" % func_name)
	assert_int(start).is_greater_equal(0)
	var end: int = source.find("\n\n\n", start)  # Two blank lines end a function (gdformat).
	if end < 0:
		end = source.length()  # The last one.
	var code: String = ""
	for line: String in source.substr(start, end - start).split("\n"):
		code += line.get_slice("#", 0) + "\n"  # Words in a comment make nothing.
	return code


func _sum(total: int, value: int) -> int:
	return total + value


func _weapon(weapon_id: StringName) -> int:
	return _runner.snapshot.weapon_ids.find(weapon_id)


func _type(type_id: StringName) -> int:
	return _runner.snapshot.type_ids.find(type_id)
