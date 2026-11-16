extends GdUnitTestSuite
## `data/audio_settings.tres` and the bus layout (ADR 0041 sections 2, 3, 5 and 6): the numbers of
## the ADR are in the data file, and the layout has the four buses with a hard limiter on Master.

const SETTINGS_PATH: String = "res://data/audio_settings.tres"
const LAYOUT_PATH: String = "res://default_bus_layout.tres"


func test_data_file_loads_as_audio_settings() -> void:
	assert_object(load(SETTINGS_PATH)).is_instanceof(AudioSettings)


func test_data_file_holds_the_adr_numbers() -> void:
	var s: AudioSettings = load(SETTINGS_PATH)
	assert_int(s.world_voices).is_equal(16)
	assert_int(s.ui_voices).is_equal(4)
	assert_int(s.voices_per_tick).is_equal(6)
	assert_int(s.crossfade_ms).is_equal(1500)
	assert_float(s.duck_db).is_equal(6.0)
	assert_int(s.fade_ms).is_equal(150)
	assert_int(s.duck_release_ms).is_equal(100)
	assert_int(s.steps).is_equal(10)


func test_default_steps_are_inside_the_scale() -> void:
	var s: AudioSettings = load(SETTINGS_PATH)
	for step: int in [s.default_music_step, s.default_sfx_step, s.default_ui_step]:
		assert_bool(step >= 0 and step <= s.steps).is_true()


func test_layout_has_four_buses_sent_to_master() -> void:
	assert_object(load(LAYOUT_PATH)).is_instanceof(AudioBusLayout)
	for bus: StringName in [&"Music", &"Sfx", &"Ui"]:
		var index: int = AudioServer.get_bus_index(bus)
		assert_int(index).is_greater(0)
		assert_str(String(AudioServer.get_bus_send(index))).is_equal("Master")
	assert_str(String(AudioServer.get_bus_name(0))).is_equal("Master")


func test_master_has_one_hard_limiter() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	assert_int(AudioServer.get_bus_effect_count(master)).is_equal(1)
	assert_object(AudioServer.get_bus_effect(master, 0)).is_instanceof(AudioEffectHardLimiter)


func test_music_data_names_the_stings() -> void:
	var s: AudioSettings = load(SETTINGS_PATH)
	assert_array(s.sting_ids).contains_exactly([&"victory", &"defeat"])
