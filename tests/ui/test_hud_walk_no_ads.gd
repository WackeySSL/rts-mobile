extends GdUnitTestSuite
## The no-ad guard of the HUD v2 walk (plan P125, ADR 0025 section 17, CLAUDE.md's monetization
## rules and the admob-policy skill): in no walked state, the pause menu included, at the six sizes
## of ScreenSizes.ALL, is there an ad node in the tree: nothing of the ad plugin, nothing from
## `game/ads`, no banner, interstitial or rewarded node. The pause menu's banner may come later
## (P127), and then this test changes in that row; today none exists. `test_pause_prefs` reads the
## scene file for the same words; this reads the tree in every state.

const HudWalk: GDScript = preload("res://tests/ui/support/hud_walk.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _window_size_before: Vector2i
var _main: Node2D
var _ads: Array[String] = []
var _seen: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_ads.clear()
	_seen.clear()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func test_no_ad_node_exists_in_any_walked_state_the_pause_menu_included() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_battle(self, _main, _look)
		_main.free()
		await await_idle_frame()
		_main = auto_free(await HudWalk.open(self, size))
		await HudWalk.walk_aim(self, _main, _look)
		_main.free()
		await await_idle_frame()
	assert_array(_ads).is_empty()
	assert_array(_seen).contains(["battle", "pause", "resumed", "aim"])
	assert_int(_seen.size()).is_equal(12 * ScreenSizes.ALL.size())


## The scan is not blind: a node whose script lives in `game/ads`, and a node of a class with an ad
## word, are found.
func test_the_scan_finds_an_ad_node() -> void:
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


func _look(label: String, main: Node2D) -> void:
	_seen.append(label)
	for found: String in HudWalk.ad_nodes(main):
		_ads.append("%s at %s: %s" % [label, HudWalk.size_of(main), found])
