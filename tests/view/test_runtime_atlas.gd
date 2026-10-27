extends GdUnitTestSuite
## The runtime atlas helper (plan P113, from the shelved P84; ADR 0023 section 2): sources are put
## into one RGBA8 image, packed in rows, each with a 2 px gutter that repeats its own edge pixels,
## and every region is the source's pixels at the source's size. Read from `image()`, the CPU side;
## the ImageTexture reads back stale after an update. `build` takes imported textures (the ground,
## P116), `build_images` images (the sorted world's frames, `IsoAtlas`).

const RED: Color = Color(1.0, 0.0, 0.0, 1.0)
const GREEN: Color = Color(0.0, 1.0, 0.0, 1.0)
const BLUE: Color = Color(0.0, 0.0, 1.0, 1.0)
const CLEAR: Color = Color(0.0, 0.0, 0.0, 0.0)
const GUTTER: int = RuntimeAtlas.GUTTER_PX


func test_the_regions_hold_each_source_at_its_own_size_in_rows_with_a_gutter_round_each() -> void:
	var atlas: RuntimeAtlas = RuntimeAtlas.build(
		{&"a": _solid(10, 6, RED), &"b": _solid(8, 8, GREEN), &"c": _solid(20, 4, BLUE)}, 30
	)
	# Cells of 14 x 10, 12 x 12 and 24 x 8: a and b share the first row (26 wide), c starts a new one.
	assert_that(atlas.region(&"a")).is_equal(Rect2i(2, 2, 10, 6))
	assert_that(atlas.region(&"b")).is_equal(Rect2i(16, 2, 8, 8))
	assert_that(atlas.region(&"c")).is_equal(Rect2i(2, 14, 20, 4))
	assert_that(atlas.image().get_size()).is_equal(Vector2i(30, 20))
	assert_int(atlas.image().get_format()).is_equal(Image.FORMAT_RGBA8)
	assert_object(atlas.texture()).is_not_null()
	assert_that(atlas.texture().get_size()).is_equal(Vector2(30, 20))
	for key: StringName in [&"a", &"b", &"c"]:
		var region: Rect2i = atlas.region(key)
		var want: Color = {&"a": RED, &"b": GREEN, &"c": BLUE}[key]
		for corner: Vector2i in [region.position, region.end - Vector2i.ONE]:
			assert_that(atlas.image().get_pixelv(corner)).is_equal(want)


func test_a_key_the_atlas_does_not_hold_has_no_region_and_an_empty_set_has_no_texture() -> void:
	var atlas: RuntimeAtlas = RuntimeAtlas.build({&"a": _solid(4, 4, RED)})
	assert_bool(atlas.has_region(&"a")).is_true()
	assert_bool(atlas.has_region(&"b")).is_false()
	assert_that(atlas.region(&"b")).is_equal(Rect2i())
	var empty: RuntimeAtlas = RuntimeAtlas.build({})
	assert_object(empty.texture()).is_null()
	assert_bool(empty.has_region(&"a")).is_false()
	assert_bool(empty.image().is_empty()).is_true()


func test_the_gutter_repeats_the_edge_pixels_of_a_region_corners_included() -> void:
	var source: Image = Image.create(3, 2, false, Image.FORMAT_RGBA8)
	var colors: Array[Color] = [RED, GREEN, BLUE, Color.WHITE, Color.BLACK, Color.YELLOW]
	for index: int in colors.size():
		source.set_pixel(index % 3, index / 3, colors[index])
	var atlas: RuntimeAtlas = RuntimeAtlas.build({&"s": ImageTexture.create_from_image(source)})
	var region: Rect2i = atlas.region(&"s")
	var image: Image = atlas.image()
	for step: int in GUTTER:
		for x: int in range(-GUTTER, 3 + GUTTER):  # The rows above and below, corners included.
			var at: int = clampi(x, 0, 2)
			(
				assert_that(image.get_pixel(region.position.x + x, region.position.y - 1 - step))
				. is_equal(source.get_pixel(at, 0))
			)
			assert_that(image.get_pixel(region.position.x + x, region.end.y + step)).is_equal(
				source.get_pixel(at, 1)
			)
		for y: int in 2:  # The columns left and right.
			(
				assert_that(image.get_pixel(region.position.x - 1 - step, region.position.y + y))
				. is_equal(source.get_pixel(0, y))
			)
			assert_that(image.get_pixel(region.end.x + step, region.position.y + y)).is_equal(
				source.get_pixel(2, y)
			)
	# Past the gutter nothing is written.
	assert_that(image.get_pixel(region.position.x + 3 + GUTTER, region.position.y)).is_equal(CLEAR)


func test_a_transparent_edge_repeats_transparent_pixels_and_never_a_neighbours() -> void:
	var edged: Image = Image.create(6, 6, false, Image.FORMAT_RGBA8)
	edged.fill_rect(Rect2i(1, 1, 4, 4), RED)  # A one pixel clear border round a red square.
	var atlas: RuntimeAtlas = RuntimeAtlas.build(
		{&"edged": ImageTexture.create_from_image(edged), &"next": _solid(6, 6, GREEN)}, 40
	)
	var region: Rect2i = atlas.region(&"edged")
	var image: Image = atlas.image()
	for step: int in GUTTER:
		for y: int in 6:  # The columns on both sides of the sprite are clear, not green.
			(
				assert_that(image.get_pixel(region.position.x - 1 - step, region.position.y + y))
				. is_equal(CLEAR)
			)
			assert_that(image.get_pixel(region.end.x + step, region.position.y + y)).is_equal(CLEAR)


func test_a_source_that_is_not_rgba8_comes_out_as_rgba8() -> void:
	var grey: Image = Image.create(4, 4, false, Image.FORMAT_L8)
	grey.fill(Color(0.5, 0.5, 0.5, 1.0))
	var atlas: RuntimeAtlas = RuntimeAtlas.build({&"grey": ImageTexture.create_from_image(grey)})
	assert_int(atlas.image().get_format()).is_equal(Image.FORMAT_RGBA8)
	var texel: Color = atlas.image().get_pixelv(atlas.region(&"grey").position)
	assert_int(texel.a8).is_equal(255)
	assert_int(texel.r8).is_equal(texel.g8)
	assert_int(texel.r8).is_between(126, 129)


func test_a_cell_wider_than_the_atlas_widens_it_and_the_sources_keep_their_order() -> void:
	var atlas: RuntimeAtlas = RuntimeAtlas.build(
		{&"wide": _solid(40, 2, RED), &"small": _solid(2, 2, GREEN)}, 16
	)
	assert_that(atlas.region(&"wide").position).is_equal(Vector2i(2, 2))
	assert_int(atlas.image().get_width()).is_equal(44)
	assert_int(atlas.region(&"small").position.y).is_greater(atlas.region(&"wide").end.y)


func test_the_imported_textures_are_copied_whole_at_their_own_size() -> void:
	var paths: Dictionary[StringName, String] = {
		&"ellipse": "res://assets/art/svg/ui/selection_ellipse.svg",
		&"seen": "res://assets/art/svg/ui/ghost_seen.svg",
		&"hatch": "res://assets/art/svg/ui/ghost_hatch.svg",
	}
	var sources: Dictionary[StringName, Texture2D] = {}
	for key: StringName in paths:
		sources[key] = load(paths[key])
	var atlas: RuntimeAtlas = RuntimeAtlas.build(sources)
	for key: StringName in paths:
		var texture: Texture2D = sources[key]
		var region: Rect2i = atlas.region(key)
		assert_that(region.size).is_equal(Vector2i(texture.get_size()))
		var copy: Image = atlas.image().get_region(region)
		assert_that(copy.get_data()).is_equal(texture.get_image().get_data())
	# No two regions overlap, gutters included, and all lie inside the image.
	var cells: Array[Rect2i] = []
	for key: StringName in paths:
		cells.append(atlas.region(key).grow(GUTTER))
	for first: int in cells.size():
		(
			assert_bool(Rect2i(Vector2i.ZERO, atlas.image().get_size()).encloses(cells[first]))
			. is_true()
		)
		for second: int in range(first + 1, cells.size()):
			assert_bool(cells[first].intersects(cells[second])).is_false()
	assert_int(atlas.image().get_width()).is_equal(RuntimeAtlas.DEFAULT_WIDTH_PX)


func test_images_are_packed_as_given_and_the_cpu_page_is_dropped_on_request() -> void:
	var images: Dictionary[StringName, Image] = {
		&"a": _solid(10, 6, RED).get_image(), &"b": _solid(8, 8, GREEN).get_image()
	}
	var atlas: RuntimeAtlas = RuntimeAtlas.build_images(images, 30, false)
	assert_that(atlas.region(&"a")).is_equal(Rect2i(2, 2, 10, 6))
	assert_that(atlas.region(&"b")).is_equal(Rect2i(16, 2, 8, 8))
	assert_that(atlas.texture().get_size()).is_equal(Vector2(30, 12))
	assert_bool(atlas.image().is_empty()).is_true()
	var kept: RuntimeAtlas = RuntimeAtlas.build_images(images, 30)
	assert_that(kept.image().get_size()).is_equal(Vector2i(30, 12))
	assert_that(kept.image().get_pixel(2, 2)).is_equal(RED)


func test_an_image_that_is_null_or_empty_is_left_out_and_reported() -> void:
	var ok: Image = _solid(4, 4, RED).get_image()
	var made: Array[RuntimeAtlas] = []
	for bad: Image in [null, Image.new()]:
		var images: Dictionary[StringName, Image] = {&"bad": bad, &"ok": ok}
		await (
			assert_error(func() -> void: made.append(RuntimeAtlas.build_images(images)))
			. is_push_error("RuntimeAtlas: no image to read for bad")
		)
	assert_array(made).has_size(2)
	for atlas: RuntimeAtlas in made:
		assert_bool(atlas.has_region(&"ok")).is_true()
		assert_bool(atlas.has_region(&"bad")).is_false()


func test_the_layout_is_pure_shelves_in_the_given_order() -> void:
	var places: Array[Vector2i] = [Vector2i(9, 9)]  # Cleared first.
	var cells: Array[Vector2i] = [Vector2i(14, 10), Vector2i(12, 12), Vector2i(24, 8)]
	assert_that(RuntimeAtlas.layout(cells, 30, places)).is_equal(Vector2i(30, 20))
	assert_array(places).is_equal([Vector2i(0, 0), Vector2i(14, 0), Vector2i(0, 12)])
	# A cell wider than the width widens the page; no cells make a page of no height.
	assert_that(RuntimeAtlas.layout(cells, 20, places)).is_equal(Vector2i(24, 30))
	assert_that(RuntimeAtlas.layout([] as Array[Vector2i], 64, places)).is_equal(Vector2i(64, 0))
	assert_array(places).is_empty()
	assert_that(RuntimeAtlas.cell_size(Vector2i(10, 6))).is_equal(Vector2i(14, 10))


func _solid(width: int, height: int, color: Color) -> ImageTexture:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
