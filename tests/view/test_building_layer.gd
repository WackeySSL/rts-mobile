extends GdUnitTestSuite
## What BuildingLayer makes of the buildings of a snapshot (plan P115, ADR 0023 sections 2 and 3):
## one node in the sorted world per building row, standing at its projected footprint centre,
## whose Body is one sprite on the atlas with the footprint centre as its origin, a defence's Head,
## the cast shadow in the decal layer, and the rows they follow. The sort against units is in
## test_building_sort.gd, the fog in test_building_layer_fog.gd and the turning heads in
## test_building_layer_heads.gd. The runner is not in the tree: only the calls here move time.
## On a 32 x 32 map: the Derrick League's Headquarters (3x3), power plant (2x2) and Redoubt (1x1)
## for player 1 and the Lumen Accord's Headquarters (3x3) and defence (1x1) for player 2; the
## enemy buildings are shown (`reveal_enemies`) unless a case is about the fog.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 4, 4],
	[1, "power_plant", 10, 4],
	[1, "defence_turret", 14, 4],
	[2, "renew_hq", 4, 12],
	[2, "renew_defence", 10, 12],
]

var _runner: MatchRunner
var _layer: BuildingLayer


func after_test() -> void:
	CommandQueue.clear()


func test_a_building_is_a_node_in_the_sort_at_its_projected_footprint_centre() -> void:
	_open()
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(5)
	assert_int(_layer.building_count()).is_equal(5)
	assert_int(_layer.world_sort.get_child_count()).is_equal(5)
	for row: int in 5:
		var id: int = snap.unit_id[row]
		var node: Node2D = _layer.building(id)
		var size: int = snap.type_foot_w[snap.type_index[row]]
		var origin: Vector2i = Vector2i(SPAWNS[row][2], SPAWNS[row][3])
		assert_object(node.get_parent()).is_same(_layer.world_sort)
		assert_str(node.name).is_equal("Building%d" % id)
		# (c - r) * 32 across and (c + r + n) * 16 down: the footprint centre, the sort key.
		assert_that(node.position).is_equal(
			Vector2((origin.x - origin.y) * 32.0, (origin.x + origin.y + size) * 16.0)
		)
		assert_that(node.position).is_equal(
			IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		)
	assert_object(_layer.building(snap.unit_id[0] + 99)).is_null()  # No such building.
	assert_bool(_layer.world_sort.y_sort_enabled).is_true()


func test_the_footprint_of_a_row_is_its_origin_tile_and_its_side() -> void:
	_open()
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in 5:
		var size: int = snap.type_foot_w[snap.type_index[row]]
		var origin: Vector2i = Vector2i(SPAWNS[row][2], SPAWNS[row][3])
		# The position is the origin plus half the side, so the 2x2 and the 1x1 round the same way.
		assert_that(BuildingLayer.footprint_of(snap, row)).is_equal(
			Rect2i(origin.x, origin.y, size, size)
		)
	assert_array([_layer.is_shown(0), _layer.is_shown(4)]).is_equal([true, true])


func test_the_body_is_one_sprite_whose_back_corner_lies_16_n_px_above_the_centre() -> void:
	_open()
	var snap: MatchSnapshot = _runner.snapshot
	var atlas: IsoAtlas = _layer.world_sort.atlas
	for row: int in 5:
		var type: int = snap.type_index[row]
		var art_id: StringName = snap.type_ids[type]
		var size: int = snap.type_foot_w[type]
		var sheet: IsoSheetDef = _layer.world_sort.sheet(art_id)
		var node: Node2D = _layer.building(snap.unit_id[row])
		var bodies: Array[Node] = node.find_children("Body", "Sprite2D", false, false)
		assert_int(bodies.size()).override_failure_message(String(art_id)).is_equal(1)
		var body: Sprite2D = bodies[0]
		var slot: int = _layer.world_sort.slot_of(snap.owner[row])
		assert_object(body.texture).is_same(atlas.texture())
		assert_bool(body.region_enabled).is_true()
		assert_that(Rect2i(body.region_rect)).is_equal(atlas.region(art_id, &"hull", -1, slot))
		assert_bool(body.region_rect.has_area()).is_true()
		assert_that(body.position).is_equal(Vector2.ZERO)
		# The sprite draws at 0.5 px per px of the 2x art, over the bake scale, and its anchor, the
		# footprint's back corner, lands 16 n px above the node (Spec 03: the art's origin).
		assert_float(body.scale.x).is_equal_approx(0.5 / atlas.bake_scale(), 0.0001)
		var anchor: Vector2 = Vector2(sheet.anchor(&"hull"))
		var corner: Vector2 = (body.offset + anchor * atlas.bake_scale()) * body.scale
		assert_vector(corner).is_equal_approx(Vector2(0.0, -16.0 * size), Vector2(0.01, 0.01))


func test_a_defence_has_a_head_at_the_sheets_mount_and_no_other_building_has_one() -> void:
	_open()
	var snap: MatchSnapshot = _runner.snapshot
	var atlas: IsoAtlas = _layer.world_sort.atlas
	var heads: int = 0
	for row: int in 5:
		var id: int = snap.unit_id[row]
		var art_id: StringName = snap.type_ids[snap.type_index[row]]
		var sheet: IsoSheetDef = _layer.world_sort.sheet(art_id)
		var node: Node2D = _layer.building(id)
		if not sheet.has_part(&"head"):
			assert_object(Rig.head(_layer, id)).is_null()
			assert_int(Rig.head_frame(_layer, id)).is_equal(BuildingLayer.NO_FRAME)
			assert_array(_child_names(node)).is_equal([&"Body"])
			continue
		heads += 1
		var head: Sprite2D = Rig.head(_layer, id)
		var slot: int = _layer.world_sort.slot_of(snap.owner[row])
		assert_array(_child_names(node)).is_equal([&"Body", &"Head"])  # The head over the body.
		assert_object(head.get_parent()).is_same(node)
		assert_object(head.texture).is_same(atlas.texture())
		assert_that(head.position).is_equal(sheet.mount(6) * WorldSort.ART_SCALE)
		assert_that(head.position.y).is_less(0.0)  # Above the footprint centre.
		assert_that(Rect2i(head.region_rect)).is_equal(atlas.region(art_id, &"head", 6, slot))
		assert_int(Rig.head_frame(_layer, id)).is_equal(6)  # d06 faces grid east.
		# Its pivot is the sprite's origin: the anchor of the head canvas, whatever the bake scale.
		var anchor: Vector2 = Vector2(sheet.anchor(&"head"))
		assert_vector(head.offset + anchor * atlas.bake_scale()).is_equal_approx(
			Vector2.ZERO, Vector2(0.01, 0.01)
		)
	assert_int(heads).is_equal(2)  # The Redoubt and the Lumen Accord's defence.


func test_the_cast_shadow_is_a_sprite_of_the_decal_layer_at_the_footprint_centre() -> void:
	_open()
	var snap: MatchSnapshot = _runner.snapshot
	var atlas: IsoAtlas = _layer.world_sort.atlas
	var decals: DecalLayer = _layer.decals
	assert_int(decals.z_index).is_equal(1)
	assert_bool(decals.z_as_relative).is_false()
	assert_int(decals.shadow_count()).is_equal(5)
	for row: int in 5:
		var id: int = snap.unit_id[row]
		var type: int = snap.type_index[row]
		var art_id: StringName = snap.type_ids[type]
		var shadow: Sprite2D = Rig.shadow(_layer, id)
		var slot: int = _layer.world_sort.slot_of(snap.owner[row])
		assert_object(shadow.get_parent().get_parent()).is_same(decals)
		assert_object(shadow.texture).is_same(atlas.texture())
		assert_that(Rect2i(shadow.region_rect)).is_equal(atlas.region(art_id, &"shadow", -1, slot))
		assert_bool(shadow.region_rect.has_area()).is_true()
		assert_that(shadow.position).is_equal(_layer.building(id).position)
		assert_bool(shadow.visible).is_true()
		var sheet: IsoSheetDef = _layer.world_sort.sheet(art_id)
		var anchor: Vector2 = Vector2(sheet.anchor(&"shadow"))
		var corner: Vector2 = (shadow.offset + anchor * atlas.bake_scale()) * shadow.scale
		var size: int = snap.type_foot_w[type]
		assert_vector(corner).is_equal_approx(Vector2(0.0, -16.0 * size), Vector2(0.01, 0.01))
		# The shadow of a footprint is under every unit of the sort: the layer's z 1, the sort's 10.
		assert_bool(shadow.is_inside_tree()).is_true()
		assert_int(decals.z_index + shadow.z_index).is_less(WorldSort.Z_SORT)


func test_every_sprite_of_a_building_is_on_the_one_atlas_page_in_white() -> void:
	_open()
	var atlas: IsoAtlas = _layer.world_sort.atlas
	var sprites: Array[Node] = _layer.world_sort.find_children("*", "Sprite2D", true, false)
	sprites.append_array(_layer.decals.find_children("*", "Sprite2D", true, false))
	assert_int(sprites.size()).is_equal(5 + 5 + 2)  # Bodies, shadows and two heads.
	for node: Node in sprites:
		var sprite: Sprite2D = node
		var why: String = "%s of %s" % [sprite.name, sprite.get_parent().name]
		assert_object(sprite.texture).override_failure_message(why).is_same(atlas.texture())
		assert_that(sprite.modulate).override_failure_message(why).is_equal(Color.WHITE)
		assert_that(sprite.self_modulate).override_failure_message(why).is_equal(Color.WHITE)
		assert_object(sprite.material).override_failure_message(why).is_null()
		assert_bool(sprite.region_rect.has_area()).override_failure_message(why).is_true()
	# A Lumen Accord building and a Derrick League one are different regions of the same page, in
	# their owners' triads.
	var snap: MatchSnapshot = _runner.snapshot
	var own: Rect2i = atlas.region(snap.type_ids[snap.type_index[0]], &"hull", -1, 0)
	var enemy: Rect2i = atlas.region(snap.type_ids[snap.type_index[3]], &"hull", -1, 1)
	assert_bool(own.has_area() and enemy.has_area()).is_true()
	assert_bool(own != enemy).is_true()


func test_the_nodes_are_made_when_rows_version_moves_and_in_no_frame_between() -> void:
	_open()
	var snap: MatchSnapshot = _runner.snapshot
	var first: Node2D = _layer.building(snap.unit_id[0])
	assert_int(_layer.redraw_count()).is_equal(1)  # The match start.
	for _frame: int in 60:  # A second of frames, with a tick between some of them.
		snap.tick += 1 if _frame % 4 == 0 else 0
		_layer._process(1.0 / 60.0)
	assert_int(_layer.redraw_count()).is_equal(1)
	assert_object(_layer.building(snap.unit_id[0])).is_same(first)
	snap.rows_version += 1  # Another row appeared or left, not a building of ours.
	_layer._process(0.0)
	assert_int(_layer.redraw_count()).is_equal(2)
	assert_object(_layer.building(snap.unit_id[0])).is_same(first)  # Kept by id.
	assert_int(_layer.world_sort.get_child_count()).is_equal(5)
	assert_int(_layer.decals.shadow_count()).is_equal(5)
	_layer._process(0.0)
	assert_int(_layer.redraw_count()).is_equal(2)


func test_a_destroyed_building_loses_its_nodes_the_others_keep_theirs_and_a_crater_stays() -> void:
	_open()
	var crater: Texture2D = ImageTexture.create_from_image(
		Image.create(8, 4, false, Image.FORMAT_RGBA8)
	)
	_layer.decals.crater_texture = crater  # P105's art stands in.
	var snap: MatchSnapshot = _runner.snapshot
	var plant_id: int = snap.unit_id[1]
	var plant: Node2D = _layer.building(plant_id)
	var shadow: Sprite2D = Rig.shadow(_layer, plant_id)
	var kept: Node2D = _layer.building(snap.unit_id[2])
	_runner.world.hp[1] = 0  # The 2x2 power plant dies in the next tick.
	_runner.run_ticks(1)
	_layer._process(0.0)
	snap = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(4)
	assert_int(_layer.building_count()).is_equal(4)
	assert_object(_layer.building(plant_id)).is_null()
	assert_object(_layer.building(snap.unit_id[1])).is_same(kept)  # The Redoubt, one row up.
	assert_int(_layer.decals.shadow_count()).is_equal(4)
	assert_int(_layer.world_sort.get_child_count()).is_equal(4)
	await await_idle_frame()  # The freed nodes go.
	assert_bool(is_instance_valid(plant)).is_false()
	assert_bool(is_instance_valid(shadow)).is_false()
	# It was shown, so it left a crater of the 2x2 footprint's inscribed circle at its centre.
	assert_int(_layer.decals.crater_count()).is_equal(1)
	var mark: Sprite2D = _layer.decals.find_child("Crater", true, false)
	assert_that(mark.position).is_equal(IsoProjection.ground_to_px(11000, 5000))
	assert_vector(mark.scale).is_equal_approx(
		Vector2.ONE * (1000.0 / 1500.0), Vector2(0.001, 0.001)
	)
	assert_object(mark.texture).is_same(crater)


func test_a_new_match_makes_every_node_again_and_leaves_no_crater() -> void:
	_open()
	var snap: MatchSnapshot = _runner.snapshot
	_layer.decals.crater_texture = ImageTexture.create_from_image(
		Image.create(8, 4, false, Image.FORMAT_RGBA8)
	)
	var first: Node2D = _layer.building(snap.unit_id[0])
	_runner.start()  # The same scenario again: another match serial.
	_layer._process(0.0)
	assert_int(_layer.building_count()).is_equal(5)
	assert_object(_layer.building(_runner.snapshot.unit_id[0])).is_not_same(first)
	assert_int(_layer.world_sort.get_child_count()).is_equal(5)
	assert_int(_layer.decals.shadow_count()).is_equal(5)
	assert_int(_layer.decals.crater_count()).is_equal(0)
	assert_int(_layer.redraw_count()).is_equal(2)


func test_a_building_with_no_sheet_or_an_atlas_that_did_not_bake_is_a_flat_diamond_marker() -> void:
	var shed: BuildingDef = BuildingDef.new()  # A type with no sheet.
	shed.type_id = &"shed_test"
	shed.max_hp = 100
	shed.footprint = Vector2i(2, 2)
	var spawn: SpawnDef = Rig.spawn(2, "renew_defence", 10, 12)
	spawn.unit = shed
	_open_with([Rig.spawn(1, "headquarters", 4, 4), spawn])
	var snap: MatchSnapshot = _runner.snapshot
	var art: Node2D = _layer.building(snap.unit_id[0])
	assert_array(_child_names(art)).is_equal([&"Body"])
	var bare: Node2D = _layer.building(snap.unit_id[1])
	assert_array(_child_names(bare)).is_equal([&"Marker"])
	var marker: Node2D = bare.get_node("Marker")
	assert_str(marker.get_script().get_instance_base_type()).is_equal("Node2D")
	assert_that(marker.colour).is_equal(_layer.world_sort.mid_colour(2))
	assert_int(marker.foot).is_equal(2)
	assert_object(Rig.shadow(_layer, snap.unit_id[1])).is_null()
	assert_int(_layer.decals.shadow_count()).is_equal(1)
	assert_float(_layer.bar_lift_px(1)).is_equal(0.0)  # A flat diamond has no height.
	# An atlas that did not bake gives every building the marker, over sprites that show nothing.
	_layer.world_sort.atlas = IsoAtlas.new()
	_runner.start()
	_layer._process(0.0)
	for id: int in [1, 2]:
		assert_bool(_layer.building(id).has_node("Marker")).is_true()
	for sprite: Node in _layer.building(1).find_children("*", "Sprite2D", false, false):
		assert_object((sprite as Sprite2D).texture).is_null()


func _open() -> void:
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_open_with(spawns)


func _open_with(spawns: Array[SpawnDef]) -> void:
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	_layer.reveal_enemies = true
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func _child_names(node: Node) -> Array:
	return node.get_children().map(func(n: Node) -> StringName: return n.name)
