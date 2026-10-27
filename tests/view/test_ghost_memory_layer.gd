extends GdUnitTestSuite
## The last-seen ghosts (plan P115c, ADR 0023 sections 2 and 3, P84c's acceptance): a remembered
## enemy building is drawn at z 5 in `GhostMemoryLayer` from the local player's block of the
## snapshot's ghost arrays, as the live building's body (the same atlas region, offset and scale)
## under one dim colour on the layer, on a footprint no cell of which is seen now, so exactly one
## of the live building and its ghost is drawn. The layer reads the arrays by `p * ghost_cap + i`,
## draws only below `ghost_count[p]`, pools its sprites, and redraws only when the match, the local
## player's fog version or its record count moves. The real sim's records and the flows through
## it are in test_ghost_memory_flow.gd.
## On a 32 x 32 map, player 1 the local one: its Headquarters (3x3) at tile (4, 4), and player 2's
## Headquarters (3x3, id 2, tiles 4-6 by 12-14, centre tile (5, 13)), Redoubt (1x1, id 3, tile
## (10, 12)) and Wind Park (2x2, id 4, tiles 16-17 by 12-13, centre tile (17, 13)). The runner is
## not in the tree: only the calls here move time. The cases write the published snapshot (ADR 0012
## section 3) with `Ghosts.remember` and `Rig.see`.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Ghosts: GDScript = preload("res://tests/view/support/ghost_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ARENA_SCENE: String = "res://scenes/dev/perf_arena.tscn"
const HQ_ID: int = 2
const DEFENCE_ID: int = 3
const POWER_ID: int = 4
## Id, roster entry, top-left tile and side of the three enemy buildings.
const ENEMIES: Array[Array] = [
	[HQ_ID, &"renew_hq", Vector2i(4, 12), 3],
	[DEFENCE_ID, &"renew_defence", Vector2i(10, 12), 1],
	[POWER_ID, &"renew_power", Vector2i(16, 12), 2],
]
## Where the layer must put them: the footprint centre in milli-tiles. A 3x3 and a 1x1 stand on
## the middle of their centre tile, the 2x2 on the corner between four.
const CENTRES: Array[Vector2i] = [
	Vector2i(5500, 13500), Vector2i(10500, 12500), Vector2i(17000, 13000)
]

var _window_size_before: Vector2i
var _runner: MatchRunner
var _sort: WorldSort
var _buildings: BuildingLayer
var _ghosts: GhostMemoryLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "headquarters", 4, 4),
		Rig.spawn(2, "renew_hq", 4, 12),
		Rig.spawn(2, "renew_defence", 10, 12),
		Rig.spawn(2, "renew_power", 16, 12),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_sort = auto_free(WorldSort.new())
	_sort.runner = _runner
	add_child(_sort)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.world_sort = _sort
	add_child(_buildings)
	_ghosts = auto_free(GhostMemoryLayer.new())
	_ghosts.runner = _runner
	_ghosts.world_sort = _sort
	add_child(_ghosts)
	for layer: Node in [_buildings, _ghosts]:
		layer.set_process(false)
		layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_the_layer_is_flat_at_z_5_sorted_by_y_and_carries_one_dim_colour() -> void:
	assert_int(_ghosts.z_index).is_equal(5)
	assert_int(GhostMemoryLayer.Z_GHOSTS).is_equal(5)
	assert_bool(_ghosts.z_as_relative).is_false()
	assert_bool(_ghosts.y_sort_enabled).is_true()
	# The explored fog is black at alpha 140, which leaves 115/255 of a colour: that, on each
	# channel and nothing on alpha, is the one dim the whole layer is multiplied by.
	var keep: float = (255.0 - 140.0) / 255.0
	assert_that(_ghosts.modulate).is_equal(_ghosts.dim_colour())
	assert_float(_ghosts.dim_colour().r).is_equal_approx(keep, 0.0001)
	assert_float(_ghosts.dim_colour().g).is_equal_approx(keep, 0.0001)
	assert_float(_ghosts.dim_colour().b).is_equal_approx(keep, 0.0001)
	assert_float(_ghosts.dim_colour().a).is_equal(1.0)
	_ghosts.explored_alpha = 0
	assert_that(_ghosts.dim_colour()).is_equal(Color.WHITE)
	_ghosts.explored_alpha = 255
	assert_that(_ghosts.dim_colour()).is_equal(Color.BLACK)
	_ghosts.explored_alpha = 999  # Past the ends it stays a colour a sprite can be multiplied by.
	assert_that(_ghosts.dim_colour()).is_equal(Color.BLACK)
	_ghosts.explored_alpha = -5
	assert_that(_ghosts.dim_colour()).is_equal(Color.WHITE)
	# The ghosts are as dark as the ground they stand on: the fog layer's explored alpha.
	var fog: FogLayer = auto_free(FogLayer.new())
	var fresh: GhostMemoryLayer = auto_free(GhostMemoryLayer.new())
	assert_int(fresh.explored_alpha).is_equal(fog.explored_alpha)


func test_a_building_out_of_sight_is_drawn_where_its_footprint_centre_is() -> void:
	_remember_all()
	_look([])
	assert_int(_ghosts.ghost_count()).is_equal(3)
	assert_array(_ghosts.ghost_ids()).is_equal([HQ_ID, DEFENCE_ID, POWER_ID])  # The record order.
	for at: int in 3:
		var id: int = ENEMIES[at][0]
		var ghost: Sprite2D = _ghosts.ghost(id)
		assert_object(ghost).is_not_null()
		assert_that(ghost.position).is_equal(
			IsoProjection.ground_to_px(CENTRES[at].x, CENTRES[at].y)
		)
		# Its y is the sort key of the live buildings, (c + r + n) * 16 px for an n x n footprint at
		# tile (c, r), so the engine's sort puts a remembered building as the live one is put.
		var origin: Vector2i = ENEMIES[at][2]
		var side: int = ENEMIES[at][3]
		assert_float(ghost.position.y).is_equal(float(origin.x + origin.y + side) * 16.0)
		assert_float(ghost.position.y).is_equal(_buildings.building(id).position.y)
		# The record's cell and the building's own row agree on where the centre is.
		var snap: MatchSnapshot = _runner.snapshot
		var row: int = snap.index_of(id)
		assert_that(Vector2i(snap.pos_x[row], snap.pos_y[row])).is_equal(CENTRES[at])
		assert_int(snap.cell_of(snap.pos_x[row], snap.pos_y[row])).is_equal(
			snap.ghost_cell[Ghosts.cap_of(snap) + at]
		)


func test_a_ghost_is_the_live_buildings_body_on_the_same_atlas_region() -> void:
	_remember_all()
	_look([])
	for entry: Array in ENEMIES:
		var id: int = entry[0]
		var body: Sprite2D = _buildings.building(id).get_node("Body") as Sprite2D
		var ghost: Sprite2D = _ghosts.ghost(id)
		assert_bool(ghost.visible).is_true()
		assert_object(ghost.texture).is_same(body.texture)
		assert_bool(ghost.region_enabled).is_true()
		assert_that(ghost.region_rect).is_equal(body.region_rect)
		assert_that(ghost.offset).is_equal(body.offset)
		assert_that(ghost.scale).is_equal(body.scale)
		assert_bool(ghost.centered).is_equal(body.centered)
		# And that region is the owner's body frame on the atlas (a building has no direction).
		var region: Rect2i = _sort.atlas.region(entry[1], &"hull", -1, _sort.slot_of(2))
		assert_bool(region.has_area()).is_true()
		assert_that(ghost.region_rect).is_equal(Rect2(region))


func test_the_owner_of_the_record_picks_the_colour_and_a_missing_frame_hides_the_ghost() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var cell: int = Ghosts.centre_cell(snap, Vector2i(4, 12), 3, 3)
	var other: int = Ghosts.centre_cell(snap, Vector2i(20, 20), 3, 3)
	# Player 2 wears the Lumen Accord's pictures, player 1 the Derrick League's. The second record
	# is a Derrick League building owned by player 2, which has no frame on its atlas page.
	(
		Ghosts
		. remember(
			snap,
			1,
			[
				Ghosts.record(31, &"renew_hq", 2, cell),
				Ghosts.record(32, &"headquarters", 2, cell),
				Ghosts.record(33, &"headquarters", 1, other),
			]
		)
	)
	_look([])
	assert_array(_ghosts.ghost_ids()).is_equal([31, 33])  # The unframed one is not counted.
	var lumen: Rect2i = _sort.atlas.region(&"renew_hq", &"hull", -1, _sort.slot_of(2))
	var derrick: Rect2i = _sort.atlas.region(&"headquarters", &"hull", -1, _sort.slot_of(1))
	assert_that(_ghosts.ghost(31).region_rect).is_equal(Rect2(lumen))
	assert_that(_ghosts.ghost(33).region_rect).is_equal(Rect2(derrick))
	assert_object(_ghosts.ghost(32)).is_null()
	assert_int(_ghosts.get_child_count()).is_equal(2)  # Its slot was dressed again for the next.
	assert_bool((_ghosts.get_child(1) as Sprite2D).visible).is_true()


func test_exactly_one_of_a_building_and_its_ghost_is_drawn_whatever_the_fog_shows() -> void:
	_remember_all()
	_look([])
	for entry: Array in ENEMIES:
		assert_str(_state(entry[0])).override_failure_message("unseen %d" % entry[0]).is_equal(
			"ghost"
		)
	for entry: Array in ENEMIES:
		var id: int = entry[0]
		var foot: Rect2i = Rect2i(entry[2], Vector2i(entry[3], entry[3]))
		for cell: Vector2i in _cells(foot):  # One cell of the footprint is enough, whichever it is.
			_look([cell])
			assert_str(_state(id)).override_failure_message("%d seen at %s" % [id, cell]).is_equal(
				"live"
			)
			for other: Array in ENEMIES:  # The others stay remembered.
				if other[0] != id:
					assert_str(_state(other[0])).is_equal("ghost")
		for cell: Vector2i in _cells(foot.grow(1)):  # The cells that touch it are not its own.
			if not foot.has_point(cell):
				_look([cell])
				assert_str(_state(id)).override_failure_message("%d near %s" % [id, cell]).is_equal(
					"ghost"
				)
		_look(_cells(foot))
		assert_str(_state(id)).is_equal("live")
	_look(_cells(Rect2i(0, 0, 32, 32)))  # Everything seen: three live buildings, no ghost.
	assert_int(_ghosts.ghost_count()).is_equal(0)
	for entry: Array in ENEMIES:
		assert_str(_state(entry[0])).is_equal("live")


func test_the_layer_and_the_building_layer_agree_with_is_seen_on_a_standing_building() -> void:
	_remember_all()
	var snap: MatchSnapshot = _runner.snapshot
	for entry: Array in ENEMIES:
		var id: int = entry[0]
		var row: int = snap.index_of(id)
		var foot: Rect2i = BuildingLayer.footprint_of(snap, row)
		assert_that(foot).is_equal(Rect2i(entry[2], Vector2i(entry[3], entry[3])))
		for cell: Vector2i in [foot.position, foot.end - Vector2i.ONE, Vector2i(0, 0)]:
			_look([cell])
			var seen: bool = BuildingLayer.is_seen(snap, 1, row)
			assert_bool(_ghosts.ghost(id) == null).is_equal(seen)
			assert_bool(BuildingLayer.footprint_seen(snap, 1, foot)).is_equal(seen)


func test_a_dropped_record_or_a_seen_spot_takes_its_ghost_away_and_the_others_stay() -> void:
	_remember_all()
	_look([])
	assert_int(_ghosts.ghost_count()).is_equal(3)
	var snap: MatchSnapshot = _runner.snapshot
	# The sim drops a record whose spot the player saw empty; the block closes up, in order.
	(
		Ghosts
		. remember(
			snap,
			1,
			[
				Ghosts.record(
					DEFENCE_ID, &"renew_defence", 2, snap.ghost_cell[Ghosts.cap_of(snap) + 1]
				),
				Ghosts.record(
					POWER_ID, &"renew_power", 2, snap.ghost_cell[Ghosts.cap_of(snap) + 2]
				),
			]
		)
	)
	_ghosts._process(0.0)  # No fog move: the record count alone redraws.
	assert_array(_ghosts.ghost_ids()).is_equal([DEFENCE_ID, POWER_ID])
	assert_object(_ghosts.ghost(HQ_ID)).is_null()
	# Seen again: the Redoubt's own tile, and its ghost goes while the Wind Park's stays.
	_look([Vector2i(10, 12)])
	assert_array(_ghosts.ghost_ids()).is_equal([POWER_ID])
	assert_str(_state(DEFENCE_ID)).is_equal("live")
	# A pooled sprite that no ghost uses is hidden, not freed.
	assert_int(_ghosts.get_child_count()).is_equal(3)
	var shown: int = 0
	for sprite: Node in _ghosts.get_children():
		shown += int((sprite as Sprite2D).visible)
	assert_int(shown).is_equal(1)


func test_only_the_local_players_block_is_read_at_p_times_the_cap_plus_i() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Ghosts.remember(
		snap, 1, [Ghosts.record(2, &"renew_hq", 2, Ghosts.centre_cell(snap, Vector2i(4, 12), 3, 3))]
	)
	Ghosts.remember(
		snap,
		2,
		[Ghosts.record(1, &"headquarters", 1, Ghosts.centre_cell(snap, Vector2i(4, 4), 3, 3))]
	)
	_look([])
	assert_array(_ghosts.ghost_ids()).is_equal([2])  # Player 1's block, not player 2's.
	_runner.scenario.local_player = 2  # The other player's view of the same snapshot.
	Rig.see(snap, 2, [])
	_ghosts._process(0.0)
	assert_array(_ghosts.ghost_ids()).is_equal([1])
	assert_that(_ghosts.ghost(1).position).is_equal(IsoProjection.ground_to_px(5500, 5500))
	_runner.scenario.local_player = 1
	Rig.see(snap, 1, [])
	_ghosts._process(0.0)
	assert_array(_ghosts.ghost_ids()).is_equal([2])


func test_a_full_block_is_drawn_whole_and_a_count_past_the_end_stays_in_the_block() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var cap: int = Ghosts.cap_of(snap)
	assert_int(cap).is_equal(40)  # data/rules.tres: ghost_cap.
	var records: Array = []
	for at: int in cap:  # 40 Redoubts on distinct tiles of rows 20 and 21.
		var tile: Vector2i = Vector2i(at % 32, 20 + at / 32)
		records.append(Ghosts.record(100 + at, &"renew_defence", 2, tile.y * 32 + tile.x))
	Ghosts.remember(snap, 1, records)
	_look([])
	assert_int(_ghosts.ghost_count()).is_equal(cap)
	assert_int(_ghosts.get_child_count()).is_equal(cap)
	snap.ghost_count[1] = cap + 7  # More than a block holds: the block's end is the limit.
	_look([])
	assert_int(_ghosts.ghost_count()).is_equal(cap)
	snap.ghost_count[1] = 2  # Entries past the count are history and are not drawn.
	_look([])
	assert_array(_ghosts.ghost_ids()).is_equal([100, 101])
	assert_int(_ghosts.get_child_count()).is_equal(cap)  # The pool keeps its sprites.


func test_a_frame_compares_three_integers_and_the_layer_redraws_only_when_one_moves() -> void:
	_remember_all()
	_look([])
	var drawn: int = _ghosts.redraw_count()
	for _frame: int in 10:
		_ghosts._process(0.0)
	assert_int(_ghosts.redraw_count()).is_equal(drawn)
	_look([Vector2i(0, 0)])  # The local player's fog version moved.
	assert_int(_ghosts.redraw_count()).is_equal(drawn + 1)
	var snap: MatchSnapshot = _runner.snapshot
	snap.ghost_count[1] = 2  # Its record count moved, its fog version did not.
	_ghosts._process(0.0)
	assert_int(_ghosts.redraw_count()).is_equal(drawn + 2)
	snap.ghost_count[2] = 1  # Another player's count is nothing to it.
	_ghosts._process(0.0)
	assert_int(_ghosts.redraw_count()).is_equal(drawn + 2)
	_runner.start()  # A new match: another serial and no memory yet.
	_ghosts._process(0.0)
	assert_int(_ghosts.redraw_count()).is_equal(drawn + 3)
	assert_int(_ghosts.ghost_count()).is_equal(0)


func test_reveal_enemies_and_a_fog_that_does_not_cover_the_player_draw_no_ghost() -> void:
	_remember_all()
	_ghosts.reveal_enemies = true  # The perf arena's: every enemy building is live there.
	_look([])
	assert_int(_ghosts.ghost_count()).is_equal(0)
	_ghosts.reveal_enemies = false
	_look([Vector2i(0, 1)])
	assert_int(_ghosts.ghost_count()).is_equal(3)
	_runner.snapshot.fog = FogGrid.new()  # No cells: nothing is hidden, so nothing is remembered.
	_ghosts._process(0.0)
	assert_int(_ghosts.ghost_count()).is_equal(0)


func test_a_ghost_is_a_plain_sprite_in_white_on_the_atlas_page_with_no_input_surface() -> void:
	_remember_all()
	_look([])
	for node: Node in _ghosts.get_children():
		var sprite: Sprite2D = node as Sprite2D
		assert_object(sprite).is_not_null()
		assert_object(sprite.texture).is_same(_sort.atlas.texture())  # One page: one draw call.
		assert_that(sprite.modulate).is_equal(Color.WHITE)  # The dim is the layer's, one for all.
		assert_that(sprite.self_modulate).is_equal(Color.WHITE)
		assert_object(sprite.material).is_null()
		assert_int(sprite.get_child_count()).is_equal(0)  # No head, no bar, no ring.
	assert_array(_ghosts.find_children("*", "CollisionObject2D", true, false)).is_empty()
	assert_array(_ghosts.find_children("*", "Control", true, false)).is_empty()
	assert_bool(_ghosts.is_class("Control")).is_false()
	assert_that(_ghosts.modulate).is_equal(_ghosts.dim_colour())


func test_a_ghost_is_the_same_picture_on_every_screen_and_a_turn_redraws_nothing() -> void:
	_remember_all()
	_look([])
	var drawn: int = _ghosts.redraw_count()
	var picture: Array = _picture()
	assert_int(picture.size()).is_equal(3)
	var sizes: Array[Vector2i] = []
	for size: Vector2i in ScreenSizes.ALL:  # 1280x720, 2400x1080, 2048x1536, both ways.
		sizes.append(size)
		get_window().size = size
		await await_idle_frame()  # size_changed: a layer that kept screen state would read it now.
		_buildings._process(0.0)
		_ghosts._process(0.0)
		assert_array(_picture()).override_failure_message("at %s" % size).is_equal(picture)
		assert_int(_ghosts.redraw_count()).is_equal(drawn)
		assert_that(_ghosts.modulate).is_equal(_ghosts.dim_colour())
	assert_array(sizes).is_equal(ScreenSizes.ALL)


func test_both_scenes_hold_the_layer_wired_to_the_runner_and_the_sort_and_only_the_arena_reveals(
) -> void:
	for path: String in [MAIN_SCENE, ARENA_SCENE]:
		var state: SceneState = (load(path) as PackedScene).get_state()
		var note: String = path
		(
			assert_object(_scene_value(state, "GhostMemoryLayer", &"script", null))
			. override_failure_message(note)
			. is_same(GhostMemoryLayer)
		)
		assert_int(_scene_value(state, "GhostMemoryLayer", &"z_index", 0)).is_equal(5)
		assert_bool(_scene_value(state, "GhostMemoryLayer", &"z_as_relative", true)).is_false()
		assert_bool(_scene_value(state, "GhostMemoryLayer", &"y_sort_enabled", false)).is_true()
		assert_that(_scene_value(state, "GhostMemoryLayer", &"runner", null)).is_equal(
			NodePath("../MatchRunner")
		)
		assert_that(_scene_value(state, "GhostMemoryLayer", &"world_sort", null)).is_equal(
			NodePath("../WorldSort")
		)
		# Neither scene sets a dim of its own, so the layer and the fog layer keep their defaults.
		assert_object(_scene_value(state, "GhostMemoryLayer", &"explored_alpha", null)).is_null()
		assert_object(_scene_value(state, "FogLayer", &"explored_alpha", null)).is_null()
		var reveals: bool = _scene_value(state, "GhostMemoryLayer", &"reveal_enemies", false)
		assert_bool(reveals).override_failure_message(note).is_equal(path == ARENA_SCENE)
		# The arena's building layer reveals too, so the two agree on what a ghost would double.
		var live: bool = _scene_value(state, "BuildingLayer", &"reveal_enemies", false)
		assert_bool(live).is_equal(reveals)


## The ghosts and the live buildings that the cases compare, for what the sim remembers of
## player 2's three buildings: the cell of each footprint centre.
func _remember_all() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var records: Array = []
	for entry: Array in ENEMIES:
		var cell: int = Ghosts.centre_cell(snap, entry[2], entry[3], entry[3])
		records.append(Ghosts.record(entry[0], entry[1], 2, cell))
	Ghosts.remember(snap, 1, records)


## What the ghosts look like: position, offset, scale, region and visibility of each, by slot.
func _picture() -> Array:
	var shown: Array = []
	for node: Node in _ghosts.get_children():
		var sprite: Sprite2D = node as Sprite2D
		if sprite.visible:
			shown.append(
				[sprite.position, sprite.offset, sprite.scale, sprite.region_rect, sprite.texture]
			)
	return shown


## Player 1 sees exactly `tiles`; both layers draw that frame.
func _look(tiles: Array) -> void:
	Rig.see(_runner.snapshot, 1, tiles)
	_buildings._process(0.0)
	_ghosts._process(0.0)


## What is drawn for building `id`: "live", "ghost", "both" or "none".
func _state(id: int) -> String:
	var node: Node2D = _buildings.building(id)
	var live: bool = node != null and node.visible
	var ghost: bool = _ghosts.ghost(id) != null
	if live and ghost:
		return "both"
	return "live" if live else ("ghost" if ghost else "none")


## The tiles of `area` that lie on the map, as Vector2i.
func _cells(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(maxi(area.position.y, 0), mini(area.end.y, 32)):
		for x: int in range(maxi(area.position.x, 0), mini(area.end.x, 32)):
			cells.append(Vector2i(x, y))
	return cells


func _scene_value(
	state: SceneState, node_name: String, prop: StringName, fallback: Variant
) -> Variant:
	for index: int in state.get_node_count():
		if state.get_node_name(index) != node_name:
			continue
		for at: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, at) == prop:
				return state.get_node_property_value(index, at)
	return fallback
