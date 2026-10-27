extends GdUnitTestSuite
## The ghosts against the real sim's records (plan P115c; P84c's acceptance): what `LastSeen` leaves
## in the published snapshot is what the layer draws, so a building destroyed out of sight stays
## drawn as a ghost until its spot is seen, a building seen destroyed leaves none, and a ghost never
## has a bar. On a 32 x 32 map: player 1's light tank at tile (8, 10) sees 7 tiles, player 2's Wind
## Park (2x2, id 2, tiles 12-13 by 10-11, unarmed so that nothing shoots the tank) stands in its
## sight. The case kills the tank by its hp (the world is the test's to touch; the layers read the
## snapshot only) and runs ticks, so player 1's fog turn, which comes every third tick, sees the
## park, remembers it and later no longer sees it. The cell and the layout of the records are the
## sim's own here; the arrays written by hand are in test_ghost_memory_layer.gd.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Ghosts: GDScript = preload("res://tests/view/support/ghost_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TANK_ID: int = 1
const PARK_ID: int = 2
const PARK_CENTRE: Vector2i = Vector2i(13000, 11000)
## The tile that holds the centre, which is the record's cell.
const PARK_TILE: Vector2i = Vector2i(13, 11)
const FAR_TILE: Vector2i = Vector2i(30, 30)
## Two fog turns of a player, which come every third tick: the fog and the memory follow the world.
const TURNS: int = 6

var _runner: MatchRunner
var _sort: WorldSort
var _camera: RtsCamera
var _units: UnitLayer
var _buildings: BuildingLayer
var _ghosts: GhostMemoryLayer
var _bars: HealthBarLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "light_tank", 8, 10),
		Rig.spawn(2, "renew_power", 12, 10),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_sort = auto_free(WorldSort.new())
	_sort.runner = _runner
	add_child(_sort)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.world_sort = _sort
	add_child(_units)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.world_sort = _sort
	add_child(_buildings)
	_ghosts = auto_free(GhostMemoryLayer.new())
	_ghosts.runner = _runner
	_ghosts.world_sort = _sort
	add_child(_ghosts)
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = _units
	_bars.building_layer = _buildings
	add_child(_bars)
	for layer: Node in [_units, _buildings, _ghosts, _bars]:
		layer.set_process(false)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_building_seen_and_then_lost_from_sight_is_remembered_where_it_stands() -> void:
	_runner.run_ticks(TURNS)
	var snap: MatchSnapshot = _runner.snapshot
	assert_array(_records()).is_equal([[PARK_ID, Ghosts.type_of(snap, &"renew_power"), 2]])
	assert_int(snap.ghost_cell[Ghosts.cap_of(snap) + 0]).is_equal(
		PARK_TILE.y * snap.fog.cols + PARK_TILE.x
	)
	_draw()
	assert_str(_state(PARK_ID)).is_equal("live")  # Seen now: the building, and no ghost beside it.
	_kill(TANK_ID)
	_runner.run_ticks(TURNS)
	_draw()
	assert_bool(_runner.snapshot.fog.is_visible(1, _cell(PARK_TILE))).is_false()
	assert_str(_state(PARK_ID)).is_equal("ghost")  # Out of sight: the memory, in its place.
	var ghost: Sprite2D = _ghosts.ghost(PARK_ID)
	assert_that(ghost.position).is_equal(IsoProjection.ground_to_px(PARK_CENTRE.x, PARK_CENTRE.y))
	assert_that(ghost.position).is_equal(_buildings.building(PARK_ID).position)


func test_a_building_destroyed_out_of_sight_stays_a_ghost_until_its_spot_is_seen() -> void:
	_runner.run_ticks(TURNS)
	_kill(TANK_ID)
	_runner.run_ticks(TURNS)
	_kill(PARK_ID)  # Nobody of player 1 is there to see it fall.
	_runner.run_ticks(TURNS)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(_buildings_row(snap)).is_equal(-1)  # The building is gone from the rows ...
	assert_array(_records()).is_equal([[PARK_ID, Ghosts.type_of(snap, &"renew_power"), 2]])
	_draw()
	assert_object(_buildings.building(PARK_ID)).is_null()
	assert_str(_state(PARK_ID)).is_equal("ghost")  # ... and still stands in the memory.
	assert_that(_ghosts.ghost(PARK_ID).position).is_equal(
		IsoProjection.ground_to_px(PARK_CENTRE.x, PARK_CENTRE.y)
	)
	for _frame: int in 30:  # Time passes and the ghost stays, with nothing to redraw.
		_runner.run_ticks(1)
		_ghosts._process(0.0)
	assert_str(_state(PARK_ID)).is_equal("ghost")
	# Any one cell of the footprint seen takes the ghost away while it is seen (the layer's rule is
	# the live building's, and it does not wait for a fog turn), a cell beside it does not. The
	# sim's memory drops a record on its centre tile only (`LastSeen`), so the case stops at the
	# glimpse: with the sim run on, the record of the park outlives a glimpse of the north tile.
	Rig.see(_runner.snapshot, 1, [PARK_TILE + Vector2i(2, 0)])
	_ghosts._process(0.0)
	assert_str(_state(PARK_ID)).is_equal("ghost")
	Rig.see(_runner.snapshot, 1, [Vector2i(12, 10)])  # The park's north tile, not its centre tile.
	_ghosts._process(0.0)
	assert_int(_ghosts.ghost_count()).is_equal(0)


func test_a_building_destroyed_in_sight_leaves_no_ghost_once_the_player_has_looked() -> void:
	_runner.run_ticks(TURNS)
	assert_int(_records().size()).is_equal(1)
	_kill(PARK_ID)  # The tank still sees the spot.
	_runner.run_ticks(TURNS)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(_buildings_row(snap)).is_equal(-1)
	assert_array(_records()).is_empty()  # The player saw the spot empty: the record is dropped.
	_draw()
	assert_int(_ghosts.ghost_count()).is_equal(0)
	assert_str(_state(PARK_ID)).is_equal("none")


func test_a_remembered_spot_seen_again_with_the_building_there_shows_it_alive_and_once() -> void:
	_runner.run_ticks(TURNS)
	_kill(TANK_ID)
	_runner.run_ticks(TURNS)
	_draw()
	assert_str(_state(PARK_ID)).is_equal("ghost")
	Rig.see(_runner.snapshot, 1, [PARK_TILE])  # A scout comes back.
	_draw()
	assert_str(_state(PARK_ID)).is_equal("live")
	Rig.see(_runner.snapshot, 1, [FAR_TILE])
	_draw()
	assert_str(_state(PARK_ID)).is_equal("ghost")  # Gone again: the memory is still there.


func test_a_ghost_has_no_bar_even_when_the_building_is_hit_out_of_sight() -> void:
	_runner.run_ticks(TURNS)
	_kill(TANK_ID)
	_runner.run_ticks(TURNS)
	_draw()
	assert_str(_state(PARK_ID)).is_equal("ghost")
	var row: int = _runner.snapshot.index_of(PARK_ID)
	_hit(row)
	_bars._process(0.0)
	assert_int(_bars.bar_count()).is_equal(0)  # Hit, remembered and unseen: no bar for it.
	assert_int(_ghosts.ghost(PARK_ID).get_child_count()).is_equal(0)
	Rig.see(_runner.snapshot, 1, [PARK_TILE])  # Control: the same hit shows a bar once seen.
	_draw()
	_hit(row)
	_bars._process(0.0)
	assert_int(_bars.bar_count()).is_equal(1)
	assert_str(_state(PARK_ID)).is_equal("live")


func test_a_ghost_cannot_be_picked_by_a_tap_with_or_without_a_selection() -> void:
	_runner.run_ticks(TURNS)
	Rig.see(_runner.snapshot, 1, [FAR_TILE])  # The tank's sight is elsewhere now.
	_draw()
	assert_str(_state(PARK_ID)).is_equal("ghost")
	var picks: PickSnapshot = PickSnapshot.new()
	_units.fill_pick_snapshot(picks, 24.0)
	var park: int = picks.ids.find(PARK_ID)
	assert_int(park).is_greater(-1)
	assert_int(picks.pickable[park]).is_equal(0)  # A building the player does not see now.
	var at: Vector2 = _camera.world_to_screen(_ghosts.ghost(PARK_ID).position)
	assert_int(Picker.pick(picks, at, 1, true)).is_equal(-1)
	assert_int(Picker.pick(picks, at, 1, false)).is_equal(-1)
	# The layer is sprites and nothing else: no area, no body, no control to take a touch.
	assert_array(_ghosts.find_children("*", "CollisionObject2D", true, false)).is_empty()
	assert_array(_ghosts.find_children("*", "Control", true, false)).is_empty()
	# A building destroyed out of sight has no row, so there is nothing for a pick to name.
	_kill(TANK_ID)
	_runner.run_ticks(TURNS)
	_kill(PARK_ID)
	_runner.run_ticks(TURNS)
	_draw()
	assert_str(_state(PARK_ID)).is_equal("ghost")
	_units.fill_pick_snapshot(picks, 24.0)
	assert_int(picks.size()).is_equal(0)
	assert_int(Picker.pick(picks, at, 1, true)).is_equal(-1)


## The ghost records of player 1 as [id, type index, owner], from the published snapshot.
func _records() -> Array:
	var snap: MatchSnapshot = _runner.snapshot
	var cap: int = Ghosts.cap_of(snap)
	var found: Array = []
	for at: int in snap.ghost_count[1]:
		var entry: int = cap + at
		found.append([snap.ghost_id[entry], snap.ghost_type[entry], snap.ghost_owner[entry]])
	return found


## The row of the Wind Park in `snap`, -1 when it is not in the rows.
func _buildings_row(snap: MatchSnapshot) -> int:
	return snap.index_of(PARK_ID)


## Marks unit `id` to die in the next tick (the test touches the world, as the building tests do).
func _kill(id: int) -> void:
	_runner.world.hp[_runner.snapshot.index_of(id)] = 0


## Draws a frame of every layer.
func _draw() -> void:
	_units._process(0.0)
	_buildings._process(0.0)
	_ghosts._process(0.0)
	_bars._process(0.0)


## Takes hp off row `row` of the published snapshot and tells the unit layer, which times the hit.
func _hit(row: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_units.sync_rows()
	snap.hp[row] -= 1
	_units._note_hits(snap)


## The fog cell of tile `tile`.
func _cell(tile: Vector2i) -> int:
	return tile.y * _runner.snapshot.fog.cols + tile.x


## What is drawn for building `id`: "live", "ghost", "both" or "none".
func _state(id: int) -> String:
	var node: Node2D = _buildings.building(id)
	var live: bool = node != null and node.visible
	var ghost: bool = _ghosts.ghost(id) != null
	if live and ghost:
		return "both"
	return "live" if live else ("ghost" if ghost else "none")
