extends GdUnitTestSuite
## P70c: World.gd handed its hash code to WorldHash and its scenario loader to WorldLoad and kept
## every public name as a wrapper. These cases pin that nothing moved with the code: each wrapper
## returns what its helper returns for the same world, a world built through the wrapper is the
## world the loader builds, the map digest cache stays the World's own, and World.gd fits gdlint
## without the max-file-lines pragma. The hash values themselves are pinned where they always were
## (test_world_hash's TICK_0_SEED_1, test_world_v2_hash, tests/perf/test_golden_hashes.gd and
## tests/perf/test_hash_bytes.gd), so no literal is repeated here.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const CONTROLS_PATH: String = "res://data/scenarios/controls_test.tres"
const WORLD_SOURCE: String = "res://game/sim/World.gd"
## gdlint's max-file-lines.
const LINE_LIMIT: int = 1000
const PRAGMA: String = "max-file-lines"


## Every hashing wrapper of World returns what the WorldHash function behind it returns, on a world
## whose projectile slots and last-seen records hold live entries, so that every section feeds
## bytes.
func test_each_hash_wrapper_returns_what_its_helper_returns() -> void:
	var world: World = _loaded(ARENA_PATH, 42)
	world.proj_id[3] = 9
	world.proj_x[3] = 1234
	world.proj_free_top -= 1
	world.ghost_count[1] = 1
	world.ghost_id[world.ghost_cap] = 5
	world.ghost_cell[world.ghost_cap] = 17
	assert_int(world.state_hash()).is_equal(WorldHash.state_hash(world))
	assert_array(world.hash_parts()).is_equal(WorldHash.hash_parts(world))
	assert_int(world.defs_hash()).is_equal(WorldHash.defs_hash(world))
	assert_array(World.hash_section_names()).is_equal(WorldHash.hash_section_names())
	for value: int in [0, 1, -1, 0x7edcba9876543210, world.state_hash()]:
		assert_str(World.hash_hex(value)).is_equal(WorldHash.hash_hex(value))
	assert_array(world.hash_parts()).has_size(World.hash_section_names().size())
	assert_int(world.state_hash()).is_not_equal(_loaded(ARENA_PATH, 42).state_hash())


## World.from_scenario is WorldLoad.from_scenario: the same hash, definitions hash and stream for a
## map scenario, a jittered one, none at all, and one that is a roster of buildings only (a type
## chain whose links are copied in after it, and one that points back at itself).
func test_from_scenario_builds_the_world_the_loader_builds() -> void:
	var scenarios: Array[ScenarioDef] = [
		load(ARENA_PATH) as ScenarioDef,
		load(CONTROLS_PATH) as ScenarioDef,
		null,
		_building_roster(),
	]
	for scenario: ScenarioDef in scenarios:
		var through_world: World = World.from_scenario(
			scenario, DetRandom.create(42, DetRandom.STREAM_SIM)
		)
		var through_loader: World = WorldLoad.from_scenario(
			scenario, DetRandom.create(42, DetRandom.STREAM_SIM)
		)
		assert_int(through_world.state_hash()).is_equal(through_loader.state_hash())
		assert_int(through_world.defs_hash()).is_equal(through_loader.defs_hash())
		assert_array(through_world.type_ids).is_equal(through_loader.type_ids)
		assert_array(through_world.rng.state()).is_equal(through_loader.rng.state())
	var chain: World = World.from_scenario(_building_roster())
	assert_array(chain.type_ids).is_equal([&"refinery", &"plant", &"harvester"])
	assert_array(chain.type_requires).is_equal([1, -1, -1])
	assert_array(chain.type_free_unit).is_equal([2, 0, -1])


## The map digest cache is the World's `_map_digest` and `_map_digest_version`: prepare() fills it
## through WorldHash.map_digest(), a stale version is recomputed to the same value, and a terrain
## change (which bumps map_version) moves the digest and the cached version with it.
func test_the_map_digest_cache_stays_in_the_world() -> void:
	var world: World = _loaded(CONTROLS_PATH, 1)
	var digest: int = world._map_digest
	assert_int(world._map_digest_version).is_equal(world.map_version)
	assert_int(WorldHash.map_digest(world)).is_equal(digest)
	world._map_digest = 0
	world._map_digest_version = -1
	assert_int(WorldHash.map_digest(world)).is_equal(digest)
	assert_int(world._map_digest).is_equal(digest)
	assert_int(world._map_digest_version).is_equal(world.map_version)
	world.set_terrain(0, 1)
	assert_int(WorldHash.map_digest(world)).is_not_equal(digest)
	assert_int(world._map_digest_version).is_equal(world.map_version)


## WorldLoad.derive_open_grass, which World.prepare() calls for a world without a map: whole tiles
## rounded up, one terrain (grass) and one cost per class, and no map at all for a size of 0 or
## less on either axis.
func test_derive_open_grass_rounds_up_and_leaves_no_map_for_an_empty_size() -> void:
	var world: World = World.new()
	world.map_w = 3500
	world.map_h = 2001
	WorldLoad.derive_open_grass(world)
	assert_array([world.map_cols, world.map_rows]).is_equal([4, 3])
	assert_int(world.terrain.size()).is_equal(12)
	assert_int(world.move_cost.size()).is_equal(36)
	assert_array(world.terrain_ids).is_equal([World.GRASS_ID])
	assert_array(world.terrain_cost).is_equal([10, 10, 10])
	var flat: World = World.new()
	flat.map_w = 0
	flat.map_h = 5000
	WorldLoad.derive_open_grass(flat)
	assert_array([flat.map_cols, flat.map_rows, flat.terrain.size()]).is_equal([0, 0, 0])


## World.gd is under gdlint's line limit and carries no pragma that lifts it, so the next row that
## adds to it sees the limit.
func test_world_source_fits_gdlint_without_the_pragma() -> void:
	var source: String = FileAccess.get_file_as_string(WORLD_SOURCE)
	assert_str(source).is_not_empty()
	assert_bool(source.contains(PRAGMA)).is_false()
	assert_int(source.count("\n")).is_less_equal(LINE_LIMIT)


func _loaded(path: String, seed_value: int) -> World:
	return World.from_scenario(
		load(path) as ScenarioDef, DetRandom.create(seed_value, DetRandom.STREAM_SIM)
	)


## A scenario with a roster of one refinery that requires a plant and gives a harvester. The plant's
## own free unit is the refinery, a type known by then, so that copy ends and the link is index 0.
func _building_roster() -> ScenarioDef:
	var harvester: UnitDef = UnitDef.new()
	harvester.type_id = &"harvester"
	harvester.harvest_capacity = 500
	var plant: BuildingDef = BuildingDef.new()
	plant.type_id = &"plant"
	plant.footprint = Vector2i(2, 3)
	var refinery: BuildingDef = BuildingDef.new()
	refinery.type_id = &"refinery"
	refinery.footprint = Vector2i(3, 3)
	refinery.requires = plant
	refinery.free_unit = harvester
	plant.free_unit = refinery
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.roster.append(refinery)
	return scenario
