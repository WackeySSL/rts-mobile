extends GdUnitTestSuite
## The AI's base layout (plan row P195b, the seat bias of the first balance run): a refinery goes
## on the valid slot nearest the nearest ore cell, and the slot spiral is turned by the direction
## to the enemy base estimate, so a base fills its back first and two mirrored bases are half turns
## of each other. The fog is opened in every case: the start-area explored rule is the sim's
## (P195c), not the AI's.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")

const SIDE: int = 64
const HQ_WIDE: int = 3
const STRIDE: int = 4
const HQ_1: Vector2i = Vector2i(7, 7)
const HQ_2: Vector2i = Vector2i(54, 54)


func test_a_refinery_goes_on_the_valid_slot_nearest_the_nearest_ore_cell() -> void:
	var world: World = _flats()
	var view: PlayerView = PlayerView.of(world, 1)
	var refinery: int = view.type_index_of(&"refinery")
	var wide: int = view.type_foot_w[refinery]
	var ore: Vector2i = _nearest_ore(world, HQ_1)
	var best: Vector2i = Vector2i(-1, -1)
	var least: int = 1 << 40
	var first_valid: Vector2i = Vector2i(-1, -1)
	var cells: PackedInt32Array = PlacementSpiral.cells(Rig.def_of("fossil").spiral_slots)
	for slot: int in cells.size() / 2:
		var tile: Vector2i = HQ_1 + Vector2i(cells[slot * 2], cells[slot * 2 + 1]) * STRIDE
		if view.placement(refinery, tile.x, tile.y) != Placement.Reason.OK:
			continue
		if first_valid.x < 0:
			first_valid = tile
		var dx: int = tile.x * 2 + wide - (ore.x * 2 + 1)
		var dy: int = tile.y * 2 + wide - (ore.y * 2 + 1)
		if dx * dx + dy * dy < least:
			least = dx * dx + dy * dy
			best = tile
	var placed: Vector2i = _place(world, 1, "refinery")
	assert_object(placed).is_equal(best)
	# Not the first free slot of the spiral, which the AI took before this row.
	assert_object(placed).is_not_equal(first_valid)


func test_the_first_three_buildings_of_two_mirrored_ais_are_half_turns() -> void:
	var world: World = _flats()
	var first: Array[Vector2i] = []
	var second: Array[Vector2i] = []
	for id: String in ["power_plant", "refinery"]:
		first.append(_place(world, 1, id))
		second.append(_place(world, 2, id))
		var wide: int = PlayerView.of(world, 1).type_foot_w[AiRig.type_of(world, id)]
		var turned: Vector2i = Vector2i(SIDE - first[-1].x - wide, SIDE - first[-1].y - wide)
		assert_object(second[-1]).override_failure_message(id).is_equal(turned)
	# The Headquarters themselves are half turns (the scenario), and the ore is what moved the
	# refinery off the first slot: the two plants stand apart from the refineries.
	assert_object(HQ_2).is_equal(Vector2i(SIDE - HQ_1.x - HQ_WIDE, SIDE - HQ_1.y - HQ_WIDE))
	assert_object(first[0]).is_not_equal(first[1])


func test_the_walk_turns_away_from_the_enemy_estimate() -> void:
	# The estimate in each direction from player 1's Headquarters at (7, 7): the first plant lies on
	# the side away from it, in both axes (the spiral's first cell is a corner of ring 1).
	for enemy: Vector2i in [Vector2i(55, 55), Vector2i(2, 55), Vector2i(2, 2), Vector2i(55, 2)]:
		var world: World = _flats()
		var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
		memory.base_x = enemy.x
		memory.base_y = enemy.y
		var plant: Vector2i = _place(world, 1, "power_plant", memory)
		var away: Vector2i = Vector2i(signi(HQ_1.x - enemy.x), signi(HQ_1.y - enemy.y))
		var at: Vector2i = Vector2i(signi(plant.x - HQ_1.x), signi(plant.y - HQ_1.y))
		assert_object(at).override_failure_message(str(enemy)).is_equal(away)
	# North-west of the base the walk is the half turn of the south-east one (the Headquarters is 3
	# wide, a plant 2): the same slots, turned about the Headquarters' centre.
	var west: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	west.base_x = 2
	west.base_y = 2
	var turned: Vector2i = _place(_flats(), 1, "power_plant", west)
	var east: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	east.base_x = 55
	east.base_y = 55
	var plain: Vector2i = _place(_flats(), 1, "power_plant", east)
	assert_object(plain).is_equal(Vector2i(3, 3))
	assert_object(turned).is_equal(
		Vector2i(HQ_1.x * 2 + HQ_WIDE - plain.x - 2, HQ_1.y * 2 + HQ_WIDE - plain.y - 2)
	)


func test_without_an_estimate_the_enemy_is_where_the_point_mirror_of_the_base_lies() -> void:
	var world: World = _flats()
	var none: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	var known: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	known.base_x = 56
	known.base_y = 56
	assert_object(_place(world, 1, "power_plant", none)).is_equal(
		_place(_flats(), 1, "power_plant", known)
	)


func test_the_layout_does_not_depend_on_the_player_number() -> void:
	# Swap the seats: player 2 owns the top-left base. The offsets of its first buildings from its
	# own Headquarters are the ones player 1 had there, and player 1's at the far corner are those
	# player 2 had.
	var base: World = _flats()
	var swapped: World = _flats()
	for row: int in swapped.unit_count():
		swapped.owner[row] = 3 - swapped.owner[row]
	AiRig.explore_all(swapped)
	for id: String in ["power_plant", "refinery"]:
		var top: Vector2i = _place(base, 1, id) - HQ_1
		var top_swapped: Vector2i = _place(swapped, 2, id) - HQ_1
		assert_object(top_swapped).override_failure_message(id).is_equal(top)
		var bottom: Vector2i = _place(base, 2, id) - HQ_2
		var bottom_swapped: Vector2i = _place(swapped, 1, id) - HQ_2
		assert_object(bottom_swapped).override_failure_message(id).is_equal(bottom)


func test_the_view_and_the_order_do_not_change_after_the_first_place() -> void:
	# The turn is found once: a later sighting of the enemy does not turn the base round.
	var world: World = _flats()
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1)
	var first: Vector2i = _place_with(economy, world, 1, "power_plant", memory)
	memory.base_x = 2
	memory.base_y = 2
	var second: Vector2i = _place_with(economy, _flats(), 1, "power_plant", memory)
	assert_object(second).is_equal(first)


# --- Helpers ---------------------------------------------------------------------------------


## The fossil mirror of Kestrel Flats with the fog open.
func _flats() -> World:
	var world: World = SmokeRun.world_of(1, SmokeRun.FOSSIL_MIRROR)
	AiRig.explore_all(world)
	return world


## The tile of the ore cell nearest the centre of the Headquarters at `hq`, the lower cell first.
func _nearest_ore(world: World, hq: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var least: int = 1 << 40
	for cell: int in world.ore_cell:
		var tile: Vector2i = Vector2i(cell % world.map_cols, cell / world.map_cols)
		var dx: int = tile.x * 2 + 1 - (hq.x * 2 + HQ_WIDE)
		var dy: int = tile.y * 2 + 1 - (hq.y * 2 + HQ_WIDE)
		if dx * dx + dy * dy < least:
			least = dx * dx + dy * dy
			best = tile
	return best


## The top-left tile `player`'s economy puts a `id` building on (a fresh economy of the Normal
## level), which then stands in `world`.
func _place(world: World, player: int, id: String, memory: AiMemory = null) -> Vector2i:
	var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), Rig.level_of("normal"), player)
	return _place_with(economy, world, player, id, memory)


func _place_with(
	economy: AiEconomy, world: World, player: int, id: String, memory: AiMemory = null
) -> Vector2i:
	var type: int = AiRig.type_of(world, id)
	var queue: int = player * World.TABS + World.Tab.STRUCTURES
	world.queue_type[queue * world.queue_slots] = type
	world.queue_count[queue] = 1
	world.queue_progress[queue] = world.type_build_ticks[type] * Production.PROGRESS_PER_TICK
	var mind: AiMemory = memory if memory != null else AiMemory.create(Rig.def_of("fossil"))
	var found: Array[Command] = []
	for _think: int in 12:
		mind.commands_left = 99
		var out: Array[Command] = []
		economy.run(
			PlayerView.of(world, player), mind, DetRandom.create(1, DetRandom.STREAM_AI_BASE), out
		)
		for command: Command in out:
			if command.type == Command.Type.PLACE:
				found.append(command)
		if not found.is_empty():
			break
	assert_int(found.size()).is_equal(1)
	var tile: Vector2i = Vector2i(
		found[0].target_x / PlayerView.MILLI_PER_TILE, found[0].target_y / PlayerView.MILLI_PER_TILE
	)
	world.queue_count[queue] = 0
	world.add_building(player, type, tile.x, tile.y)
	return tile
