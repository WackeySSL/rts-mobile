extends "res://tests/ai/support/strike_suite.gd"
## The Dusk Array's rules of `AiStrikes` (plan row P181, ADR 0030 sections 1 and 6) on a hand-built
## World: it fires once per wave, while the wave is in the field, on the cluster of most enemy
## producer value; own rows inside its radius do not matter (a blackout hits no own building). The
## strike building is the Lumen Accord's, so player 1 is the Lumen Accord and player 2 the Derrick
## League. One case plays the wave through the real `AiArmy`.

## The factory's centre, the cluster's point: no other producer is within the radius of 4,000.
const CLUSTER_POINT: Vector2i = Vector2i(31500, 31500)
## The far barracks the wave's goal may point at.
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
