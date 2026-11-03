extends GdUnitTestSuite
## The recoil's cost (plan P136, ADR 0027 section 9): the functions that run every tick or every
## frame make no array and grow none, frames and shots leave no object behind, and the sprite
## writes of a big volley stay inside the budget (at most 60 a frame on average and 150 in any
## frame). The volley is the stress case: 40 heavy and 30 light tanks of one player all fire in one
## tick, three times 30 ticks apart, with four frames to a tick. P146's combined test measures the
## whole life layer on the base arena; this is the recoil's share.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const SourceScan: GDScript = preload("res://tests/view/support/source_scan.gd")
## Functions that run every tick or every frame, by file, and the calls that make or grow an array
## or a container, as test_effects_layer_frames.gd lists them.
const FRAME_PATH: Dictionary[String, Array] = {
	"res://game/view/RigLife.gd":
	[
		"follow",
		"count",
		"id_at",
		"age_at",
		"turret_offset",
		"hull_offset",
		"shot",
		"advance",
		"end",
		"sweep",
		"_slot_of",
		"_curve",
		"_quantised",
		"shake_offset",
		"look_side",
		"sweep_offset",
		"_forever",
		"idle_clock",
		"idle_step",
		"sweep_step",
	],
	"res://game/view/GroundFx.gd":
	["_process", "_draw", "_plan", "_on_ticked", "_add", "_empty", "quad_rect"],
	"res://game/view/StrikeFx.gd":
	[
		"_process",
		"_draw",
		"_on_ticked",
		"_add_strike",
		"_take_slot",
		"_radius_of",
		"_launch_point",
		"_plan",
		"_plan_launch",
		"_plan_fall",
		"_plan_settle",
		"_fall_below",
		"_follow_match",
		"_make_slots_if_resized",
		"_quad",
		"_empty",
		"quad_rect",
	],
	"res://game/view/StrikeNet.gd":
	[
		"clear",
		"plan",
		"count",
		"at",
		"scale_of",
		"alpha",
		"ring_alpha",
		"lattice_of",
		"draw",
		"_pass",
		"drawn_nets",
		"drawn_segments",
		"drawn_alpha",
		"drawn_edge_width",
		"drawn_light_width",
	],
	"res://game/view/LifeClock.gd": ["ms", "tick_ms", "age_ms", "mix", "pick"],
	"res://game/view/UnitLayer.gd":
	[
		"_on_ticked",
		"_note_shot",
		"_kick_rigs",
		"_apply_kick",
		"_apply_idle",
		"_update_rigs",
	],
	"res://game/view/BuildingLayer.gd": ["_on_ticked", "_note_shot", "_kick_heads", "_sweep_heads"],
}
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
	"[]",
	"= [",
	"([",
	", [",
	"return [",
	" in [",
	": Array",
	"Array[",
	'" % ',  # A string being formatted; the modulo of two numbers is no allocation.
	"str(",
	"String(",
]
## The two lines of `UnitLayer._update_rigs` that name an array type without making an array: local
## names for the layer's own arrays. They are taken out before the tokens are looked for, and the
## test checks that they are there, so nothing else is let through.
const ALIASES: Array[String] = [
	"var rigs: Array[Node2D] = _rigs",
	"var layers: Array[Sprite2D] = _layers",
]
const HEAVY_TANKS: int = 40
const LIGHT_TANKS: int = 30
const VOLLEYS: int = 3
const VOLLEY_TICKS: int = 30
const FRAMES_PER_TICK: int = 4
## The sprite writes of the three volleys, pinned: 830 for each, a heavy tank's Turret 10 and Hull 4
## and a light tank's Turret 9 (40 x 14 + 30 x 9, restated in Python from the curve at four frames
## to a tick), and the busiest frame, the first, when all 70 Turrets and 40 Hulls move.
const VOLLEY_WRITES: int = 2490
const BUSIEST_FRAME: int = 110

var _runner: MatchRunner
var _units: UnitLayer
var _buildings: BuildingLayer


func before_test() -> void:
	_runner = auto_free(Rig.runner())


func after_test() -> void:
	CommandQueue.clear()


func test_the_tick_and_frame_path_makes_no_array_and_grows_none() -> void:
	for path: String in FRAME_PATH:
		for func_name: String in FRAME_PATH[path]:
			var code: String = SourceScan.function(path, func_name)
			assert_int(code.count("\n")).override_failure_message(func_name).is_greater(2)
			if func_name == "_update_rigs":
				for alias: String in ALIASES:
					assert_bool(code.contains(alias)).override_failure_message(alias).is_true()
					code = code.replace(alias, "")
			for token: String in ALLOCATING:
				var note: String = (
					"%s %s makes an array or grows one with %s" % [path, func_name, token]
				)
				assert_bool(code.contains(token)).override_failure_message(note).is_false()


func test_shots_and_frames_leave_no_object_or_node_behind() -> void:
	_make_layers()
	var shooters: Array[int] = [Rig.LIGHT, Rig.HEAVY, Rig.REDOUBT]
	for index: int in 40:  # Warm up: the first frames may make the engine's own objects.
		_play_frame(index, shooters)
	var objects: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for index: int in range(40, 640):  # Many shots, many kicks that start, run and end.
		_play_frame(index, shooters)
	assert_int(roundi(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(objects)
	assert_int(roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))).is_equal(nodes)
	assert_int(_units.life_writes()).is_greater(0)  # The shots did kick.
	assert_int(_buildings.life_writes()).is_greater(0)


func test_a_volley_of_seventy_tanks_stays_inside_the_sprite_write_budget() -> void:
	_runner = auto_free(Buildings.runner(_volley_scenario()))
	_make_layers()
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(HEAVY_TANKS + LIGHT_TANKS)
	var total: int = 0
	var busiest: int = 0
	var frames: int = VOLLEYS * VOLLEY_TICKS * FRAMES_PER_TICK
	for frame: int in frames:
		var tick: int = 30 + frame / FRAMES_PER_TICK
		if frame % (VOLLEY_TICKS * FRAMES_PER_TICK) == 0:
			Rig.deliver(_runner, _volley(snap), tick)
		Rig.at(_runner, tick, float(frame % FRAMES_PER_TICK) / FRAMES_PER_TICK)
		var before: int = _units.life_writes()
		_units._process(0.0)
		var written: int = _units.life_writes() - before
		total += written
		busiest = maxi(busiest, written)
	assert_int(busiest).is_less_equal(150)
	assert_float(float(total) / frames).is_less_equal(60.0)
	assert_int(busiest).is_equal(BUSIEST_FRAME)
	assert_int(total).is_equal(VOLLEY_WRITES)
	assert_int(_units.kick_count()).is_equal(0)  # Every kick ended and was dropped.


## The runner's scenario with two big groups: 40 Derrick League heavy tanks and 30 light tanks.
func _volley_scenario() -> ScenarioDef:
	var heavy: SpawnDef = Buildings.spawn(1, "heavy_tank", 2, 2)
	heavy.count = HEAVY_TANKS
	heavy.columns = 8
	heavy.spacing = 1300
	var light: SpawnDef = Buildings.spawn(1, "light_tank", 2, 16)
	light.count = LIGHT_TANKS
	light.columns = 8
	light.spacing = 1300
	var spawns: Array[SpawnDef] = [heavy, light]
	return Buildings.scenario(spawns)


## One SHOT record per tank, each from its own place and straight east on the screen.
func _volley(snap: MatchSnapshot) -> PackedInt32Array:
	var events: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		var from: Vector2i = Vector2i(snap.pos_x[row], snap.pos_y[row])
		var weapon: int = snap.type_weapon[snap.type_index[row]]
		events.append_array(
			PackedInt32Array(
				[
					World.Event.SHOT,
					snap.unit_id[row],
					from.x,
					from.y,
					0,
					weapon,
					from.x + Rig.EAST_ON_SCREEN.x,
					from.y + Rig.EAST_ON_SCREEN.y
				]
			)
		)
	return events


func _make_layers() -> void:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = camera
	_units.life = Rig.calmed(null)  # The recoil's share: the idle life has suites of its own.
	add_child(_units)
	_units.set_process(false)
	_units._process(0.0)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.life = Rig.calmed(null)
	add_child(_buildings)
	_buildings.set_process(false)
	_buildings._process(0.0)


## Frame `index` of a long play: a tick every 4 frames, every 10th frame a shot of each of
## `shooters`, straight east on the screen with the shooter's own weapon.
func _play_frame(index: int, shooters: Array[int]) -> void:
	var tick: int = 30 + index / FRAMES_PER_TICK
	if index % 10 == 0:
		for id: int in shooters:
			var snap: MatchSnapshot = _runner.snapshot
			var row: int = snap.index_of(id)
			var weapon: int = snap.type_weapon[snap.type_index[row]]
			var from: Vector2i = Rig.position_of(_runner, id)
			var aim: Vector2i = from + Rig.EAST_ON_SCREEN
			var events: PackedInt32Array = PackedInt32Array(
				[World.Event.SHOT, id, from.x, from.y, 0, weapon, aim.x, aim.y]
			)
			Rig.deliver(_runner, events, tick)
	Rig.at(_runner, tick, float(index % FRAMES_PER_TICK) / FRAMES_PER_TICK)
	_units._process(0.0)
	_buildings._process(0.0)
