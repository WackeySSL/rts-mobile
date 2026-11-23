extends GdUnitTestSuite
## P449: a Sound or Music chip mute (pause menu, a session mute that never writes the saved step)
## and the Settings sliders opened over it must agree: a muted bus shows its slider at 0, the
## saved step stays on disk.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiStateGuard: GDScript = preload("res://tests/support/ui_state_guard.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")

var _menu: Control
var _screen: SettingsScreen
var _audio: ChipAudio
var _window_size_before: Vector2i
var _sfx_before: int
var _music_before: int


## An audio service with the real set_step and set_sound_step semantics, no buses. `sets` spies on
## every write.
class ChipAudio:
	extends Node
	var settings: AudioSettings = AudioSettings.new()
	var steps: Dictionary = {&"Music": 7, &"Sfx": 10}
	var sets: int = 0

	func get_step(bus: StringName) -> int:
		return steps.get(bus, 0)

	func set_step(bus: StringName, step: int) -> void:
		sets += 1
		steps[bus] = step

	func set_sound_step(step: int) -> void:
		sets += 1
		steps[&"Sfx"] = step


func before_test() -> void:
	_window_size_before = get_window().size
	_sfx_before = AudioService.get_step(AudioService.BUS_SFX)
	_music_before = AudioService.get_step(AudioService.BUS_MUSIC)
	MenuRig.begin()
	_audio = ChipAudio.new()


func after_test() -> void:
	_close()
	_audio.free()
	MenuRig.end()
	UiStateGuard.restore(get_window(), _window_size_before)
	AudioService.set_sound_step(_sfx_before)
	AudioService.set_step(AudioService.BUS_MUSIC, _music_before)
	CommandQueue.clear()


func test_a_chip_mute_shows_the_sliders_at_zero_and_keeps_the_saved_step() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 0, &"Sfx": 0}  # The pause chips turned both off.
	await _open()
	assert_int(_audio.get_step(&"Sfx")).is_equal(0)
	assert_int(int(_screen.sound_slider.value)).is_equal(_audio.get_step(&"Sfx"))
	assert_int(int(_screen.music_slider.value)).is_equal(_audio.get_step(&"Music"))
	assert_str(_value(_screen.sound_slider)).is_equal("OFF")  # The chip's word, not a bare 0.
	assert_str(_value(_screen.music_slider)).is_equal("OFF")
	assert_int(MenuPrefs.sound_step(-1)).is_equal(6)  # The save is never overwritten with 0.
	assert_int(MenuPrefs.music_step(-1)).is_equal(4)


func test_a_drag_while_muted_unmutes_to_the_dragged_step_and_saves_it() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 0, &"Sfx": 0}
	await _open()
	_screen.sound_slider.value = 3.0
	_screen.music_slider.value = 2.0
	assert_str(_value(_screen.sound_slider)).is_equal("3")  # The number is back above 0.
	assert_str(_value(_screen.music_slider)).is_equal("2")
	assert_int(_audio.get_step(&"Sfx")).is_equal(3)  # The chip reads on: its step is above 0.
	assert_int(_audio.get_step(&"Music")).is_equal(2)
	assert_int(MenuPrefs.sound_step(-1)).is_equal(3)
	assert_int(MenuPrefs.music_step(-1)).is_equal(2)


func test_opening_and_closing_settings_writes_nothing_while_muted() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 0, &"Sfx": 0}
	await _open()
	await await_idle_frame()
	_close()
	assert_int(_audio.sets).is_equal(0)
	assert_int(MenuPrefs.sound_step(-1)).is_equal(6)
	assert_int(MenuPrefs.music_step(-1)).is_equal(4)
	assert_int(_audio.get_step(&"Sfx")).is_equal(0)
	assert_int(_audio.get_step(&"Music")).is_equal(0)


func test_a_turn_while_muted_keeps_the_sliders_at_zero() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 0, &"Sfx": 0}
	await _open()
	for size: Vector2i in [ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0]]:
		get_window().size = size
		get_window().size_changed.emit()
		for _frame: int in range(3):
			await await_idle_frame()
		assert_int(int(_screen.sound_slider.value)).override_failure_message(str(size)).is_equal(0)
		assert_int(int(_screen.music_slider.value)).override_failure_message(str(size)).is_equal(0)
	assert_int(_audio.sets).is_equal(0)
	assert_int(MenuPrefs.sound_step(-1)).is_equal(6)


func test_settings_from_the_main_menu_with_no_session_mute_shows_the_saved_step() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 4, &"Sfx": 6}  # MenuFlow put the save on the service at launch.
	await _open(false)
	assert_int(int(_screen.sound_slider.value)).is_equal(6)
	assert_int(int(_screen.music_slider.value)).is_equal(4)
	assert_str(_value(_screen.sound_slider)).is_equal("6")


## The chip mute lasts the session: after a muted match the main menu's Settings reads what is
## heard (OFF), a drag then turns the sound back on and saves.
func test_a_chip_mute_that_outlives_the_match_reads_off_on_the_main_menu() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 0, &"Sfx": 0}
	await _open(false)
	assert_str(_value(_screen.sound_slider)).is_equal("OFF")
	assert_str(_value(_screen.music_slider)).is_equal("OFF")
	_screen.sound_slider.value = 5.0
	_screen.music_slider.value = 3.0
	assert_int(_audio.get_step(&"Sfx")).is_equal(5)
	assert_int(_audio.get_step(&"Music")).is_equal(3)
	assert_int(MenuPrefs.sound_step(-1)).is_equal(5)
	assert_int(MenuPrefs.music_step(-1)).is_equal(3)


## First launch, Settings never opened: nothing is saved, and the chip's mute still reads OFF; a bus
## at its default reads the number.
func test_with_no_save_a_chip_mute_reads_off_and_a_default_bus_reads_its_number() -> void:
	_audio.steps = {&"Music": 0, &"Sfx": 0}
	await _open()
	assert_str(_value(_screen.sound_slider)).is_equal("OFF")
	assert_str(_value(_screen.music_slider)).is_equal("OFF")
	_close()
	var settings: AudioSettings = _audio.settings
	_audio.steps = {&"Music": settings.default_music_step, &"Sfx": settings.default_sfx_step}
	await _open()
	assert_str(_value(_screen.sound_slider)).is_equal(str(settings.default_sfx_step))
	assert_str(_value(_screen.music_slider)).is_equal(str(settings.default_music_step))
	assert_int(_audio.sets).is_equal(0)


func test_a_player_saved_zero_reads_0_not_off() -> void:
	MenuPrefs.set_sound_step(0)
	MenuPrefs.set_music_step(0)
	_audio.steps = {&"Music": 0, &"Sfx": 0}
	await _open()
	assert_str(_value(_screen.sound_slider)).is_equal("0")
	assert_str(_value(_screen.music_slider)).is_equal("0")


## A live step above the slider's own default (0): `value =` must come before `connect`, or the
## build itself would write the bus and the save. Open, a turn and close write nothing.
func test_a_sounding_bus_is_not_written_by_open_turn_or_close() -> void:
	MenuPrefs.set_sound_step(7)
	MenuPrefs.set_music_step(7)
	_audio.steps = {&"Music": 7, &"Sfx": 7}
	await _open()
	assert_int(_audio.sets).is_equal(0)
	for size: Vector2i in [ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0]]:
		get_window().size = size
		get_window().size_changed.emit()
		for _frame: int in range(3):
			await await_idle_frame()
	assert_int(int(_screen.sound_slider.value)).is_equal(7)
	assert_str(_value(_screen.sound_slider)).is_equal("7")
	_close()
	assert_int(_audio.sets).is_equal(0)
	assert_int(MenuPrefs.sound_step(-1)).is_equal(7)
	assert_int(MenuPrefs.music_step(-1)).is_equal(7)


## The real pause menu, the real service: chips off, Settings opened over them and closed without a
## touch. The steps, the save and the chips stay as they were.
func test_settings_over_the_pause_chips_leaves_save_bus_and_chips_alone() -> void:
	var rig: Array = await _muted_over_pause()
	var pause: PauseMenu = rig[0]
	var state: HudState = rig[1]
	var screen: SettingsScreen = rig[2]
	assert_int(int(screen.sound_slider.value)).is_equal(0)
	assert_int(int(screen.music_slider.value)).is_equal(0)
	assert_str(_value(screen.sound_slider)).is_equal("OFF")
	state.close(HudState.Unfold.PAUSE)
	await await_idle_frame()
	assert_int(MenuPrefs.sound_step(-1)).is_equal(6)
	assert_int(MenuPrefs.music_step(-1)).is_equal(4)
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(0)
	assert_int(AudioService.get_step(AudioService.BUS_MUSIC)).is_equal(0)
	state.open(HudState.Unfold.PAUSE)
	assert_str((pause.find_child(&"SoundButton", true, false) as Button).text).contains("OFF")
	assert_str((pause.find_child(&"MusicButton", true, false) as Button).text).contains("OFF")


## A drag over the muted chips, then Back: the pause chips read on again.
func test_a_drag_in_settings_over_the_pause_chips_turns_them_on() -> void:
	var rig: Array = await _muted_over_pause()
	var pause: PauseMenu = rig[0]
	var screen: SettingsScreen = rig[2]
	screen.sound_slider.value = 3.0
	screen.music_slider.value = 2.0
	(pause.find_child("HelpOverlay", true, false) as MenuStack).pop()
	await await_idle_frame()
	pause.call(&"_show_chips")
	assert_str((pause.find_child(&"SoundButton", true, false) as Button).text).is_equal("SOUND")
	assert_str((pause.find_child(&"MusicButton", true, false) as Button).text).is_equal("MUSIC")
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(3)


## Saved 6 and 4, both chips pressed off, Settings open over the pause menu: [pause, state, screen].
func _muted_over_pause() -> Array:
	var main: Node = auto_free(await MatchRig.open(self))
	var pause: PauseMenu = main.get_node("Hud/PauseMenu")
	var state: HudState = (main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	pause.routes = MenuRoutes.new()
	pause.routes.register(MenuRoutes.SETTINGS, SettingsScreen.new)
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	AudioService.set_sound_step(6)
	AudioService.set_step(AudioService.BUS_MUSIC, 4)
	state.open(HudState.Unfold.PAUSE)
	(pause.find_child(&"SoundButton", true, false) as Button).pressed.emit()
	(pause.find_child(&"MusicButton", true, false) as Button).pressed.emit()
	(pause.find_child(&"SettingsButton", true, false) as Button).pressed.emit()
	await await_idle_frame()
	var overlay: MenuStack = pause.find_child("HelpOverlay", true, false) as MenuStack
	return [pause, state, overlay.current() as SettingsScreen]


func _value(slider: HSlider) -> String:
	return (slider.get_parent().get_node("Value") as Label).text


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _open(in_match: bool = true) -> void:
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	var stack: MenuStack = _menu.get_node("MenuStack") as MenuStack
	stack.slide_ms = 0
	_screen = SettingsScreen.new()
	_screen.routes = MenuRoutes.new()
	_screen.audio = _audio
	_screen.dev_enabled = func() -> bool: return false
	_screen.in_match = func() -> bool: return in_match
	stack.push(_screen)
	for _frame: int in range(3):
		await await_idle_frame()
