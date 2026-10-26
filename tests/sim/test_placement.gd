extends GdUnitTestSuite
## Placement.reason (plan row P71, ADR 0017 section 2): each Reason in a case built for it, in the
## stated order, the edges of each rule, and the guards for a hand-built World whose arrays are not
## all sized. The probe is the shipped 2x2 power plant on a 20 x 14 map: player 1 has a Headquarters
## (3x3) at (2, 2), player 2 one at (14, 9), `build_reach_tiles` is 4 and `building_cap` is 40.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const OK: int = Placement.Reason.OK
const OUTSIDE: int = Placement.Reason.OUTSIDE
const GROUND: int = Placement.Reason.GROUND
const OCCUPIED: int = Placement.Reason.OCCUPIED
const UNEXPLORED: int = Placement.Reason.UNEXPLORED
const TOO_FAR: int = Placement.Reason.TOO_FAR
const CAP: int = Placement.Reason.CAP
const COLS: int = 20
const ROWS: int = 14


## The map: rock at (8, 2), scrub at (8, 6), the rest grass.
func _world() -> World:
	var lines: PackedStringArray = GridWorld.grass(COLS, ROWS, [Vector2i(8, 2)])
	lines[6] = lines[6].left(8) + "^" + lines[6].substr(9)
	var world: World = Worlds.world(lines)
	world.build_reach_tiles = 4
	world.building_cap = 40
	world.add_building(1, Worlds.type_of(world, "headquarters"), 2, 2)
	world.add_building(2, Worlds.type_of(world, "headquarters"), 14, 9)
	return world


func _reason(world: World, player: int, id: String, col: int, line: int) -> int:
	var input: PlacementInput = PlacementInput.of_world(world)
	return Placement.reason(input, player, Worlds.type_of(world, id), col, line)


func _plant(world: World, col: int, line: int, player: int = 1) -> int:
	return _reason(world, player, "power_plant", col, line)


func _unexplore(world: World, player: int, col: int, line: int) -> void:
	world.fog.explored[(player - 1) * COLS * ROWS + line * COLS + col] = 0


## Adds a unit (a rifle squad unless `type` says otherwise) and returns its row.
func _unit_at(world: World, x: int, y: int, owner: int = 1, type: int = 0) -> int:
	world.add_unit(owner, type, x, y)
	return world.unit_count() - 1


func test_a_footprint_on_explored_free_ground_near_an_own_building_is_ok() -> void:
	var world: World = _world()
	assert_int(_plant(world, 6, 2)).is_equal(OK)
	assert_int(_reason(world, 1, "defence_turret", 6, 3)).is_equal(OK)
	assert_int(_reason(world, 1, "headquarters", 5, 5)).is_equal(OK)
	assert_int(_plant(world, 12, 9, 2)).is_equal(OK)


func test_a_cell_outside_the_map_or_a_type_with_no_footprint_is_outside() -> void:
	var world: World = _world()
	for origin: Vector2i in [Vector2i(-1, 2), Vector2i(2, -1), Vector2i(19, 2), Vector2i(2, 13)]:
		assert_int(_plant(world, origin.x, origin.y)).is_equal(OUTSIDE)
	assert_int(_reason(world, 1, "rifle_squad", 6, 2)).is_equal(OUTSIDE)
	var input: PlacementInput = PlacementInput.of_world(world)
	assert_int(Placement.reason(input, 1, -1, 6, 2)).is_equal(OUTSIDE)
	assert_int(Placement.reason(input, 1, 99, 6, 2)).is_equal(OUTSIDE)
	# The last column and row that fit are not outside (this one is too far, which comes later).
	assert_int(_plant(world, 18, 12, 2)).is_equal(OK)


func test_rock_scrub_and_another_building_are_ground() -> void:
	var world: World = _world()
	assert_int(_plant(world, 7, 2)).is_equal(GROUND)  # Rock at (8, 2), a corner of the footprint.
	assert_int(_plant(world, 8, 1)).is_equal(GROUND)  # The same rock, the other corner.
	assert_int(_plant(world, 8, 5)).is_equal(GROUND)  # Scrub: foot units cross it, none builds.
	assert_int(_plant(world, 4, 3)).is_equal(GROUND)  # One tile of the Headquarters.
	assert_int(_plant(world, 3, 4)).is_equal(GROUND)
	assert_int(_plant(world, 5, 4)).is_equal(OK)  # Beside it.
	# Buildable ground with a foot cost of 0 is ground too: the flag alone does not decide.
	var cells: int = COLS * ROWS
	world.move_cost[World.MoveClass.FOOT * cells + 3 * COLS + 6] = 0
	assert_int(_plant(world, 6, 2)).is_equal(GROUND)


@warning_ignore("integer_division")
func test_a_unit_whose_disc_touches_the_footprint_occupies_it() -> void:
	var world: World = _world()
	var radius: int = world.type_radius[0]
	var fifth: int = radius / 5
	# The footprint (6, 2) spans x 6000..8000 and y 2000..4000. The edge counts as touching.
	var row: int = _unit_at(world, 6000 - radius, 3000)
	assert_int(_plant(world, 6, 2)).is_equal(OCCUPIED)
	world.pos_x[row] -= 1
	assert_int(_plant(world, 6, 2)).is_equal(OK)
	world.pos_x[row] = 8000 + radius
	assert_int(_plant(world, 6, 2)).is_equal(OCCUPIED)
	world.pos_x[row] = 7000
	assert_int(_plant(world, 6, 2)).is_equal(OCCUPIED)  # Inside the footprint.
	# The corner: (3, 4, 5) times a fifth of the radius from the corner is on the disc.
	world.pos_x[row] = 6000 - 3 * fifth
	world.pos_y[row] = 2000 - 4 * fifth
	assert_int(_plant(world, 6, 2)).is_equal(OCCUPIED)
	world.pos_x[row] -= 1
	assert_int(_plant(world, 6, 2)).is_equal(OK)
	# An enemy unit occupies it too, and a unit does not occupy a footprint it stands far from.
	world.pos_x[row] = 7000
	world.pos_y[row] = 3000
	world.owner[row] = 2
	assert_int(_plant(world, 6, 2)).is_equal(OCCUPIED)
	assert_int(_plant(world, 9, 2)).is_equal(OK)


func test_a_cell_the_player_never_explored_is_unexplored_for_that_player_only() -> void:
	var world: World = _world()
	_unexplore(world, 1, 7, 3)
	assert_int(_plant(world, 6, 2)).is_equal(UNEXPLORED)
	assert_int(_plant(world, 6, 3)).is_equal(UNEXPLORED)
	assert_int(_plant(world, 5, 3)).is_equal(OK)  # The cell is not in this footprint.
	_unexplore(world, 2, 12, 10)
	assert_int(_plant(world, 12, 9, 2)).is_equal(UNEXPLORED)
	assert_int(_plant(world, 12, 9, 1)).is_equal(TOO_FAR)  # Player 1 explored it, and is far.


func test_a_footprint_farther_than_the_reach_from_every_own_building_is_too_far() -> void:
	var world: World = _world()
	# The Headquarters spans columns 2..4 and rows 2..4: the gap is the empty tiles between.
	assert_int(_plant(world, 5, 5)).is_equal(OK)  # Gap 0 on both axes.
	assert_int(_plant(world, 9, 2)).is_equal(OK)  # Gap 4 to the right.
	assert_int(_plant(world, 10, 2)).is_equal(TOO_FAR)  # Gap 5.
	assert_int(_plant(world, 2, 9)).is_equal(OK)  # Gap 4 down.
	assert_int(_plant(world, 2, 10)).is_equal(TOO_FAR)
	assert_int(_plant(world, 9, 9)).is_equal(OK)  # Chebyshev: both gaps 4.
	assert_int(_plant(world, 10, 3)).is_equal(TOO_FAR)  # One axis past the reach is enough.
	# Player 2's Headquarters spans columns 14..16 and rows 9..11: left and up.
	assert_int(_plant(world, 8, 9, 2)).is_equal(OK)
	assert_int(_plant(world, 7, 9, 2)).is_equal(TOO_FAR)
	assert_int(_plant(world, 14, 3, 2)).is_equal(OK)
	assert_int(_plant(world, 14, 2, 2)).is_equal(TOO_FAR)
	world.build_reach_tiles = 1
	assert_int(_plant(world, 2, 6)).is_equal(OK)  # Gap 1: "within" means at most the reach.
	assert_int(_plant(world, 2, 7)).is_equal(TOO_FAR)


func test_any_own_building_is_near_enough_and_an_enemy_one_is_not() -> void:
	var world: World = _world()
	assert_int(_plant(world, 15, 2)).is_equal(TOO_FAR)
	world.add_building(1, Worlds.type_of(world, "defence_turret"), 18, 2)
	assert_int(_plant(world, 15, 2)).is_equal(OK)  # Gap 1 to the turret, 10 to the Headquarters.
	assert_int(_plant(world, 12, 9, 1)).is_equal(TOO_FAR)  # Beside player 2's Headquarters.
	var none: World = Worlds.open(COLS, ROWS)
	assert_int(_plant(none, 0, 0)).is_equal(TOO_FAR)  # No building: far from every tile.
	assert_int(_plant(none, 9, 9, 2)).is_equal(TOO_FAR)


func test_a_player_with_the_cap_of_buildings_gets_cap_when_near_and_too_far_when_not() -> void:
	var world: World = _world()
	world.add_building(1, Worlds.type_of(world, "defence_turret"), 18, 2)
	world.building_cap = 3
	assert_int(_plant(world, 6, 2)).is_equal(OK)  # Two buildings of three.
	world.building_cap = 2
	assert_int(_plant(world, 6, 2)).is_equal(CAP)
	assert_int(_plant(world, 10, 10)).is_equal(TOO_FAR)  # The reach comes before the cap.
	assert_int(_plant(world, 12, 9, 2)).is_equal(OK)  # Player 2 has one building of two.
	world.building_cap = 1
	assert_int(_plant(world, 12, 9, 2)).is_equal(CAP)
	# Units are not buildings.
	world.building_cap = 3
	for _unit: int in 5:
		_unit_at(world, 1000, 8000)
	assert_int(_plant(world, 6, 2)).is_equal(OK)


func test_the_first_rule_that_fails_is_the_reason() -> void:
	var world: World = _world()
	world.building_cap = 1  # Player 1 is at the cap.
	_unexplore(world, 1, 7, 3)
	var row: int = _unit_at(world, 7000, 3000)
	assert_int(_plant(world, 19, 12)).is_equal(OUTSIDE)  # Also far, and out of the map.
	assert_int(_plant(world, 7, 2)).is_equal(GROUND)  # Also occupied, unexplored and capped.
	assert_int(_plant(world, 6, 2)).is_equal(OCCUPIED)  # Also unexplored and capped.
	world.pos_y[row] = 9000
	assert_int(_plant(world, 6, 2)).is_equal(UNEXPLORED)  # Also capped.
	assert_int(_plant(world, 10, 10)).is_equal(TOO_FAR)  # Far and capped.
	assert_int(_plant(world, 5, 5)).is_equal(CAP)
	world.building_cap = 2
	assert_int(_plant(world, 5, 5)).is_equal(OK)


func test_a_hand_built_world_with_a_grid_and_no_buildable_flags_does_not_index_past_them() -> void:
	var world: World = GridWorld.from_rows(
		["....", "....", "..^#", "...."], [World.MoveClass.FOOT, World.MoveClass.FOOT]
	)
	assert_int(world.terrain_buildable.size()).is_equal(1)  # prepare() sizes it for grass only.
	world.type_speed[1] = 0
	world.type_radius[1] = 0
	world.type_foot_w[1] = 2
	world.type_foot_h[1] = 2
	world.fog.explored.fill(1)
	world.add_building(1, 1, 0, 0)
	var input: PlacementInput = PlacementInput.of_world(world)
	assert_int(Placement.reason(input, 1, 1, 0, 2)).is_equal(OK)  # Grass: flagged by prepare().
	assert_int(Placement.reason(input, 1, 1, 1, 2)).is_equal(GROUND)  # Scrub, past the flags.
	assert_int(Placement.reason(input, 1, 1, 2, 1)).is_equal(GROUND)  # Scrub and rock.
	world.terrain_buildable = PackedByteArray()
	input = PlacementInput.of_world(world)
	assert_int(Placement.reason(input, 1, 1, 0, 2)).is_equal(GROUND)  # No flag for grass either.


func test_an_input_whose_arrays_are_short_is_refused_not_indexed() -> void:
	var world: World = _world()
	var input: PlacementInput = PlacementInput.of_world(world)
	input.move_cost = PackedByteArray()
	assert_int(Placement.reason(input, 1, Worlds.type_of(world, "power_plant"), 6, 2)).is_equal(
		GROUND
	)
	input = PlacementInput.of_world(world)
	input.terrain = PackedByteArray()
	assert_int(Placement.reason(input, 1, Worlds.type_of(world, "power_plant"), 6, 2)).is_equal(
		GROUND
	)
	input = PlacementInput.of_world(world)
	input.explored = PackedByteArray()
	assert_int(Placement.reason(input, 1, Worlds.type_of(world, "power_plant"), 6, 2)).is_equal(
		UNEXPLORED
	)
	# A fog whose block is not the map's, or a player it has no block for, has hidden nothing.
	input = PlacementInput.of_world(world)
	input.fog_cells = 7
	assert_int(Placement.reason(input, 1, Worlds.type_of(world, "power_plant"), 6, 2)).is_equal(OK)
	input = PlacementInput.of_world(world)
	input.fog_player_count = 0
	assert_int(Placement.reason(input, 1, Worlds.type_of(world, "power_plant"), 6, 2)).is_equal(OK)


func test_an_input_filled_from_copies_gives_the_same_reason_on_every_origin() -> void:
	var world: World = _world()
	world.add_building(1, Worlds.type_of(world, "defence_turret"), 18, 2)
	_unexplore(world, 1, 12, 6)
	_unit_at(world, 9300, 7100)
	_unit_at(world, 5000, 9000, 2)
	var live: PlacementInput = PlacementInput.of_world(world)
	var copy: PlacementInput = PlacementInput.new()  # What the view fills from its snapshot.
	for name: String in ["terrain", "terrain_buildable", "move_cost", "explored", "owner"]:
		copy.set(name, live.get(name).duplicate())
	for name: String in ["type_index", "pos_x", "pos_y", "type_speed", "type_radius"]:
		copy.set(name, live.get(name).duplicate())
	for name: String in ["type_foot_w", "type_foot_h"]:
		copy.set(name, live.get(name).duplicate())
	for name: String in ["map_cols", "map_rows", "fog_cells", "fog_player_count"]:
		copy.set(name, live.get(name))
	copy.build_reach_tiles = live.build_reach_tiles
	copy.building_cap = live.building_cap
	var hash_before: int = world.state_hash()
	var seen: Dictionary[int, int] = {}
	for id: String in ["power_plant", "defence_turret", "headquarters", "rifle_squad"]:
		var type: int = Worlds.type_of(world, id)
		for player: int in [1, 2]:
			for line: int in range(-1, ROWS + 1):
				for col: int in range(-1, COLS + 1):
					var want: int = Placement.reason(live, player, type, col, line)
					assert_int(Placement.reason(copy, player, type, col, line)).is_equal(want)
					seen[want] = seen.get(want, 0) + 1
	assert_int(world.state_hash()).is_equal(hash_before)
	for reason: int in [OK, OUTSIDE, GROUND, OCCUPIED, UNEXPLORED, TOO_FAR]:
		assert_bool(seen.has(reason)).override_failure_message("never %d" % reason).is_true()


func test_of_world_holds_the_worlds_own_arrays_and_rule_ints() -> void:
	var world: World = _world()
	world.build_reach_tiles = 3
	world.building_cap = 9
	var input: PlacementInput = PlacementInput.of_world(world)
	assert_int(input.map_cols).is_equal(COLS)
	assert_int(input.map_rows).is_equal(ROWS)
	assert_int(input.build_reach_tiles).is_equal(3)
	assert_int(input.building_cap).is_equal(9)
	assert_int(input.fog_cells).is_equal(COLS * ROWS)
	assert_int(input.fog_player_count).is_equal(2)
	assert_array(input.owner).is_equal(world.owner)
	assert_array(input.pos_x).is_equal(world.pos_x)
	assert_array(input.type_foot_w).is_equal(world.type_foot_w)
	assert_array(input.terrain_buildable).is_equal(world.terrain_buildable)
	assert_array(input.move_cost).is_equal(world.move_cost)
	assert_array(input.explored).is_equal(world.fog.explored)
