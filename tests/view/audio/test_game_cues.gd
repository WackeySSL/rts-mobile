extends GdUnitTestSuite
## The game cues of plan row P505a (ADR 0041 section 4): each cue id resolves to its generated file
## (no placeholder tone is left for sell, repair and unload), an own SPAWNED row sounds as "unit
## ready" or "building placed" and an enemy one never does, the order chirps take turns, switching
## a repair on has its own sound, and the Ready chip and the low-power pill chirp.

const Fog: GDScript = preload("res://tests/view/support/fog_rig.gd")
const AudioSpy: GDScript = preload("res://tests/view/audio/support/audio_spy.gd")
const TABLE: AudioCueTable = preload("res://data/audio_cues.tres")
const UI: UiSoundsDef = preload("res://data/audio_ui_sounds.tres")
const SFX: String = "res://assets/audio/sfx/"
const EVERYWHERE: Rect2 = Rect2(-100000, -100000, 200000, 200000)
const DARK: Vector2i = Vector2i(40500, 40500)
## World cue id -> the file of its one stream.
const WORLD_FILES: Dictionary[StringName, String] = {
	&"unit_ready": "unit/ready_1.wav",
	&"building_placed": "building/placed_1.wav",
	&"board": "unit/board_1.wav",
	&"unloaded": "unit/unload_1.wav",
	&"sold": "building/sold_1.wav",
	&"repaired": "building/repair_1.wav",
}


## Records the stream and cue of each Ui play.
class FakeAudio:
	extends Node
	var cues: Array[StringName] = []
	var streams: Array[AudioStream] = []

	func play_ui(
		stream: AudioStream,
		cue: StringName,
		_priority: int = 0,
		_max_voices: int = 0,
		_volume_db: float = 0.0
	) -> bool:
		cues.append(cue)
		streams.append(stream)
		return true


var _runner: MatchRunner
var _spy: AudioSpy
var _sounds: BattleSounds
var _tick: int = 0
var _now_ms: int = 0


func before_test() -> void:
	_tick = 0
	_now_ms = 1000
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Fog.scenario(1)
	_runner.start()
	_spy = auto_free(AudioSpy.new())
	_spy.settings = (load("res://data/audio_settings.tres") as AudioSettings).duplicate()
	_sounds = auto_free(BattleSounds.new())
	_sounds.runner = _runner
	_sounds.audio = _spy
	_sounds.clock = func() -> int: return _now_ms
	_sounds.view_rect = func() -> Rect2: return EVERYWHERE
	add_child(_sounds)


func _deliver(events: PackedInt32Array) -> void:
	_tick += 1
	_now_ms += 1000
	_runner.snapshot.events = events
	_runner.ticked.emit(_tick)


func _spawned(type: int, owner_id: int, at: Vector2i = Vector2i(8500, 18500)) -> PackedInt32Array:
	return PackedInt32Array([World.Event.SPAWNED, 7, at.x, at.y, type, owner_id, 0, 0])


## A mobile type (index 0 of the roster) and, for a building, the same row marked as one.
func _first_of(armour_is_building: bool) -> int:
	_runner.snapshot.type_armour[0] = (
		World.Armour.BUILDING if armour_is_building else World.Armour.LIGHT
	)
	return 0


func test_every_world_cue_resolves_to_its_generated_file() -> void:
	for cue_id: StringName in WORLD_FILES:
		var def: AudioCueDef = TABLE.cues[TABLE.index_of(cue_id)]
		assert_int(def.streams.size()).override_failure_message(str(cue_id)).is_equal(1)
		assert_str(def.streams[0].resource_path).override_failure_message(str(cue_id)).is_equal(
			SFX + WORLD_FILES[cue_id]
		)
		assert_bool(FileAccess.file_exists(SFX + WORLD_FILES[cue_id])).is_true()
	assert_str(TABLE.unit_ready).is_equal(&"unit_ready")
	assert_str(TABLE.building_placed).is_equal(&"building_placed")
	assert_str(TABLE.board).is_equal(&"board")


func test_sell_repair_and_unload_use_files_not_the_placeholder_tone() -> void:
	for cue_id: StringName in [TABLE.sold, TABLE.repaired, TABLE.unloaded]:
		var def: AudioCueDef = TABLE.cues[TABLE.index_of(cue_id)]
		assert_bool(def.streams.is_empty()).override_failure_message(str(cue_id)).is_false()
		var made: BattleSounds.Built = BattleSounds._make_built(TABLE)
		var at: int = made.first[TABLE.index_of(cue_id)]
		for stream: AudioStream in made.streams.slice(at, at + def.streams.size()):
			assert_str(stream.resource_path).starts_with(SFX)


func test_the_ui_cues_resolve_to_their_files() -> void:
	var orders: Array[String] = []
	for stream: AudioStream in UI.order_streams:
		orders.append(stream.resource_path)
	assert_array(orders).is_equal(
		[SFX + "radio/order_1.wav", SFX + "radio/order_2.wav", SFX + "radio/order_3.wav"]
	)
	assert_str(UI.alert_stream.resource_path).is_equal(SFX + "radio/alert_1.wav")
	assert_str(UI.ready_stream.resource_path).is_equal(SFX + "building/complete_1.wav")
	assert_str(UI.power_stream.resource_path).is_equal(SFX + "radio/low_power_1.wav")
	assert_str(UI.mend_stream.resource_path).is_equal(SFX + "building/mend_1.wav")


func test_an_own_unit_spawn_sounds_ready_wherever_the_camera_is() -> void:
	var unit: int = _first_of(false)
	_sounds.view_rect = func() -> Rect2: return Rect2(DARK.x, DARK.y, 1, 1)
	_deliver(_spawned(unit, 1, DARK))
	assert_array(_spy.cues).is_equal([&"unit_ready"])


func test_an_own_building_spawn_sounds_placed_and_an_enemy_spawn_is_silent() -> void:
	_deliver(_spawned(_first_of(true), 1))
	assert_array(_spy.cues).is_equal([&"building_placed"])
	_deliver(_spawned(_first_of(true), 2))
	_deliver(_spawned(_first_of(false), 2))
	assert_int(_spy.plays).is_equal(1)


func _queue() -> Node:
	return auto_free((load("res://game/core/command_queue_service.gd") as GDScript).new())


func _ui_sounds(audio: Node, queue: Node) -> UiSounds:
	var sounds: UiSounds = auto_free(UiSounds.new())
	sounds.def = UI
	sounds.audio = audio
	sounds.queue = queue
	sounds.local_player = 1
	add_child(sounds)
	return sounds


func test_the_order_chirps_take_turns_and_a_repair_switch_has_its_own_sound() -> void:
	var audio: FakeAudio = auto_free(FakeAudio.new())
	var queue: Node = _queue()
	_ui_sounds(audio, queue)
	for i: int in 4:
		queue.submit(Command.stop(1, PackedInt32Array([1])))
	assert_array(audio.streams.slice(0, 4)).is_equal(
		[UI.order_streams[0], UI.order_streams[1], UI.order_streams[2], UI.order_streams[0]]
	)
	queue.submit(Command.mend(1, 5, true))
	assert_str(audio.cues[4]).is_equal(&"ui_mend")
	queue.submit(Command.mend(1, 5, false))
	assert_str(audio.cues[5]).is_equal(&"ui_order")


func test_the_ready_chip_and_the_low_power_pill_chirp() -> void:
	var audio: FakeAudio = auto_free(FakeAudio.new())
	var queue: Node = _queue()
	var sounds: UiSounds = _ui_sounds(audio, queue)
	var button: BuildButton = auto_free(BuildButton.new())
	var pill: EconomyPill = auto_free(EconomyPill.new())
	sounds.connect_hud(button, pill)
	button.ready_type = -1
	button.ready_changed.emit()  # The chip went: silent.
	assert_int(audio.cues.size()).is_equal(0)
	button.ready_type = 3
	button.ready_changed.emit()
	pill.low_power_started.emit()
	assert_array(audio.cues).is_equal([&"ui_ready", &"ui_low_power"])
