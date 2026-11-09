extends GdUnitTestSuite
## Seat probes of the AI's placement (plan row P195): `PlacementSpiral` walks its slots clockwise
## from the top-left whoever the player is, so the base in the top-left corner (player 1) fills its
## back first and the base in the bottom-right corner (player 2) fills its front first. These cases
## pin the asymmetry as measured; the fix that orients the spiral to the enemy moves them.

const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")

const SIDE: int = 64
const STRIDE: int = 4
const HQ_1: Vector2i = Vector2i(7, 7)
const HQ_2: Vector2i = Vector2i(54, 54)
const HQ_WIDE: int = 3
const PLANT_WIDE: int = 2


## The slot lattices are not half turns of each other: the Headquarters is 3 wide and a plant 2, so
## the half turn of player 2's slot for the cell (-x, -y) is one tile east and south of player 1's
## slot for (x, y). Pure arithmetic of `AiEconomy._place`.
func test_the_two_slot_lattices_are_one_tile_apart() -> void:
	var cells: PackedInt32Array = PlacementSpiral.cells(16)
	for at: int in 16:
		var cell: Vector2i = Vector2i(cells[at * 2], cells[at * 2 + 1])
		var first: Vector2i = HQ_1 + cell * STRIDE
		var second: Vector2i = HQ_2 - cell * STRIDE
		var turned: Vector2i = Vector2i(SIDE - second.x - PLANT_WIDE, SIDE - second.y - PLANT_WIDE)
		assert_object(turned - first).is_equal(Vector2i(HQ_WIDE - PLANT_WIDE, HQ_WIDE - PLANT_WIDE))


## The first three slots where a plant is placeable at the start: player 1's lie north and east of
## its Headquarters (away from the enemy in the south-east), player 2's north and north-west of its
## own (toward the enemy). Their mean squared distance to the enemy Headquarters' centre is 4725
## tiles squared for player 1 and 3979 for player 2.
func test_the_first_slots_of_player_2_stand_nearer_the_enemy_than_player_1s() -> void:
	var world: World = SmokeRun.world_of(1, SmokeRun.FOSSIL_MIRROR)
	var first: Array[Vector2i] = _first_slots(world, 1, 3)
	var second: Array[Vector2i] = _first_slots(world, 2, 3)
	assert_array(first).is_equal([Vector2i(7, 3), Vector2i(11, 3), Vector2i(11, 7)])
	assert_array(second).is_equal([Vector2i(50, 50), Vector2i(54, 50), Vector2i(58, 50)])
	assert_int(_gap(first, Vector2i(55, 55))).is_greater(_gap(second, Vector2i(8, 8)))


## The first plant of a real think of each Normal opponent (300 ticks): player 1 puts it 4 tiles
## north of its Headquarters (the back, at the map's top edge), player 2 4 tiles north of its own
## (the side that faces the enemy).
func test_the_first_plant_of_each_opponent_goes_north_of_its_base() -> void:
	var levels: Array[String] = ["normal", "normal"]
	var match_setup: Dictionary = SmokeRun.start(1, "fossil-mirror", levels)
	var world: World = match_setup["world"]
	SmokeRun.run(world, match_setup["loop"], match_setup["controllers"], 300)
	var plant: int = PlayerView.of(world, 1).type_index_of(&"power_plant")
	var sites: Dictionary[int, Vector2i] = {}
	for row: int in world.unit_count():
		if world.type_index[row] == plant:
			sites[world.owner[row]] = world.footprint_origin(row)
	assert_object(sites[1]).is_equal(Vector2i(7, 3))
	assert_object(sites[2]).is_equal(Vector2i(54, 50))


## The first `count` slots of `player`'s spiral where a plant can be placed now.
func _first_slots(world: World, player: int, count: int) -> Array[Vector2i]:
	var view: PlayerView = PlayerView.of(world, player)
	var plant: int = view.type_index_of(&"power_plant")
	var spiral: PackedInt32Array = PlacementSpiral.cells(64)
	var anchor: Vector2i = HQ_1 if player == 1 else HQ_2
	var found: Array[Vector2i] = []
	for at: int in 64:
		var slot: Vector2i = anchor + Vector2i(spiral[at * 2], spiral[at * 2 + 1]) * STRIDE
		if view.placement(plant, slot.x, slot.y) == Placement.Reason.OK:
			found.append(slot)
			if found.size() == count:
				break
	return found


## The mean squared distance, in tiles squared, of the slots' centres to `target`.
func _gap(slots: Array[Vector2i], target: Vector2i) -> int:
	var total: int = 0
	for slot: Vector2i in slots:
		var dx: int = slot.x + PLANT_WIDE / 2 - target.x
		var dy: int = slot.y + PLANT_WIDE / 2 - target.y
		total += dx * dx + dy * dy
	return total / slots.size()
