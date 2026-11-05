extends GdUnitTestSuite
## The 48 dp scan of the HUD v2 walk (plan P125, ADR 0025 section 17, ADR 0004 section 3): in every
## walked state and at the six sizes of ScreenSizes.ALL, each visible `Control` that takes input (a
## button, or a control that stops the mouse) is at least dp(48) on its short side. The states are
## the walk's, so the scan reaches what `test_touch_target_sizes` does not: the drawer and its
## cards, placement, the command bar with its chips, the pinned full map, the aim and the pause
## menu. While the pause menu shows, the menu alone takes touches and is what is scanned.

const HudWalk: GDScript = preload("res://tests/ui/support/hud_walk.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

## Least controls that take input in a state, counted by hand: the walk reached the state, and the
## scan did not read an empty one. The menu has Resume, Restart, Surrender and Exit.
const MINIMUM: Dictionary[String, int] = {"pause": 3, "drawer": 6, "drawer again": 6}

var _window_size_before: Vector2i
var _main: Node2D
var _small: Array[String] = []
var _scanned: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_small.clear()
	_scanned.clear()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func test_every_control_that_takes_input_is_48_dp_in_every_walked_state() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_battle(self, _main, _scan)
		_main.free()
		await await_idle_frame()
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_aim(self, _main, _scan)
		_main.free()
		await await_idle_frame()
	assert_array(_small).is_empty()
	assert_int(_scanned.size()).is_equal(12 * ScreenSizes.ALL.size())


## The scan is not blind: a 20 px button, and a 20 px control with a `_gui_input`, in the HUD of a
## state are found; a decoration that only stops the mouse by default, one that ignores the mouse
## and a hidden one are not.
func test_the_scan_finds_a_small_button_and_leaves_the_rest_alone() -> void:
	_main = auto_free(await HudWalk.open(self, ScreenSizes.ALL[0]))
	assert_array(HudWalk.small_targets(_main, "start")).is_empty()
	var hud: Node = _main.get_node("Hud")
	var button: Button = Button.new()
	button.name = "TinyButton"
	button.custom_minimum_size = Vector2(20, 20)
	hud.add_child(button)
	var stopper: Control = Control.new()
	stopper.name = "TinyStopper"
	stopper.custom_minimum_size = Vector2(20, 20)
	stopper.mouse_filter = Control.MOUSE_FILTER_STOP
	var script: GDScript = GDScript.new()  # A control with a `_gui_input` of its own.
	script.source_code = "extends Control\nfunc _gui_input(_event: InputEvent) -> void:\n\tpass\n"
	script.reload()
	stopper.set_script(script)
	hud.add_child(stopper)
	var decor: ColorRect = ColorRect.new()  # Stops the mouse by its class default only.
	decor.name = "TinyDecor"
	decor.custom_minimum_size = Vector2(20, 20)
	hud.add_child(decor)
	var ghost: Control = Control.new()
	ghost.name = "TinyGhost"
	ghost.custom_minimum_size = Vector2(20, 20)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ghost)
	var hidden: Button = Button.new()
	hidden.name = "TinyHidden"
	hidden.custom_minimum_size = Vector2(20, 20)
	hidden.visible = false
	hud.add_child(hidden)
	await await_idle_frame()
	var found: String = "\n".join(HudWalk.small_targets(_main, "crafted"))
	assert_str(found).contains("TinyButton")
	assert_str(found).contains("TinyStopper")
	assert_str(found).not_contains("TinyDecor")
	assert_str(found).not_contains("TinyGhost")
	assert_str(found).not_contains("TinyHidden")


func _scan(label: String, main: Node2D) -> void:
	_scanned.append(label)
	var count: int = HudWalk.input_controls(main).size()
	assert_int(count).override_failure_message("%s: %d controls" % [label, count]).is_greater(
		MINIMUM.get(label, 1)
	)
	_small.append_array(HudWalk.small_targets(main, label))
