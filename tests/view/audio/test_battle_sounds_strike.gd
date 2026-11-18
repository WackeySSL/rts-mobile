extends GdUnitTestSuite
## BattleSounds and the strike cues (plan P504b, ADR 0041 section 4): the launch and the landing of
## a rupture, the blackout and the sweep; own or seen only (the fog gate), the landing waits for
## its tick, and a cue without a file falls back to the tone. On controls_test player 1 sees
## tile (8, 18) and not tile (40, 40).

const Fog: GDScript = preload("res://tests/view/support/fog_rig.gd")
const AudioSpy: GDScript = preload("res://tests/view/audio/support/audio_spy.gd")
const TABLE: AudioCueTable = preload("res://data/audio_cues.tres")
const SEEN: Vector2i = Vector2i(8500, 18500)
const DARK: Vector2i = Vector2i(40500, 40500)
const EVERYWHERE: Rect2 = Rect2(-100000, -100000, 200000, 200000)
const LAUNCH: StringName = &"strike_rupture_launch"
const LAND: StringName = &"strike_rupture_land"
const BLACKOUT: StringName = &"strike_blackout"
const SWEEP: StringName = &"strike_sweep"

var _now_ms: int = 0
var _tick: int = 0
var _runner: MatchRunner
var _sounds: BattleSounds
var _spy: AudioSpy
var _settings: AudioSettings


func before_test() -> void:
	_now_ms = 1000
	_tick = 0
	_settings = (load("res://data/audio_settings.tres") as AudioSettings).duplicate()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Fog.scenario(1)
	_runner.start()
	_spy = auto_free(AudioSpy.new())
	_spy.settings = _settings
	_make(TABLE)


func after_test() -> void:
	CommandQueue.clear()


func _make(table: AudioCueTable) -> void:
	if _sounds != null:
		_sounds.free()
	_sounds = BattleSounds.new()
	_sounds.runner = _runner
	_sounds.audio = _spy
	_sounds.table = table
	_sounds.clock = func() -> int: return _now_ms
	_sounds.view_rect = func() -> Rect2: return EVERYWHERE
	add_child(_sounds)


func _deliver(events: PackedInt32Array) -> void:
	_tick += 1
	_now_ms += 1000
	_runner.snapshot.events = events
	_runner.ticked.emit(_tick)


## `[STRIKE, building id, x, y, kind, owner, landing tick, 0]`.
func _strike(kind: int, at: Vector2i, owner_id: int, landing: int = 0) -> PackedInt32Array:
	return PackedInt32Array([World.Event.STRIKE, 7, at.x, at.y, kind, owner_id, landing, 0])


func test_a_rupture_launch_sounds_when_own_or_seen_and_not_in_the_dark() -> void:
	_deliver(_strike(Strike.Kind.RUPTURE, DARK, 2))
	assert_int(_spy.plays).is_equal(0)
	_deliver(_strike(Strike.Kind.RUPTURE, SEEN, 2))
	assert_array(_spy.cues).is_equal([LAUNCH])
	_deliver(_strike(Strike.Kind.RUPTURE, DARK, 1))
	assert_array(_spy.cues).is_equal([LAUNCH, LAUNCH])


func test_the_landing_sounds_at_its_tick_even_in_a_tick_without_events() -> void:
	_deliver(_strike(Strike.Kind.RUPTURE, SEEN, 2, _tick + 4))
	assert_array(_spy.cues).is_equal([LAUNCH])
	for _step: int in 2:
		_deliver(PackedInt32Array())
	assert_int(_spy.plays).is_equal(1)
	_deliver(PackedInt32Array())
	assert_array(_spy.cues).is_equal([LAUNCH, LAND])
	_deliver(PackedInt32Array())
	assert_int(_spy.plays).is_equal(2)


func test_an_enemy_landing_in_the_dark_is_silent_and_an_own_one_sounds() -> void:
	_deliver(_strike(Strike.Kind.RUPTURE, DARK, 2, _tick + 2))
	_deliver(PackedInt32Array())
	_deliver(PackedInt32Array())
	assert_int(_spy.plays).is_equal(0)
	_deliver(_strike(Strike.Kind.RUPTURE, DARK, 1, _tick + 2))
	_deliver(PackedInt32Array())
	_deliver(PackedInt32Array())
	assert_array(_spy.cues).is_equal([LAUNCH, LAND])


func test_the_blackout_and_the_sweep_follow_the_fog_gate() -> void:
	_deliver(_strike(Strike.Kind.BLACKOUT, DARK, 2))
	assert_int(_spy.plays).is_equal(0)
	_deliver(_strike(Strike.Kind.BLACKOUT, SEEN, 2))
	assert_array(_spy.cues).is_equal([BLACKOUT])
	_deliver(_strike(Strike.Kind.REVEAL, Vector2i.ZERO, 2))
	assert_int(_spy.plays).is_equal(1)
	_deliver(_strike(Strike.Kind.REVEAL, Vector2i.ZERO, 1))
	assert_array(_spy.cues).is_equal([BLACKOUT, SWEEP])


func test_a_strike_cue_without_a_file_falls_back_to_the_tone() -> void:
	var bare: AudioCueTable = TABLE.duplicate(true) as AudioCueTable
	for def: AudioCueDef in bare.cues:
		if str(def.id).begins_with("strike_"):
			def.streams = []
	_make(bare)
	_deliver(_strike(Strike.Kind.BLACKOUT, SEEN, 1))
	assert_array(_spy.cues).is_equal([BLACKOUT])
	assert_str(_spy.streams[0].resource_path).is_empty()
	_make(TABLE)
	_deliver(_strike(Strike.Kind.BLACKOUT, SEEN, 1))
	assert_str(_spy.streams[1].resource_path).starts_with("res://assets/audio/sfx/strike/")


func test_the_table_names_the_strike_cues_and_each_has_a_recording() -> void:
	for cue_id: StringName in [
		TABLE.strike_rupture_launch,
		TABLE.strike_rupture_land,
		TABLE.strike_blackout,
		TABLE.strike_sweep
	]:
		var at: int = TABLE.index_of(cue_id)
		assert_int(at).override_failure_message(str(cue_id)).is_greater(-1)
		assert_int(TABLE.cues[at].streams.size()).override_failure_message(str(cue_id)).is_equal(1)
