extends GdUnitTestSuite
## UiSounds (ADR 0041 section 4): the click of a button added after it, the opt-out meta, the order
## chirp for the local player's Commands only, and the alert chirp on a shown attack cue. The
## service and the queue are the test's own instances, so the real autoloads stay untouched.

const SERVICE_SCRIPT: String = "res://game/view/audio/audio_service.gd"
const QUEUE_SCRIPT: String = "res://game/core/command_queue_service.gd"
const SETTINGS_PATH: String = "res://data/audio_settings.tres"

var _service: Node
var _queue: Node
var _sounds: UiSounds
var _cues: AttackCues


func _stream() -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.data = PackedByteArray([0, 0, 0, 0])
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 4
	return wav


func _make_sounds() -> UiSounds:
	var def: UiSoundsDef = UiSoundsDef.new()
	def.click_stream = _stream()
	def.order_stream = _stream()
	def.alert_stream = _stream()
	var sounds: UiSounds = UiSounds.new()
	sounds.def = def
	sounds.audio = _service
	sounds.queue = _queue
	return sounds


func before_test() -> void:
	var settings: AudioSettings = (load(SETTINGS_PATH) as AudioSettings).duplicate()
	settings.fade_ms = 0
	_service = (load(SERVICE_SCRIPT) as GDScript).new()
	_service.set("settings", settings)
	add_child(_service)
	_queue = auto_free((load(QUEUE_SCRIPT) as GDScript).new())
	_cues = AttackCues.new()
	add_child(_cues)
	_sounds = _make_sounds()
	add_child(_sounds)
	_sounds.connect_attack_cues(_cues)


func after_test() -> void:
	_sounds.free()
	_cues.free()
	_service.free()


func _active(cue: StringName) -> int:
	return (_service.call(&"get_pool_for_tests") as VoicePool).active_of(cue)


func test_a_button_added_after_the_node_clicks() -> void:
	var button: Button = Button.new()
	add_child(button)
	button.pressed.emit()
	assert_int(_active(&"ui_click")).is_equal(1)
	button.free()


func test_a_button_in_the_tree_before_the_node_clicks() -> void:
	var early: Button = Button.new()
	add_child(early)
	var late: UiSounds = _make_sounds()
	add_child(late)
	early.pressed.emit()
	assert_int(_active(&"ui_click")).is_equal(1)
	early.free()
	late.free()


func test_a_button_with_no_click_meta_is_silent_also_when_set_after_entering() -> void:
	var button: Button = Button.new()
	add_child(button)
	button.set_meta(UiSounds.META_NO_CLICK, true)
	button.pressed.emit()
	assert_int(_active(&"ui_click")).is_equal(0)
	button.free()


func test_re_entering_the_tree_does_not_double_the_hook() -> void:
	var button: Button = Button.new()
	add_child(button)
	remove_child(button)
	add_child(button)
	assert_int(button.pressed.get_connections().size()).is_equal(1)
	button.free()


func test_the_order_chirp_plays_for_the_local_player_only() -> void:
	_queue.submit(Command.stop(2, PackedInt32Array([1])))
	assert_int(_active(&"ui_order")).is_equal(0)
	_queue.submit(Command.stop(1, PackedInt32Array([1])))
	assert_int(_active(&"ui_order")).is_equal(1)


func test_a_logged_command_does_not_chirp() -> void:
	_queue.submit_logged(Command.stop(1, PackedInt32Array([1])))
	assert_int(_active(&"ui_order")).is_equal(0)


func test_the_alert_chirp_plays_for_a_shown_cue_not_a_dismissed_one() -> void:
	_cues.active = false
	_cues.cue_changed.emit()
	assert_int(_active(&"ui_alert")).is_equal(0)
	_cues.active = true
	_cues.cue_changed.emit()
	assert_int(_active(&"ui_alert")).is_equal(1)


func test_nothing_plays_while_the_service_is_muted() -> void:
	_service.call(&"add_mute_reason", &"ad")
	var button: Button = Button.new()
	add_child(button)
	button.pressed.emit()
	assert_int(_active(&"ui_click")).is_equal(0)
	_service.call(&"clear_mute_reason", &"ad")
	button.free()


func test_the_shipped_data_loads() -> void:
	var def: UiSoundsDef = load(UiSounds.DEF_PATH) as UiSoundsDef
	assert_object(def).is_not_null()
	assert_int(def.max_voices).is_greater(0)
