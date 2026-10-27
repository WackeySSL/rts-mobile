extends GdUnitTestSuite
## The oil and gas fields on the ground (plan P116, ADR 0023 sections 2 and 11, STYLE.md "Fields"):
## the fields as groups of ore cells joined side to side or corner to corner (the numbering of
## `MapDef.field_kinds`, plan P79), the stage of a cell by integer thirds of
## `ore_cell_max`, a stage tile written only when a cell's stage changes, the kind of a field from
## one lookup that says oil until the map data names it, and one wellhead with its shadow on each
## field, drawn from the ground's one page. The fixture map is tests/view/support/ground_rig.gd's.

const Rig: GDScript = preload("res://tests/view/support/ground_rig.gd")

var _runner: MatchRunner
var _ground: GroundLayer
var _fields: FieldLayer


func before_test() -> void:
	_build(Rig.scenario())


func after_test() -> void:
	CommandQueue.clear()


func test_a_stage_is_an_integer_third_of_the_most_a_cell_holds() -> void:
	# The shipped 20: above 13.3 is full, above 6.7 half, the rest dry.
	for case: Array in [[20, 0], [14, 0], [13, 1], [7, 1], [6, 2], [1, 2], [0, 2]]:
		var stage: int = FieldLayer.stage_of(case[0], 20)
		assert_int(stage).override_failure_message("%d of 20" % case[0]).is_equal(case[1])
	# On a third exactly the cell is not above it: full needs more than two thirds, half more than one.
	for case: Array in [[3, 0], [2, 1], [1, 2], [0, 2]]:
		var stage: int = FieldLayer.stage_of(case[0], 3)
		assert_int(stage).override_failure_message("%d of 3" % case[0]).is_equal(case[1])
	assert_int(FieldLayer.stage_of(6, 9)).is_equal(1)  # Two thirds exactly: half.
	assert_int(FieldLayer.stage_of(3, 9)).is_equal(2)  # One third exactly: dry.


func test_a_field_is_a_group_of_ore_cells_joined_side_to_side_or_corner_to_corner() -> void:
	assert_array(_runner.snapshot.ore_cell).contains_exactly(Rig.ORE_CELLS)  # 44 joins the line at 35.
	assert_int(_fields.fields().size()).is_equal(Rig.FIELDS.size())
	for at: int in Rig.FIELDS.size():
		var members: Array[int] = []
		members.assign(_fields.fields()[at])
		assert_int(members[0]).is_equal(Rig.FIELDS[at][0])  # The lowest cell comes first.
		assert_array(members).contains_exactly_in_any_order(Rig.FIELDS[at])


func test_a_row_end_and_the_next_row_start_are_no_neighbours_and_fields_keep_their_numbers(
) -> void:
	# Cells 7 and 8 follow each other in the numbering but sit at opposite ends of two rows.
	_build(Rig.scenario(PackedStringArray([".......o", "o.......", "...o....", "....o..."])))
	var members: Array[Array] = []
	for field: PackedInt32Array in _fields.fields():
		members.append(Array(field))
	# Fields are numbered by their lowest cell: 7, 8, then 19 with its corner neighbour 28.
	assert_array(members).contains_exactly([[0], [1], [2, 3]])
	assert_array(_fields.wellhead_cells()).contains_exactly([7, 8, 19])


func test_each_field_has_one_wellhead_on_the_cell_nearest_its_middle() -> void:
	assert_array(_fields.wellhead_cells()).contains_exactly(Rig.WELLHEADS)
	for at: int in Rig.FIELDS.size():  # And it is a cell of its own field.
		var cells: Array[int] = []
		for index: int in Rig.FIELDS[at]:
			cells.append(Rig.ORE_CELLS[index])
		assert_array(cells).contains([_fields.wellhead_cells()[at]])


func test_every_ore_cell_starts_full_with_the_oil_stage_tile_written_once() -> void:
	assert_int(_fields.write_count()).is_equal(9)
	for index: int in 9:
		var cell: int = Rig.ORE_CELLS[index]
		var at: Vector2i = Vector2i(cell % Rig.COLS, cell / Rig.COLS)
		assert_int(_stage(index)).is_equal(0)
		assert_that(_fields.get_cell_atlas_coords(at)).is_equal(_ground.atlas().coords(&"oil_full"))
	assert_int(_fields.get_used_cells().size()).is_equal(9)
	# Quiet frames write nothing: the layer looks again only for a new tick.
	for _i: int in 3:
		await await_idle_frame()
	assert_int(_fields.write_count()).is_equal(9)


func test_a_cell_shows_full_half_or_dry_at_the_thresholds_and_climbs_back() -> void:
	# Ore indexes 0 to 4 hold 14, 13, 7, 6 and 0 of 20: full, half, half, dry, dry.
	await _set_ore([14, 13, 7, 6, 0])
	var keys: Array[StringName] = [&"oil_full", &"oil_half", &"oil_half", &"oil_dry", &"oil_dry"]
	for index: int in 5:
		assert_that(_tile_at(index)).is_equal(_ground.atlas().coords(keys[index]))
	assert_int(_fields.write_count()).is_equal(9 + 4)  # Index 0 stayed full: four changes.
	# The rest is as it was, and a regrown cell climbs back.
	assert_that(_tile_at(5)).is_equal(_ground.atlas().coords(&"oil_full"))
	await _set_ore([20, 20, 20, 7, 14])
	assert_int(_stage(0)).is_equal(0)
	assert_int(_stage(1)).is_equal(0)
	assert_int(_stage(2)).is_equal(0)
	assert_int(_stage(3)).is_equal(1)
	assert_int(_stage(4)).is_equal(0)


func test_only_a_changed_stage_is_written_and_a_tick_with_no_change_writes_nothing() -> void:
	await _set_ore([12, 13, 14])  # Half, half, full: one change in three, the first two.
	assert_int(_fields.write_count()).is_equal(9 + 2)
	await _set_ore([11, 10, 9])  # Still half, half, half: only the third changes.
	assert_int(_fields.write_count()).is_equal(9 + 2 + 1)
	_runner.run_ticks(3)  # Ticks that change no amount.
	await await_idle_frame()
	assert_int(_fields.write_count()).is_equal(9 + 2 + 1)


func test_the_most_a_cell_holds_is_the_scenarios_rule_and_not_a_number_of_the_layer() -> void:
	_build(Rig.scenario(Rig.ROWS, 30))  # A rule of 30: 20 is two thirds, which is half, and 10 dry.
	await _set_ore([20, 10])
	assert_int(_stage(0)).is_equal(1)
	assert_int(_stage(1)).is_equal(2)
	_build(Rig.scenario(Rig.ROWS, 0))  # No rules: the script defaults, ore_cell_max 20.
	await _set_ore([20, 10])
	assert_int(_stage(0)).is_equal(0)
	assert_int(_stage(1)).is_equal(1)


func test_the_kind_of_a_field_comes_from_one_lookup_that_says_oil_by_default() -> void:
	var asked: Array[int] = []
	_build(
		Rig.scenario(),
		func(field: int) -> StringName:
			asked.append(field)
			return &"gas" if field == 1 else &"oil"
	)
	assert_array(asked).contains_exactly([0, 1, 2])  # Each field once, by its number.
	assert_that(_tile_at(0)).is_equal(_ground.atlas().coords(&"oil_full"))  # The 2 x 2 field.
	assert_that(_tile_at(2)).is_equal(_ground.atlas().coords(&"gas_full"))  # The lone cell 15.
	assert_that(_tile_at(6)).is_equal(_ground.atlas().coords(&"oil_full"))  # The line.
	await _set_ore([20, 20, 5])  # The gas cell steps down in gas, the others are untouched.
	assert_that(_tile_at(2)).is_equal(_ground.atlas().coords(&"gas_dry"))
	# Without a lookup of its own every field is oil, until the map names its kinds (plan P79).
	_build(Rig.scenario())
	for index: int in 9:
		assert_that(_tile_at(index)).is_equal(_ground.atlas().coords(&"oil_full"))


func test_a_wellhead_and_its_shadow_stand_at_the_cell_centre_from_the_one_page() -> void:
	var props: Array[Node] = _props()
	assert_int(props.size()).is_equal(6)  # Three shadows, then three bodies.
	var props_node: Node2D = props[0].get_parent() as Node2D
	assert_int(props_node.z_index).is_equal(FieldLayer.Z_PROPS)  # With the decals, at z 1,
	assert_bool(props_node.z_as_relative).is_false()  # whatever the parents' z.
	for at: int in 3:
		var cell: int = Rig.WELLHEADS[at]
		var centre: Vector2 = IsoProjection.cell_centre_px(cell % Rig.COLS, cell / Rig.COLS)
		for kind: int in 2:  # 0 the shadow, 1 the body: the shadows first, so a body is on top.
			var sprite: Sprite2D = props[kind * 3 + at] as Sprite2D
			var key: StringName = GroundAtlas.WELLHEAD_SHADOW if kind == 0 else GroundAtlas.WELLHEAD
			assert_object(sprite.texture).is_same(_ground.atlas().texture())
			assert_bool(sprite.region_enabled).is_true()
			assert_that(sprite.region_rect).is_equal(Rect2(_ground.atlas().region(key)))
			assert_bool(sprite.centered).is_false()
			# The anchor of the picture lands on the cell's centre: the picture hangs by its anchor.
			assert_that(sprite.offset).is_equal(-GroundAtlas.ANCHORS[key])
			assert_that(sprite.global_position).is_equal_approx(centre, Vector2(0.001, 0.001))
			assert_that(sprite.modulate).is_equal(Color.WHITE)
	assert_that(GroundAtlas.ANCHORS[GroundAtlas.WELLHEAD]).is_equal(Vector2(28, 44))
	assert_that(GroundAtlas.ANCHORS[GroundAtlas.WELLHEAD_SHADOW]).is_equal(Vector2(28, 15.5))


func test_the_ground_the_stages_and_the_props_are_one_texture() -> void:
	var page: ImageTexture = _ground.atlas().texture()
	assert_object((_ground.tile_set.get_source(0) as TileSetAtlasSource).texture).is_same(page)
	assert_object(_fields.tile_set).is_same(_ground.tile_set)  # The stages use the ground's set.
	for sprite: Node in _props():
		assert_object((sprite as Sprite2D).texture).is_same(page)


func test_a_new_match_stands_its_own_fields_and_frees_the_old_wellheads() -> void:
	var old: Array[Node] = _props()
	assert_int(old.size()).is_equal(6)
	_runner.scenario = Rig.scenario(PackedStringArray(["...", ".o."]))
	_runner.start()
	await await_idle_frame()
	assert_int(_fields.fields().size()).is_equal(1)
	assert_int(_props().size()).is_equal(2)
	assert_int(_fields.get_used_cells().size()).is_equal(1)
	assert_bool(is_instance_valid(old[0])).is_false()
	_runner.scenario = Rig.scenario(PackedStringArray(["...", "..."]))  # No ore at all.
	_runner.start()
	await await_idle_frame()
	assert_int(_fields.fields().size()).is_equal(0)
	assert_int(_props().size()).is_equal(0)
	assert_int(_fields.get_used_cells().size()).is_equal(0)


func _build(scenario: ScenarioDef, kind_of: Callable = Callable()) -> void:
	if is_instance_valid(_ground):
		_ground.free()
	if is_instance_valid(_runner):
		_runner.free()
	_runner = auto_free(Rig.runner(scenario))
	_runner.run_ticks(1)  # Past tick 0, whose regrowth would add 1 to every cell below the most.
	_ground = auto_free(GroundLayer.new())
	_ground.runner = _runner
	_fields = _ground.get_node("Fields")
	if kind_of.is_valid():
		_fields.kind_of = kind_of
	add_child(_ground)


## Puts `amounts` into the first ore cells of the World, plays a tick and lets the layer look.
func _set_ore(amounts: Array[int]) -> void:
	for index: int in amounts.size():
		_runner.world.ore_amount[index] = amounts[index]
	_runner.run_ticks(1)
	await await_idle_frame()


## The atlas coordinates of the stage tile on ore cell `index`.
func _tile_at(index: int) -> Vector2i:
	var cell: int = Rig.ORE_CELLS[index]
	return _fields.get_cell_atlas_coords(Vector2i(cell % Rig.COLS, cell / Rig.COLS))


## The wellhead sprites: the shadows first, then the bodies.
func _props() -> Array[Node]:
	return _fields.get_node("Props").get_children()


## The stage (0 full, 1 half, 2 dry) of the tile on ore cell `index`, -1 for none or another tile.
func _stage(index: int) -> int:
	for stage: int in GroundAtlas.STAGES.size():
		var key: StringName = StringName("oil_%s" % GroundAtlas.STAGES[stage])
		if _tile_at(index) == _ground.atlas().coords(key):
			return stage
	return -1
