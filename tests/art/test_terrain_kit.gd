extends GdUnitTestSuite
## The terrain kit (plan row P656c, ADR 0053 sections 7 and 9), headless: completeness against
## the sim's terrains and the mask table, the sizes and the lip rule, no key-band pixel, the byte
## budget, the page budget and the manifest. The look is Michael's (P659), not tested.

const KIT: String = "res://assets/art/terrain/kit.tres"
const TERRAINS: String = "res://data/terrain/standard.tres"
const PAGE_WIDTH: int = 4096  ## ADR 0053 section 7: the ground page is at most 512 rows of 4096 px.
const PAGE_ROWS: int = 512
const GUTTER: int = 2  ## What the atlas keeps between two pieces, px.
## The kinds that may rise above their diamond: only over a cell that blocks every move class.
const RISING: Array[StringName] = [&"lip", &"shore"]


func _kit() -> TerrainKitDef:
	return load(KIT) as TerrainKitDef


func _sim() -> TerrainSetDef:
	return load(TERRAINS) as TerrainSetDef


func _image(path: String) -> Image:
	var image: Image = Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return image


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
	assert_int(kit.masks[&"lip"].size()).is_equal(12)
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


func test_every_piece_is_128_wide_and_64_to_100_tall_and_only_lips_and_shores_rise() -> void:
	var kit: TerrainKitDef = _kit()
	var cost_zero: Dictionary = {}
	for terrain: TerrainDef in _sim().terrains:
		cost_zero[terrain.id] = terrain.cost == PackedInt32Array([0, 0, 0])
	for item: Array in _all(kit):
		var size: Vector2i = _image(item[3]).get_size()
		assert_int(size.x).is_equal(TerrainKitDef.TILE.x)
		var rise: int = size.y - TerrainKitDef.TILE.y
		(
			assert_bool(rise >= 0 and rise <= TerrainKitDef.RISE_MAX)
			. override_failure_message("%s is %s: a lip rises at most 36 texels" % [item[3], size])
			. is_true()
		)
		if rise > 0:
			(
				assert_bool(item[1] in RISING and cost_zero[item[0]])
				. override_failure_message(
					"%s rises %d over a cell a unit can enter" % [item[3], rise]
				)
				. is_true()
			)


func test_a_lip_stands_but_stays_under_the_rise_limit() -> void:
	var kit: TerrainKitDef = _kit()
	var tallest: int = 0
	for item: Array in _all(kit):
		if item[1] == &"lip":
			tallest = maxi(tallest, _image(item[3]).get_height() - TerrainKitDef.TILE.y)
	assert_int(tallest).is_between(12, TerrainKitDef.RISE_MAX)


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
