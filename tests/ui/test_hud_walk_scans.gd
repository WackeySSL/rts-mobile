extends GdUnitTestSuite
## The scans of the HUD v2 walk are not blind (plan P125): a 20 px button and a 20 px control with
## a `_gui_input` are found by the 48 dp scan, a decoration that only stops the mouse by default,
## a control that ignores the mouse and a hidden one are not; a node whose script lives in
## `game/ads` is found by the ad scan.
## `test_hud_walk` runs the scans in every walked state.

const HudWalk: GDScript = preload("res://tests/ui/support/hud_walk.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _window_size_before: Vector2i
var _main: Node2D


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


## The scan is not blind: a 20 px button, and a 20 px control with a `_gui_input`, in the HUD of a
## state are found; a decoration that only stops the mouse by default, one that ignores the mouse
## and a hidden one are not.
func test_the_48_dp_scan_finds_a_small_button_and_leaves_the_rest_alone() -> void:
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


## The scan is not blind: a node whose script lives in `game/ads`, and a node of a class with an ad
## word, are found.
func test_the_ad_scan_finds_an_ad_node() -> void:
	_main = auto_free(await HudWalk.open(self, ScreenSizes.ALL[0]))
	assert_array(HudWalk.ad_nodes(_main)).is_empty()
	var service: Node = Node.new()
	service.name = "Service"
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node\n"
	script.take_over_path("res://game/ads/FakeService.gd")
	script.reload()
	service.set_script(script)
	_main.add_child(service)
	var found: String = "\n".join(HudWalk.ad_nodes(_main))
	assert_str(found).contains("Service")
	assert_str(found).contains("/ads/")
	_main.remove_child(service)
	service.free()
	script.take_over_path("")
