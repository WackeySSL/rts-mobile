extends GdUnitTestSuite
## PlayerView's state (plan row P78, ADR 0020 section 1): the player's credits, queues, power and
## rally points, the explored cells, the placement answer, the re-exported constants and the type
## tables. The base world of `production_worlds.gd` (revealed, two players, the shipped rules) and
## the crafted World of `view_worlds.gd` (real fog) are the maps; every expected number is derived
## from the World's own arrays and tables. The rows are in test_player_view_rows.gd.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const PlaceRig: GDScript = preload("res://tests/sim/support/place_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const ViewWorlds: GDScript = preload("res://tests/sim/support/view_worlds.gd")
const STRUCTURES: int = World.Tab.STRUCTURES
const INFANTRY: int = World.Tab.INFANTRY


## The power that `player`'s buildings make and use (positive numbers), scanned from the rows.
func _power(world: World, player: int) -> Vector2i:
	var made: int = 0
	var used: int = 0
	for row: int in world.unit_count():
		if world.owner[row] != player:
			continue
		var power: int = world.type_power[world.type_index[row]]
		made += maxi(power, 0)
		used += maxi(-power, 0)
	return Vector2i(made, used)


## Compares the view's `placement` with `Placement.reason` for every tile from one outside the map
## to one outside on the other side, for each of the types and players given, and returns the
## reasons that came up (a key for each).
func _compare_placements(world: World, players: Array[int], types: Array[int]) -> Dictionary:
	var found: Dictionary = {}
	for player: int in players:
		var view: PlayerView = PlayerView.of(world, player)
		var input: PlacementInput = PlacementInput.of_world(world)
		for type: int in types:
			for line: int in range(-1, world.map_rows + 1):
				for col: int in range(-1, world.map_cols + 1):
					var expected: int = Placement.reason(input, player, type, col, line)
					if view.placement(type, col, line) != expected:
						fail("player %d type %d tile (%d, %d)" % [player, type, col, line])
						return found
					if player == 1:
						found[expected] = true
	return found


func _placement_types(world: World) -> Array[int]:
	var types: Array[int] = []
	for id: String in ["headquarters", "power_plant", "refinery", "rifle_squad"]:
		types.append(Worlds.type_of(world, id))
	types.append_array([-1, world.type_ids.size() + 3])
	return types


func test_credits_are_the_players_own_account() -> void:
	var world: World = PlaceRig.world()
	assert_int(PlayerView.of(world, 1).credits).is_equal(world.start_credits)
	assert_int(PlayerView.of(world, 2).credits).is_equal(world.start_credits)
	Rig.step(world, [Rig.queue(world, 1, "power_plant")])
	assert_int(PlayerView.of(world, 1).credits).is_equal(
		world.start_credits - PlaceRig.cost(world, "power_plant")
	)
	assert_int(PlayerView.of(world, 2).credits).is_equal(world.start_credits)
	assert_int(PlayerView.of(world, 1).credits).is_equal(world.credits[1])


func test_the_queues_are_the_players_own_one_entry_per_tab() -> void:
	var world: World = PlaceRig.world()
	(
		Rig
		. step(
			world,
			[
				Rig.queue(world, 1, "power_plant", 0),
				Rig.queue(world, 1, "rifle_squad", 1),
				Rig.queue(world, 1, "rifle_squad", 2),
				Rig.queue(world, 2, "rifle_squad", 3),
			]
		)
	)
	Rig.run(world, 3)
	for player: int in [1, 2]:
		var view: PlayerView = PlayerView.of(world, player)
		assert_int(view.queue_slots).is_equal(world.queue_slots)
		assert_array([view.queue_count.size(), view.queue_progress.size()]).is_equal(
			[World.TABS, World.TABS]
		)
		assert_int(view.queue_type.size()).is_equal(World.TABS * world.queue_slots)
		assert_array([view.rally_x.size(), view.rally_y.size()]).is_equal([World.TABS, World.TABS])
		for tab: int in World.TABS:
			var queue: int = player * World.TABS + tab
			assert_int(view.queue_count[tab]).is_equal(world.queue_count[queue])
			assert_int(view.queue_progress[tab]).is_equal(world.queue_progress[queue])
			for slot: int in world.queue_slots:
				assert_int(view.queue_type[tab * world.queue_slots + slot]).is_equal(
					world.queue_type[queue * world.queue_slots + slot]
				)
	# What the cases above are made of: player 1 has one structure and two riflemen waiting,
	# player 2 one rifleman, and nobody has a vehicle.
	var first: PlayerView = PlayerView.of(world, 1)
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	assert_array(Array(first.queue_count)).is_equal([1, 2, 0])
	assert_int(first.queue_type[INFANTRY * world.queue_slots]).is_equal(rifle)
	assert_int(first.queue_type[INFANTRY * world.queue_slots + 2]).is_equal(-1)
	assert_array(Array(PlayerView.of(world, 2).queue_count)).is_equal([0, 1, 0])
	assert_int(first.queue_progress[STRUCTURES]).is_greater(0)


func test_a_structure_is_ready_when_a_place_can_take_it() -> void:
	var world: World = PlaceRig.world()
	var ticks: int = PlaceRig.build_ticks(world, "power_plant")
	assert_bool(PlayerView.of(world, 1).structure_ready()).is_false()
	Rig.step(world, [Rig.queue(world, 1, "power_plant")])
	Rig.run(world, ticks - 2)
	var rows: int = world.unit_count()
	# One step short: not ready, and the PLACE of this step is dropped.
	assert_bool(PlayerView.of(world, 1).structure_ready()).is_false()
	Rig.step(world, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	assert_array([world.dropped_commands, world.unit_count()]).is_equal([1, rows])
	# At its goal: ready, and the spot is a legal one, so the PLACE is applied.
	var view: PlayerView = PlayerView.of(world, 1)
	var plant: int = Worlds.type_of(world, "power_plant")
	assert_bool(view.structure_ready()).is_true()
	assert_int(view.placement(plant, PlaceRig.SPOT.x, PlaceRig.SPOT.y)).is_equal(
		Placement.Reason.OK
	)
	Rig.step(world, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	assert_array([world.dropped_commands, world.unit_count()]).is_equal([1, rows + 1])
	assert_bool(PlayerView.of(world, 1).structure_ready()).is_false()
	# A unit queue at its goal is not a structure waiting: the head of another tab does not count.
	assert_bool(PlayerView.of(world, 2).structure_ready()).is_false()


func test_power_totals_and_low_power_are_the_players_own() -> void:
	var world: World = PlaceRig.world()
	Rig.step(world)
	for player: int in [1, 2]:
		var view: PlayerView = PlayerView.of(world, player)
		var scanned: Vector2i = _power(world, player)
		assert_array([view.power_made, view.power_used]).is_equal([scanned.x, scanned.y])
		assert_array([view.power_made, view.power_used]).is_equal(
			[world.power_made[player], world.power_used[player]]
		)
		assert_bool(view.low_power).is_equal(Power.is_low(world, player))
	# Player 2's barracks uses power and nothing makes any; player 1 has plants.
	assert_bool(PlayerView.of(world, 2).low_power).is_true()
	assert_bool(PlayerView.of(world, 1).low_power).is_false()
	Rig.add_plant(world, 2, 12, 12)
	Rig.step(world)
	var second: PlayerView = PlayerView.of(world, 2)
	assert_bool(second.low_power).is_false()
	assert_int(second.power_made).is_greater(0)
	assert_int(second.power_made).is_equal(world.power_made[2])


func test_rally_points_are_the_players_own_per_tab() -> void:
	var world: World = PlaceRig.world()
	var queue: int = 1 * World.TABS + INFANTRY
	world.rally_x[queue] = 7500
	world.rally_y[queue] = 3500
	var view: PlayerView = PlayerView.of(world, 1)
	assert_array(Array(view.rally_x)).is_equal([-1, 7500, -1])
	assert_array(Array(view.rally_y)).is_equal([-1, 3500, -1])
	var second: PlayerView = PlayerView.of(world, 2)
	assert_array(Array(second.rally_x)).is_equal([-1, -1, -1])
	assert_array(Array(second.rally_y)).is_equal([-1, -1, -1])


func test_a_cell_is_explored_by_the_players_own_block() -> void:
	var world: World = ViewWorlds.crafted()
	var cells: int = world.map_cols * world.map_rows
	for player: int in [1, 2]:
		var view: PlayerView = PlayerView.of(world, player)
		var explored: int = 0
		for cell: int in cells:
			var expected: bool = world.fog.explored[(player - 1) * cells + cell] != 0
			assert_bool(view.is_explored(cell)).is_equal(expected)
			explored += 1 if expected else 0
		# Each player has explored something and not everything, and not the same cells.
		assert_bool(explored > 0 and explored < cells).is_true()
	var first: PlayerView = PlayerView.of(world, 1)
	var second: PlayerView = PlayerView.of(world, 2)
	var own_hq: int = 3 * world.map_cols + 3
	var far_hq: int = 10 * world.map_cols + 15
	assert_array([first.is_explored(own_hq), first.is_explored(far_hq)]).is_equal([true, false])
	assert_array([second.is_explored(own_hq), second.is_explored(far_hq)]).is_equal([false, true])


func test_a_cell_outside_the_map_is_never_explored_and_no_block_means_all() -> void:
	var world: World = ViewWorlds.crafted()
	var cells: int = world.map_cols * world.map_rows
	for player: int in [0, 1, 2, 3]:
		var view: PlayerView = PlayerView.of(world, player)
		for cell: int in [-1, -50, cells, cells + 1, 1 << 40]:
			assert_bool(view.is_explored(cell)).is_false()
	# The neutral player and one past the fog's players have hidden nothing from themselves.
	for player: int in [0, 3]:
		for cell: int in [0, 63, cells - 1]:
			assert_bool(PlayerView.of(world, player).is_explored(cell)).is_true()


func test_placement_is_placement_reason_for_the_player_on_every_tile() -> void:
	var world: World = ViewWorlds.crafted()
	var reasons: Dictionary = _compare_placements(world, [1, 2, 0], _placement_types(world))
	# The rows of the crafted World give every reason but TOO_FAR and CAP (below): a comparison
	# that never met a reason would pass for nothing.
	for reason: int in [
		Placement.Reason.OK,
		Placement.Reason.OUTSIDE,
		Placement.Reason.GROUND,
		Placement.Reason.OCCUPIED,
		Placement.Reason.UNEXPLORED,
	]:
		assert_bool(reasons.has(reason)).override_failure_message("reason %d" % reason).is_true()


func test_placement_too_far_and_cap_are_the_same_answers_too() -> void:
	var world: World = ViewWorlds.crafted()
	world.fog.explored.fill(1)
	var types: Array[int] = _placement_types(world)
	var far: Dictionary = _compare_placements(world, [1, 2], types)
	assert_bool(far.has(Placement.Reason.TOO_FAR)).is_true()
	assert_bool(far.has(Placement.Reason.UNEXPLORED)).is_false()
	# One building each, so a cap of 1 turns every reachable tile into CAP.
	world.building_cap = 1
	var capped: Dictionary = _compare_placements(world, [1, 2], types)
	assert_bool(capped.has(Placement.Reason.CAP)).is_true()
	assert_bool(capped.has(Placement.Reason.OK)).is_false()


func test_the_constants_are_the_worlds() -> void:
	assert_int(PlayerView.TABS).is_equal(World.TABS)
	assert_int(PlayerView.MILLI_PER_TILE).is_equal(World.MILLI_PER_TILE)
	assert_int(PlayerView.TILE_CENTRE).is_equal(World.TILE_CENTRE)
	assert_int(PlayerView.MISSING).is_equal(-1)
	assert_array(PlayerView.Tab.keys()).is_equal(World.Tab.keys())
	assert_array(PlayerView.Tab.values()).is_equal(World.Tab.values())
	assert_array(PlayerView.HarvestMode.keys()).is_equal(World.HarvestMode.keys())
	assert_array(PlayerView.HarvestMode.values()).is_equal(World.HarvestMode.values())
	assert_array(PlayerView.Order.keys()).is_equal(World.Order.keys())
	assert_array(PlayerView.Order.values()).is_equal(World.Order.values())
	assert_int(PlayerView.Tab.size()).is_equal(World.TABS)


func test_the_type_tables_are_the_worlds_and_a_write_stays_in_the_view() -> void:
	var world: World = PlaceRig.world()
	var view: PlayerView = PlayerView.of(world, 1)
	assert_array(Array(view.type_cost)).is_equal(Array(world.type_cost))
	assert_array(Array(view.type_tab)).is_equal(Array(world.type_tab))
	assert_array(Array(view.type_requires)).is_equal(Array(world.type_requires))
	assert_array(Array(view.type_produces)).is_equal(Array(world.type_produces))
	assert_array(Array(view.type_foot_w)).is_equal(Array(world.type_foot_w))
	assert_array(Array(view.type_foot_h)).is_equal(Array(world.type_foot_h))
	assert_array(Array(view.type_speed)).is_equal(Array(world.type_speed))
	assert_array(Array(view.type_weapon)).is_equal(Array(world.type_weapon))
	assert_array(Array(view.type_harvest)).is_equal(Array(world.type_harvest))
	assert_array(Array(view.type_power)).is_equal(Array(world.type_power))
	assert_array(Array(view.type_build_ticks)).is_equal(Array(world.type_build_ticks))
	# GDScript passes a packed array by reference, so a table that the view only aliased would be
	# the World's: this write must land in the view's own copy.
	var cost: int = world.type_cost[0]
	view.type_cost[0] = cost + 12345
	assert_int(world.type_cost[0]).is_equal(cost)
	assert_int(view.type_cost[0]).is_equal(cost + 12345)
	assert_int(PlayerView.of(world, 1).type_cost[0]).is_equal(cost)


## A caller can reach every public field, so none of them may be an array of the World's: writing
## into each leaves the state hash and the defs hash alone, and the write does land in the view.
func test_no_public_array_of_the_view_is_one_of_the_worlds() -> void:
	var world: World = PlaceRig.world()
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	var state: int = world.state_hash()
	var defs: int = world.defs_hash()
	var costs: PackedInt32Array = world.type_cost.duplicate()
	var view: PlayerView = PlayerView.of(world, 1)
	var touched: int = 0
	for property: Dictionary in view.get_property_list():
		var field: StringName = StringName(property["name"])
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or field.begins_with("_"):
			continue
		var value: Variant = view.get(field)
		if not value is PackedInt32Array:
			continue
		var table: PackedInt32Array = value
		for at: int in table.size():
			table[at] += 1000
		touched += 1
		if table.size() > 0:
			var changed: PackedInt32Array = view.get(field)
			assert_int(changed[0]).override_failure_message(String(field)).is_equal(table[0])
	# Two lists, five slices of the player's state and eleven type tables.
	assert_int(touched).is_equal(18)
	assert_int(world.state_hash()).is_equal(state)
	assert_int(world.defs_hash()).is_equal(defs)
	assert_array(Array(world.type_cost)).is_equal(Array(costs))


func test_type_ids_resolve_and_only_the_refinery_has_a_dock() -> void:
	var world: World = PlaceRig.world()
	var view: PlayerView = PlayerView.of(world, 1)
	for type: int in world.type_ids.size():
		assert_int(view.type_index_of(world.type_ids[type])).is_equal(type)
		var docked: bool = world.type_dock_x[type] != 0 or world.type_dock_y[type] != 0
		assert_bool(view.is_refinery(type)).is_equal(docked)
	assert_int(view.type_index_of(&"no_such_type")).is_equal(PlayerView.MISSING)
	assert_int(view.type_index_of(&"")).is_equal(PlayerView.MISSING)
	var refinery: int = Worlds.type_of(world, "refinery")
	assert_bool(view.is_refinery(refinery)).is_true()
	for id: String in ["power_plant", "barracks", "rifle_squad", "harvester"]:
		assert_bool(view.is_refinery(Worlds.type_of(world, id))).is_false()
	for type: int in [-1, world.type_ids.size(), 1 << 40]:
		assert_bool(view.is_refinery(type)).is_false()


func test_the_view_keeps_no_reference_to_the_world() -> void:
	var world: World = PlaceRig.world()
	var view: PlayerView = PlayerView.of(world, 1)
	var checked: int = 0
	for property: Dictionary in view.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var value: Variant = view.get(StringName(property["name"]))
		assert_bool(value is World or value is FogGrid or value is FlowCache).is_false()
		checked += 1
	assert_int(checked).is_greater(30)


func test_a_player_past_the_worlds_arrays_gets_empty_state_and_no_error() -> void:
	var world: World = PlaceRig.world()
	for player: int in [0, 3, 99]:
		var view: PlayerView = PlayerView.of(world, player)
		assert_array([view.credits, view.power_made, view.power_used]).is_equal([0, 0, 0])
		assert_bool(view.low_power).is_false()
		assert_bool(view.structure_ready()).is_false()
		(
			assert_array([view.queue_count.size(), view.queue_type.size(), view.rally_x.size()])
			. is_equal([0, 0, 0])
		)
		assert_int(view.queue_slots).is_equal(world.queue_slots)
