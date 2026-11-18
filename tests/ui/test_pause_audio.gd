extends GdUnitTestSuite
## P531c: the pause menu's Sound and Music chips turn back on to the step saved in `MenuPrefs`
## (a chip mute is a session mute and never writes it).

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")

var _main: Node
var _menu: PauseMenu
var _state: HudState
var _sound_before: int
var _music_before: int


func before_test() -> void:
	MenuRig.begin()
	_sound_before = AudioService.get_step(AudioService.BUS_SFX)
	_music_before = AudioService.get_step(AudioService.BUS_MUSIC)


func after_test() -> void:
	AudioService.set_sound_step(_sound_before)
	AudioService.set_step(AudioService.BUS_MUSIC, _music_before)
	MenuRig.end()
	CommandQueue.clear()


func test_the_chips_turn_back_on_to_the_saved_step_and_never_write_it() -> void:
	await _open_main()
	var settings: AudioSettings = AudioService.settings
	var sound: int = settings.default_sfx_step - 1  # In range and not the default.
	var music: int = settings.default_music_step - 1
	MenuPrefs.set_sound_step(sound)
	MenuPrefs.set_music_step(music)
	AudioService.set_sound_step(sound)
	AudioService.set_step(AudioService.BUS_MUSIC, music)
	_press(&"SoundButton")
	_press(&"MusicButton")
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(0)
	assert_int(MenuPrefs.sound_step(-1)).is_equal(sound)  # A session mute: the save is kept.
	assert_int(MenuPrefs.music_step(-1)).is_equal(music)
	_press(&"SoundButton")
	_press(&"MusicButton")
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(sound)
	assert_int(AudioService.get_step(AudioService.BUS_MUSIC)).is_equal(music)
	assert_int(MenuPrefs.sound_step(-1)).is_equal(sound)
	assert_int(MenuPrefs.music_step(-1)).is_equal(music)


func test_a_chip_without_a_usable_saved_step_turns_on_to_the_default() -> void:
	await _open_main()
	MenuPrefs.set_sound_step(0)  # Settings left it silent: the chip must still be heard.
	MenuPrefs.set_music_step(0)
	AudioService.set_sound_step(0)
	AudioService.set_step(AudioService.BUS_MUSIC, 0)
	_press(&"SoundButton")
	_press(&"MusicButton")
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(
		AudioService.settings.default_sfx_step
	)
	assert_int(AudioService.get_step(AudioService.BUS_MUSIC)).is_equal(
		AudioService.settings.default_music_step
	)


func _open_main() -> void:
	_main = auto_free(await MatchRig.open(self))
	_menu = _main.get_node("Hud/PauseMenu")
	_state = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state


func _press(button_name: StringName) -> void:
	_state.open(HudState.Unfold.PAUSE)
	(_menu.find_child(button_name, true, false) as Button).pressed.emit()
