extends GdUnitTestSuite
## The build sidebar's item tiles (plan P85b, ADR 0019 section 1) read from snapshots of a real
## World with the shipped tables: which tiles the open tab shows and in what order, each tile's icon
## by name and its cost, and the five states (available, locked, unaffordable, full, ready) with the
## shape each one shows, the count badge and the head's fill. The match is paused, so only the
## snapshots a test publishes are on show. What a finger does to a tile is in
## test_build_sidebar_orders, the layout at the sizes in test_build_sidebar_items_layout.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const ICONS: String = "res://assets/art/svg/icons/%s.svg"
const AVAILABLE: int = ItemTile.State.AVAILABLE
const LOCKED: int = ItemTile.State.LOCKED
const UNAFFORDABLE: int = ItemTile.State.UNAFFORDABLE
const FULL: int = ItemTile.State.FULL
const READY: int = ItemTile.State.READY
const STRUCTURES: Array[String] = [
	"power_plant", "barracks", "refinery", "vehicle_factory", "defence_turret"
]
const INFANTRY: Array[String] = ["rifle_squad", "rocket_squad"]
const VEHICLES: Array[String] = ["light_tank", "heavy_tank", "harvester", "artillery"]
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


func test_the_open_tab_shows_its_types_in_table_order_with_the_icon_by_name_and_the_cost() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, BASE)
	_publish(world)
	assert_array(_shown()).is_equal(STRUCTURES)
	for id: String in STRUCTURES + INFANTRY + VEHICLES:
		var tile: ItemTile = _tile(id)
		var icon: TextureRect = tile.find_child("Icon", false, false)
		assert_str(icon.texture.resource_path).is_equal(ICONS % ("item_" + id))
		var cost: int = world.type_cost[Sw.type_of(world, id)]
		assert_str((tile.find_child("Cost", false, false) as Label).text).is_equal(str(cost))
		assert_int(tile.tab).is_equal(world.type_tab[Sw.type_of(world, id)])
	assert_array(_all_ids()).is_not_empty()
	assert_array(_all_ids()).not_contains(["headquarters"])  # Not buildable: no tile.
	_sidebar.select_tab(World.Tab.INFANTRY)
	assert_array(_shown()).is_equal(INFANTRY)
	_sidebar.select_tab(World.Tab.VEHICLES)
	assert_array(_shown()).is_equal(VEHICLES)
	assert_array(_sent).is_empty()


func test_a_tile_is_locked_by_a_missing_requirement_or_a_missing_producer() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, ["headquarters"])  # The plant is the only structure with a requirement met.
	_publish(world)
	assert_array(_states(STRUCTURES)).is_equal([AVAILABLE, LOCKED, LOCKED, LOCKED, LOCKED])
	assert_array(_states(INFANTRY)).is_equal([LOCKED, LOCKED])  # No barracks.
	assert_array(_states(VEHICLES)).is_equal([LOCKED, LOCKED, LOCKED, LOCKED])  # No factory.
	world = Sw.world()
	Sw.own(world, ["power_plant", "barracks", "refinery"])  # Every requirement, but no Headquarters.
	_publish(world)
	assert_array(_states(STRUCTURES)).is_equal([LOCKED, LOCKED, LOCKED, LOCKED, LOCKED])
	assert_array(_states(INFANTRY)).is_equal([AVAILABLE, AVAILABLE])
	world = Sw.world()
	Sw.own(world, BASE)
	_publish(world)
	assert_array(_states(STRUCTURES)).is_equal(
		[AVAILABLE, AVAILABLE, AVAILABLE, AVAILABLE, AVAILABLE]
	)
	assert_array(_states(VEHICLES)).is_equal([AVAILABLE, AVAILABLE, AVAILABLE, AVAILABLE])
	world = Sw.world()
	Sw.own(world, BASE)
	Sw.own(world, ["headquarters", "barracks"], 2)  # The enemy's rows are nobody's producers here.
	world.owner[world.index_of(2)] = 2  # The power plant is the enemy's: the requirement is gone.
	_publish(world)
	assert_int(_state("barracks")).is_equal(LOCKED)
	assert_int(_state("rifle_squad")).is_equal(AVAILABLE)  # The own barracks still stands.


func test_a_tile_the_bank_cannot_pay_is_unaffordable_and_exactly_enough_is_available() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, BASE)
	world.credits[1] = 250
	_publish(world)
	assert_int(_state("power_plant")).is_equal(UNAFFORDABLE)  # 300.
	assert_int(_state("rifle_squad")).is_equal(AVAILABLE)  # 100.
	assert_int(_state("rocket_squad")).is_equal(UNAFFORDABLE)  # 300.
	world.credits[1] = 300
	_publish(world)
	assert_int(_state("power_plant")).is_equal(AVAILABLE)
	assert_int(_state("rocket_squad")).is_equal(AVAILABLE)
	assert_int(_state("barracks")).is_equal(UNAFFORDABLE)  # 400.
	world.credits[2] = 99999  # The other player's bank is not the local player's.
	world.credits[1] = 0
	_publish(world)
	assert_int(_state("rifle_squad")).is_equal(UNAFFORDABLE)


func test_a_full_queue_shows_the_stripes_and_only_five_items_fill_it() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(
		world, World.Tab.INFANTRY, ["rifle_squad", "rifle_squad", "rocket_squad", "rifle_squad"]
	)
	_publish(world)
	assert_int(_state("rifle_squad")).is_equal(AVAILABLE)  # Four of the five slots.
	Sw.enqueue(
		world,
		World.Tab.INFANTRY,
		["rifle_squad", "rifle_squad", "rocket_squad", "rifle_squad", "rifle_squad"]
	)
	_publish(world)
	assert_array(_states(INFANTRY)).is_equal([FULL, FULL])
	assert_int(_tile("rifle_squad").queued).is_equal(4)
	assert_int(_tile("rocket_squad").queued).is_equal(1)
	assert_int(_state("light_tank")).is_equal(AVAILABLE)  # Another tab's queue.
	world.credits[1] = 50  # Money is the louder reason.
	_publish(world)
	assert_array(_states(INFANTRY)).is_equal([UNAFFORDABLE, UNAFFORDABLE])
	world = Sw.world()  # And a lock louder than money.
	Sw.own(world, ["headquarters"])
	world.credits[1] = 0
	_publish(world)
	assert_int(_state("refinery")).is_equal(LOCKED)


## Only a finished structure at the head is ready: a unit waiting at 100 % to spawn is not, a
## structure behind the head is not, and a structure that is ready stays so when its requirement is
## gone (the PLACE needs the ready head only).
func test_a_structure_finished_at_the_head_of_its_queue_is_ready() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var done: int = (
		world.type_build_ticks[Sw.type_of(world, "power_plant")] * Production.PROGRESS_PER_TICK
	)
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant", "barracks"], done - 1)
	_publish(world)
	assert_int(_state("power_plant")).is_equal(AVAILABLE)
	assert_float(_tile("power_plant").progress).is_less(1.0)
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant", "barracks"], done)
	_publish(world)
	assert_int(_state("power_plant")).is_equal(READY)
	assert_int(_state("barracks")).is_equal(AVAILABLE)  # Behind the head: queued, not ready.
	assert_int(_tile("barracks").queued).is_equal(1)
	assert_float(_tile("barracks").progress).is_equal(0.0)
	var rifle_done: int = (
		world.type_build_ticks[Sw.type_of(world, "rifle_squad")] * Production.PROGRESS_PER_TICK
	)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], rifle_done)
	_publish(world)
	assert_int(_state("rifle_squad")).is_equal(AVAILABLE)  # Units never show ready.
	world = Sw.world()
	Sw.own(world, ["barracks"])  # No Headquarters, no plant: the queue's head still stands ready.
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], done)
	_publish(world)
	assert_int(_state("power_plant")).is_equal(READY)
	assert_int(_state("refinery")).is_equal(LOCKED)


## Every state is a shape: a padlock, stripes, a banner; a count and a fill are shapes too. The
## colour only adds: the cost turns amber for money, the icon dims behind the lock.
func test_each_state_shows_its_own_shape() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, ["headquarters", "power_plant", "barracks"])
	world.credits[1] = 350
	var plant: int = Sw.type_of(world, "power_plant")
	var done: int = world.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], done)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"] + _times("rifle_squad", 4), 3750)
	_publish(world)
	# [padlock, stripes, banner, badge, fill] per tile.
	var looks: Dictionary[String, Array] = {
		"power_plant": [false, false, true, true, false],  # Ready.
		"vehicle_factory": [true, false, false, false, false],  # Locked: no refinery.
		"barracks": [false, true, false, false, false],  # Unaffordable: 400 of 350.
		"rifle_squad": [false, true, false, true, true],  # Full, its head half built.
		"rocket_squad": [false, true, false, false, false],  # Full: no room for it either.
		"light_tank": [true, false, false, false, false],  # Locked: no factory.
	}
	for id: String in looks:
		var got: Array = [
			_part(id, "Lock").visible,
			_part(id, "Stripes").visible,
			_part(id, "Banner").visible,
			_part(id, "Badge").visible,
			_part(id, "Fill").visible,
		]
		assert_array(got).override_failure_message(id).is_equal(looks[id])
	assert_str(str(_part("barracks", "Cost").theme_type_variation)).is_equal("ItemCostLow")
	assert_str(str(_part("rifle_squad", "Cost").theme_type_variation)).is_equal("ItemCost")
	assert_float((_part("vehicle_factory", "Icon") as TextureRect).modulate.a).is_less(0.5)
	assert_float((_part("barracks", "Icon") as TextureRect).modulate.a).is_equal(1.0)
	world = Sw.world()
	Sw.own(world, BASE)
	_publish(world)
	for id: String in STRUCTURES + INFANTRY + VEHICLES:  # Available: bare but for the cost.
		for part: String in ["Lock", "Stripes", "Banner", "Badge", "Fill"]:
			assert_bool(_part(id, part).visible).override_failure_message(id + part).is_false()


func test_the_count_badge_and_the_fill_follow_the_queue() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var half: int = (
		world.type_build_ticks[Sw.type_of(world, "light_tank")] * Production.PROGRESS_PER_TICK / 4
	)
	Sw.enqueue(world, World.Tab.VEHICLES, ["light_tank", "harvester", "light_tank"], half)
	_publish(world)
	assert_int(_tile("light_tank").queued).is_equal(2)
	assert_str((_part("light_tank", "Badge") as Label).text).is_equal("2")
	assert_int(_tile("harvester").queued).is_equal(1)
	assert_int(_tile("heavy_tank").queued).is_equal(0)
	assert_float(_tile("light_tank").progress).is_equal_approx(0.25, 0.001)
	assert_float((_part("light_tank", "Fill") as Control).anchor_top).is_equal_approx(0.75, 0.001)
	assert_float(_tile("harvester").progress).is_equal(0.0)  # Only the head's tile fills.
	assert_bool(_part("harvester", "Fill").visible).is_false()
	world.queue_progress[World.TABS + World.Tab.VEHICLES] = 10 * half  # Past the goal: still a share.
	_publish(world)
	assert_float(_tile("light_tank").progress).is_equal(1.0)
	assert_int(_state("light_tank")).is_equal(AVAILABLE)  # Ready is for structures.
	Sw.enqueue(world, World.Tab.VEHICLES, [])
	_publish(world)
	assert_array([_tile("light_tank").queued, _tile("light_tank").progress]).is_equal([0, 0.0])
	assert_bool(_part("light_tank", "Badge").visible).is_false()


## The tiles belong to a match: a new one makes them again from its own tables, and one match's
## snapshots, tick after tick, keep the same nodes.
func test_a_new_match_makes_the_tiles_again_and_a_new_tick_keeps_them() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, BASE)
	_publish(world, 7)
	var first: ItemTile = _tile("power_plant")
	world.credits[1] = 10
	_publish(world, 7)
	assert_object(_tile("power_plant")).is_same(first)
	assert_int(first.state).is_equal(UNAFFORDABLE)
	_publish(world, 8)
	assert_object(_tile("power_plant")).is_not_same(first)
	assert_int(_state("power_plant")).is_equal(UNAFFORDABLE)
	await await_idle_frame()
	assert_bool(is_instance_valid(first) and first.is_inside_tree()).is_false()
	assert_array(_all_ids()).has_size(STRUCTURES.size() + INFANTRY.size() + VEHICLES.size())


## Another player's rows, bank and queue are not the local player's.
func test_the_local_players_rows_queue_and_bank_are_the_ones_shown() -> void:
	await _open()
	var world: World = Sw.world()
	Sw.own(world, ["headquarters"], 2)
	Sw.own(world, ["headquarters", "barracks"], 1)
	var queue: int = 2 * World.TABS + World.Tab.INFANTRY  # Player 2's queue.
	world.queue_type[queue * world.queue_slots] = Sw.type_of(world, "rifle_squad")
	world.queue_count[queue] = 1
	_publish(world)
	assert_int(_tile("rifle_squad").queued).is_equal(0)
	var other: ScenarioDef = _runner.scenario.duplicate() as ScenarioDef  # The file stays as it is.
	other.local_player = 2
	_runner.scenario = other
	_publish(world)
	assert_int(_tile("rifle_squad").queued).is_equal(1)
	assert_int(_state("rifle_squad")).is_equal(LOCKED)  # Player 2 has no barracks.
	assert_int(_state("power_plant")).is_equal(AVAILABLE)


## `id` repeated `count` times.
func _times(id: String, count: int) -> Array[String]:
	var ids: Array[String] = []
	ids.resize(count)
	ids.fill(id)
	return ids


func _grid() -> GridContainer:
	return _sidebar.find_children("*", "GridContainer", true, false)[0]


func _all_ids() -> Array[String]:
	var ids: Array[String] = []
	for node: Node in _grid().get_children():
		ids.append(node.name.trim_prefix("Tile_"))
	return ids


## The ids of the visible tiles, in the grid's order.
func _shown() -> Array[String]:
	var ids: Array[String] = []
	for node: Node in _grid().get_children():
		if (node as Control).visible:
			ids.append(node.name.trim_prefix("Tile_"))
	return ids


func _tile(id: String) -> ItemTile:
	return _sidebar.find_child("Tile_" + id, true, false) as ItemTile


func _part(id: String, part: String) -> Control:
	return _tile(id).find_child(part, false, false) as Control


func _state(id: String) -> int:
	return _tile(id).state


func _states(ids: Array[String]) -> Array[int]:
	var states: Array[int] = []
	for id: String in ids:
		states.append(_state(id))
	return states


## Publishes the world's snapshot as the match's latest and reads it at once.
func _publish(world: World, serial: int = 0) -> void:
	_runner.snapshot = Sw.snapshot(world, serial)
	_sidebar.refresh()


## A new main scene on the 6-inch phone, its match paused, with the Commands caught.
func _open() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	# The sidebar reads a runner of its own: the map's layers have no art for a building before P84.
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _main.get_node("MatchRunner").scenario
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_sidebar.runner = _runner
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = (func(
		command: Command
	) -> void:
		_sent.append(command))
