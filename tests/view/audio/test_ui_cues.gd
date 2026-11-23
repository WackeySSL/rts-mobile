extends GdUnitTestSuite
## UiSounds, P505b: the back, confirm and refuse cues (the `ui_cue` meta, a press on a disabled
## button, `back_requested`), the opt-out meta over them, and the shipped definition. The service
## and the queue are the test's own instances. The test streams loop, so a voice stays active.

const SERVICE_SCRIPT: String = "res://game/view/audio/audio_service.gd"
const QUEUE_SCRIPT: String = "res://game/core/command_queue_service.gd"
const SETTINGS_PATH: String = "res://data/audio_settings.tres"


## Records the cue ids it is asked to play (the real service's `play_ui` signature).
class FakeAudio:
	extends Node
	var cues: Array[StringName] = []

	func play_ui(
		_stream: AudioStream,
		cue: StringName,
		_priority: int = 0,
		_max_voices: int = 0,
		_volume_db: float = 0.0
	) -> bool:
		cues.append(cue)
		return true


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
	def.back_stream = _stream()
	def.confirm_stream = _stream()
	def.refuse_stream = _stream()
	def.order_streams = [_stream()]
	def.alert_stream = _stream()
	var sounds: UiSounds = UiSounds.new()
	sounds.def = def
	sounds.audio = _service
	sounds.queue = _queue
	sounds.local_player = 1
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


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _button() -> Button:
	var button: Button = auto_free(Button.new())
	return button


func _press_cue(role: StringName) -> void:
	var button: Button = _button()
	add_child(button)
	button.set_meta(UiSounds.META_CUE, role)
	button.pressed.emit()
	await _frames()


func test_a_back_button_plays_the_back_cue_not_the_click() -> void:
	await _press_cue(UiSounds.CUE_BACK)
	assert_int(_active(&"ui_back")).is_equal(1)
	assert_int(_active(&"ui_click")).is_equal(0)


func test_a_confirm_button_plays_the_confirm_cue() -> void:
	await _press_cue(UiSounds.CUE_CONFIRM)
	assert_int(_active(&"ui_confirm")).is_equal(1)
	assert_int(_active(&"ui_click")).is_equal(0)


func test_no_click_also_silences_a_button_with_a_cue_meta() -> void:
	var button: Button = _button()
	add_child(button)
	button.set_meta(UiSounds.META_CUE, UiSounds.CUE_BACK)
	button.set_meta(UiSounds.META_NO_CLICK, true)
	button.pressed.emit()
	await _frames()
	assert_int(_active(&"ui_back")).is_equal(0)


func _mouse_press() -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func test_a_press_on_a_disabled_button_plays_the_refuse_cue() -> void:
	var button: Button = _button()
	button.disabled = true
	add_child(button)
	button.gui_input.emit(_mouse_press())
	await _frames()
	assert_int(_active(&"ui_refuse")).is_equal(1)


func test_a_touch_and_its_emulated_mouse_press_refuse_once() -> void:
	var fake: FakeAudio = auto_free(FakeAudio.new())
	_sounds.audio = fake
	var button: Button = _button()
	button.disabled = true
	add_child(button)
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	button.gui_input.emit(touch)
	button.gui_input.emit(_mouse_press())
	await _frames()
	assert_array(fake.cues).is_equal([UiSounds.CUE_REFUSE])


func test_an_enabled_button_a_release_and_a_no_click_button_do_not_refuse() -> void:
	var live: Button = _button()
	add_child(live)
	live.gui_input.emit(_mouse_press())
	var silent: Button = _button()
	silent.disabled = true
	silent.set_meta(UiSounds.META_NO_CLICK, true)
	add_child(silent)
	silent.gui_input.emit(_mouse_press())
	var released: Button = _button()
	released.disabled = true
	add_child(released)
	var up: InputEventMouseButton = _mouse_press()
	up.pressed = false
	released.gui_input.emit(up)
	await _frames()
	assert_int(_active(&"ui_refuse")).is_equal(0)


class BackSource:
	extends Node
	signal back_requested


func test_a_back_requested_signal_plays_the_back_cue_also_on_a_node_in_the_tree_before() -> void:
	var late: BackSource = auto_free(BackSource.new())
	add_child(late)
	late.back_requested.emit()
	await _frames()
	assert_int(_active(&"ui_back")).is_equal(1)
	remove_child(_sounds)
	var early: BackSource = auto_free(BackSource.new())
	add_child(early)
	add_child(_sounds)
	var fake: FakeAudio = auto_free(FakeAudio.new())
	_sounds.audio = fake
	early.back_requested.emit()
	await _frames()
	assert_array(fake.cues).is_equal([UiSounds.CUE_BACK])
	assert_int(late.back_requested.get_connections().size()).is_equal(1)


func test_the_phone_back_button_of_the_menu_stack_emits_the_signal() -> void:
	var stack: MenuStack = auto_free(MenuStack.new())
	add_child(stack)
	var hits: Array[int] = [0]
	stack.back_requested.connect(func() -> void: hits[0] += 1)
	stack.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames()  # The back is handled deferred; the root opens its quit question.
	stack.back_enabled = false
	stack.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames()
	assert_int(hits[0]).is_equal(1)


func test_the_dialog_buttons_carry_the_confirm_and_back_cues() -> void:
	var dialog: ConfirmDialog = auto_free(ConfirmDialog.new())
	add_child(dialog)
	var yes: Button = dialog.find_child("YesButton", true, false) as Button
	var no: Button = dialog.find_child("NoButton", true, false) as Button
	assert_str(str(yes.get_meta(UiSounds.META_CUE))).is_equal(str(UiSounds.CUE_CONFIRM))
	assert_str(str(no.get_meta(UiSounds.META_CUE))).is_equal(str(UiSounds.CUE_BACK))


func test_the_shipped_definition_has_a_stream_for_every_interface_cue() -> void:
	var shipped: UiSoundsDef = load(UiSounds.DEF_PATH) as UiSoundsDef
	for stream: AudioStream in [
		shipped.click_stream, shipped.back_stream, shipped.confirm_stream, shipped.refuse_stream
	]:
		assert_object(stream).is_not_null()
		assert_float(stream.get_length()).is_between(0.03, 0.3)
