extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin where the vision cut takes a sight away (plan row
## P573, ADR 0047 section 2): an enemy that only a blacked-out building sees is not targetable, in
## both versions, for a scan, a held target and an ATTACK lock. The pair gets the same World; one
## FOG phase (FogUpdate, the kernel on the native side) applies the cut, then one TARGETING phase as
## Sim.step runs it, and the two Worlds are compared in full (StateDiff). The twin's targets are
## held to what the rule says, so two versions that agree on the wrong answer fail as well.
##
## The lookout is a unit type with a hand-written `offline_until` (no strike writes one on a unit;
## the lockstep only needs a row the cut can reach).
##
## Player 1's gun (id 1, sight 1500, reach 4000) stands at tile (10, 10), its lookout (id 2, sight
## 4000, no weapon) at tile (9, 10), and player 2's gun (id 3) at tile (13, 10): 3 tiles from the
## gun, outside the gun's own disc (1 tile) and inside the lookout's (4 tiles). The enemy moves,
## so it scans nothing and the gun's target is the whole answer. Every cadence is 1.

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const GUN: int = 0
const LOOKOUT: int = 1
const SQUARE: int = 30
const ENEMY_ID: int = 3


## The World: the rule on, `until` the lookout's `offline_until` (0 = on), and `mode` how the gun
## holds the enemy: "scan" (idle), "held" (the enemy is its target already) or "lock" (an ATTACK).
func _world(mode: String, until: int) -> World:
	var gun: UnitDef = TargetingRig.unit(&"gun", 1500, 5000, 4000, 0, [100, 100, 100, 100])
	var lookout: UnitDef = TargetingRig.unit(&"lookout", 4000, 5000, 0, 0, [])
	var units: Array[UnitDef] = [gun, lookout]
	var world: World = TargetingRig.world_of(units, SQUARE, SQUARE, false)
	world.retarget_period_ticks = 1
	world.fog_period_ticks = 1
	world.blackout_sight_cut = 1
	world.add_unit(1, GUN, 10500, 10500)
	world.add_unit(1, LOOKOUT, 9500, 10500)
	world.add_unit(2, GUN, 13500, 10500)
	Worlds.stamp_fog(world)
	world.order[2] = World.Order.MOVE
	world.offline_until[1] = until
	if mode == "held":
		world.target[0] = ENEMY_ID
	elif mode == "lock":
		world.order[0] = World.Order.ATTACK
		world.order_target[0] = ENEMY_ID
	return world


## One FOG phase and one TARGETING phase of the pair that `_world` makes; the twin's target of the
## gun (the kernel's is asserted equal), and whether the lookout still has its disc.
func _run(mode: String, until: int, label: String) -> Array:
	var problems: Array[String] = []
	var worlds: Array[World] = Rig.pair(_world.bind(mode, until), Rig.ALL, problems)
	assert_array(problems).override_failure_message(label).is_empty()
	for world: World in worlds:
		# The stamp of the added rows: the world was stamped at tick 0 with the lookout on.
		FogUpdate.begin(world)
		FogUpdate.run(world)
		world.stats.fill(0)
		world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
		Targeting.run(world)
	assert_str(StateDiff.first(worlds[0], worlds[1])).override_failure_message(label).is_empty()
	assert_int(worlds[1].target[0]).override_failure_message(label).is_equal(worlds[0].target[0])
	return [worlds[0].target[0], worlds[0].fog_cell[1] >= 0]


func test_an_enemy_seen_only_by_a_cut_building_is_not_targetable_in_both_versions() -> void:
	for mode: String in ["scan", "held", "lock"]:
		var label: String = mode
		# The lookout is on: its disc shows the enemy and the gun takes it.
		var on: Array = _run(mode, 0, label + ", on")
		assert_array(on).override_failure_message(label + ", on").is_equal([ENEMY_ID, true])
		# Blacked out (until the stamp of a long way off): no disc, so no target.
		var off: Array = _run(mode, 500, label + ", cut")
		assert_array(off).override_failure_message(label + ", cut").is_equal([0, false])


func test_the_rule_at_zero_leaves_the_enemy_targetable_in_both_versions() -> void:
	for mode: String in ["scan", "held", "lock"]:
		var problems: Array[String] = []
		var build: Callable = func() -> World:
			var world: World = _world(mode, 500)
			world.blackout_sight_cut = 0
			return world
		var worlds: Array[World] = Rig.pair(build, Rig.ALL, problems)
		assert_array(problems).is_empty()
		for world: World in worlds:
			FogUpdate.begin(world)
			FogUpdate.run(world)
			world.stats.fill(0)
			world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
			Targeting.run(world)
			assert_int(world.target[0]).override_failure_message(mode).is_equal(ENEMY_ID)
		assert_str(StateDiff.first(worlds[0], worlds[1])).override_failure_message(mode).is_empty()
