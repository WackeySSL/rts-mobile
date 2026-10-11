class_name HoldButton
extends Button
## Tells a tap from a hold (ADR 0004 section 5). A press released before `hold_ms` emits `tapped`.
## A press that lasts `hold_ms` emits `held` once, while the finger is still down, and not `tapped`
## when it lifts. Time comes from `clock`, so tests can fake it.

signal tapped
signal held

## Returns the time in ms. Tests replace it.
var clock: Callable = Time.get_ticks_msec
## ArmyBar sets it from `InputSettings.group_assign_ms`.
var hold_ms: int = InputSettings.new().group_assign_ms

var _down_ms: int = 0
var _is_held: bool = false


func _init() -> void:
	set_process(false)  # Only while a finger is down.
	button_down.connect(_on_down)
	button_up.connect(set_process.bind(false))
	pressed.connect(_on_pressed)


## Polls the clock, so the hold lands while the finger rests and not only on release.
func _process(_delta: float) -> void:
	var now_ms: int = clock.call()
	if not _is_held and now_ms - _down_ms >= hold_ms:
		_is_held = true
		held.emit()


func _on_down() -> void:
	_down_ms = clock.call()
	_is_held = false
	set_process(true)


## Released inside the button. No frame may have run since the time passed, so look again.
func _on_pressed() -> void:
	_process(0.0)
	if not _is_held:
		tapped.emit()
