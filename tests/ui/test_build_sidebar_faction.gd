extends GdUnitTestSuite
## The build menu lists the local player's faction only (plan P85d, ADR 0023 sections 6 and 12): a
## tile of a type whose `type_faction` is another faction's is never shown, in any tab, and a type
## with no faction is shown to everyone. The player's faction is that of their own rows, as the
## producer-faction rule of `Production.apply_queue` reads it, from the published snapshot alone: an
## enemy's rows tell nothing, a player with no faction row sees only the types with none, the
## faction stays while the match goes on and is read again for the next match. The scenarios that
## list no faction (every type -1) are test_build_sidebar_items' and show every type, as before.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const FOSSIL: int = 0
const RENEW: int = 1
## The faction of every buildable type, by id: -1 is any faction. The headquarters is set per world.
const TABLE: Dictionary[String, int] = {
	"power_plant": FOSSIL,
	"barracks": RENEW,
	"refinery": -1,
	"vehicle_factory": FOSSIL,
	"defence_turret": RENEW,
	"rifle_squad": FOSSIL,
	"rocket_squad": RENEW,
	"light_tank": FOSSIL,
	"heavy_tank": RENEW,
	"harvester": -1,
	"artillery": RENEW,
}
## What each faction sees per tab (Structures, Infantry, Vehicles), in the type table's order.
const FOSSIL_SEES: Array[Array] = [
	["power_plant", "refinery", "vehicle_factory"], ["rifle_squad"], ["light_tank", "harvester"]
]
const RENEW_SEES: Array[Array] = [
	["barracks", "refinery", "defence_turret"],
	["rocket_squad"],
	["heavy_tank", "harvester", "artillery"]
]
const NEUTRAL_SEES: Array[Array] = [["refinery"], [], ["harvester"]]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_each_faction_sees_its_own_types_and_the_types_with_none_in_every_tab() -> void:
	await _open()
	_publish(_world(FOSSIL, ["headquarters", "refinery"]))
	assert_array(_seen()).is_equal(FOSSIL_SEES)
	_publish(_world(RENEW, ["headquarters", "refinery"]), 1)
	assert_array(_seen()).is_equal(RENEW_SEES)


func test_a_tile_of_another_faction_is_never_shown_in_any_tab_at_any_size() -> void:
	await _open()
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	for profile: StringName in profiles:
		UiScale.set_override(profiles[profile])
		get_window().size = profiles[profile].window_size
		await await_idle_frame()
		for faction: int in [FOSSIL, RENEW]:
			_publish(_world(faction, ["headquarters"]), faction)
			for tab: int in World.TABS:
				_sidebar.select_tab(tab)
				for node: Node in _grid().get_children():
					var tile: ItemTile = node as ItemTile
					var why: String = "%s, faction %d, %s" % [profile, faction, tile.name]
					var allowed: bool = tile.faction < 0 or tile.faction == faction
					if tile.tab == tab:  # The tiles of the open tab show exactly when allowed.
						assert_bool(tile.visible).override_failure_message(why).is_equal(allowed)
					else:
						assert_bool(tile.visible).override_failure_message(why).is_false()


func test_the_faction_is_the_local_players_own_rows_and_not_the_enemys() -> void:
	await _open()
	var world: World = _world(FOSSIL, ["headquarters"])
	Sw.own(world, ["headquarters"], 2)  # The enemy's Headquarters is the same type, so fossil too.
	_publish(world)
	assert_array(_seen()).is_equal(FOSSIL_SEES)
	var other: World = _world(RENEW, ["refinery"])  # The local player has no faction row.
	Sw.own(other, ["headquarters"], 2)  # And the enemy's Headquarters is renew's.
	_publish(other, 1)
	assert_array(_seen()).is_equal(NEUTRAL_SEES)


func test_a_player_with_no_faction_row_sees_only_the_types_with_none() -> void:
	await _open()
	_publish(_world(FOSSIL, ["refinery"]))  # A building with no faction says nothing.
	assert_array(_seen()).is_equal(NEUTRAL_SEES)
	_publish(_world(FOSSIL, []), 1)  # No rows at all.
	assert_array(_seen()).is_equal(NEUTRAL_SEES)


func test_the_faction_stays_while_the_match_goes_on_and_is_read_again_for_the_next() -> void:
	await _open()
	_publish(_world(FOSSIL, ["headquarters", "refinery"]))
	assert_array(_seen()).is_equal(FOSSIL_SEES)
	_publish(_world(FOSSIL, []))  # The last row of it is gone, in the same match.
	assert_array(_seen()).is_equal(FOSSIL_SEES)
	_publish(_world(RENEW, ["headquarters"]), 1)  # The next match.
	assert_array(_seen()).is_equal(RENEW_SEES)
	_publish(_world(RENEW, ["refinery"]), 2)  # And a next one where no row shows a faction.
	assert_array(_seen()).is_equal(NEUTRAL_SEES)


## A world of the shipped tables with two factions set on them (`TABLE`, and the Headquarters of
## `hq`), and player 1, the local player, owning one building of each of `own`.
func _world(hq: int, own: Array) -> World:
	var world: World = Sw.world()
	world.faction_ids = [&"fossil", &"renew"]
	for id: String in TABLE:
		world.type_faction[Sw.type_of(world, id)] = TABLE[id]
	world.type_faction[Sw.type_of(world, "headquarters")] = hq
	Sw.own(world, own)
	return world


## The ids of the visible tiles of each tab, in the grid's order.
func _seen() -> Array[Array]:
	var seen: Array[Array] = []
	for tab: int in World.TABS:
		_sidebar.select_tab(tab)
		var ids: Array[String] = []
		for node: Node in _grid().get_children():
			if (node as Control).visible:
				ids.append(node.name.trim_prefix("Tile_"))
		seen.append(ids)
	return seen


func _grid() -> GridContainer:
	return _sidebar.find_children("*", "GridContainer", true, false)[0]


## Publishes the world's snapshot as the match's latest (a new match when `serial` is another
## number) and reads it at once.
func _publish(world: World, serial: int = 0) -> void:
	_runner.snapshot = Sw.snapshot(world, serial)
	_sidebar.refresh()


## A new main scene on the 6-inch phone, its match paused, the sidebar reading a runner of its own.
func _open() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _main.get_node("MatchRunner").scenario
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_sidebar.runner = _runner
