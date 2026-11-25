extends GdUnitTestSuite
## The two Skirmish routes (plan P90, rev 5, ADR 0025 answer 7): the dev menu has
## "Skirmish (Nordværn)" and "Skirmish (Facet)" first; each opens the main scene on Kestrel Flats
## with the player on that side as player 1, the computer of the other side as
## `MatchRunner.opponents` (plan P183: `OpponentAi`), the build menu of the player's own side only,
## and the player's units in the other colour: since P632 (ADR 0050 section 3, answer 3) the team
## marker is your own white (Sne) and the computer's red (Karmin) on every route, the scenario's
## `team_triads`. The
## layout of the menu is test_dev_menu_layout's, the rest of the dev routes are test_dev_routes'.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const ROUTES: Array[Dictionary] = [
	{
		"button": "SkirmishDerrickButton",
		"text": "Skirmish (Nordværn)",
		"scenario": "res://data/scenarios/skirmish_kestrel_flats.tres",
		"opponent": &"opponent_renew",
		"own_hq": &"headquarters",
		"other_hq": &"renew_hq",
		"own_faction": &"fossil",
		"own_triad": 6,
		"other_triad": 2,
	},
	{
		"button": "SkirmishLumenButton",
		"text": "Skirmish (Facet)",
		"scenario": "res://data/scenarios/skirmish_kestrel_flats_mirrored.tres",
		"opponent": &"opponent_fossil",
		"own_hq": &"renew_hq",
		"other_hq": &"headquarters",
		"own_faction": &"renew",
		"own_triad": 6,
		"other_triad": 2,
	},
]
## Player 1's Headquarters tile in both scenarios (the minimap paints its footprint).
const HQ_TILE: Vector2i = Vector2i(7, 7)
## The default marker colours (WorldSort.TRIADS): your own Sne, the computer's Karmin.
const OWN_DEFAULT: int = 6
const OTHER_DEFAULT: int = 2
const THINK_TICKS: int = 150

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


## The scene a test left is freed, and the orders a test queued are dropped.
func after_test() -> void:
	MenuRig.end()
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:
		tree.current_scene.free()
		tree.current_scene = null
	CommandQueue.clear()


func test_the_dev_menu_lists_both_routes_first_as_enabled_buttons() -> void:
	var menu: Node = await _open_menu()
	var grid: Node = menu.find_child("Grid", true, false)
	for index: int in ROUTES.size():
		var button: Button = menu.find_child(ROUTES[index]["button"], true, false)
		assert_object(button).is_not_null()
		assert_str(button.text).is_equal(ROUTES[index]["text"])
		assert_bool(button.disabled).is_false()
		assert_int(button.get_index()).is_equal(index)  # Before the test map.
		assert_object(button.get_parent()).is_same(grid)
	assert_int(menu.find_child("TestMapButton", true, false).get_index()).is_equal(ROUTES.size())


func test_each_route_opens_its_scenario_with_the_other_sides_computer() -> void:
	for route: Dictionary in ROUTES:
		var main: Node = await _press(route["button"])
		var label: String = route["text"]
		assert_str(main.scene_file_path).override_failure_message(label).is_equal(
			DevRoutes.MAIN_SCENE
		)
		var runner: MatchRunner = main.get_node("MatchRunner")
		assert_str(runner.scenario.resource_path).override_failure_message(label).is_equal(
			route["scenario"]
		)
		assert_int(runner.scenario.local_player).is_equal(1)  # Player 1 is local in both.
		assert_int(runner.opponents.size()).is_equal(1)
		assert_str(str(runner.opponents[0].id)).override_failure_message(label).is_equal(
			str(route["opponent"])
		)
		assert_str(str(_hq_type(runner, 1))).override_failure_message(label).is_equal(
			str(route["own_hq"])
		)
		assert_str(str(_hq_type(runner, 2))).override_failure_message(label).is_equal(
			str(route["other_hq"])
		)
		main.free()
		get_tree().current_scene = null
		CommandQueue.clear()


## The computer of the other side plays the match: its Commands appear in the replay as player 2's,
## a QUEUE and a PLACE among them, and the sim drops none.
func test_the_computer_plays_its_own_side_in_each_route() -> void:
	for route: Dictionary in ROUTES:
		var main: Node = await _press(route["button"])
		var runner: MatchRunner = main.get_node("MatchRunner")
		runner.run_ticks(THINK_TICKS * 4)
		var kinds: Dictionary[int, int] = {}
		var at: int = 0
		while at < runner.replay.commands.size():
			var command: Command = Command.new()
			at = Command.decode(runner.replay.commands, at, command)
			assert_int(at).is_greater(0)
			if at <= 0:
				break
			assert_int(command.player_id).override_failure_message(route["text"]).is_equal(2)
			kinds[command.type] = kinds.get(command.type, 0) + 1
		assert_bool(kinds.has(Command.Type.QUEUE) and kinds.has(Command.Type.PLACE)).is_true()
		assert_int(runner.world.dropped_commands).override_failure_message(route["text"]).is_equal(
			0
		)
		main.free()
		get_tree().current_scene = null
		CommandQueue.clear()


## The build menu of each route lists the player's own side and the types of no side, in every tab.
func test_the_build_menu_shows_only_the_players_own_side_in_each_route() -> void:
	for route: Dictionary in ROUTES:
		var main: Node = await _press(route["button"])
		var runner: MatchRunner = main.get_node("MatchRunner")
		var sidebar: BuildSidebar = main.find_child("BuildSidebar", true, false)
		sidebar.refresh()
		var snap: MatchSnapshot = runner.snapshot
		var shown: int = 0
		for tab: int in World.Tab.FLIGHT:  # The tabs every roster fills; Flight waits for P245.
			sidebar.select_tab(tab)
			var grid: GridContainer = sidebar.find_children("*", "GridContainer", true, false)[0]
			for tile: Node in grid.get_children():
				if not (tile as Control).visible:
					continue
				shown += 1
				var type: int = snap.type_ids.find(StringName(tile.name.trim_prefix("Tile_")))
				assert_int(type).is_greater_equal(0)
				var faction: int = snap.type_faction[type]
				var who: String = "%s: %s" % [route["text"], tile.name]
				if faction >= 0:
					(
						assert_str(str(snap.faction_ids[faction]))
						. override_failure_message(who)
						. is_equal(str(route["own_faction"]))
					)
		assert_int(shown).override_failure_message(route["text"]).is_greater(4)
		main.free()
		get_tree().current_scene = null
		CommandQueue.clear()


## Your units take the default marker colours (answer 3): player 1 wears Sne in the atlas and on
## the minimap, player 2 Karmin, whichever side the route plays.
func test_each_routes_player_wears_the_colour_of_its_side_and_the_other_the_other() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]  # Sideways, so that the minimap shows.
	await await_idle_frame()
	for route: Dictionary in ROUTES:
		var main: Node = await _press(route["button"])
		var runner: MatchRunner = main.get_node("MatchRunner")
		var sorted: WorldSort = main.get_node("WorldSort")
		runner.run_ticks(2)
		await await_idle_frame()
		sorted.sync()
		var label: String = route["text"]
		var own: Array = WorldSort.TRIADS[route["own_triad"]]
		var other: Array = WorldSort.TRIADS[route["other_triad"]]
		assert_str(sorted.mid_colour(1).to_html(false)).override_failure_message(label).is_equal(
			Color(own[1]).to_html(false)
		)
		assert_str(sorted.mid_colour(2).to_html(false)).override_failure_message(label).is_equal(
			Color(other[1]).to_html(false)
		)
		var picture: MinimapImage = (main.find_child("Minimap", true, false) as Minimap).picture()
		var pixel: Color = picture.image().get_pixel(HQ_TILE.x, HQ_TILE.y)
		(
			assert_vector(Vector3i(pixel.r8, pixel.g8, pixel.b8))
			. override_failure_message(label)
			. is_equal(Vector3i(Color(own[1]).r8, Color(own[1]).g8, Color(own[1]).b8))
		)
		main.free()
		get_tree().current_scene = null
		CommandQueue.clear()


## The data behind it: every Skirmish scenario (both sides of all three maps, and the mirrors) names
## `(0, 6, 2)`, entry 0 unused, so the default marker colours are the route's rule, not a swap.
## The fixed faction colours are the HUD accents (ADR 0050 section 3): the art's `faction` material
## mid of each side equals the theme's accent token. The route test above proves the markers (own
## units Sne, the computer's Karmin) per route.
func test_the_fixed_faction_colours_are_the_hud_accents() -> void:
	var theme: Theme = load("res://game/ui/theme.tres") as Theme
	var pairs: Dictionary[StringName, StringName] = {
		&"fossil": &"AccentFossil", &"renew": &"AccentRenew"
	}
	for faction: StringName in pairs:
		var accent: Color = theme.get_color(&"accent", pairs[faction])
		var mid: Color = Color(ArtPalette.MATERIALS[faction][ArtPalette.FACTION])
		assert_str(mid.to_html(false)).override_failure_message(faction).is_equal(
			accent.to_html(false)
		)


func test_every_skirmish_scenario_defaults_to_own_white_and_the_computer_red() -> void:
	var seen: int = 0
	for file: String in DirAccess.get_files_at("res://data/scenarios"):
		if not file.begins_with("skirmish_") or not file.ends_with(".tres"):
			continue
		var scenario: ScenarioDef = load("res://data/scenarios/" + file)
		assert_array(scenario.team_triads).override_failure_message(file).is_equal(
			PackedInt32Array([0, OWN_DEFAULT, OTHER_DEFAULT])
		)
		assert_int(WorldSort.triad_index(scenario.team_triads, 1)).is_equal(OWN_DEFAULT)
		assert_int(WorldSort.triad_index(scenario.team_triads, 2)).is_equal(OTHER_DEFAULT)
		seen += 1
	assert_int(seen).is_equal(12)
	assert_array(WorldSort.TRIADS[OWN_DEFAULT]).is_equal(["#FFFFFF", "#DCE2E6", "#A3ACB3"])
	assert_array(WorldSort.TRIADS[OTHER_DEFAULT]).is_equal(["#F26A5E", "#CF3A2E", "#922219"])


## The type id of player `player`'s Headquarters: the first of its buildings with "hq" in its id or
## the Derrick League's own.
func _hq_type(runner: MatchRunner, player: int) -> StringName:
	var snap: MatchSnapshot = runner.snapshot
	for row: int in snap.unit_count():
		var type_id: StringName = snap.type_ids[snap.type_index[row]]
		if snap.owner[row] == player and [&"headquarters", &"renew_hq"].has(type_id):
			return type_id
	return &""


## Opens the dev menu as the current scene, in the tree for two frames.
func _open_menu() -> Node:
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	return menu


## Presses `button_name` on the dev menu; the scene that the press changed to.
func _press(button_name: String) -> Node:
	var menu: Node = await _open_menu()
	var button: Button = menu.find_child(button_name, true, false)
	assert_bool(button.disabled).is_false()
	button.pressed.emit()
	await await_idle_frame()
	await await_idle_frame()
	return get_tree().current_scene
