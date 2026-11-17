extends GdUnitTestSuite
## BattleSounds, second suite (plan P502; the first is test_battle_sounds.gd, and gdlint allows 20
## public methods per file): the stack cap, no object per tick on the real pool, the match end, the
## data guards (a null stream, no pitch steps) and what the cue data names.

const Fog: GDScript = preload("res://tests/view/support/fog_rig.gd")
const AudioSpy: GDScript = preload("res://tests/view/audio/support/audio_spy.gd")
const Rig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const SERVICE_SCRIPT: String = "res://game/view/audio/audio_service.gd"
const TABLE: AudioCueTable = preload("res://data/audio_cues.tres")
const SEEN: Vector2i = Vector2i(8500, 18500)
const DARK: Vector2i = Vector2i(40500, 40500)
const EVERYWHERE: Rect2 = Rect2(-100000, -100000, 200000, 200000)

var _now_ms: int = 0
var _tick: int = 0
var _runner: MatchRunner
var _sounds: BattleSounds
var _spy: AudioSpy
var _settings: AudioSettings
var _service: Node
var _tank: int = 0


func before_test() -> void:
	_now_ms = 1000
	_tick = 0
	_settings = (load("res://data/audio_settings.tres") as AudioSettings).duplicate()
	_settings.fade_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Fog.scenario(1)
	_runner.start()
	_tank = _runner.snapshot.type_ids.find(&"light_tank")
	_spy = auto_free(AudioSpy.new())
	_spy.settings = _settings
	_make(_spy)


func after_test() -> void:
	if _service != null:
		_service.free()
		_service = null
	CommandQueue.clear()


func _make(audio: Node) -> void:
	if _sounds != null:
		_sounds.free()
	_sounds = BattleSounds.new()
	_sounds.runner = _runner
	_sounds.audio = audio
	_sounds.clock = func() -> int: return _now_ms
	_sounds.view_rect = func() -> Rect2: return EVERYWHERE
	add_child(_sounds)


func _real_service() -> Node:
	_service = (load(SERVICE_SCRIPT) as GDScript).new()
	_service.set("settings", _settings)
	add_child(_service)
	_make(_service)
	return _service


func _deliver(events: PackedInt32Array) -> void:
	_tick += 1
	_runner.snapshot.events = events
	_runner.ticked.emit(_tick)


func _record(kind: int, at: Vector2i, unit_id: int = 1, owner_id: int = 2) -> PackedInt32Array:
	match kind:
		World.Event.SHOT:
			return Rig.shot(at, at, 0, unit_id)
		World.Event.IMPACT:
			return Rig.impact(at, 0, unit_id)
		World.Event.DIED:
			return Rig.died(at, _tank, unit_id, owner_id)
	return PackedInt32Array([kind, unit_id, at.x, at.y, 0, owner_id, 0, 0])


func test_a_real_pool_tick_makes_no_object() -> void:
	_real_service()
	var events: PackedInt32Array = _record(World.Event.SHOT, SEEN)
	events.append_array(_record(World.Event.DIED, SEEN, 2))
	events.append_array(_record(World.Event.IMPACT, DARK, 3))
	for _warm: int in 8:  # Every voice of the cues has played once.
		_now_ms += 1000
		_deliver(events)
	var before: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	for _round: int in 200:
		_now_ms += 1000
		_deliver(events)
	assert_int(roundi(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(before)
	assert_int(_service.get_pool_for_tests().active_world()).is_greater(0)


func test_the_stack_stops_at_max_stack() -> void:
	var table: AudioCueTable = TABLE
	var def: AudioCueDef = table.cues[table.index_of(&"shot_cannon")]
	var events: PackedInt32Array = PackedInt32Array()
	for unit_id: int in 6:
		events.append_array(_record(World.Event.SHOT, SEEN, unit_id))
	_deliver(events)
	assert_int(_spy.plays).is_equal(1)
	var expected: float = def.volume_db + float(def.max_stack) * _settings.stack_db
	assert_float(_spy.last_db).is_equal_approx(expected, 0.001)


func test_the_end_of_a_match_lifts_the_pool_budget() -> void:
	_runner.match_ended.emit(1)
	assert_int(_spy.ended).is_equal(1)
	_settings.voices_per_tick = 1
	var service: Node = _real_service()
	_deliver(_record(World.Event.SHOT, SEEN))
	service.begin_tick()
	_runner.match_ended.emit(1)
	var pool: VoicePool = service.get_pool_for_tests()
	var stream: AudioStream = PlaceholderTone.make(200, 50, 0)
	# The budget of 1 is spent; with it lifted two more voices start outside a tick loop.
	assert_bool(pool.play_world(stream, Vector2.ZERO, &"a")).is_true()
	assert_bool(pool.play_world(stream, Vector2.ZERO, &"b")).is_true()


func test_a_cue_with_a_null_stream_or_no_pitch_steps_does_not_crash() -> void:
	var table: AudioCueTable = (TABLE).duplicate(true)
	var def: AudioCueDef = table.cues[table.index_of(&"shot_cannon")]
	var nothing: AudioStream = null
	def.streams = [nothing]
	def.pitch_steps = PackedInt32Array()
	def.variants = 99
	_sounds.free()
	_sounds = BattleSounds.new()
	_sounds.runner = _runner
	_sounds.table = table
	_sounds.audio = _spy
	_sounds.clock = func() -> int: return _now_ms
	_sounds.view_rect = func() -> Rect2: return EVERYWHERE
	add_child(_sounds)
	_deliver(_record(World.Event.SHOT, SEEN))
	assert_int(_spy.plays).is_equal(1)
	assert_float(_spy.last_pitch).is_equal(1.0)
	assert_object(_spy.streams[0]).is_not_null()


func test_the_cue_data_names_real_weapons_and_is_safe_to_play() -> void:
	var table: AudioCueTable = TABLE
	var ids: Array[StringName] = [
		table.shot_hitscan,
		table.shot_shell,
		table.impact_default,
		table.mine_blast,
		table.repaired,
		table.unloaded,
		table.death_foot,
		table.death_vehicle,
		table.death_air,
		table.death_building,
		table.sold,
	]
	ids.append_array(table.shot_cues.values())
	ids.append_array(table.impact_cues.values())
	for cue_id: StringName in ids:
		assert_int(table.index_of(cue_id)).override_failure_message(str(cue_id)).is_greater(-1)
	var weapons: Array[StringName] = []
	for file: String in DirAccess.get_files_at("res://data/weapons"):
		if file.ends_with(".tres"):
			weapons.append((load("res://data/weapons/" + file) as WeaponDef).id)
	assert_int(weapons.size()).is_greater(10)
	for map: Dictionary in [table.shot_cues, table.impact_cues]:
		for weapon: StringName in map:
			assert_bool(weapons.has(weapon)).override_failure_message(str(weapon)).is_true()
	for def: AudioCueDef in table.cues:
		var named: String = str(def.id)
		assert_int(def.pitch_steps.size()).override_failure_message(named).is_greater(0)
		assert_int(def.variants).override_failure_message(named).is_greater(0)
		assert_int(def.tone_ms).override_failure_message(named).is_greater(0)
		for stream: AudioStream in def.streams:
			assert_object(stream).override_failure_message(named).is_not_null()
