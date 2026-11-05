extends GdUnitTestSuite
## The HUD v2 state walk (plan P125, ADR 0025 sections 1, 2 and 17) at the six sizes of
## ScreenSizes.ALL, a turn in each state: battle, the drawer, placement of a ready structure (the
## old way: order it, let it get READY, place it), the drawer again, the command bar (Stop, then
## Deselect), the pinned full map, the pause menu and Resume; and a strike aim with a group tap,
## whose bottom layout stays where it was (the freeze). In every state each HUD control that shows
## is inside the safe rect and none overlaps another. `tests/ui/support/hud_walk.gd` holds the walk.

const HudWalk: GDScript = preload("res://tests/ui/support/hud_walk.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const STATES: Array[String] = [
	"battle",
	"drawer",
	"placement",
	"drawer again",
	"command bar",
	"deselected",
	"full map pinned",
	"pause",
	"resumed",
]
## What must show in a state (a name of a HUD control, or "Drawer" and "PauseMenu"): a walk that
## missed its state would otherwise check an empty layout.
const SHOWS: Dictionary[String, Array] = {
	"battle": ["EconomyPill", "RadarScope", "BuildButton", "CommandBar"],
	"drawer": ["Drawer"],
	"placement": ["PlaceConfirm", "PlaceCancel"],
	"drawer again": ["Drawer"],
	"command bar": ["CommandBar", "Stop"],
	"full map pinned": ["RadarMap"],
	"pause": ["PauseMenu"],
	"resumed": ["EconomyPill", "BuildButton"],
	"aim": ["StrikeConfirm", "StrikeCancel", "GroupColumn"],
	"aim group tap": ["StrikeConfirm", "StrikeCancel", "GroupColumn", "CommandBar"],
	"aim group tap after deselect": ["StrikeConfirm", "StrikeCancel", "CommandBar"],
}
const AIM_STATES: Array[String] = ["aim", "aim group tap", "aim group tap after deselect"]

var _window_size_before: Vector2i
var _main: Node2D
var _seen: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_seen.clear()


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func test_the_walk_holds_the_layout_in_every_state_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_battle(self, _main, _check)
		_main.free()
		await await_idle_frame()
	assert_array(_seen).is_equal(_repeat(STATES))


func test_the_strike_aim_with_a_group_tap_holds_the_layout_and_the_freeze_at_the_six_sizes(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_aim(self, _main, _check)
		_main.free()
		await await_idle_frame()
	assert_array(_seen).is_equal(_repeat(AIM_STATES))


func _check(label: String, main: Node2D) -> void:
	_seen.append(label)
	HudWalk.check_layout(self, main, label)
	for part: String in SHOWS.get(label, []):
		var shown: bool = false
		if part == "Drawer":
			shown = (HudWalk.hud(main, "BuildSidebar") as BuildSidebar).is_open()
		elif part == "Stop":
			shown = (
				(HudWalk.hud(main, "CommandBar") as CommandBar)
				. order_button(&"stop")
				. is_visible_in_tree()
			)
		else:
			shown = HudWalk.hud(main, part).is_visible_in_tree()
		var why: String = "%s at %s: %s does not show" % [label, HudWalk.size_of(main), part]
		assert_bool(shown).override_failure_message(why).is_true()


func _repeat(states: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for _size: Vector2i in ScreenSizes.ALL:
		out.append_array(states)
	return out
