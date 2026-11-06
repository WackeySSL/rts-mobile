extends "res://tests/ai/support/intel_suite.gd"
## `AiIntel`'s sector map, sightings and enemy base estimate (plan row P177, ADR 0030 sections 3
## and 6) on hand-built Worlds read through `PlayerView`; the scout is `test_ai_scout.gd`.


func test_the_sector_map_counts_own_and_seen_value_in_one_pass_each() -> void:
	AiRig.give(_world, 2, "barracks", 10, 10)
	var enemy: int = AiRig.add_unit_of(_world, 2, "rifle_squad", 9500, 9500)
	_settle()
	var view: PlayerView = _view()
	assert_bool(view.row_of(enemy) >= 0).is_true()
	_intel.refresh(view, _memory)
	assert_int(_intel.passes).is_equal(2)
	# 40 x 40 tiles in sectors of 8: 25 sectors, inside the 64 allowed.
	assert_array([_intel.sector_side, _intel.sector_count()]).is_equal([8, 25])
	var own: int = 0
	for row: int in view.own_rows:
		own += view.type_cost[view.row_type(row)]
	var seen: int = 0
	for row: int in view.seen_rows:
		seen += view.type_cost[view.row_type(row)]
	var sum_own: int = 0
	var sum_enemy: int = 0
	for sector: int in _memory.sector_own.size():
		sum_own += _memory.sector_own[sector]
		sum_enemy += _memory.sector_enemy[sector]
	assert_int(sum_own).is_equal(own)
	assert_int(sum_enemy).is_equal(seen)
	assert_bool(own > 0 and seen > 0).is_true()
	# The Headquarters (tile 7, 7) is in sector 0, the barracks (10, 10) in sector (1, 1) = 6.
	assert_int(_memory.sector_own[0]).is_greater_equal(view.type_cost[_type("headquarters")])
	assert_int(_memory.sector_enemy[6]).is_greater_equal(view.type_cost[_type("barracks")])
	# A second refresh of the same view gives the same map, not a sum (the map is rebuilt).
	var again: PackedInt32Array = _memory.sector_enemy.duplicate()
	_intel.refresh(view, _memory)
	assert_array(_memory.sector_enemy).is_equal(again)


func test_a_hurt_row_counts_its_hit_points_share_of_its_cost() -> void:
	var enemy: int = AiRig.add_unit_of(_world, 2, "heavy_tank", 9500, 9500)
	_settle()
	var row: int = _row(enemy)
	var full: int = _view().type_cost[_type("heavy_tank")]
	_intel.refresh(_view(), _memory)
	var whole: int = _memory.sector_enemy[6]
	_world.hp[row] = _world.hp[row] / 2
	_intel.refresh(_view(), _memory)
	assert_int(whole - _memory.sector_enemy[6]).is_between(full / 2 - 1, full / 2 + 1)


func test_the_map_never_has_more_sectors_than_the_def_allows() -> void:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.sectors_max = 4
	_intel = AiIntel.create(def, Rig.level_of("normal"), 1)
	_memory = AiMemory.create(def)
	_intel.refresh(_view(), _memory)
	assert_int(_intel.sector_count()).is_less_equal(4)
	assert_int(_memory.sector_own.size()).is_equal(4)
	# Every row lands in a sector of the grid: the own value is all there.
	var sum: int = 0
	for value: int in _memory.sector_own:
		sum += value
	assert_int(sum).is_greater(0)


func test_a_remembered_building_counts_in_the_enemy_map_at_its_full_cost() -> void:
	_remember_barracks(24, 4)
	_intel.refresh(_view(), _memory)
	# Tile (24, 4) is in sector column 3, row 0.
	assert_int(_memory.sector_enemy[3]).is_equal(_view().type_cost[_type("barracks")])


# --- sightings ------------------------------------------------------------------------------


func test_sightings_keep_the_count_and_the_first_tick_per_enemy_type() -> void:
	var rifle: int = _type("rifle_squad")
	AiRig.add_unit_of(_world, 2, "rifle_squad", 9500, 9500)
	_settle()
	_run(100)
	assert_array(_triple(rifle)).is_equal([1, 100, 100])
	assert_array(_triple(_type("heavy_tank"))).is_equal([0, -1, -1])
	AiRig.add_unit_of(_world, 2, "rifle_squad", 10500, 9500)
	_settle()
	_run(200)
	assert_array(_triple(rifle)).is_equal([2, 100, 200])
	# Both leave sight (here: die): the count last seen and the ticks stay.
	for id: int in AiRig.ids_of(_world, 2, "rifle_squad"):
		AiRig.kill(_world, _loop, _row_in_world(id))
	_settle()
	_run(300)
	assert_array(_triple(rifle)).is_equal([2, 100, 200])
	# Our own rows are no sighting.
	assert_array(_triple(_type("headquarters"))).is_equal([0, -1, -1])


func test_a_hidden_enemy_row_never_enters_the_memory() -> void:
	_settle()
	var view: PlayerView = _view()
	for row: int in view.seen_rows:
		assert_int(view.row_owner(row)).is_not_equal(2)
	assert_int(view.ghost_count).is_equal(0)
	_intel.refresh(view, _memory)
	_run(100)
	for type: int in _memory.seen_count.size():
		assert_array(_triple(type)).is_equal([0, -1, -1])
	var enemy: int = 0
	for value: int in _memory.sector_enemy:
		enemy += value
	assert_int(enemy).is_equal(0)
	assert_int(_intel.passes).is_equal(2)


# --- the base estimate ----------------------------------------------------------------------


func test_the_base_estimate_is_the_mirror_of_the_headquarters_until_a_producer_is_known() -> void:
	_settle()
	assert_bool(_memory.has_base_estimate()).is_false()
	_run(10)
	assert_array([_memory.base_x, _memory.base_y]).is_equal([MIRROR.x, MIRROR.y])


func test_a_seen_enemy_producer_replaces_the_mirror_and_the_nearest_one_wins() -> void:
	var near: int = AiRig.give(_world, 2, "barracks", 10, 10)
	var far: int = AiRig.give(_world, 2, "vehicle_factory", 12, 6)
	AiRig.add_unit_of(_world, 2, "rifle_squad", 9500, 5500)
	_settle()
	_run(10)
	var view: PlayerView = _view()
	assert_bool(view.row_of(near) >= 0 and view.row_of(far) >= 0).is_true()
	var pos: Vector2i = view.row_pos(view.row_of(near))
	assert_array([_memory.base_x, _memory.base_y]).is_equal([pos.x / 1000, pos.y / 1000])


func test_a_building_that_is_both_seen_and_remembered_counts_once() -> void:
	AiRig.give(_world, 2, "barracks", 10, 10)
	_settle()
	# The memory phase records a building the player sees, and keeps the record while it stands.
	_world.tick = 3
	LastSeen.run(_world)
	assert_int(_view().ghost_count).is_equal(1)
	_intel.refresh(_view(), _memory)
	assert_int(_memory.sector_enemy[6]).is_equal(_view().type_cost[_type("barracks")])
	_run(30)
	assert_array(_triple(_type("barracks"))).is_equal([1, 30, 30])


func test_producers_at_an_equal_distance_go_to_the_lower_id() -> void:
	# Mirror images about the diagonal through the Headquarters: the same distance from it.
	var first: int = AiRig.give(_world, 2, "barracks", 12, 4)
	var second: int = AiRig.give(_world, 2, "barracks", 4, 12)
	_settle()
	var view: PlayerView = _view()
	assert_bool(view.row_of(first) >= 0 and view.row_of(second) >= 0).is_true()
	_run(10)
	var pos: Vector2i = view.row_pos(view.row_of(first))
	assert_bool(first < second).is_true()
	assert_array([_memory.base_x, _memory.base_y]).is_equal([pos.x / 1000, pos.y / 1000])


func test_a_neutral_row_is_no_sighting_and_no_enemy_value() -> void:
	_world.add_unit(0, _type("rifle_squad"), 9500, 9500)
	_settle()
	var view: PlayerView = _view()
	assert_int(view.seen_rows.size()).is_equal(1)
	_intel.refresh(view, _memory)
	_run(10)
	for type: int in _memory.seen_count.size():
		assert_array(_triple(type)).is_equal([0, -1, -1])
	for value: int in _memory.sector_enemy:
		assert_int(value).is_equal(0)


func test_a_remembered_enemy_producer_is_the_estimate_when_nothing_is_seen() -> void:
	_settle()
	_remember_barracks(30, 4)
	_run(10)
	var view: PlayerView = _view()
	var pos: Vector2i = view.ghost_pos(0)
	assert_array([_memory.base_x, _memory.base_y]).is_equal([pos.x / 1000, pos.y / 1000])
	# The record is a sighting too: the type is counted once, at this tick.
	assert_array(_triple(_type("barracks"))).is_equal([1, 10, -1])


func test_an_enemy_unit_alone_is_no_producer_and_leaves_the_mirror() -> void:
	AiRig.add_unit_of(_world, 2, "rifle_squad", 9500, 9500)
	_settle()
	_run(10)
	assert_array([_memory.base_x, _memory.base_y]).is_equal([MIRROR.x, MIRROR.y])


# --- through the controller -----------------------------------------------------------------


func test_run_makes_two_passes_and_sends_nothing_in_this_row() -> void:
	AiRig.add_unit_of(_world, 2, "rifle_squad", 9500, 9500)
	_settle()
	_run(1800)
	assert_int(_intel.passes).is_equal(2)
	assert_array(_out).is_empty()


func test_the_controller_runs_the_refresh_in_the_army_slot_and_the_intel_in_the_intel_slot(
) -> void:
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 1)
	AiRig.add_unit_of(_world, 2, "rifle_squad", 9500, 9500)
	_settle()
	var sent: Array[Command] = []
	# Player 1 thinks on ticks 0 (ECONOMY), 5 (ARMY), 10 (INTEL), ...
	_world.tick = 1800
	ai.think(PlayerView.of(_world, 1), sent)
	assert_int(ai.last_slot).is_equal(OpponentAi.Slot.ECONOMY)
	assert_int(ai.work).is_equal(1)
	assert_bool(ai.memory.has_base_estimate()).is_false()
	_world.tick = 1805
	ai.think(PlayerView.of(_world, 1), sent)
	assert_int(ai.last_slot).is_equal(OpponentAi.Slot.ARMY)
	assert_int(ai.work).is_equal(3)
	var own: int = 0
	var enemy: int = 0
	for sector: int in ai.memory.sector_own.size():
		own += ai.memory.sector_own[sector]
		enemy += ai.memory.sector_enemy[sector]
	assert_bool(own > 0 and enemy > 0).is_true()
	assert_bool(ai.memory.has_base_estimate()).is_false()
	_world.tick = 1810
	ai.think(PlayerView.of(_world, 1), sent)
	assert_int(ai.last_slot).is_equal(OpponentAi.Slot.INTEL)
	assert_int(ai.work).is_equal(3)
	assert_bool(ai.memory.has_base_estimate()).is_true()
	assert_array([ai.work_max, ai.commands, ai.commands_cut]).is_equal([3, 0, 0])
	assert_array(sent).is_empty()


func test_the_manager_copies_its_defs_and_keeps_no_resource() -> void:
	for property: Dictionary in _intel.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = _intel.get(property["name"])
		assert_bool(value is Resource or value is Node).is_false()
