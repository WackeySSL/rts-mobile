extends GdUnitTestSuite
## OrderRules on a snapshot built by hand (plan P87, ADR 0019 section 3): who "All army" and a box
## take, which selection is tankers, which building a ground tap gives a rally point, and what is
## on or near a field. Types: 0 Headquarters (produces structures), 1 barracks (infantry), 2 vehicle
## factory (vehicles), 3 power plant (nothing), 4 rifle squad, 5 tank, 6 tanker. Rows by id, player
## 1's first: 1 Headquarters, 2 barracks, 3 factory, 4 power plant, 5 rifle, 6 tank, 7 tanker;
## player 2's: 8 tanker, 9 rifle, 10 barracks.

const HQ: int = 1
const BARRACKS: int = 2
const FACTORY: int = 3
const PLANT: int = 4
const RIFLE: int = 5
const TANK: int = 6
const TANKER: int = 7
const ENEMY_TANKER: int = 8
const ENEMY_RIFLE: int = 9
const ENEMY_BARRACKS: int = 10

var _snap: MatchSnapshot


func before_test() -> void:
	_snap = MatchSnapshot.new()
	_snap.type_speed = PackedInt32Array([0, 0, 0, 0, 50, 60, 73])
	_snap.type_harvest = PackedInt32Array([0, 0, 0, 0, 0, 0, 500])
	_snap.type_produces = PackedInt32Array(
		[World.Tab.STRUCTURES, World.Tab.INFANTRY, World.Tab.VEHICLES, -1, -1, -1, -1]
	)
	_snap.unit_id = PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_snap.owner = PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 2, 2, 2])
	_snap.type_index = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 6, 4, 1])


func test_a_tanker_is_a_type_with_a_harvest_capacity() -> void:
	assert_bool(OrderRules.is_tanker(_snap, 6)).is_true()
	for type: int in [0, 1, 4, 5, -1, 99]:
		(
			assert_bool(OrderRules.is_tanker(_snap, type))
			. override_failure_message(str(type))
			. is_false()
		)
	_snap.type_harvest = PackedInt32Array()  # A snapshot with no such column: nobody is a tanker.
	assert_bool(OrderRules.is_tanker(_snap, 6)).is_false()


func test_all_army_is_the_players_units_that_move_without_tankers_or_buildings() -> void:
	assert_array(OrderRules.all_army(_snap, 1)).is_equal([RIFLE, TANK])
	assert_array(OrderRules.all_army(_snap, 2)).is_equal([ENEMY_RIFLE])
	assert_array(OrderRules.all_army(_snap, 3)).is_empty()


func test_a_box_drops_its_tankers_when_it_holds_any_other_unit() -> void:
	assert_array(OrderRules.box_selection(_snap, PackedInt32Array([RIFLE, TANK, TANKER]))).is_equal(
		[RIFLE, TANK]
	)
	assert_array(OrderRules.box_selection(_snap, PackedInt32Array([TANKER, RIFLE]))).is_equal(
		[RIFLE]
	)


func test_a_box_of_tankers_alone_keeps_them_and_an_empty_box_stays_empty() -> void:
	assert_array(OrderRules.box_selection(_snap, PackedInt32Array([TANKER]))).is_equal([TANKER])
	(
		assert_array(OrderRules.box_selection(_snap, PackedInt32Array([ENEMY_TANKER, TANKER])))
		. is_equal([ENEMY_TANKER, TANKER])
	)
	assert_array(OrderRules.box_selection(_snap, PackedInt32Array([RIFLE]))).is_equal([RIFLE])
	assert_array(OrderRules.box_selection(_snap, PackedInt32Array())).is_empty()
	assert_array(OrderRules.box_selection(null, PackedInt32Array())).is_empty()


## FLIGHT and RESEARCH buildings (TABS 5, P232) are no rally target: the sim refuses them too.
func test_a_building_of_the_flight_or_research_tab_is_no_rally_target() -> void:
	var type: int = _snap.type_index[_snap.index_of(BARRACKS)]
	var kept: int = _snap.type_produces[type]
	for tab: int in [World.Tab.FLIGHT, World.Tab.RESEARCH]:
		_snap.type_produces[type] = tab
		assert_int(OrderRules.rally_building(_snap, PackedInt32Array([BARRACKS]), 1)).is_equal(0)
	_snap.type_produces[type] = kept
	assert_int(OrderRules.rally_building(_snap, PackedInt32Array([BARRACKS]), 1)).is_equal(BARRACKS)


func test_only_tankers_is_true_for_a_selection_of_tankers_and_nothing_else() -> void:
	assert_bool(OrderRules.only_tankers(_snap, PackedInt32Array([TANKER]))).is_true()
	assert_bool(OrderRules.only_tankers(_snap, PackedInt32Array([TANKER, ENEMY_TANKER]))).is_true()
	assert_bool(OrderRules.only_tankers(_snap, PackedInt32Array([TANKER, TANK]))).is_false()
	assert_bool(OrderRules.only_tankers(_snap, PackedInt32Array([HQ]))).is_false()
	assert_bool(OrderRules.only_tankers(_snap, PackedInt32Array())).is_false()
	assert_bool(OrderRules.only_tankers(null, PackedInt32Array([TANKER]))).is_false()


func test_a_rally_goes_to_one_own_building_that_produces_infantry_or_vehicles() -> void:
	assert_int(OrderRules.rally_building(_snap, PackedInt32Array([BARRACKS]), 1)).is_equal(BARRACKS)
	assert_int(OrderRules.rally_building(_snap, PackedInt32Array([FACTORY]), 1)).is_equal(FACTORY)
	assert_int(OrderRules.rally_building(_snap, PackedInt32Array([ENEMY_BARRACKS]), 2)).is_equal(
		ENEMY_BARRACKS
	)


func test_no_other_selection_gets_a_rally() -> void:
	for ids: Array in [
		[HQ], [PLANT], [ENEMY_BARRACKS], [RIFLE], [TANKER], [BARRACKS, FACTORY], [], [99]
	]:
		var selected: PackedInt32Array = PackedInt32Array(ids)
		(
			assert_int(OrderRules.rally_building(_snap, selected, 1))
			. override_failure_message(str(ids))
			. is_equal(0)
		)
	assert_int(OrderRules.rally_building(null, PackedInt32Array([BARRACKS]), 1)).is_equal(0)


func test_the_tab_a_type_produces() -> void:
	assert_int(OrderRules.produced_tab(_snap, 0)).is_equal(World.Tab.STRUCTURES)
	assert_int(OrderRules.produced_tab(_snap, 1)).is_equal(World.Tab.INFANTRY)
	assert_int(OrderRules.produced_tab(_snap, 2)).is_equal(World.Tab.VEHICLES)
	for type: int in [3, 4, -1, 99]:
		(
			assert_int(OrderRules.produced_tab(_snap, type))
			. override_failure_message(str(type))
			. is_equal(-1)
		)


## One ore cell, tile (col 2, row 1) of a map 8 tiles wide: a diamond 64 px wide and 32 high round
## (32, 64). A point past an edge is on the field when the reach grows the diamond to it.
func test_a_point_is_on_a_field_in_its_diamond_grown_by_the_reach() -> void:
	_snap.map_cols = 8
	_snap.ore_cell = PackedInt32Array([10])
	var centre: Vector2 = IsoProjection.cell_centre_px(2, 1)
	assert_vector(centre).is_equal(Vector2(32.0, 64.0))
	assert_bool(OrderRules.near_field(_snap, centre, 0.0)).is_true()
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(0.0, 15.0), 0.0)).is_true()
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(0.0, 17.0), 0.0)).is_false()
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(0.0, 17.0), 2.0)).is_true()
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(0.0, -17.0), 2.0)).is_true()
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(33.0, 0.0), 0.0)).is_false()
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(33.0, 0.0), 2.0)).is_true()
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(-35.0, 0.0), 2.0)).is_false()
	# Along a diagonal the grown diamond is only as far as its edge: not the corner of a box.
	assert_bool(OrderRules.near_field(_snap, centre + Vector2(30.0, 15.0), 2.0)).is_false()


func test_any_cell_of_the_field_counts_and_no_field_or_no_map_is_nowhere() -> void:
	_snap.map_cols = 8
	_snap.ore_cell = PackedInt32Array([10, 11, 18, 19])
	assert_bool(OrderRules.near_field(_snap, IsoProjection.cell_centre_px(3, 2), 0.0)).is_true()
	assert_bool(OrderRules.near_field(_snap, IsoProjection.cell_centre_px(6, 4), 0.0)).is_false()
	_snap.ore_cell = PackedInt32Array()
	assert_bool(OrderRules.near_field(_snap, IsoProjection.cell_centre_px(2, 1), 50.0)).is_false()
	_snap.ore_cell = PackedInt32Array([10])
	_snap.map_cols = 0
	assert_bool(OrderRules.near_field(_snap, IsoProjection.cell_centre_px(2, 1), 50.0)).is_false()


func test_the_tab_a_building_produces_by_its_id() -> void:
	assert_int(OrderRules.rally_tab(_snap, BARRACKS)).is_equal(World.Tab.INFANTRY)
	assert_int(OrderRules.rally_tab(_snap, FACTORY)).is_equal(World.Tab.VEHICLES)
	assert_int(OrderRules.rally_tab(_snap, HQ)).is_equal(World.Tab.STRUCTURES)
	for id: int in [PLANT, RIFLE, 99]:
		assert_int(OrderRules.rally_tab(_snap, id)).override_failure_message(str(id)).is_equal(-1)


## One ore cell, index 0 = cell 10 of a map 8 tiles wide: tile (2, 1), whose centre is the ground
## point (2500, 1500). The sim looks at a box and then a circle round the HARVEST's point, both
## inclusive (`Harvest._scan`), and only at cells with ore in them.
func test_ore_is_within_reach_in_the_sims_own_box_and_circle_and_only_where_there_is_some() -> void:
	_snap.map_cols = 8
	_snap.ore_cell = PackedInt32Array([10])
	_snap.ore_amount = PackedInt32Array([5])
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 3000)).is_true()
	assert_bool(OrderRules.ore_within(_snap, Vector2i(5500, 1500), 3000)).is_true()  # On the edge.
	assert_bool(OrderRules.ore_within(_snap, Vector2i(5501, 1500), 3000)).is_false()
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 4501), 3000)).is_false()
	# 2121 along both axes is 2999.8 away: in; 2122 is 3000.6: out. The box alone would let it in.
	assert_bool(OrderRules.ore_within(_snap, Vector2i(4621, 3621), 3000)).is_true()
	assert_bool(OrderRules.ore_within(_snap, Vector2i(4622, 3622), 3000)).is_false()
	_snap.ore_amount = PackedInt32Array([0])  # Dry: nothing to take.
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 3000)).is_false()


func test_a_dry_cell_beside_a_cell_with_ore_is_not_the_field_being_dry() -> void:
	_snap.map_cols = 8
	_snap.ore_cell = PackedInt32Array([10, 11])  # Tiles (2, 1) and (3, 1).
	_snap.ore_amount = PackedInt32Array([0, 7])
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 1000)).is_true()  # The next one.
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 999)).is_false()
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 0)).is_false()
	assert_bool(OrderRules.ore_within(_snap, Vector2i(3500, 1500), 0)).is_true()


func test_no_map_no_cells_or_a_short_amount_column_means_no_ore() -> void:
	_snap.ore_cell = PackedInt32Array([10])
	_snap.ore_amount = PackedInt32Array([5])
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 3000)).is_false()  # No map.
	_snap.map_cols = 8
	_snap.ore_amount = PackedInt32Array()  # A column shorter than the cells.
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 3000)).is_false()
	_snap.ore_cell = PackedInt32Array()
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), 3000)).is_false()
	assert_bool(OrderRules.ore_within(_snap, Vector2i(2500, 1500), -5)).is_false()
