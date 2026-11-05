extends RefCounted
## The HUD v2 walk (plan P125, ADR 0025 sections 1, 2, 9 and 17). Not a suite. It opens the main
## scene at one size and walks the HUD states, with a turn of the phone in each: after a state's
## visit the window is turned to its transpose, the state is checked to be kept (the unfold and
## its pin, the drawer's tab, placement, the pause), the visit runs again as "<label> turned", and
## the window turns back. `walk_battle` goes battle, drawer, placement, drawer again, the command
## bar (Stop, Deselect), the pinned full map, pause and resume. Placement is the old way, except
## that the structure's READY is forced in the published snapshot (no order is run), and placement
## ends with the X (`cancel`), not a build. `walk_aim` goes into a strike aim twice: with nothing
## selected, where a group tap fills the selection, and with a tank selected, where Deselect empties
## it and a group tap fills it again; the bottom stays where it was (the freeze), and a turn ends
## the aim and sends no Command (the designed behaviour; the aim's later states are not turned).
## After each state `visit` is called with (label, main), so a suite chooses what it checks there.
## A suite that uses it calls `MenuRig.begin()` and `MenuRig.end()` itself.

## What a visit does after the state: turns the phone and finds the state kept, finds the aim
## ended, or does not turn.
enum Turn { KEPT, ENDS_AIM, NONE }
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
	main.set_meta("size", size)
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
	var pill_rect: Rect2 = hud(main, "EconomyPill").get_global_rect()
	await _visit(suite, main, "battle", visit)
	await tap(suite, hud(main, "BuildButton"))
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.DRAWER)).is_true()
	var pill: Control = hud(main, "EconomyPill")  # P120e: the pill stays in its corner.
	suite.assert_that(pill.get_global_rect()).is_equal(pill_rect)
	suite.assert_bool(pill.is_visible_in_tree() and pill.modulate.a == 1.0).is_true()
	# A tab other than the default one, so that a turn that reset the tab would be seen.
	await tap(suite, sidebar.find_child("TabInfantry", true, false) as Control)
	await frames(suite)
	suite.assert_int(sidebar.tab).is_equal(World.Tab.INFANTRY)
	await _visit(suite, main, "drawer", visit)
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
	await _visit(suite, main, "placement", visit)
	placement.cancel()  # The X: the drawer stays down (Michael, 2026-11-05) ...
	await frames(suite)
	suite.assert_bool(placement.active).is_false()
	suite.assert_bool(state(main).is_open(HudState.Unfold.DRAWER)).is_false()
	await tap(suite, hud(main, "BuildButton"))  # ... and BUILD brings it back.
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.DRAWER)).is_true()
	await _visit(suite, main, "drawer again", visit)
	await tap(suite, sidebar.find_child("Close", true, false) as Control)
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.NONE)).is_true()
	suite.assert_bool(bar.visible).is_true()
	await _visit(suite, main, "command bar", visit)
	await tap(suite, bar.order_button(&"stop"))
	await tap(suite, bar.find_child("Deselect", true, false) as Control)
	await frames(suite)
	suite.assert_array(controller.selection.selected).is_empty()
	suite.assert_int(sent.size()).is_equal(1)
	suite.assert_int(sent[0].type).is_equal(Command.Type.STOP)
	await _visit(suite, main, "deselected", visit)
	await tap(suite, hud(main, "RadarScope"))
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.RADAR)).is_true()
	await tap(suite, hud(main, "MapPin"))
	await frames(suite)
	suite.assert_bool(state(main).pinned).is_true()
	controller.selection.set_ids(own_units(main))
	await frames(suite)
	await _visit(suite, main, "full map pinned", visit)
	runner.paused = false  # The match runs, so that the menu's pause is seen to be the menu's.
	tap_now(suite, hud(main, "Menu"))  # No frame between: the menu's pause is what is seen.
	suite.assert_bool(runner.paused).is_true()
	await frames(suite)
	suite.assert_bool(state(main).is_open(HudState.Unfold.PAUSE)).is_true()
	for part: String in ["EconomyPill", "BuildButton", "RadarScope", "CommandBar"]:
		var covered: Control = hud(main, part)  # P124b: the HUD is clear under the menu.
		suite.assert_float(covered.modulate.a).override_failure_message(part).is_equal(0.0)
	await _visit(suite, main, "pause", visit)
	tap_now(suite, hud(main, "ResumeButton"))
	suite.assert_bool(runner.paused).is_false()  # Resume gives the match back ...
	runner.paused = true  # ... and the test takes it again in the same frame: no tick plays.
	await frames(suite)
	suite.assert_float(pill.modulate.a).is_equal(1.0)
	suite.assert_bool(state(main).is_open(HudState.Unfold.PAUSE)).is_false()
	suite.assert_int(sent.size()).is_equal(1)  # Pause, Resume and the rest sent nothing.
	await _visit(suite, main, "resumed", visit)


## The strike aim, twice (ADR 0025 section 1's freeze). First with nothing selected: a group tap
## fills the selection and the bottom stays where it was, with no bar. Then with the tank
## selected: Deselect empties the selection and leaves an empty plate, a group tap fills it again,
## and nothing under the thumb moves. A turn ends the aim and sends no Command.
static func walk_aim(suite: GdUnitTestSuite, main: Node2D, visit: Callable) -> void:
	var controller: PlayerController = main.get_node("PlayerController")
	var aim: StrikeAim = main.get_node("StrikeAim")
	var bar: CommandBar = hud(main, "CommandBar")
	var tank: int = id_of(main, &"light_tank")
	var rifle: int = id_of(main, &"rifle_squad")
	for entry: Array in [[tank, 1], [rifle, 2]]:
		controller.selection.set_ids(PackedInt32Array([entry[0]]))
		controller.assign_group(entry[1])
	controller.deselect()
	var snap: MatchSnapshot = main.get_node("MatchRunner").snapshot
	snap.ready_tick[snap.index_of(id_of(main, &"fossil_strike"))] = snap.tick + 1
	await _begin_aim(suite, main)
	suite.assert_bool(bar.has_slot()).is_false()
	await _visit(suite, main, "aim", visit, Turn.ENDS_AIM)
	await _begin_aim(suite, main)  # The turn ended the first.
	var before: Dictionary[String, Rect2] = frozen_rects(main)
	suite.assert_array(before.keys()).contains(["BuildButton", "StrikeConfirm", "StrikeCancel"])
	await tap(suite, hud(main, "Group2"))
	await frames(suite)
	suite.assert_array(controller.selection.selected).is_equal([rifle])
	suite.assert_that(frozen_rects(main)).is_equal(before)
	suite.assert_bool(bar.has_slot()).is_false()  # Filled under the freeze: no bar appears.
	await _visit(suite, main, "aim group tap", visit, Turn.NONE)
	aim.cancel()
	controller.selection.set_ids(PackedInt32Array([tank]))
	await frames(suite)
	await _begin_aim(suite, main)
	before = frozen_rects(main)
	suite.assert_bool(bar.has_slot()).is_true()
	await tap(suite, hud(main, "Deselect"))
	await frames(suite)
	suite.assert_array(controller.selection.selected).is_empty()
	suite.assert_that(frozen_rects(main)).is_equal(before)
	suite.assert_bool(bar.has_slot()).is_true()  # An empty plate, not a gone one.
	await _visit(suite, main, "aim deselected", visit, Turn.NONE)
	await tap(suite, hud(main, "Group1"))
	await frames(suite)
	suite.assert_array(controller.selection.selected).is_equal([tank])
	suite.assert_that(frozen_rects(main)).is_equal(before)
	suite.assert_bool(bar.has_slot()).is_true()
	await _visit(suite, main, "aim group tap after deselect", visit, Turn.NONE)
	aim.cancel()
	await frames(suite)
	suite.assert_array(main.get_meta("sent")).is_empty()


static func _begin_aim(suite: GdUnitTestSuite, main: Node2D) -> void:
	var aim: StrikeAim = main.get_node("StrikeAim")
	aim.refresh()
	await frames(suite)
	suite.assert_bool(aim.begin()).is_true()
	await frames(suite)


## Calls `visit` for the state, then turns the phone: the state must be kept (the aim excepted: a
## turn ends it, with no Command), `visit` runs as "<label> turned", and the window turns back.
static func _visit(
	suite: GdUnitTestSuite, main: Node2D, label: String, visit: Callable, turn: Turn = Turn.KEPT
) -> void:
	visit.call(label, main)
	if turn == Turn.NONE:  # The aim goes on: a turn would end it.
		return
	var aiming: bool = turn == Turn.ENDS_AIM
	var kept: Dictionary = facts(main)
	var size: Vector2i = main.get_meta("size")
	suite.get_window().size = Vector2i(size.y, size.x)
	await frames(suite)
	var why: String = "%s: after a turn to %s" % [label, suite.get_window().size]
	if aiming:
		var aim: StrikeAim = main.get_node("StrikeAim")
		suite.assert_bool(aim.active).override_failure_message(why + ": aim still on").is_false()
		suite.assert_array(main.get_meta("sent")).override_failure_message(why).is_empty()
	else:
		suite.assert_dict(facts(main)).override_failure_message(why).is_equal(kept)
	visit.call(label + " turned", main)
	suite.get_window().size = size
	await frames(suite)
	if not aiming:
		suite.assert_dict(facts(main)).override_failure_message(label + ": turned back").is_equal(
			kept
		)


## What a turn keeps: the unfold and its pin, the drawer's tab, placement, the pause, the
## selection.
static func facts(main: Node2D) -> Dictionary:
	return {
		"unfold": state(main).current,
		"pinned": state(main).pinned,
		"tab": (hud(main, "BuildSidebar") as BuildSidebar).tab,
		"placing": (main.get_node("PlacementController") as PlacementController).active,
		"paused": (main.get_node("MatchRunner") as MatchRunner).paused,
		"selected":
		Array((main.get_node("PlayerController") as PlayerController).selection.selected),
	}


## The rects the strike aim freezes: BUILD and the check mark and X.
static func frozen_rects(main: Node2D) -> Dictionary[String, Rect2]:
	var out: Dictionary[String, Rect2] = {}
	for part: String in ["BuildButton", "StrikeConfirm", "StrikeCancel", "StrikeButton"]:
		var node: Control = hud(main, part)
		if node.is_visible_in_tree():
			out[part] = node.get_global_rect()
	return out


## The layout check of one state: every HUD part that shows is inside the safe rect, and no two
## overlap. The Ready chip is BUILD's child and stands beside it (upright, above it or the strike
## button); the drawer's rect is its panel without the strip that reaches on to the screen's edge.
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
## two buttons are 16 dp apart by construction and are checked like the rest.
static func exempt(a: String, b: String, _main: Node2D) -> bool:
	if a == "RadarScope" and b == "Drawer":
		return not HudLayout.is_portrait()
	return false


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
	tap_now(suite, control)
	await suite.await_idle_frame()


## The same touch, with no frame after it.
static func tap_now(suite: GdUnitTestSuite, control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(suite.get_viewport(), 0, at)
	TouchEvents.release(suite.get_viewport(), 0, at)


static func frames(suite: GdUnitTestSuite) -> void:
	await suite.await_idle_frame()
	await suite.await_idle_frame()
