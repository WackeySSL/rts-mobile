extends GdUnitTestSuite
## The terrain kit (plan row P656c, ADR 0053 sections 7 and 9), headless: completeness against
## the sim's terrains and the mask table, the sizes (ground 128 x 64, wall pieces the 128 x 136
## canvas inside the raised prism plus its rim), the light order on the wall faces, no key-band
## pixel, the byte budget, the page budget and the manifest. The look is Michael's (P659), not
## tested.

const KIT: String = "res://assets/art/terrain/kit.tres"
const TERRAINS: String = "res://data/terrain/standard.tres"
const PAGE_WIDTH: int = 4096  ## ADR 0053 section 7: the ground page is at most 512 rows of 4096 px.
const PAGE_ROWS: int = 512
const GUTTER: int = 2  ## What the atlas keeps between two pieces, px.
const WALL_KINDS: Array[StringName] = [&"wall_top", &"wall_face", &"wall_rim"]


func _kit() -> TerrainKitDef:
	return load(KIT) as TerrainKitDef


func _sim() -> TerrainSetDef:
	return load(TERRAINS) as TerrainSetDef


func _image(path: String) -> Image:
	var image: Image = Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return image


func _is_wall(item: Array) -> bool:
	return item[1] in WALL_KINDS


## Every piece the kit lists as [terrain, kind, mask, path].
func _all(kit: TerrainKitDef) -> Array[Array]:
	var found: Array[Array] = []
	for terrain: StringName in kit.terrains:
		for kind: StringName in kit.kinds[terrain]:
			for mask: StringName in kit.masks[kind]:
				found.append([terrain, kind, mask, kit.path_of(terrain, kind, mask)])
	return found


func test_every_sim_terrain_has_all_its_base_variants() -> void:
	var kit: TerrainKitDef = _kit()
	for terrain: TerrainDef in _sim().terrains:
		assert_bool(kit.terrains.has(String(terrain.id))).is_true()
		for variant: int in kit.variants:
			assert_str(kit.path_of(terrain.id, &"base", StringName(str(variant)))).is_not_empty()
	assert_int(kit.variants).is_equal(4)


func test_every_mask_of_the_table_has_a_piece_that_exists() -> void:
	var kit: TerrainKitDef = _kit()
	var count: int = 0
	for item: Array in _all(kit):
		(
			assert_bool(FileAccess.file_exists(item[3]))
			. override_failure_message(
				"%s/%s/%s: no file at '%s'" % [item[0], item[1], item[2], item[3]]
			)
			. is_true()
		)
		count += 1
	assert_int(kit.masks[&"blend"].size()).is_equal(8)
	assert_bool(kit.masks.has(&"lip")).is_false()
	assert_int(kit.masks[&"wall_top"].size()).is_equal(4)
	assert_array(kit.masks[&"wall_face"]).is_equal(PackedStringArray(["se", "sw", "s"]))
	assert_array(kit.masks[&"wall_rim"]).is_equal(PackedStringArray(["ne", "nw", "n", "inner_n"]))
	assert_array(kit.kinds[&"rock"]).is_equal(
		PackedStringArray(["base", "wall_top", "wall_face", "wall_rim"])
	)
	assert_int(kit.masks[&"shore"].size()).is_equal(12)
	assert_int(count).is_equal(kit.pieces.size())


func test_no_png_in_the_kit_folder_is_unlisted() -> void:
	var kit: TerrainKitDef = _kit()
	var listed: PackedStringArray = PackedStringArray()
	for file: String in kit.pieces.values():
		listed.append(file)
	for file: String in DirAccess.get_files_at(kit.dir):
		if file.ends_with(".png"):
			(
				assert_bool(listed.has(file))
				. override_failure_message(file + " is not in kit.tres")
				. is_true()
			)


func test_ground_pieces_are_128_x_64_and_wall_pieces_the_128_x_136_canvas() -> void:
	for item: Array in _all(_kit()):
		var size: Vector2i = _image(item[3]).get_size()
		var want: Vector2i = TerrainKitDef.WALL_CANVAS if _is_wall(item) else TerrainKitDef.TILE
		(
			assert_vector(Vector2(size))
			. override_failure_message("%s is %s, not %s" % [item[3], size, want])
			. is_equal(Vector2(want))
		)
		if _is_wall(item):
			assert_str(String(item[0])).is_equal("rock")  # only rock rises: it blocks every move class


func test_the_wall_canvas_is_the_diamond_the_rise_and_the_rim() -> void:
	assert_int(TerrainKitDef.RISE_MAX).is_equal(64)
	assert_int(TerrainKitDef.RIM_MAX).is_equal(8)
	var canvas: Vector2i = TerrainKitDef.WALL_CANVAS
	assert_int(canvas.x).is_equal(TerrainKitDef.TILE.x)
	assert_int(canvas.y).is_equal(
		TerrainKitDef.TILE.y + TerrainKitDef.RISE_MAX + TerrainKitDef.RIM_MAX
	)
	# The ground centre lies a half diamond above the canvas's foot.
	assert_vector(Vector2(TerrainKitDef.WALL_ORIGIN)).is_equal(
		Vector2(64, canvas.y - TerrainKitDef.TILE.y / 2)
	)


## How far texel (x, y) lies above the raised prism's silhouette, texels (0 or less: inside). The
## prism's hexagon runs from the top diamond's apex (64, 8) to the ground diamond's foot (64, 136).
func _over_prism(x: int, y: int) -> float:
	var slant: float = absf(float(x) + 0.5 - 64.0) * 0.5
	return (8.0 + slant) - (float(y) + 0.5)


func test_a_wall_piece_stays_inside_the_prism_and_its_rim() -> void:
	for item: Array in _all(_kit()):
		if not _is_wall(item):
			continue
		var image: Image = _image(item[3])
		var most: float = -999.0
		for y: int in image.get_height():
			for x: int in image.get_width():
				if image.get_pixel(x, y).a > 0.0:
					most = maxf(most, _over_prism(x, y))
					var below: float = float(y) + 0.5 - (136.0 - absf(float(x) + 0.5 - 64.0) * 0.5)
					(
						assert_float(below)
						. override_failure_message(
							"%s: texel (%d, %d) is below the prism" % [item[3], x, y]
						)
						. is_less_equal(0.5)
					)
		(
			assert_float(most)
			. override_failure_message("%s lies %.1f texels over the prism" % [item[3], most])
			. is_less_equal(float(TerrainKitDef.RIM_MAX) + 0.5)
		)


## The mean HSV value of the opaque texels.
func _value(path: String) -> float:
	var image: Image = _image(path)
	var total: float = 0.0
	var count: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			if c.a > 0.9:
				total += c.v
				count += 1
	return total / maxi(count, 1)


func test_the_faces_are_lit_from_the_left_and_darker_than_the_top_on_the_right() -> void:
	var kit: TerrainKitDef = _kit()
	var top: float = _value(kit.path_of(&"rock", &"wall_top", &"0"))
	var sw: float = _value(kit.path_of(&"rock", &"wall_face", &"sw"))
	var se: float = _value(kit.path_of(&"rock", &"wall_face", &"se"))
	assert_float(sw).is_greater(se + 0.08)
	assert_float(se).is_less(top)
	assert_float(sw).is_between(0.40, 0.52)  # P653's cliff face: about 0.45 to 0.48
	assert_float(se).is_between(0.28, 0.42)


func test_no_pixel_of_the_kit_is_in_the_key_band() -> void:
	for item: Array in _all(_kit()):
		var image: Image = _image(item[3])
		var bad: int = 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				var c: Color = image.get_pixel(x, y)
				if c.a > 0.0 and c.s >= ArtPalette.BAND_SATURATION:
					var gap: float = absf(c.h * 360.0 - 300.0)
					bad += 1 if minf(gap, 360.0 - gap) <= ArtPalette.BAND_DEGREES else 0
		(
			assert_int(bad)
			. override_failure_message("%s: %d key-band pixels" % [item[3], bad])
			. is_zero()
		)


func test_the_kit_files_total_at_most_five_megabytes() -> void:
	var total: int = 0
	for item: Array in _all(_kit()):
		total += FileAccess.get_file_as_bytes(item[3]).size()
	assert_int(total).is_less_equal(5 * 1024 * 1024)


func test_the_kit_packs_into_at_most_512_rows_of_4096_px() -> void:
	var sizes: Array[Vector2i] = []
	for item: Array in _all(_kit()):
		if not _is_wall(item):  # the wall pieces are packed on the sorted page (P656d2)
			sizes.append(_image(item[3]).get_size() + Vector2i(GUTTER, GUTTER))
	sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	var rows: int = 0
	var x: int = 0
	var row_height: int = 0
	for size: Vector2i in sizes:
		if x + size.x > PAGE_WIDTH:
			rows += row_height
			x = 0
			row_height = 0
		x += size.x
		row_height = maxi(row_height, size.y)
	rows += row_height
	assert_int(rows).is_less_equal(PAGE_ROWS)


func test_the_manifest_lists_every_kit_png_with_its_model() -> void:
	var manifest: ArtManifest = ArtManifest.read()
	var paths: PackedStringArray = PackedStringArray()
	for line: String in manifest.entries:
		var fields: PackedStringArray = line.split("|")
		paths.append(fields[0])
		if fields[0].begins_with(manifest.kit_dir):
			assert_str(fields[4]).contains("assets/art/models/terrain/").contains("_detail.tres=")
	for item: Array in _all(_kit()):
		(
			assert_bool(paths.has(item[3]))
			. override_failure_message(item[3] + " is not in the manifest")
			. is_true()
		)
	(
		assert_array(
			manifest.problems(ArtManifest.OWNED, func(p: String) -> IsoSheetDef: return load(p))
		)
		. is_empty()
	)


func test_the_sheet_generator_reads_no_detail_model_as_an_art_model() -> void:
	var paths: Array[String] = ArtGen.model_paths()
	assert_array(paths).is_not_empty()
	for path: String in paths:
		assert_str(path).not_contains("_detail.tres").not_contains("/terrain/")
		assert_object(load(path) as ArtModel).is_not_null()


## A five by five patch of one base piece, every texel inside the patch's outline (less a margin) is
## opaque: no pinhole at any of the interior vertices where four tiles meet.
func test_the_ground_leaves_no_pinhole_where_four_tiles_meet() -> void:
	var kit: TerrainKitDef = _kit()
	var n: int = 5
	var canvas: Image = Image.create((n + 2) * 128, n * 64 + 64, false, Image.FORMAT_RGBA8)
	for terrain: String in kit.terrains:
		var tile: Image = _image(kit.path_of(StringName(terrain), &"base", &"0"))
		canvas.fill(Color(0, 0, 0, 0))
		for r: int in n:
			for c: int in n:
				canvas.blend_rect(
					tile,
					Rect2i(Vector2i.ZERO, tile.get_size()),
					Vector2i((c - r) * 64 + n * 64, (c + r) * 32)
				)
		var holes: int = 0
		var centre: Vector2 = Vector2((n + 1) * 64.0, n * 32.0)
		for y: int in canvas.get_height():
			for x: int in canvas.get_width():
				var s: float = (
					absf(float(x) + 0.5 - centre.x) / (n * 64.0)
					+ absf(float(y) + 0.5 - centre.y) / (n * 32.0)
				)
				if s < 0.85 and canvas.get_pixel(x, y).a < 1.0:
					holes += 1
		(
			assert_int(holes)
			. override_failure_message("%s tiles leave %d holes" % [terrain, holes])
			. is_zero()
		)


## The baked contact shadow must stay clear of the diamond's edge (within 3 texels): a texel there,
## half transparent and near black, reads over a neighbouring cell as a dashed seam line. The shadow
## band's alpha is 0.35 (stored as 89 of 255), so the test counts from 0.3, and a shadow
## texel is near black (channels summing under 60 of 255; a piece's own dark brown edge texels are
## above it).
func test_no_blend_or_shore_has_a_shadow_texel_at_the_diamond_edge() -> void:
	for item: Array in _all(_kit()):
		if item[1] != &"blend" and item[1] != &"shore":
			continue
		var image: Image = _image(item[3])
		var bad: int = 0
		for y: int in 64:
			for x: int in 128:
				var s: float = absf(x + 0.5 - 64.0) / 64.0 + absf(y + 0.5 - 32.0) / 32.0
				var c: Color = image.get_pixel(x, y)
				if (1.0 - s) * 28.6 <= 3.0 and c.a >= 0.3 and c.a <= 200.0 / 255.0:
					bad += 1 if c.r + c.g + c.b < 60.0 / 255.0 else 0
		(
			assert_int(bad)
			. override_failure_message("%s: %d shadow texels at the edge" % [item[3], bad])
			. is_zero()
		)
