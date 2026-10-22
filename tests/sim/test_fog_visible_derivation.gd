extends GdUnitTestSuite
## fog.visible is derived state, so it is not in the state hash (plan P65, ADR 0016, STATE_FORMAT
## 2): its counts are rebuilt from the rows, which are hashed. The seed-42 perf arena runs 900 ticks
## through MatchLoop under each implementation of the simulation (the GDScript twins, then the C++
## kernels through SimImpls), and at each of its 60 checkpoints (every Replay.CHECKPOINT_PERIOD
## ticks) the counts rebuilt from owner, type_index and fog_cell and the sight of the type
## (tests/sim/support/fog_derivation.gd, written from the definition of a sight disc) equal
## fog.visible. The crafted cases of the FOG lockstep (tests/sim/native/test_fog_lockstep_cases.gd)
## run the same check after every tick. The cases below pin the rebuild itself, with literal
## counts, and show that it fails when the counts and the rows part ways, so a green run is not one
## whose check looks at nothing.

const Derivation: GDScript = preload("res://tests/sim/support/fog_derivation.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const TICKS: int = 900
const SEED: int = 42
## The checkpoints of the run: ticks 15, 30 ... 900.
const CHECKPOINTS: int = 60


## The arena, at each checkpoint of a 900-tick run and in either implementation: visible equals
## what the rows say. The run reaches overlaps (a cell seen by several rows), discs clipped at the
## map's edge and deaths (a row's disc taken out), so the rebuild is not the trivial one.
func test_visible_equals_the_counts_rebuilt_from_the_rows_at_every_checkpoint(
	impl: int, _test_parameters := _both()
) -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, world)
	assert_array(SimImpls.use(world, impl)).is_empty()
	assert_bool(SimImpls.is_native(world, SimProbe.Phase.FOG)).is_equal(
		impl == SimImpls.Impl.NATIVE
	)
	assert_str(Derivation.mismatch(world)).is_empty()
	var wrong: Array[String] = []
	var checked: int = 0
	var most_seen: int = 0
	var rows_at_start: int = world.unit_count()
	var rows_least: int = rows_at_start
	var queued: Array[Command] = []
	for _tick: int in TICKS:
		loop.step(world, queued)
		if world.tick % Replay.CHECKPOINT_PERIOD != 0:
			continue
		checked += 1
		rows_least = mini(rows_least, world.unit_count())
		for count: int in world.fog.visible:
			most_seen = maxi(most_seen, count)
		var found: String = Derivation.mismatch(world)
		if found != "":
			wrong.append("tick %d: %s" % [world.tick, found])
	assert_int(checked).is_equal(CHECKPOINTS)
	assert_array(wrong).is_empty()
	# Units died during the run, and cells were seen by several rows at once.
	assert_int(rows_least).is_less(rows_at_start)
	assert_int(most_seen).is_greater(1)


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## One unit of sight 2000 on the middle tile of a 7 x 7 map sees the 13 tiles with dx^2 + dy^2 <= 4
## (a plus-shaped disc of radius 2), once each, in its player's block alone; the other player's
## block is 0. Two units of another sight (2500: 21 tiles) and a type with no sight entry (one
## tile) add up.
func test_the_rebuild_counts_the_tiles_within_the_sight_of_each_row() -> void:
	var middle: int = Worlds.centre(3)
	var world: World = Worlds.field(7, 7, 2, [2000, 2500], [[1, 0, middle, middle]])
	var counts: PackedInt32Array = Derivation.rebuild(world)
	assert_array(counts).is_equal(world.fog.visible)
	assert_int(counts.size()).is_equal(98)
	assert_int(_sum(counts, 0, 49)).is_equal(13)
	assert_int(_sum(counts, 49, 98)).is_equal(0)
	assert_int(counts[3 * 7 + 3]).is_equal(1)
	assert_int(counts[3 * 7 + 5]).is_equal(1)
	assert_int(counts[3 * 7 + 6]).is_equal(0)
	assert_int(counts[1 * 7 + 1]).is_equal(0)
	var units: Array = [[1, 0, middle, middle], [1, 1, middle, middle], [2, 4, middle, middle]]
	var crowd: World = Worlds.field(7, 7, 2, [2000, 2500], units)
	var crowded: PackedInt32Array = Derivation.rebuild(crowd)
	assert_array(crowded).is_equal(crowd.fog.visible)
	assert_int(_sum(crowded, 0, 49)).is_equal(13 + 21)
	assert_int(crowded[3 * 7 + 3]).is_equal(2)
	assert_int(crowded[3 * 7 + 5]).is_equal(2)
	assert_int(crowded[1 * 7 + 4]).is_equal(1)
	assert_int(_sum(crowded, 49, 98)).is_equal(1)


## A disc is cut at the map's edge, and a row that was never stamped, or belongs to no player, or to
## a player past player_count, has none.
func test_the_rebuild_clips_at_the_edge_and_skips_rows_with_no_disc() -> void:
	var corner: World = Worlds.field(7, 7, 2, [2000], [[2, 0, Worlds.centre(0), Worlds.centre(0)]])
	# The tiles of the plus-shaped disc that lie in the map: 3 + 2 + 1 of the quarter, so 6.
	assert_int(_sum(Derivation.rebuild(corner), 49, 98)).is_equal(6)
	assert_array(Derivation.rebuild(corner)).is_equal(corner.fog.visible)
	var world: World = Worlds.field(7, 7, 2, [2000], [[1, 0, Worlds.centre(3), Worlds.centre(3)]])
	world.fog_cell[0] = -1
	assert_int(_sum(Derivation.rebuild(world), 0, 98)).is_equal(0)
	world.fog_cell[0] = 24
	world.owner[0] = 0
	assert_int(_sum(Derivation.rebuild(world), 0, 98)).is_equal(0)
	world.owner[0] = 3
	assert_int(_sum(Derivation.rebuild(world), 0, 98)).is_equal(0)


## The check fails when the counts and the rows part ways, whichever of them moved: a count, the
## cell a row was stamped at, its owner, its type, or the sight of its type. It names the player
## and the tile of the first difference.
func test_a_count_and_the_rows_that_part_ways_are_a_mismatch() -> void:
	var units: Array = [[1, 0, Worlds.centre(3), Worlds.centre(3)], [2, 1, Worlds.centre(4), 500]]
	var base: World = Worlds.field(8, 6, 2, [2000, 3000], units)
	assert_str(Derivation.mismatch(base)).is_empty()
	var count: World = Worlds.field(8, 6, 2, [2000, 3000], units)
	count.fog.visible[48 + 5] += 1
	assert_str(Derivation.mismatch(count)).is_equal("player 2, tile 5: visible 2, the rows say 1")
	var moved: World = Worlds.field(8, 6, 2, [2000, 3000], units)
	moved.fog_cell[0] += 1
	assert_str(Derivation.mismatch(moved)).starts_with("player 1")
	var owner: World = Worlds.field(8, 6, 2, [2000, 3000], units)
	owner.owner[0] = 2
	assert_str(Derivation.mismatch(owner)).is_not_empty()
	var kind: World = Worlds.field(8, 6, 2, [2000, 3000], units)
	kind.type_index[1] = 0
	assert_str(Derivation.mismatch(kind)).is_not_empty()
	var sight: World = Worlds.field(8, 6, 2, [2000, 3000], units)
	sight.type_sight[0] = 3000
	assert_str(Derivation.mismatch(sight)).is_not_empty()
	var short: World = Worlds.field(8, 6, 2, [2000, 3000], units)
	short.fog.visible.resize(short.fog.visible.size() - 1)
	assert_str(Derivation.mismatch(short)).starts_with("visible holds")


## The sum of counts[from .. to).
func _sum(counts: PackedInt32Array, from: int, to: int) -> int:
	var total: int = 0
	for at: int in range(from, to):
		total += counts[at]
	return total
