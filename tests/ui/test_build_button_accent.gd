extends GdUnitTestSuite
## BUILD's ring and disc wear the local player's side (plan P120f): the accent is keyed by
## the faction id (`type_faction` indexes `faction_ids`, in order of first appearance, so index 0
## is fossil on the Derrick League's routes), as the pause menu's is. A row without a faction is
## skipped.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_the_derrick_route_wears_fossil_orange_and_the_lumen_route_renew_cyan() -> void:
	var accents: Dictionary[String, StringName] = {
		MatchRig.DERRICK: &"AccentFossil", MatchRig.LUMEN: &"AccentRenew"
	}
	for route: String in [MatchRig.DERRICK, MatchRig.LUMEN]:
		get_window().size = ScreenSizes.LANDSCAPE[0]
		await await_idle_frame()
		var main: Node = auto_free(await MatchRig.open(self, route))
		var runner: MatchRunner = main.get_node("MatchRunner")
		runner.paused = true
		var button: BuildButton = main.get_node("Hud/BuildButton")
		var snap: MatchSnapshot = runner.snapshot
		var player: int = runner.scenario.local_player
		# A queue with a head and an item, so that the ring and the count are drawn.
		var type: int = -1
		for row: int in snap.unit_id.size():
			if snap.owner[row] == player:
				type = snap.type_index[row]
				break
		var queue: int = player * World.TABS + World.Tab.INFANTRY
		var slots: int = BuildSidebar._queue_slots(snap)
		snap.queue_type[queue * slots] = type
		snap.queue_count[queue] = 1
		snap.queue_progress[queue] = 100
		button.refresh(snap)
		for frame: int in 2:
			await await_idle_frame()
		var accent: StringName = accents[route]
		var why: String = route.get_file()
		assert_bool(button.ring_drawn).override_failure_message(why).is_true()
		assert_object(button.ring_color).override_failure_message(why).is_equal(
			button.get_theme_color(&"light", accent)
		)
		assert_object(button.disc_color).override_failure_message(why).is_equal(
			button.get_theme_color(&"accent", accent)
		)
		main.free()
		CommandQueue.clear()


func test_a_first_own_row_without_a_faction_is_skipped_and_the_id_decides() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	var main: Node = auto_free(await MatchRig.open(self))
	(main.get_node("MatchRunner") as MatchRunner).paused = true
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = main.get_node("MatchRunner").scenario
	var button: BuildButton = main.get_node("Hud/BuildButton")
	button.runner = runner
	var world: World = Sw.world()
	Sw.own(world, ["headquarters", "power_plant"])
	for case: Array in [[&"AccentFossil", 0], [&"AccentRenew", 1]]:
		var snap: MatchSnapshot = Sw.snapshot(world, int(case[1]))
		snap.faction_ids = [&"fossil", &"renew"]
		var first: int = -1
		var second: int = -1
		for row: int in snap.unit_id.size():
			if snap.owner[row] == 1:
				if first < 0:
					first = snap.type_index[row]
				elif snap.type_index[row] != first:
					second = snap.type_index[row]
					break
		assert_bool(first >= 0 and second >= 0).is_true()
		snap.type_faction.fill(-1)
		snap.type_faction[second] = int(case[1])  # The first own row has none; the next names it.
		runner.snapshot = snap
		button.refresh(snap)
		await await_idle_frame()
		await await_idle_frame()
		var accent: StringName = case[0]
		assert_object(button.disc_color).override_failure_message(str(accent)).is_equal(
			button.get_theme_color(&"accent", accent)
		)


## No side to read: an id ACCENTS lacks, and no own row with a faction, both draw renew (a fresh
## button each), and a side seen before is dropped when a snapshot names none.
func test_an_unknown_id_or_no_own_faction_row_falls_back_to_renew() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	var main: Node = auto_free(await MatchRig.open(self))
	(main.get_node("MatchRunner") as MatchRunner).paused = true
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = main.get_node("MatchRunner").scenario
	var button: BuildButton = main.get_node("Hud/BuildButton")
	button.runner = runner
	var world: World = Sw.world()
	Sw.own(world, ["headquarters", "power_plant"])
	var renew: Color = button.get_theme_color(&"accent", &"AccentRenew")
	for case: String in ["unknown", "none", "dropped"]:
		var snap: MatchSnapshot = Sw.snapshot(world, 0)
		snap.faction_ids = _ids([&"martian"] if case == "unknown" else [&"fossil", &"renew"])
		if case == "unknown":
			snap.type_faction.fill(0)
		else:
			snap.type_faction.fill(-1)
		if case == "dropped":  # Fossil first, then a snapshot without a faction.
			var named: MatchSnapshot = Sw.snapshot(world, 0)
			named.faction_ids = _ids([&"fossil", &"renew"])
			named.type_faction.fill(0)
			runner.snapshot = named
			button.refresh(named)
			await await_idle_frame()
			assert_object(button.disc_color).is_not_equal(renew)
		runner.snapshot = snap
		button.refresh(snap)
		await await_idle_frame()
		await await_idle_frame()
		assert_object(button.disc_color).override_failure_message(case).is_equal(renew)


func _ids(ids: Array) -> Array[StringName]:
	var typed: Array[StringName] = []
	typed.assign(ids)
	return typed
