extends RefCounted
## The HUD v2 walk (plan P125, ADR 0025 sections 1, 2, 9 and 17). Not a suite. It opens the main
## scene at one size and walks the HUD states with a turn in each: `walk_battle` goes battle,
## drawer, placement (of a ready structure, the old way: order, READY, place), drawer again, the
## command bar (Stop, Deselect) and the pinned full map, pause and resume; `walk_aim` goes into a
## strike aim and taps a group in it. After each state `visit` is called with (label, main), so a
## suite chooses what it checks there: the layout, the 48 dp scan or the no-ad guard.
## A suite that uses it calls `MenuRig.begin()` and `MenuRig.end()` itself.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const PlacementRig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const TOLERANCE_PX: float = 1.5
const MIN_DP: float = 48.0
## Player 1's own buildings and units besides its Headquarters (id 1): [unit, x, y]. The Deep Bore
## is the strike building; the enemy Headquarters is id 2.
const MORE: Array[Array] = [
	["fossil_strike", 6, 12],
	["light_tank", 14, 14],
	["rifle_squad", 15, 15],
]
const ROSTER: Array[String] = ["power_plant", "barracks"]
## The HUD controls whose rects the layout check reads, by node name.
const PARTS: Array[String] = [
	"EconomyPill",
	"RadarScope",
	"BuildButton",
	"ReadyChip",
	"CommandBar",
	"GroupColumn",
	"RadarMap",
	"StrikeButton",
	"StrikeConfirm",
	"StrikeCancel",
	"PlaceConfirm",
	"PlaceCancel",
]
const AD_WORDS: Array[String] = ["admob", "adservice", "banner", "interstitial", "rewarded"]


## A new main scene at `size` on the engine's own metrics, its match paused, with player 1's
## Commands caught in `main.get_meta("sent")`.
static func open(suite: GdUnitTestSuite, size: Vector2i) -> Node2D:
	UiScale.clear_override()
	suite.get_window().size = size
	await suite.await_idle_frame()
	var main: Node2D = (load(DevRoutes.MAIN_SCENE) as PackedScene).instantiate()
	var scenario: ScenarioDef = PlacementRig.scenario_for(1, "headquarters", MORE, ROSTER)
	var runner: MatchRunner = main.get_node("MatchRunner")
	runner.scenario = scenario
	runner.paused = true
	suite.add_child(main)
	await suite.await_idle_frame()
	var sent: Array[Command] = []
	main.set_meta("sent", sent)
	(main.get_node("PlayerController") as PlayerController).command_sink = func(
		command: Command
	) -> void:
		sent.append(command)
	await suite.await_idle_frame()
	return main


## Battle with own units selected, drawer, placement, drawer, command bar, full map pinned, pause,
## resume. The Commands that went out are checked here: one STOP, nothing else.
static func walk_battle(suite: GdUnitTestSuite, main: Node2D, visit: Callable) -> void:
	var controller: PlayerController = main.get_node("PlayerController")
	var runner: MatchRunner = main.get_node("MatchRunner")
	var sidebar: BuildSidebar = hud(main, "BuildSidebar")
	var placement: PlacementController = main.get_node("PlacementController")
	var bar: CommandBar = hud(main, "CommandBar")
	var sent: Array[Command] = main.get_meta("sent")
	controller.selection.set_ids(own_units(main))
	await frames(suite)
	visit.call("battle", main)
	await tap(suite, hud(main, "BuildButton"))
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.DRAWER)).is_true()
	visit.call("drawer", main)
	# A structure the old way: it is ready in the queue, and a tap on its card places it.
	var snap: MatchSnapshot = runner.snapshot
	PlacementRig.make_ready(snap)
	snap.tick += 1
	sidebar.refresh()
	await sidebar.show_ready()
	await frames(suite)
	var card: ItemTile = ready_card(sidebar)
	suite.assert_object(card).is_not_null()
	await tap(suite, card)
	await frames(suite)
	suite.assert_bool(placement.active).is_true()
	suite.assert_bool(state(main).is_open(HudState.Unfold.DRAWER)).is_false()
	visit.call("placement", main)
	placement.cancel()  # The X: the drawer returns, as it was open when placement began.
	await frames(suite)
	suite.assert_bool(placement.active).is_false()
	suite.assert_bool(state(main).is_open(HudState.Unfold.DRAWER)).is_true()
	visit.call("drawer again", main)
	await tap(suite, sidebar.find_child("Close", true, false) as Control)
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.NONE)).is_true()
	suite.assert_bool(bar.visible).is_true()
	visit.call("command bar", main)
	await tap(suite, bar.order_button(&"stop"))
	await tap(suite, bar.find_child("Deselect", true, false) as Control)
	await frames(suite)
	suite.assert_array(controller.selection.selected).is_empty()
	suite.assert_int(sent.size()).is_equal(1)
	suite.assert_int(sent[0].type).is_equal(Command.Type.STOP)
	visit.call("deselected", main)
	await tap(suite, hud(main, "RadarScope"))
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.RADAR)).is_true()
	await tap(suite, hud(main, "MapPin"))
	await frames(suite)
	suite.assert_bool(state(main).pinned).is_true()
	controller.selection.set_ids(own_units(main))
	await frames(suite)
	visit.call("full map pinned", main)
	runner.paused = false  # So that Resume has something to give back.
	await tap(suite, hud(main, "Menu"))
	await frames(suite)
	suite.assert_bool(runner.paused).is_true()
	suite.assert_bool(state(main).is_open(HudState.Unfold.PAUSE)).is_true()
	visit.call("pause", main)
	await tap(suite, hud(main, "ResumeButton"))
	runner.paused = true  # No tick runs in the frames of the test.
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.PAUSE)).is_false()
	suite.assert_int(sent.size()).is_equal(1)  # Pause, Resume and the rest sent nothing.
	visit.call("resumed", main)


## A strike aim with the tank selected, a group tap in the aim that selects the rifle squad (the
## bottom stays where it was: ADR 0025 section 1's freeze), then Deselect and a group tap again.
static func walk_aim(suite: GdUnitTestSuite, main: Node2D, visit: Callable) -> void:
	var controller: PlayerController = main.get_node("PlayerController")
	var aim: StrikeAim = main.get_node("StrikeAim")
	var tank: int = id_of(main, &"light_tank")
	var rifle: int = id_of(main, &"rifle_squad")
	for entry: Array in [[tank, 1], [rifle, 2]]:
		controller.selection.set_ids(PackedInt32Array([entry[0]]))
		controller.assign_group(entry[1])
	controller.selection.set_ids(PackedInt32Array([tank]))
	var snap: MatchSnapshot = main.get_node("MatchRunner").snapshot
	snap.ready_tick[snap.index_of(id_of(main, &"fossil_strike"))] = snap.tick + 1
	aim.refresh()
	await frames(suite)
	suite.assert_bool(aim.begin()).is_true()
	await frames(suite)
	visit.call("aim", main)
	var before: Dictionary[String, Rect2] = frozen_rects(main)
	suite.assert_array(before.keys()).contains(["BuildButton", "StrikeConfirm", "StrikeCancel"])
	await tap(suite, hud(main, "Group2"))
	await frames(suite)
	suite.assert_array(controller.selection.selected).is_equal([rifle])
	suite.assert_that(frozen_rects(main)).is_equal(before)
	visit.call("aim group tap", main)
	await tap(suite, hud(main, "Deselect"))
	await tap(suite, hud(main, "Group1"))
	await frames(suite)
	suite.assert_array(controller.selection.selected).is_equal([tank])
	suite.assert_that(frozen_rects(main)).is_equal(before)
	suite.assert_bool((hud(main, "CommandBar") as CommandBar).has_slot()).is_true()
	visit.call("aim group tap after deselect", main)
	aim.cancel()
	await frames(suite)
	suite.assert_array(main.get_meta("sent")).is_empty()


## The rects the strike aim freezes: BUILD and the check mark and X.
static func frozen_rects(main: Node2D) -> Dictionary[String, Rect2]:
	var out: Dictionary[String, Rect2] = {}
	for part: String in ["BuildButton", "StrikeConfirm", "StrikeCancel", "StrikeButton"]:
		var node: Control = hud(main, part)
		if node.is_visible_in_tree():
			out[part] = node.get_global_rect()
	return out


## The layout check of one state: every HUD part that shows is inside the safe rect, and no two
## overlap. The Ready chip is BUILD's child and stands beside it; the drawer's rect is its panel
## without the strip that reaches on to the screen's edge.
static func check_layout(suite: GdUnitTestSuite, main: Node2D, label: String) -> void:
	var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
	var rects: Dictionary[String, Rect2] = {}
	for part: String in PARTS:
		var node: Control = hud(main, part)
		if node != null and node.is_visible_in_tree():
			rects[part] = node.get_global_rect()
	var drawer: BuildSidebar = hud(main, "BuildSidebar")
	if drawer.is_open():
		rects["Drawer"] = drawer_rect(main)
	for part: String in rects:
		var why: String = (
			"%s at %s: %s %s outside %s" % [label, size_of(main), part, rects[part], safe]
		)
		suite.assert_bool(safe.encloses(rects[part])).override_failure_message(why).is_true()
	var menu: Control = hud(main, "PauseMenu")
	if menu.visible:  # The menu's buttons are the controls that take touches while it shows.
		for node: Node in menu.find_children("*", "BaseButton", true, false):
			var button: Control = node as Control
			var why: String = (
				"%s at %s: %s %s outside %s"
				% [label, size_of(main), button.name, button.get_global_rect(), safe]
			)
			(
				suite
				. assert_bool(safe.encloses(button.get_global_rect()))
				. override_failure_message(why)
				. is_true()
			)
	var names: Array = rects.keys()
	for first: int in names.size():
		for second: int in range(first + 1, names.size()):
			var a: String = names[first]
			var b: String = names[second]
			if exempt(a, b, main):
				continue
			var shrunk: Rect2 = rects[a].grow(-TOLERANCE_PX)
			var why: String = (
				"%s at %s: %s %s overlaps %s %s" % [label, size_of(main), a, rects[a], b, rects[b]]
			)
			suite.assert_bool(shrunk.intersects(rects[b])).override_failure_message(why).is_false()


## Pairs the layout allows: the landscape drawer covers the scope (ADR 0025 section 2's table:
## "always but under the landscape drawer", and section 5: the backdrop covers it), and the ghost's
## two buttons are a pair of their own.
static func exempt(a: String, b: String, _main: Node2D) -> bool:
	if a == "RadarScope" and b == "Drawer":
		return not HudLayout.is_portrait()
	return a.begins_with("Place") and b.begins_with("Place")


## The drawer's panel inside the safe rect: its backdrop less the strip to the screen's edge.
static func drawer_rect(main: Node2D) -> Rect2:
	var full: Rect2 = main.get_viewport().get_visible_rect()
	var safe: Rect2 = SafeAreaMargin.rect_inside(full, SafeAreaMargin.DEFAULT_MARGIN_DP)
	var back: Rect2 = (hud(main, "Backdrop") as Control).get_global_rect()
	if HudLayout.is_portrait():
		return Rect2(back.position, Vector2(back.size.x, back.size.y - (full.end.y - safe.end.y)))
	return Rect2(back.position, Vector2(back.size.x - (full.end.x - safe.end.x), back.size.y))


## The controls of one state that take input: the visible buttons, and the visible controls that
## stop the mouse and have a `_gui_input` of their own (a card, a tap area). A divider
## or a decoration that only stops the mouse by its class default takes no input. While the pause
## menu shows, it alone takes touches and is what is read.
static func input_controls(main: Node2D) -> Array[Control]:
	var root: Node = hud(main, "PauseMenu") if state(main).is_open(HudState.Unfold.PAUSE) else main
	var found: Array[Control] = []
	for node: Node in root.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree() or control is ScrollBar:
			continue
		var scripted: bool = takes_gui_input(control.get_script())
		if (
			control is BaseButton
			or (scripted and control.mouse_filter == Control.MOUSE_FILTER_STOP)
		):
			found.append(control)
	return found


## Whether `script`, or a script it extends, defines `_gui_input`.
static func takes_gui_input(script: Script) -> bool:
	while script != null:
		for method: Dictionary in script.get_script_method_list():
			if method["name"] == "_gui_input":
				return true
		script = script.get_base_script()
	return false


## The 48 dp scan of one state: each of `input_controls` is at least 48 dp on its short side.
static func small_targets(main: Node2D, label: String) -> Array[String]:
	var least: float = UiScale.dp(MIN_DP) - 0.5
	var found: Array[String] = []
	for control: Control in input_controls(main):
		if minf(control.size.x, control.size.y) < least:
			var where: String = (
				"%s at %s: %s is %s" % [label, size_of(main), control.name, control.size]
			)
			found.append("%s, needs %.1f" % [where, least])
	return found


## Whether a node of an ad plugin or of `game/ads` is in the tree of `main` or the scene tree.
static func ad_nodes(main: Node2D) -> Array[String]:
	var found: Array[String] = []
	for node: Node in main.get_tree().root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		var text: String = node.get_class().to_lower()
		if script != null:
			text += (
				" "
				+ script.resource_path.to_lower()
				+ " "
				+ str(script.get_global_name()).to_lower()
			)
		for word: String in AD_WORDS:
			if text.contains(word) or text.contains("/ads/"):
				found.append("%s: %s" % [node.get_path(), text])
				break
	return found


static func size_of(main: Node2D) -> Vector2i:
	return main.get_window().size


static func state(main: Node2D) -> HudState:
	return (main.get_node("Hud/HudStateFeed") as HudStateFeed).state


static func hud(main: Node2D, node_name: String) -> Control:
	return main.get_node("Hud").find_child(node_name, true, false) as Control


## Player 1's own units, not its buildings, as ids.
static func own_units(main: Node2D) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for type: StringName in [&"light_tank", &"rifle_squad"]:
		out.append(id_of(main, type))
	return out


static func id_of(main: Node2D, type_id: StringName) -> int:
	var snap: MatchSnapshot = (main.get_node("MatchRunner") as MatchRunner).snapshot
	for row: int in snap.unit_count():
		if snap.owner[row] == 1 and snap.type_ids[snap.type_index[row]] == type_id:
			return snap.unit_id[row]
	return -1


static func ready_card(sidebar: BuildSidebar) -> ItemTile:
	for node: Node in sidebar.find_children("*", "ItemTile", true, false):
		var tile: ItemTile = node as ItemTile
		if tile.is_visible_in_tree() and tile.state == ItemTile.State.READY:
			return tile
	return null


## A finger down and up on the middle of `control`, then a frame.
static func tap(suite: GdUnitTestSuite, control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(suite.get_viewport(), 0, at)
	TouchEvents.release(suite.get_viewport(), 0, at)
	await suite.await_idle_frame()


static func frames(suite: GdUnitTestSuite) -> void:
	await suite.await_idle_frame()
	await suite.await_idle_frame()
