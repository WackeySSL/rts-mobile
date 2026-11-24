extends GdUnitTestSuite
## The vision cut at rule 0 is bit for bit what main did before P573 (plan row P573, ADR 0047
## section 6): a match in which a Dusk Array blacks a building out, run on the rig of
## strike_worlds.gd with the rule left at its default 0, ends on the state hash that the commit
## before the cut (47d3f7c5) gave for the same match, in the GDScript twin and in the FOG kernel.
## The rule at 1 gives another one, so the comparison is not blind to what the cut writes
## (`fog_cell` of the cut rows). The match: the array of player 1 fires at the point of the rig
## with a shed of player 2 on it and a tank of player 1 two tiles off, then 60 more ticks.
## A re-pin of MAIN_HASH (a change that moves the rig's match on purpose) means recomputing the
## hash on the parent commit of that change, never on the change itself.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
## The state hash of the match at the end, taken on 47d3f7c5 (before P573).
const MAIN_HASH: String = "2b3574a3487db245"
const TICKS: int = 61


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The match with the rule set to `rule` (-1: left alone, which is the only thing main can do).
func _match(impl: int, rule: int) -> World:
	var world: World = Strikes.world(false)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.FOG)).is_empty()
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.ARRAY))
	world.add_building(2, Strikes.type_of(world, "shed"), 15, 10)
	Strikes.add(world, 1, "tank", 17500, 10500)
	Strikes.stamp(world)
	if rule >= 0:
		world.set(&"blackout_sight_cut", rule)
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	for _step: int in TICKS - 1:
		Strikes.step(world)
	return world


func test_a_match_with_a_blackout_at_rule_zero_has_the_hash_of_main(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _match(impl, -1)
	assert_int(world.offline_until[world.index_of(6)]).is_greater(0)  # The shed was blacked out.
	assert_str(World.hash_hex(world.state_hash())).is_equal(MAIN_HASH)


func test_the_rule_at_one_gives_another_hash_on_the_same_match(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _match(impl, 1)
	assert_int(world.fog_cell[world.index_of(6)]).is_equal(-1)
	assert_str(World.hash_hex(world.state_hash())).is_not_equal(MAIN_HASH)
