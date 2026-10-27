extends GdUnitTestSuite
## The decal layer (plan P115, ADR 0023 section 2): z 1, under the unit shadows, the rings and the
## fog, holding the building shadows (children of `Shadows`) and the craters (of `Craters`, after
## them, so a later shadow never splits the craters' batch), doing nothing in a frame. A crater is
## the art's ground circle (1500 milli) scaled to the radius it is given, and none is made without
## a texture. The real crater art is P105's `decals/crater.svg`; these cases use a stand-in.

var _layer: DecalLayer


func before_test() -> void:
	_layer = auto_free(DecalLayer.new())
	add_child(_layer)


func test_the_layer_is_at_z_1_absolute_with_the_shadows_before_the_craters() -> void:
	assert_int(_layer.z_index).is_equal(DecalLayer.Z_DECALS)
	assert_int(DecalLayer.Z_DECALS).is_equal(1)
	assert_bool(_layer.z_as_relative).is_false()
	(
		assert_array(_layer.get_children().map(func(n: Node) -> StringName: return n.name))
		. is_equal([&"Shadows", &"Craters"])
	)
	assert_bool(_layer.is_processing()).is_false()  # No work in a frame.
	assert_int(WorldSort.Z_SHADOW).is_greater(DecalLayer.Z_DECALS)  # Under the unit shadows.
	assert_int(WorldSort.Z_RING).is_greater(DecalLayer.Z_DECALS)


func test_shadows_come_and_go_by_the_calls_and_stay_before_the_craters() -> void:
	_layer.crater_texture = _stand_in()
	var first: Sprite2D = Sprite2D.new()
	_layer.add_shadow(first)
	assert_bool(_layer.add_crater(Vector2(10, 20), 1500)).is_true()
	var second: Sprite2D = Sprite2D.new()
	_layer.add_shadow(second)  # Added after the crater, drawn before it.
	assert_int(_layer.shadow_count()).is_equal(2)
	assert_int(_layer.crater_count()).is_equal(1)
	var order: Array[Node] = _layer.find_children("*", "Sprite2D", true, false)
	assert_array(order).is_equal([first, second, order[2]])
	assert_str(order[2].name).is_equal("Crater")
	_layer.remove_shadow(first)
	assert_int(_layer.shadow_count()).is_equal(1)
	assert_bool(first.is_queued_for_deletion()).is_true()
	_layer.clear()
	assert_int(_layer.shadow_count()).is_equal(0)
	assert_int(_layer.crater_count()).is_equal(0)


func test_a_crater_is_the_art_circle_scaled_to_its_radius_at_its_place() -> void:
	var texture: Texture2D = _stand_in()
	_layer.crater_texture = texture
	assert_bool(_layer.add_crater(Vector2(64, 32), 1500)).is_true()  # The art's own radius.
	assert_bool(_layer.add_crater(Vector2(-64, 96), 3000)).is_true()  # A rupture's, twice that.
	assert_bool(_layer.add_crater(Vector2(0, 0), 500)).is_true()  # A 1x1 building's.
	var craters: Array[Node] = _layer.find_children("*", "Sprite2D", true, false)
	assert_int(craters.size()).is_equal(3)
	var expected: Array[float] = [1.0, 2.0, 1.0 / 3.0]
	var at: Array[Vector2] = [Vector2(64, 32), Vector2(-64, 96), Vector2.ZERO]
	for index: int in 3:
		var crater: Sprite2D = craters[index]
		assert_object(crater.texture).is_same(texture)
		assert_that(crater.position).is_equal(at[index])
		assert_vector(crater.scale).is_equal_approx(
			Vector2.ONE * expected[index], Vector2(0.001, 0.001)
		)
		assert_bool(crater.centered).is_true()  # The art is anchored on the middle of the pit.
		assert_that(crater.modulate).is_equal(Color.WHITE)


func test_without_a_crater_texture_a_crater_is_not_drawn() -> void:
	_layer.crater_texture = null
	assert_bool(_layer.add_crater(Vector2.ZERO, 1500)).is_false()
	assert_int(_layer.crater_count()).is_equal(0)


func _stand_in() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(144, 72, false, Image.FORMAT_RGBA8))
