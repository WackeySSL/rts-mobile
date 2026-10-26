extends GdUnitTestSuite
## What the fog does to the buildings (plan P84, ADR 0022 sections 2 and 4, ADR 0010 section 2): an
## own building is always drawn, an enemy one only when the local player sees a cell of its
## footprint, `reveal_enemies` and a player the fog has no grid for see everything, the roof part
## carries the footprint's fog state as its colour (white seen, the explored dim not) while the
## base part never does (the fog layer dims it), and the layers redraw only when something they
## draw changed. On the base match (Rig): player 1 is local and sees only its own corner; the enemy
## buildings stand at the east edge, the turret at tile (30, 5) and the Headquarters at (35, 2).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const FogRig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const NONE: Array[Vector2i] = []

var _runner: MatchRunner
var _units: UnitLayer
var _buildings: BuildingLayer
var _roofs: BuildingRoofLayer
var _list: Array[Dictionary] = []


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_list = Rig.buildings()
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	add_child(_units)
	_units.set_process(false)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.unit_layer = _units
	add_child(_buildings)
	_buildings.set_process(false)
	_roofs = auto_free(BuildingRoofLayer.new())
	_roofs.buildings = _buildings
	add_child(_roofs)
	_roofs.set_process(false)


func after_test() -> void:
	CommandQueue.clear()


func test_an_own_building_is_always_shown_and_an_enemy_one_where_a_cell_of_it_is_seen() -> void:
	_buildings.sync()
	_assert_shown(_own())
	var turret: int = Rig.find(_list, &"defence_turret", 2)
	var hq: int = Rig.find(_list, &"headquarters", 2)
	var version: int = _buildings.plan_version()
	FogRig.flip(_runner.snapshot, 1, [Vector2i(30, 5)] as Array[Vector2i], true)
	_buildings.sync()
	_assert_shown(_own() + [turret])
	assert_int(_buildings.plan_version()).is_greater(version)
	# One corner cell of a 3x3 footprint is enough.
	FogRig.flip(_runner.snapshot, 1, [Vector2i(37, 4)] as Array[Vector2i], true)
	_buildings.sync()
	_assert_shown(_own() + [turret, hq])
	# The cell next to the footprint is not.
	FogRig.flip(_runner.snapshot, 1, [Vector2i(30, 5)] as Array[Vector2i], false)
	FogRig.flip(_runner.snapshot, 1, [Vector2i(34, 2)] as Array[Vector2i], true)
	_buildings.sync()
	_assert_shown(_own() + [hq])


func test_reveal_enemies_and_a_player_the_fog_has_no_grid_for_show_every_building() -> void:
	_buildings.sync()
	_buildings.reveal_enemies = true
	_buildings.sync()
	_assert_shown(range(Rig.BUILDINGS))
	_buildings.reveal_enemies = false  # Read when asked, as the unit layer's is.
	_buildings.sync()
	_assert_shown(_own())
	_runner.scenario.local_player = 3  # The fog was made for two players: it hides nothing.
	_buildings.sync()
	_assert_shown(range(Rig.BUILDINGS))


func test_the_other_players_view_shows_its_own_buildings_and_hides_the_first_ones() -> void:
	_runner.scenario.local_player = 2
	_buildings.sync()
	var want: Array[int] = []
	for b: int in range(Rig.OWN_BUILDINGS, Rig.BUILDINGS):
		want.append(b)
	_assert_shown(want)


func test_the_roof_carries_the_footprints_fog_state_and_the_base_part_never_does() -> void:
	_buildings.sync()
	var snap: MatchSnapshot = _runner.snapshot
	var dim: Color = Color(1.0 - 140 / 255.0, 1.0 - 140 / 255.0, 1.0 - 140 / 255.0)
	var team: Color = _units.team_color(1)
	assert_that(_buildings.part_color(0, BuildingLayer.HULL, true)).is_equal(Color.WHITE)
	assert_that(_buildings.part_color(0, BuildingLayer.TEAM, true)).is_equal(team)
	# The player sees nothing now: an own building is still drawn, its roof dimmed and its base
	# part not, because the fog layer is what dims the base part.
	FogRig.blind(snap, 1)
	FogRig.flip(snap, 1, NONE, false)
	_buildings.sync()
	assert_bool(_buildings.is_shown(0)).is_true()
	assert_that(_buildings.part_color(0, BuildingLayer.HULL, true)).is_equal(dim)
	assert_that(_buildings.part_color(0, BuildingLayer.TEAM, true)).is_equal(team * dim)
	assert_that(_buildings.part_color(0, BuildingLayer.HULL, false)).is_equal(Color.WHITE)
	assert_that(_buildings.part_color(0, BuildingLayer.TEAM, false)).is_equal(team)
	# The dim follows the fog layer's explored alpha, one value to change by eye.
	var fog: FogLayer = auto_free(FogLayer.new())
	fog.explored_alpha = 200
	_buildings.fog_layer = fog
	var version: int = _buildings.plan_version()
	_buildings.sync()
	var darker: Color = Color(1.0 - 200 / 255.0, 1.0 - 200 / 255.0, 1.0 - 200 / 255.0)
	assert_that(_buildings.part_color(0, BuildingLayer.HULL, true)).is_equal(darker)
	assert_int(_buildings.plan_version()).is_greater(version)
	# Seen again: white.
	FogRig.flip(snap, 1, [Vector2i(3, 3)] as Array[Vector2i], true)
	_buildings.sync()
	assert_that(_buildings.part_color(0, BuildingLayer.HULL, true)).is_equal(Color.WHITE)
	assert_that(_buildings.part_color(1, BuildingLayer.HULL, true)).is_equal(darker)  # Not its cells.


func test_a_frame_without_a_published_change_redraws_nothing_and_each_change_redraws_once() -> void:
	await _frame()
	await _frame()
	var base: int = _buildings.draw_count()
	var roofs: int = _roofs.draw_count()
	for _step: int in 5:
		await _frame(0.016)
	assert_array([_buildings.draw_count(), _roofs.draw_count()]).is_equal([base, roofs])
	# Six buildings of two quads each, and the roofs also the one turret's head.
	assert_array([_buildings.drawn_quads(), _roofs.drawn_quads()]).is_equal([12, 13])
	# A tile no footprint holds changing in the fog moves the fog version, not what is drawn.
	FogRig.flip(_runner.snapshot, 1, [Vector2i(20, 20)] as Array[Vector2i], true)
	await _frame()
	assert_array([_buildings.draw_count(), _roofs.draw_count()]).is_equal([base, roofs])
	# A cell of the enemy turret's footprint: one more building to draw, in both parts.
	FogRig.flip(_runner.snapshot, 1, [Vector2i(30, 5)] as Array[Vector2i], true)
	await _frame()
	assert_array([_buildings.draw_count(), _roofs.draw_count()]).is_equal([base + 1, roofs + 1])
	assert_array([_buildings.drawn_quads(), _roofs.drawn_quads()]).is_equal([14, 16])  # And 2 heads.
	await _frame()
	assert_array([_buildings.draw_count(), _roofs.draw_count()]).is_equal([base + 1, roofs + 1])
	# Another local player is another set.
	_runner.scenario.local_player = 2
	await _frame()
	assert_array([_buildings.draw_count(), _roofs.draw_count()]).is_equal([base + 2, roofs + 2])
	# A row that went (a harvester died): the list is built again and drawn again.
	_runner.scenario.local_player = 1
	await _frame()
	_runner.world.hp[Rig.OWN_BUILDINGS] = 0
	_runner.run_ticks(1)
	var after: Array[int] = [_buildings.draw_count(), _roofs.draw_count()]
	await _frame()
	assert_array([_buildings.draw_count(), _roofs.draw_count()]).is_equal(
		[after[0] + 1, after[1] + 1]
	)


func test_a_new_match_builds_the_atlas_and_the_list_again() -> void:
	_buildings.sync()
	var atlas: RuntimeAtlas = _buildings.atlas()
	var version: int = _buildings.plan_version()
	_runner.start()
	_buildings.sync()
	assert_object(_buildings.atlas()).is_not_null()
	assert_object(_buildings.atlas()).is_not_same(atlas)
	assert_int(_buildings.building_count()).is_equal(Rig.BUILDINGS)
	assert_int(_buildings.plan_version()).is_greater(version)


func _own() -> Array[int]:
	var own: Array[int] = []
	for b: int in Rig.OWN_BUILDINGS:
		own.append(b)
	return own


## Building `b` is shown exactly when `b` is in `want`.
func _assert_shown(want: Array) -> void:
	for b: int in _buildings.building_count():
		(
			assert_bool(_buildings.is_shown(b))
			. override_failure_message("building %d shown %s" % [b, _buildings.is_shown(b)])
			. is_equal(want.has(b))
		)


## One frame of the two layers, in the scene's order, and then the engine's own frame, which
## runs the `_draw` that a layer asked for.
func _frame(delta: float = 0.0) -> void:
	_buildings._process(delta)
	_roofs._process(delta)
	await await_idle_frame()
