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
	MenuRig.begin()
	_audio = ChipAudio.new()


func after_test() -> void:
	_close()
	_audio.free()
	MenuRig.end()
	UiStateGuard.restore(get_window(), _window_size_before)


func test_a_chip_mute_shows_the_sliders_at_zero_and_keeps_the_saved_step() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 0, &"Sfx": 0}  # The pause chips turned both off.
	await _open()
	assert_int(_audio.get_step(&"Sfx")).is_equal(0)
	assert_int(int(_screen.sound_slider.value)).is_equal(_audio.get_step(&"Sfx"))
	assert_int(int(_screen.music_slider.value)).is_equal(_audio.get_step(&"Music"))
	assert_int(MenuPrefs.sound_step(-1)).is_equal(6)  # The save is never overwritten with 0.
	assert_int(MenuPrefs.music_step(-1)).is_equal(4)


func test_a_drag_while_muted_unmutes_to_the_dragged_step_and_saves_it() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 0, &"Sfx": 0}
	await _open()
	_screen.sound_slider.value = 3.0
	_screen.music_slider.value = 2.0
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


func test_settings_from_the_main_menu_shows_the_saved_step() -> void:
	MenuPrefs.set_sound_step(6)
	MenuPrefs.set_music_step(4)
	_audio.steps = {&"Music": 4, &"Sfx": 6}  # MenuFlow put the save on the service at launch.
	await _open(false)
	assert_int(int(_screen.sound_slider.value)).is_equal(6)
	assert_int(int(_screen.music_slider.value)).is_equal(4)


## The real pause menu, the real service: chips off, Settings opened over them and closed without a
## touch. The steps, the save and the chips stay as they were.
func test_settings_over_the_pause_chips_leaves_save_bus_and_chips_alone() -> void:
	var sfx_before: int = AudioService.get_step(AudioService.BUS_SFX)
	var music_before: int = AudioService.get_step(AudioService.BUS_MUSIC)
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
	var screen: SettingsScreen = overlay.current() as SettingsScreen
	assert_int(int(screen.sound_slider.value)).is_equal(0)
	assert_int(int(screen.music_slider.value)).is_equal(0)
	state.close(HudState.Unfold.PAUSE)
	await await_idle_frame()
	assert_int(MenuPrefs.sound_step(-1)).is_equal(6)
	assert_int(MenuPrefs.music_step(-1)).is_equal(4)
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(0)
	assert_int(AudioService.get_step(AudioService.BUS_MUSIC)).is_equal(0)
	state.open(HudState.Unfold.PAUSE)
	assert_str((pause.find_child(&"SoundButton", true, false) as Button).text).contains("OFF")
	assert_str((pause.find_child(&"MusicButton", true, false) as Button).text).contains("OFF")
	AudioService.set_sound_step(sfx_before)
	AudioService.set_step(AudioService.BUS_MUSIC, music_before)
	CommandQueue.clear()


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
