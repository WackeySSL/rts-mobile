extends GdUnitTestSuite
## The Research tab of the build drawer (plan P248, ADR 0036 section 2, ADR 0032) in the main scene
## at the six sizes of ScreenSizes.ALL, over a match whose Derrick League lists the two shipped
## upgrades (`FactionDef.upgrades` is empty in the shipped data until P249): there is no tab while
## the faction has no upgrade; with some it is a fifth tab inside the drawer with its name or icon
## (the rule of `_fit_tabs`), its cards are whole inside the drawer with their names in at most
## two lines and never cut, a locked card names the centre on its sash, a researched card says
## "Done" and a queued one does not queue again. A tap sends QUEUE through the controller's sink.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const HEAVY: String = "heavy_bombs"
const PLATED: String = "plated_hull"
const CENTRE: String = "fossil_engineering"

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


func test_there_is_no_research_tab_while_the_faction_lists_no_upgrade() -> void:
	await _open(ScreenSizes.ALL[0], false, [])
	assert_bool(_tab().visible).is_false()
	await _open(ScreenSizes.ALL[0], false, [CENTRE])
	assert_bool(_tab().visible).is_false()
	await _open(ScreenSizes.ALL[0], true, [])
	assert_bool(_tab().visible).is_true()
	var icon: TextureRect = _tab().find_child("Icon", true, false) as TextureRect
	assert_str(icon.texture.resource_path).is_equal("res://assets/art/svg/icons/tab_research.svg")


func test_five_tabs_fit_the_drawer_at_every_size_and_the_open_tab_keeps_its_name() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, true, [])
		await _assert_tabs(str(size))
		_tap(_tab())
		await _settle()
		assert_int(_sidebar.tab).override_failure_message(str(size)).is_equal(World.Tab.RESEARCH)
		assert_bool(_tab().find_child("Name", true, false).visible).is_true()
		await _assert_tabs(str(size) + " open")


func test_the_tabs_fit_every_profile_with_five_tabs() -> void:
	var profiles: Array[UiMetrics] = []
	profiles.append_array(UiProfiles.all().values())
	profiles.append_array(UiProfiles.portrait().values())
	profiles.append_array(UiProfiles.notch_design().values())
	for metrics: UiMetrics in profiles:
		await _open(metrics.window_size, true, [], metrics)
		for open: int in [World.Tab.STRUCTURES, World.Tab.FLIGHT, World.Tab.RESEARCH]:
			_sidebar.select_tab(open)
			await _settle()
			await _assert_tabs("%s %s tab %d" % [metrics.os_name, metrics.window_size, open])


func test_the_cards_are_whole_inside_the_drawer_with_their_names_in_two_lines_at_most() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, true, [CENTRE])
		_sidebar.select_tab(World.Tab.RESEARCH)
		await _settle()
		var items: Rect2 = (_sidebar.find_child("Items", true, false) as Control).get_global_rect()
		var shown: Array[String] = []
		for node: Node in _sidebar.find_children("Tile_*", "ItemTile", true, false):
			var tile: ItemTile = node as ItemTile
			if not tile.is_visible_in_tree():
				continue
			shown.append(tile.name)
			var at: String = "%s %s: %s" % [size, tile.name, tile.get_global_rect()]
			(
				assert_bool(items.grow(0.5).encloses(tile.get_global_rect()))
				. override_failure_message(at + " outside " + str(items))
				. is_true()
			)
			var caption: Label = tile.find_child("Caption", true, false) as Label
			(
				assert_bool(tile.get_global_rect().grow(0.5).encloses(caption.get_global_rect()))
				. override_failure_message(at + " caption out")
				. is_true()
			)
			assert_int(caption.get_line_count()).override_failure_message(at).is_between(1, 2)
			assert_int(caption.get_visible_line_count()).override_failure_message(at).is_equal(
				caption.get_line_count()
			)
			var tall: float = caption.get_line_height() * caption.get_line_count()
			assert_float(caption.size.y).override_failure_message(at + " clipped").is_greater_equal(
				tall - 0.5
			)
			var wide: float = tile.find_child("Stage", true, false).size.x
			assert_float(tile.size.x).override_failure_message(at).is_greater_equal(wide)
		assert_array(shown).override_failure_message(str(size)).is_equal(
			["Tile_" + HEAVY, "Tile_" + PLATED]
		)


func test_a_locked_card_names_the_centre_and_a_researched_card_says_done() -> void:
	await _open(ScreenSizes.ALL[1], true, [])  # No centre yet.
	_sidebar.select_tab(World.Tab.RESEARCH)
	await _settle()
	assert_int(_tile(HEAVY).state).is_equal(ItemTile.State.LOCKED)
	assert_str(_tile(HEAVY).word()).is_equal("Draft Shop")
	await _open(ScreenSizes.ALL[1], true, [CENTRE])
	_sidebar.select_tab(World.Tab.RESEARCH)
	await _settle()
	assert_int(_tile(HEAVY).state).is_equal(ItemTile.State.AVAILABLE)
	assert_int(_tile(PLATED).state).is_equal(ItemTile.State.AVAILABLE)
	assert_str((_tile(HEAVY).find_child("Cost", true, false) as Label).text).is_equal("800")
	_runner.snapshot.upgrades[1] = 1  # The first upgrade of the match: Heavy Bombs.
	_sidebar.refresh()
	await _settle()
	assert_int(_tile(HEAVY).state).is_equal(ItemTile.State.RESEARCHED)
	assert_str(_tile(HEAVY).word()).is_equal("Done")
	assert_bool((_tile(HEAVY).find_child("Cost", true, false) as Control).visible).is_false()
	assert_bool((_tile(HEAVY).find_child("Lock", true, false) as Control).visible).is_true()
	assert_int(_tile(PLATED).state).is_equal(ItemTile.State.AVAILABLE)  # The other is not.
	_tap_tile(HEAVY)
	assert_array(_sent).is_empty()  # Done: no order, a shake.
	assert_int(_tile(HEAVY).shakes).is_equal(1)


func test_a_tap_queues_one_upgrade_and_a_queued_card_does_not_queue_again() -> void:
	await _open(ScreenSizes.ALL[1], true, [CENTRE])
	_sidebar.select_tab(World.Tab.RESEARCH)
	await _settle()
	_tap_tile(PLATED)
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.QUEUE)
	assert_array(_sent[0].payload).is_equal([_runner.snapshot.type_ids.find(StringName(PLATED))])
	_sent.clear()
	var tile: ItemTile = _tile(PLATED)
	tile.show_state(ItemTile.State.AVAILABLE, 1, 0.3)  # In the queue, 30 % along.
	_tap_tile(PLATED)
	assert_array(_sent).is_empty()
	assert_int(tile.shakes).is_equal(1)


func _tab() -> Button:
	return _main.get_node("Hud").find_child("TabResearch", true, false) as Button


func _tile(id: String) -> ItemTile:
	return _sidebar.find_child("Tile_" + id, true, false) as ItemTile


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


func _tap_tile(id: String) -> void:
	_tap(_tile(id))


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## Every visible tab: at least 48 dp each way, in the drawer and the safe area, its name (when
## shown: a 6-inch phone sideways has room for icons only) whole inside it and the close
## button in the drawer too.
func _assert_tabs(why: String) -> void:
	var drawer: Rect2 = _sidebar.get_global_rect()
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 0.0)
	var shown: int = 0
	for node: Node in _sidebar.find_children("Tab*", "Button", true, false):
		var tab: Button = node as Button
		if not tab.is_visible_in_tree():
			continue
		shown += 1
		var rect: Rect2 = tab.get_global_rect()
		var at: String = "%s: %s %s in %s" % [why, tab.name, rect, drawer]
		assert_float(rect.size.x).override_failure_message(at).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		assert_float(rect.size.y).override_failure_message(at).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		assert_bool(drawer.grow(0.5).encloses(rect)).override_failure_message(at).is_true()
		assert_bool(safe.grow(0.5).encloses(rect)).override_failure_message(at).is_true()
		var label: Label = tab.find_child("Name", true, false) as Label
		if not label.visible:
			continue
		var font: Font = label.get_theme_font(&"font")
		var wide: float = (
			font
			. get_string_size(
				label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size(&"font_size")
			)
			. x
		)
		(
			assert_bool(rect.grow(0.5).encloses(label.get_global_rect()))
			. override_failure_message(at)
			. is_true()
		)
		assert_float(wide).override_failure_message(at + " name").is_less_equal(label.size.x + 0.5)
	assert_int(shown).override_failure_message(why).is_equal(5)
	var close: Rect2 = _sidebar.find_child("Close", true, false).get_global_rect()
	var gone: String = "%s: close %s, drawer %s" % [why, close, drawer]
	assert_bool(drawer.grow(0.5).encloses(close)).override_failure_message(gone).is_true()
	assert_float(close.size.x).override_failure_message(gone).is_greater_equal(
		UiScale.dp(48.0) - 0.5
	)


## A new main scene at `size` (under `metrics` when given) whose sidebar reads a snapshot of a
## match where player 1's Derrick League lists the two upgrades (`upgrades`) or none; `own` are
## the ids of the buildings and units player 1 holds besides the airfield.
func _open(size: Vector2i, upgrades: bool, own: Array[String], metrics: UiMetrics = null) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _main.get_node("MatchRunner").scenario
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_sidebar.open()
	await await_idle_frame()
	_sidebar.runner = _runner
	var controller: PlayerController = _main.get_node("PlayerController")
	_sent.clear()
	controller.command_sink = func(command: Command) -> void: _sent.append(command)
	var spawns: Array[SpawnDef] = [Rig.spawn(1, "fossil_airfield", 2, 2)]
	for at: int in own.size():
		spawns.append(Rig.spawn(1, own[at], 8 + 4 * at, 2))
	spawns.append(Rig.spawn(2, "renew_hq", 20, 20))
	var scenario: ScenarioDef = Rig.scenario(spawns)
	var fossil: FactionDef = (load("res://data/factions/fossil.tres") as FactionDef).duplicate()
	var listed: Array[UpgradeDef] = []
	if upgrades:
		listed.append(load("res://data/upgrades/%s.tres" % HEAVY) as UpgradeDef)
		listed.append(load("res://data/upgrades/%s.tres" % PLATED) as UpgradeDef)
	fossil.upgrades = listed
	var factions: Array[FactionDef] = [null, fossil, load("res://data/factions/renew.tres")]
	scenario.factions = factions
	_runner.snapshot = Sw.snapshot(World.from_scenario(scenario))
	_sidebar.refresh()
	await _settle()
