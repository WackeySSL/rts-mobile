extends GdUnitTestSuite
## UiSounds, P505b review: one cue per press when the press sends an order (the real ModalFrame
## order: the action is connected before the button enters the tree), an unknown `ui_cue` clicks
## with one warning, a wait state (`UiWait`) gives no refuse while a plain disabled button does,
## and `UiWait` puts back a `no_click` the button had before.

const QUEUE_SCRIPT: String = "res://game/core/command_queue_service.gd"


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


var _audio: FakeAudio
var _queue: Node
var _sounds: UiSounds


func before_test() -> void:
	_audio = auto_free(FakeAudio.new())
	_queue = auto_free((load(QUEUE_SCRIPT) as GDScript).new())
	var def: UiSoundsDef = UiSoundsDef.new()
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	def.click_stream = stream
	def.back_stream = stream
	def.confirm_stream = stream
	def.refuse_stream = stream
	def.order_streams = [stream]
	_sounds = auto_free(UiSounds.new())
	_sounds.def = def
	_sounds.audio = _audio
	_sounds.queue = _queue
	_sounds.local_player = 1
	add_child(_sounds)


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _mouse_press() -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _order() -> void:
	_queue.submit(Command.stop(1, PackedInt32Array([1])))


func test_a_confirm_that_sends_an_order_plays_only_the_chirp_with_the_action_connected_first(
) -> void:
	var yes: Button = auto_free(Button.new())
	yes.set_meta(&"ui_cue", &"ui_confirm")
	yes.pressed.connect(_order)  # As ModalFrame.add_button: the action, then add_child.
	add_child(yes)
	yes.pressed.emit()
	await _frames()
	assert_array(_audio.cues).is_equal([UiSounds.CUE_ORDER])


func test_a_plain_button_that_sends_an_order_plays_only_the_chirp() -> void:
	var button: Button = auto_free(Button.new())
	button.pressed.connect(_order)
	add_child(button)
	button.pressed.emit()
	await _frames()
	assert_array(_audio.cues).is_equal([UiSounds.CUE_ORDER])


func test_a_confirm_without_an_order_still_plays_the_confirm_cue() -> void:
	var yes: Button = auto_free(Button.new())
	yes.set_meta(&"ui_cue", &"ui_confirm")
	add_child(yes)
	yes.pressed.emit()
	await _frames()
	assert_array(_audio.cues).is_equal([UiSounds.CUE_CONFIRM])


func test_an_unknown_cue_value_warns_once_and_clicks() -> void:
	var button: Button = auto_free(Button.new())
	button.set_meta(&"ui_cue", &"ui_nope")
	add_child(button)
	(
		assert_error(func() -> void: button.pressed.emit())
		. is_push_warning("UiSounds: unknown ui_cue 'ui_nope'; it clicks")
	)
	await _frames()
	button.pressed.emit()
	await _frames()
	assert_array(_audio.cues).is_equal([UiSounds.CUE_CLICK, UiSounds.CUE_CLICK])


func test_a_wait_gives_no_refuse_and_a_plain_disabled_button_does() -> void:
	var waiting: Button = auto_free(Button.new())
	waiting.disabled = true
	add_child(waiting)
	UiWait.hold(waiting, true)
	waiting.gui_input.emit(_mouse_press())
	await _frames()
	assert_array(_audio.cues).is_empty()
	UiWait.hold(waiting, false)
	waiting.gui_input.emit(_mouse_press())
	await _frames()
	assert_array(_audio.cues).is_equal([UiSounds.CUE_REFUSE])


func test_a_wait_puts_back_a_no_click_the_button_had_before() -> void:
	var button: Button = auto_free(Button.new())
	button.set_meta(&"no_click", true)
	UiWait.hold(button, true)
	UiWait.hold(button, true)
	UiWait.hold(button, false)
	assert_bool(bool(button.get_meta(&"no_click", false))).is_true()
	assert_bool(button.has_meta(UiWait.PRIOR)).is_false()
	var plain: Button = auto_free(Button.new())
	UiWait.hold(plain, true)
	UiWait.hold(plain, false)
	assert_bool(plain.has_meta(&"no_click")).is_false()


func test_a_click_pending_first_then_an_order_in_the_same_frame_plays_only_the_chirp() -> void:
	var button: Button = auto_free(Button.new())
	add_child(button)
	button.pressed.emit()  # The click waits for the end of the frame.
	_order()
	await _frames()
	assert_array(_audio.cues).is_equal([UiSounds.CUE_ORDER])


func test_an_order_does_not_cancel_a_pending_back_or_refuse() -> void:
	var back: Button = auto_free(Button.new())
	back.set_meta(&"ui_cue", &"ui_back")
	add_child(back)
	back.pressed.emit()
	_order()
	await _frames()
	assert_array(_audio.cues).is_equal([UiSounds.CUE_ORDER, UiSounds.CUE_BACK])
