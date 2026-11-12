extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin with aircraft rows and every weapon mask (plan row
## P238, ADR 0036 sections 5 and 13; ADR 0013 section 4), compared like test_targeting_lockstep.gd:
## the state hash and the full state after the phase or after every tick
## (targeting_lockstep_rig.gd).
## The roster is LayerWorlds': gun (mask 1), rocket (7), rifle (5), flak (6), jet (AIR, 2), bomber
## (AIR, 1), drone (low AIR, 1) and an unarmed scout, in random rows with random orders, ATTACK
## locks, held targets and a fog stamped for a share of the rows.
## - 400 seeded states, one TARGETING phase each. Beside the lockstep, the twin's answer is held to
##   the rule written out again here: no row holds, locks or is aimed at a layer its weapon cannot
##   hit, and the cases reached are counted, so that a state set that never met the rule fails.
## - 16 seeded fields stepped 90 ticks under random waves (the tally probe holds the phase to the
##   rule on the twin's side, which now includes the layer test).
## - 24 crafted two-row pairs (six shooters against four marks, flyers among them), run 30 ticks
##   with an ATTACK order on the mark: the lock falls back or holds as the mask says.
## The floors are measured on the twin and set at about two thirds of the figure, rounded down;
## the measurements are beside each one.

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/targeting_orders.gd")
const Layers: GDScript = preload("res://tests/sim/support/layer_worlds.gd")
const STATES: int = 400
const FIELDS: int = 16
const FIELD_TICKS: int = 90
const ATTACK: int = World.Order.ATTACK
## The 400 states together, measured: 1,085 rows that took or locked a flyer (376 of them ATTACK
## locks), 1,971 ATTACK locks that fell back because the weapon cannot hit the row (1,087 of them
## on a flyer), 3,022 held targets that are flyers, 2,222 scans that found a row.
const FLOOR_AIR_TAKEN: int = 720
const FLOOR_LOCKED_ON_AIR: int = 250
const FLOOR_FELL_BACK: int = 720
const FLOOR_UNHITTABLE: int = 1300
const FLOOR_HELD_ON_AIR: int = 2000
const FLOOR_FOUND: int = 1480
## The 16 fields together, measured: 6,226 scans, 380 fallbacks, 4,179 locked rows.
const FLOOR_RUN_SCANS: int = 4150
const FLOOR_RUN_FALLBACKS: int = 250
const FLOOR_RUN_LOCKED: int = 2780


func test_states_with_aircraft_and_every_mask_match_after_one_phase() -> void:
	var held_on_air: int = 0
	var locked_on_air: int = 0
	var fell_back_from_air: int = 0
	var air_taken: int = 0
	var unhittable_seen: int = 0
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in STATES:
		var rig: RefCounted = Rig.new().setup(Layers.field.bind(1000 + salt), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		var before: World = Layers.field(1000 + salt)
		assert_str(rig.once()).override_failure_message("state %d" % salt).is_empty()
		Rig.add_to(total, rig.tally())
		var world: World = rig.worlds[0]
		for row: int in world.unit_count():
			var at: int = world.index_of(world.target[row]) if world.target[row] != 0 else -1
			var weapon: int = world.type_weapon[world.type_index[row]]
			var due: bool = (
				(world.tick + world.unit_id[row]) % maxi(world.retarget_period_ticks, 1) == 0
			)
			# A row that is not due keeps the target it was given, hittable or not: the rule is
			# tested on its turn, and on every tick for an ATTACK lock.
			if at >= 0 and weapon >= 0 and (due or world.order[row] == ATTACK):
				var layer: int = world.type_layer_bit[world.type_index[at]]
				# The rule written out again: nothing is held, locked or taken that the weapon cannot hit.
				(
					assert_int(world.weapon_targets[weapon] & layer)
					. override_failure_message(
						"state %d row %d holds a layer it cannot hit" % [salt, row]
					)
					. is_not_equal(0)
				)
				air_taken += int(layer != Layers.GROUND)
				if world.order[row] == ATTACK and layer != Layers.GROUND:
					locked_on_air += 1
			if before.order[row] == ATTACK and world.order[row] != ATTACK:
				var locked: int = before.index_of(before.order_target[row])
				var hit: bool = locked >= 0
				if hit and before.type_weapon[before.type_index[row]] >= 0:
					var bit: int = before.type_layer_bit[before.type_index[locked]]
					var mask: int = before.weapon_targets[before.type_weapon[
						before.type_index[row]
					]]
					fell_back_from_air += int(bit != Layers.GROUND and (mask & bit) == 0)
					unhittable_seen += int((mask & bit) == 0)
			held_on_air += int(
				(
					before.target[row] != 0
					and before.index_of(before.target[row]) >= 0
					and (
						before.type_layer_bit[before.type_index[before.index_of(
							before.target[row]
						)]]
						!= Layers.GROUND
					)
				)
			)
	assert_int(air_taken).is_greater(FLOOR_AIR_TAKEN)
	assert_int(locked_on_air).is_greater(FLOOR_LOCKED_ON_AIR)
	assert_int(fell_back_from_air).is_greater(FLOOR_FELL_BACK)
	assert_int(unhittable_seen).is_greater(FLOOR_UNHITTABLE)
	assert_int(held_on_air).is_greater(FLOOR_HELD_ON_AIR)
	assert_int(total[&"found"]).is_greater(FLOOR_FOUND)


func test_fields_of_aircraft_and_ground_rows_match_under_random_waves() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in FIELDS:
		var mask: int = Rig.WITH_PORTED if salt % 2 == 1 else Rig.ONLY
		var rig: RefCounted = Rig.new().setup(Layers.field.bind(2000 + salt, 90), mask)
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(FIELD_TICKS, Orders.random_waves.bind(salt, 4))
		assert_str(found).override_failure_message("field %d" % salt).is_empty()
		Rig.add_to(total, rig.tally())
	assert_int(total[&"scans"]).is_greater(FLOOR_RUN_SCANS)
	assert_int(total[&"fallbacks"]).is_greater(FLOOR_RUN_FALLBACKS)
	assert_int(total[&"locked"]).is_greater(FLOOR_RUN_LOCKED)


## Crafted: a revealed world of two rows per case (a shooter and a mark, 7000 apart), run for 30
## ticks with an ATTACK order on the mark: the lock falls back or holds as the mask says, and the
## two implementations agree after every tick.
func test_attack_locks_on_flyers_match_for_every_mask() -> void:
	for shooter: int in [
		Layers.GUN, Layers.ROCKET, Layers.RIFLE, Layers.FLAK, Layers.JET, Layers.SCOUT
	]:
		for mark: int in [Layers.GUN, Layers.JET, Layers.BOMBER, Layers.DRONE]:
			var rig: RefCounted = Rig.new().setup(_pair.bind(shooter, mark), Rig.ONLY)
			assert_array(rig.problems).is_empty()
			var label: String = "shooter %d at mark %d" % [shooter, mark]
			assert_str(rig.run(30)).override_failure_message(label).is_empty()
			var world: World = rig.worlds[1]
			var weapon: int = world.type_weapon[shooter]
			var can: bool = (
				weapon < 0 or (world.weapon_targets[weapon] & world.type_layer_bit[mark]) != 0
			)
			assert_bool(world.order[0] == ATTACK).override_failure_message(label).is_equal(can)


func _pair(shooter: int, mark: int) -> World:
	var world: World = Layers.duel(shooter, mark, 7000)
	world.order[0] = ATTACK
	world.order_target[0] = 2
	world.goal_x[0] = world.pos_x[1]
	world.goal_y[0] = world.pos_y[1]
	return world
