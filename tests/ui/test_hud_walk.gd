extends GdUnitTestSuite
## The HUD v2 state walk (plan P125, ADR 0025 sections 1, 2 and 17) at the six sizes of
## ScreenSizes.ALL, with a turn of the phone in each state (the state must be kept, and the state
## is visited again turned; the aim's later states are not turned, because a turn ends the aim):
## battle, the drawer (on the Infantry tab, so that a reset would show), placement of a structure
## whose READY is forced (the old way: place it when ready; `placement.cancel()` ends it, not a tap
## on the X), the drawer again, the command bar (Stop, then Deselect), the pinned full map, the
## pause menu and Resume; and the strike aim twice, whose bottom stays where it was under group
## taps (the freeze). In every state, turned or not:
## - each HUD control that shows is inside the safe rect and none overlaps another;
## - what the state must show shows (SHOWS);
## - each visible control that takes input is at least 48 dp on its short side;
## - no ad node is in the tree, the pause menu included.
## `support/hud_walk.gd` holds the walk, `test_hud_walk_scans` shows the scans are not blind.

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
## The aim is visited turned once: the turn ends it. The rest of the aim's states follow it.
const AIM_STATES: Array[String] = [
	"aim",
	"aim turned",
	"aim group tap",
	"aim deselected",
	"aim group tap after deselect",
]
## What must show in a state (a name of a HUD control, or "Drawer", "Stop" and "PauseMenu"): a walk
## that missed its state would otherwise check an empty layout. A turned state shows the same,
## except the aim's, which the turn ended.
const SHOWS: Dictionary[String, Array] = {
	"battle": ["EconomyPill", "RadarScope", "BuildButton", "CommandBar"],
	"drawer": ["Drawer", "EconomyPill"],
	"placement": ["PlaceConfirm", "PlaceCancel"],
	"drawer again": ["Drawer", "EconomyPill"],
	"command bar": ["CommandBar", "Stop"],
	"full map pinned": ["RadarMap"],
	"pause": ["PauseMenu"],
	"resumed": ["EconomyPill", "BuildButton", "CommandBar"],
	"aim": ["StrikeConfirm", "StrikeCancel", "GroupColumn"],
	"aim group tap": ["StrikeConfirm", "StrikeCancel", "GroupColumn"],
	"aim deselected": ["StrikeConfirm", "StrikeCancel", "GroupColumn", "CommandBar"],
	"aim group tap after deselect": ["StrikeConfirm", "StrikeCancel", "CommandBar"],
}
## Least controls that take input in a state, counted by hand: the walk reached the state, and the
## scan did not read an empty one. The menu has Resume, Restart, Surrender and Exit.
const MINIMUM: Dictionary[String, int] = {"pause": 3, "drawer": 6, "drawer again": 6}

var _window_size_before: Vector2i
var _main: Node2D
var _seen: Array[String] = []
var _small: Array[String] = []
var _ads: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_seen.clear()
	_small.clear()
	_ads.clear()


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func test_the_walk_holds_in_every_state_and_turn_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_battle(self, _main, _check)
		_main.free()
		await await_idle_frame()
	assert_array(_seen).is_equal(_repeat(_with_turns(STATES)))
	assert_array(_small).is_empty()
	assert_array(_ads).is_empty()


func test_the_strike_aim_with_group_taps_holds_the_layout_and_the_freeze_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_aim(self, _main, _check)
		_main.free()
		await await_idle_frame()
	assert_array(_seen).is_equal(_repeat(AIM_STATES))
	assert_array(_small).is_empty()
	assert_array(_ads).is_empty()


func _check(label: String, main: Node2D) -> void:
	_seen.append(label)
	var base: String = label.trim_suffix(" turned")
	var why_label: String = label  # The checks add the window's size.
	HudWalk.check_layout(self, main, why_label)
	if label != "aim turned":
		for part: String in SHOWS.get(base, []):
			var why: String = "%s: %s does not show" % [why_label, part]
			assert_bool(_shows(main, part)).override_failure_message(why).is_true()
	var count: int = HudWalk.input_controls(main).size()
	assert_int(count).override_failure_message("%s: %d controls" % [why_label, count]).is_greater(
		MINIMUM.get(base, 1)
	)
	_small.append_array(HudWalk.small_targets(main, why_label))
	for found: String in HudWalk.ad_nodes(main):
		_ads.append("%s: %s" % [why_label, found])


func _shows(main: Node2D, part: String) -> bool:
	if part == "Drawer":
		return (HudWalk.hud(main, "BuildSidebar") as BuildSidebar).is_open()
	if part == "Stop":
		return (
			(HudWalk.hud(main, "CommandBar") as CommandBar)
			. order_button(&"stop")
			. is_visible_in_tree()
		)
	return HudWalk.hud(main, part).is_visible_in_tree()


func _with_turns(states: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for state: String in states:
		out.append(state)
		out.append(state + " turned")
	return out


func _repeat(states: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for _size: Vector2i in ScreenSizes.ALL:
		out.append_array(states)
	return out
