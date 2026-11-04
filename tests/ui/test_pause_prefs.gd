extends GdUnitTestSuite
## The pause menu's Vibration switch and the no-ad guard (plan P124, ADR 0025 section 11): the
## switch writes `HudPrefs` and every `vibrate` call obeys it (one gate); no ad node on the battle
## screen, the pause menu included (admob-policy).

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")

var _window_size_before: Vector2i
var _main: Node
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


## The Vibration switch writes the suite's own file and reads it back; the other keys stay.
func test_the_vibration_switch_writes_the_prefs_file() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	assert_bool(HudPrefs.haptics_enabled()).is_true()  # Default on.
	_pill().menu_pressed.emit()
	await await_idle_frame()
	assert_str(_button("VibrationButton").text).is_equal("VIBRATION: ON")
	var other: ConfigFile = ConfigFile.new()
	other.set_value("audio", "volume", 7)
	other.save(HudPrefs.path())
	_tap(_button("VibrationButton"))
	assert_str(_button("VibrationButton").text).is_equal("VIBRATION: OFF")
	assert_bool(HudPrefs.haptics_enabled()).is_false()
	var file: ConfigFile = ConfigFile.new()
	assert_int(file.load(HudPrefs.path())).is_equal(OK)
	assert_bool(file.get_value("hud", "haptics")).is_false()
	assert_int(file.get_value("audio", "volume")).is_equal(7)
	assert_str(HudPrefs.path()).is_not_equal(HudPrefs.PATH)  # Not the machine's file.
	_tap(_button("VibrationButton"))
	assert_bool(HudPrefs.haptics_enabled()).is_true()
	assert_str(_button("VibrationButton").text).is_equal("VIBRATION: ON")


## A missing file and a key of another type mean vibration on.
func test_the_prefs_default_to_on() -> void:
	assert_bool(HudPrefs.haptics_enabled()).is_true()
	var file: ConfigFile = ConfigFile.new()
	file.set_value("hud", "haptics", "no")
	file.save(HudPrefs.path())
	assert_bool(HudPrefs.haptics_enabled()).is_true()


## Switched off, a haptic call is silent; switched on, it buzzes; the data default still holds.
func test_every_haptic_obeys_the_switch() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	var controller: PlayerController = _main.get_node("PlayerController")
	var buzzes: Array[int] = []
	controller.vibrate = func(ms: int) -> void: buzzes.append(ms)
	controller.selection.set_ids(MatchRig.units_of(_main, 1))
	assert_bool(controller.stop()).is_true()
	assert_array(buzzes).has_size(1)
	HudPrefs.set_haptics_enabled(false)
	assert_bool(controller.stop()).is_true()  # The order still goes.
	assert_array(buzzes).has_size(1)
	assert_array(_sent).has_size(2)
	HudPrefs.set_haptics_enabled(true)
	controller.settings.haptics_enabled = false
	assert_bool(HudPrefs.vibrates(controller.settings)).is_false()
	controller.settings.haptics_enabled = true  # The resource is shared by every suite.


## Every `vibrate` call in game/ stands behind `HudPrefs.vibrates`, the one gate; nothing reads
## `haptics_enabled` of the settings on its own.
func test_no_vibrate_call_bypasses_the_gate() -> void:
	var calls: int = 0
	for path: String in FileScan.list_files("res://game", ".gd"):
		if path.ends_with("HudPrefs.gd"):
			continue
		var code: String = "\n".join(FileScan.code_lines(FileAccess.get_file_as_string(path)))
		var buzzes: int = code.count("vibrate.call(")
		calls += buzzes
		assert_int(code.count("HudPrefs.vibrates(")).override_failure_message(path).is_equal(buzzes)
		assert_int(code.count("settings.haptics_enabled")).override_failure_message(path).is_equal(
			0
		)
	assert_int(calls).is_greater_equal(5)


## No ad on the pause menu or anywhere on the battle screen (admob-policy): no node of the ad
## plugin or of `game/ads` in the scene, in the tree or in its file.
func test_no_ad_in_the_battle_scene() -> void:
	await _open()
	var scene: String = FileAccess.get_file_as_string("res://scenes/main.tscn")
	for word: String in ["game/ads", "AdService", "AdMob", "Admob", "Banner", "Interstitial"]:
		assert_bool(scene.contains(word)).override_failure_message(word).is_false()
	for node: Node in _main.find_children("*", "", true, false):
		var script: Script = node.get_script()
		var path: String = "" if script == null else script.resource_path
		assert_bool(path.contains("/ads/")).override_failure_message(path).is_false()
		assert_bool(node.get_class().to_lower().contains("admob")).is_false()


## A main scene on the Derrick League's Skirmish whose controller keeps its Commands in `_sent`.
func _open() -> void:
	_main = auto_free(await MatchRig.open(self))
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = func(
		command: Command
	) -> void:
		_sent.append(command)


func _pill() -> EconomyPill:
	return _main.get_node("Hud/EconomyPill") as EconomyPill


func _menu() -> PauseMenu:
	return _main.get_node("Hud/PauseMenu") as PauseMenu


func _button(button_name: String) -> Button:
	return _menu().find_child(button_name, true, false) as Button


## A finger down and up on the middle of `control`.
func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
