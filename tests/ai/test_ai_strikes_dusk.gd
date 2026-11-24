extends "res://tests/ai/support/strike_suite.gd"
## The Dusk Array's rules of `AiStrikes` (plan row P181, ADR 0030 sections 1 and 6) on a hand-built
## World: it fires once per wave, while the wave is in the field, on the cluster of most enemy
## producer value; own rows inside its radius do not matter (a blackout hits no own building). The
## strike building is the Lumen Accord's, so player 1 is the Lumen Accord and player 2 the Derrick
## League. One case plays the wave through the real `AiArmy`.

## The factory's centre, the cluster's point: no other producer is within the radius of 4,000.
const CLUSTER_POINT: Vector2i = Vector2i(31500, 31500)
## The far barracks the wave's goal may point at.
## The second factory of the equal pair.
const TWIN_POINT: Vector2i = Vector2i(11500, 32500)
## The tile of the radar beside the twin.
const RADAR_TILE: Vector2i = Vector2i(11, 29)
const FAR_POINT: Vector2i = Vector2i(7000, 29000)
## The wave numbers of the integration case: the first tick and strength (a Lumen Accord tank and
## the two starting rifle squads: 1000 + 100 + 100); the first ARMY slot is tick 5, 15 ticks apart.
const WAVE_TICK: int = 100
const WAVE_STRENGTH: int = 1200
const LAUNCH: int = 110
## The army's own numbers for that case: staging offset and defence radius (tiles), and the keys.
const OFFSET: int = 6
const DEFENCE: int = 12
const KEYS: int = 4


func _side() -> String:
	return "renew"


func test_without_a_wave_in_the_field_the_array_waits() -> void:
	_producers()
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	_wave(0, AiMemory.SquadState.WAVE)
	_fire(KNOWN + 15)
	assert_array(_out).is_empty()
	_wave(1, AiMemory.SquadState.HOME)
	_fire(KNOWN + 30)
	assert_array(_out).is_empty()
	_wave(1, AiMemory.SquadState.RETREAT)
	_fire(KNOWN + 45)
	assert_array(_out).is_empty()
	assert_int(_memory.strike_wave).is_equal(0)


func test_a_launched_wave_makes_the_array_fire_on_the_producer_cluster() -> void:
	_producers()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	assert_array(_shots()).is_empty()
	_fire(KNOWN)
	var shots: Array[Command] = _shots()
	assert_int(shots.size()).is_equal(1)
	(
		assert_array([shots[0].player_id, shots[0].target_id, shots[0].target_x, shots[0].target_y])
		. is_equal([1, _strike, CLUSTER_POINT.x, CLUSTER_POINT.y])
	)
	assert_int(_memory.strike_wave).is_equal(1)
	assert_int(_memory.commands_left).is_equal(7)
	assert_int(_striker.strikes).is_equal(1)


func test_only_producers_count_and_own_units_in_the_radius_do_not_matter() -> void:
	# The far pair of barracks (800) and the refinery beside them (1,400) would be 2,200 if the
	# refinery counted; the lone factory (1,800) wins as a producer cluster.
	_producers()
	AiRig.add_unit_of(_world, 1, "renew_tank", 32000, 31500)
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	assert_array([_shots()[0].target_x, _shots()[0].target_y]).is_equal(
		[CLUSTER_POINT.x, CLUSTER_POINT.y]
	)


func test_the_array_answers_a_wave_once_and_the_next_wave_again() -> void:
	_producers()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	AiRig.step(_world, _loop, _shots())
	_world.ready_tick[_row_in_world(_strike)] = 0
	_world.offline_until[_row_in_world(_strike)] = 0
	_fire(KNOWN + 15)
	assert_array(_out).is_empty()
	_wave(2, AiMemory.SquadState.WAVE)
	_fire(KNOWN + 30)
	assert_int(_shots().size()).is_equal(1)
	assert_int(_memory.strike_wave).is_equal(2)


func test_the_sim_takes_the_blackout_and_it_sets_no_pending_rupture() -> void:
	_producers()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	AiRig.step(_world, _loop, _shots())
	assert_int(_world.dropped_commands).is_equal(0)
	assert_int(_view().own_strike_tick).is_equal(0)
	var factory: int = AiRig.row_of(_world, 2, "vehicle_factory")
	assert_int(_world.offline_until[factory]).is_greater(_world.tick)
	# A building outside the radius is untouched.
	var far: int = AiRig.row_of(_world, 2, "barracks")
	assert_int(_world.offline_until[far]).is_equal(0)


func test_no_known_producer_means_no_shot_and_the_wave_stays_unanswered() -> void:
	_wave(1, AiMemory.SquadState.WAVE)
	_enemy_building("refinery", 30, 30)
	_see_all()
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	assert_int(_memory.strike_wave).is_equal(0)
	_enemy_building("vehicle_factory", 34, 34)
	_fire(KNOWN + 15)
	_fire(KNOWN + 15 + REACTION)
	assert_int(_shots().size()).is_equal(1)


func test_the_charge_and_the_budget_gate_the_array_to_the_tick() -> void:
	_producers()
	_wave(1, AiMemory.SquadState.WAVE)
	_world.ready_tick[_row_in_world(_strike)] = 5000
	_fire(KNOWN)
	_fire(5000 - 2)
	assert_array(_out).is_empty()
	_fire(5000 - 1, 0)
	assert_array(_out).is_empty()
	assert_int(_memory.strike_wave).is_equal(0)
	_fire(5000 - 1)
	assert_int(_shots().size()).is_equal(1)
	AiRig.step(_world, _loop, _shots())
	assert_int(_world.dropped_commands).is_equal(0)


func test_the_levels_flag_gates_the_array() -> void:
	_producers()
	_arm_strikes("normal", 0, "renew")
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	_arm_strikes("hard", 1, "renew")
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	assert_int(_shots().size()).is_equal(1)


func test_the_array_prefers_the_producers_in_reach_of_the_waves_goal() -> void:
	_producers()
	_wave(1, AiMemory.SquadState.WAVE)
	# The wave heads for the far barracks: its tile is the goal, though the factory is richer.
	_memory.squad_goal_x[AiArmy.WAVE] = 7
	_memory.squad_goal_y[AiArmy.WAVE] = 29
	_fire(READY)
	_fire(KNOWN)
	assert_array([_shots()[0].target_x, _shots()[0].target_y]).is_equal([FAR_POINT.x, FAR_POINT.y])


func test_a_wave_without_a_live_member_does_not_make_the_array_fire() -> void:
	_producers()
	_wave(1, AiMemory.SquadState.WAVE)
	_memory.member_id = PackedInt32Array([99999])
	_memory.member_squad = PackedInt32Array([AiArmy.WAVE])
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	_memory.member_squad = PackedInt32Array([AiArmy.HOME])
	_memory.member_id = PackedInt32Array([AiRig.ids_of(_world, 1, "renew_rifle")[0]])
	_fire(KNOWN + 15)
	assert_array(_out).is_empty()


func test_a_wave_launched_by_the_army_makes_the_array_fire() -> void:
	var def: OpponentDef = Rig.def_of("renew").duplicate() as OpponentDef
	def.staging_offset_tiles = OFFSET
	def.defend_radius_tiles = DEFENCE
	def.goal_keys_max = KEYS
	_memory.goal_keys_max = KEYS
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.reaction_ticks = REACTION
	level.wave_first_tick = WAVE_TICK
	level.wave_first_strength = WAVE_STRENGTH
	level.wave_jitter_ticks = 0
	level.all_in_tick = 0
	var army: AiArmy = AiArmy.create(def, level, 1)
	AiRig.add_unit_of(_world, 1, "renew_tank", 9500, 9500)
	_settle()
	_producers()
	_memory.base_x = 31
	_memory.base_y = 31
	for tick: int in range(5, LAUNCH + 1, 15):
		_world.tick = tick
		_memory.commands_left = 8
		var view: PlayerView = _view()
		_intel.refresh(view, _memory)
		army.run(view, _memory, _rng, _scratch)
	assert_int(_memory.wave_count).is_equal(1)
	_fire(READY)
	_fire(KNOWN)
	assert_int(_shots().size()).is_equal(1)
	assert_int(_memory.strike_wave).is_equal(1)


## Two equal clusters: a lone factory at CLUSTER_POINT and another at TWIN_POINT (1,800 each). The
## wave has no goal, so both are candidates; with no radar the earlier anchor of the ranking, the
## first, wins. A radar of the League stands in a sector of its own, 2.5 tiles from the twin, so it
## does not change the ranking (a radar in the twin's sector would rank the twin first).
func test_with_no_radar_the_tie_goes_to_the_earlier_anchor() -> void:
	_twins()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_of_equal_clusters_the_ring_that_covers_a_seen_radar_wins() -> void:
	_twins()
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_the_radar_of_a_remembered_building_breaks_the_tie_too() -> void:
	_twins()
	_ghost(9999, "fossil_radar", RADAR_TILE.x, RADAR_TILE.y)  # No row shows it: a record only.
	_after_sighting()
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_a_radar_out_of_the_ring_or_not_yet_known_does_not_break_the_tie() -> void:
	_twins()
	# 5.5 tiles from the twin's centre: outside the ring of 4,000.
	_enemy_building("fossil_radar", 11, 24)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])
	# A radar in the ring whose type was sighted one run ago: not yet old enough to count.
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_memory.seen_first_tick[_world.type_ids.find(&"fossil_radar")] = AiMemory.NONE
	_memory.strike_wave = 0
	_fire(KNOWN + 60)
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_a_ring_that_already_covers_a_radar_keeps_its_place_against_another_that_does() -> void:
	_twins()
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_enemy_building("fossil_radar", 33, 28)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_a_cap_that_leaves_no_room_for_the_radar_check_leaves_the_tie_alone() -> void:
	# Three things, three anchors, nine tests: the cap of nine has no room for one more.
	_arm_strikes("normal", 1, _side(), MIN, 9)
	_twins()
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])
	assert_int(_striker.tests).is_equal(9)


func test_a_radar_does_not_outweigh_a_richer_cluster() -> void:
	# The lone factory (1,800) against the far barracks pair (800) with a radar beside it.
	_flag_radars()
	_producers()
	_enemy_building("fossil_radar", 9, 30)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_the_radar_check_is_counted_and_capped() -> void:
	_twins()
	var base: int = _striker.tests
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_after_sighting()
	assert_int(_striker.tests).is_greater(base)
	assert_int(_striker.passes).is_equal(0)
	assert_int(_striker.tests).is_less_equal(TESTS)


## A lone enemy factory (1,800) and, far off, two barracks with a refinery beside them.
func _producers() -> void:
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("barracks", 6, 28)
	_enemy_building("barracks", 8, 28)
	_enemy_building("refinery", 6, 31)
	_see_all()


## The wave table by hand: `count` waves launched, the wave squad in `state`.
func _wave(count: int, state: int) -> void:
	_memory.wave_count = count
	_memory.squad_state[AiArmy.WAVE] = state
	_memory.squad_role[AiArmy.WAVE] = AiArmy.ROLE_WAVE
	_memory.member_id = PackedInt32Array([AiRig.ids_of(_world, 1, "renew_rifle")[0]])
	_memory.member_squad = PackedInt32Array([AiArmy.WAVE])


## Two lone factories of equal value, the wave in the field, the factories sighted and fired on
## once (the shot stays in `_out` only, so a later run may fire again).
func _twins() -> void:
	_flag_radars()
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("vehicle_factory", 10, 31)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	assert_int(_shots().size()).is_equal(1)
	_memory.strike_wave = 0


## Runs until a thing first seen at `KNOWN + 15` is old enough; that run's shot stays in `_out`.
func _after_sighting() -> void:
	_fire(KNOWN + 15)
	_memory.strike_wave = 0
	_fire(KNOWN + 15 + REACTION)


## The frozen arena's radar copies carry no `radar` flag (test_radar_dark.gd), so the cases that
## need a radar set it on the World's type table the way the shipped data has it.
func _flag_radars() -> void:
	for id: String in ["fossil_radar", "renew_radar"]:
		_world.type_radar[_world.type_ids.find(StringName(id))] = 1
