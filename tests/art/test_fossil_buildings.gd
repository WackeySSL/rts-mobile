extends GdUnitTestSuite
## The Derrick League's eight buildings (plan row P103, ADR 0023 sections 5 to 7, STYLE.md
## "Buildings"): the models that replaced P99's blockouts under the same art ids, and the frames and
## sheets they generate. It pins what the art row promises: every footprint square and the data's,
## one view and one cast shadow each and the Redoubt's 16 heads, the canvas of every frame and its
## anchor at the footprint's back corner (Spec 03), the height each type has in Spec 05, the team
## share of about a tenth, the dock and the exits where the data puts them, the open lattice of the
## Deep Bore and the Signal Mast (no solid spire, STYLE.md "Palette per faction"), eight silhouettes
## that read apart at 32 px in greyscale, and the emblem. That the frames are the generator's bytes,
## the key band and the shadows' rules are in test_artgen*.gd; the Build page is in
## test_art_gallery_build.gd.

const STYLE_PATH: String = "res://assets/art/STYLE.md"
const MODEL: String = "res://assets/art/models/fossil/%s.tres"
const EMBLEM: String = "res://assets/art/svg/icons/emblem_fossil.svg"
const Z_PX: float = 39.19183588453085  ## A tile of height at zoom 1 (ArtRender.Z_PX / 2).
const IDS: Array[StringName] = [
	&"headquarters",
	&"power_plant",
	&"refinery",
	&"barracks",
	&"vehicle_factory",
	&"fossil_radar",
	&"defence_turret",
	&"fossil_strike",
]
const FOOTPRINTS: Dictionary[StringName, int] = {
	&"headquarters": 3,
	&"power_plant": 2,
	&"refinery": 3,
	&"barracks": 2,
	&"vehicle_factory": 3,
	&"fossil_radar": 2,
	&"defence_turret": 1,
	&"fossil_strike": 3,
}
## The tallest point of each type in px at zoom 1, the band of Spec 05 ("Hovedkvarter, fabrik,
## supervaaben 80-150, raffinaderi 60-80, kraftvaerk, kaserne, radar 50-100, forsvarstaarn 40-60").
const HEIGHT_PX: Dictionary[StringName, Vector2] = {
	&"headquarters": Vector2(80, 150),
	&"vehicle_factory": Vector2(80, 150),
	&"fossil_strike": Vector2(80, 150),
	&"refinery": Vector2(60, 80),
	&"power_plant": Vector2(50, 100),
	&"barracks": Vector2(50, 100),
	&"fossil_radar": Vector2(50, 100),
	&"defence_turret": Vector2(40, 60),
}
## Canvas and anchor in px of the 2x art: hull width, hull height, hull anchor y, shadow width,
## shadow height. The anchor x is half the width, the shadow's anchor is the same back corner at
## the top of its canvas. When the art changes on purpose, run `bash scripts/gen-art.sh` and read
## the new numbers from the sheets.
const CANVAS: Dictionary[StringName, Array] = {
	&"headquarters": [384, 382, 190, 384, 194],
	&"power_plant": [256, 252, 123, 256, 130],
	&"refinery": [384, 294, 102, 444, 194],
	&"barracks": [256, 200, 72, 268, 130],
	&"vehicle_factory": [384, 346, 153, 406, 196],
	&"fossil_radar": [256, 302, 173, 298, 130],
	&"defence_turret": [128, 130, 65, 164, 84],
	&"fossil_strike": [384, 362, 170, 394, 198],
}
## The team share of a default view, about a tenth (STYLE.md "Light"; the generator's own pin is 3
## to 20 %).
const SHARE: Vector2 = Vector2(0.07, 0.13)
const KEY_TOLERANCE: float = 0.06
const SCALE: float = 0.5  ## The 2x art at zoom 1.
const PAGE: Vector2i = Vector2i(320, 320)
const GROUND_POINT: Vector2i = Vector2i(160, 200)  ## Where the footprint's centre goes.
const SIDE_PX: int = 32
const MAX_OVERLAP: float = 0.88  ## Silhouettes of two types at 32 px: intersection over union.
## A lattice's members cover little of the box they stand in: at most this share on average over
## the heights between platform and crown, and under `OPEN_LEVEL` at more than `OPEN_LEVELS` of them
## (a girder ring covers a good deal of its level; a solid column covers all of every level).
const OPEN_MEAN: float = 0.25
const OPEN_LEVEL: float = 0.15
const OPEN_LEVELS: float = 0.6

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_each_model_is_a_derrick_league_building_with_a_square_footprint_and_one_silhouette_line(
) -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % id) as ArtModel
		var shown: String = "%s" % id
		assert_array(Array(model.problems())).override_failure_message(shown).is_empty()
		assert_str(String(model.art_id)).is_equal(shown)
		assert_str(String(model.faction)).override_failure_message(shown).is_equal("fossil")
		assert_str(String(model.category)).override_failure_message(shown).is_equal("bld")
		assert_int(model.footprint).override_failure_message(shown).is_equal(FOOTPRINTS[id])
		# One line, a sentence, in words (svg-art-style: describe the silhouette first).
		assert_bool(model.silhouette.contains("\n")).override_failure_message(shown).is_false()
		assert_int(model.silhouette.length()).override_failure_message(shown).is_greater(90)
		assert_bool(model.silhouette.ends_with(".")).override_failure_message(shown).is_true()


## The art's footprint is the data's: BuildingDef.footprint is square, the same for the type's
## model, and the dock and the exit cells are south of the footprint's middle column or half.
func test_every_footprint_is_the_data_footprint_and_square() -> void:
	for id: StringName in IDS:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		assert_object(def).override_failure_message("%s" % id).is_not_null()
		assert_int(def.footprint.x).override_failure_message("%s" % id).is_equal(def.footprint.y)
		assert_int(def.footprint.x).override_failure_message("%s" % id).is_equal(FOOTPRINTS[id])
		assert_str(String(def.faction)).override_failure_message("%s" % id).is_equal("fossil")


func test_a_building_has_one_view_and_a_cast_shadow_and_the_redoubt_has_16_heads() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_object(sheet).override_failure_message("%s" % id).is_not_null()
		var armed: bool = id == &"defence_turret"
		var parts: Array = ["hull", "head", "shadow"] if armed else ["hull", "shadow"]
		var counts: Array = [1, 16, 1] if armed else [1, 1]
		assert_array(Array(sheet.parts)).override_failure_message("%s" % id).is_equal(parts)
		assert_array(Array(sheet.counts)).override_failure_message("%s" % id).is_equal(counts)
		assert_array(Array(sheet.directions(&"hull"))).is_equal([-1])
		# The body and the shadow carry no direction in their names, a head carries one of 16.
		for part: StringName in [&"hull", &"shadow"]:
			var path: String = sheet.path(part, -1)
			assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
			assert_bool(FileAccess.file_exists(path + ".import")).is_true()
			assert_bool(path.contains("_d0")).override_failure_message(path).is_false()
			assert_bool(FileAccess.file_exists(sheet.path(part, 0))).is_false()
		if armed:
			assert_array(Array(sheet.directions(&"head"))).is_equal(range(16))
			for dir: int in 16:
				var head: String = sheet.path(&"head", dir)
				assert_bool(FileAccess.file_exists(head)).override_failure_message(head).is_true()
				assert_str(head).ends_with("_head_d%02d.svg" % dir)
			assert_array(_distinct(sheet, &"head")).override_failure_message("heads").has_size(16)


## The canvas of every frame is the sheet's, the width of a body is the footprint's, the anchor is
## the back corner of the footprint's diamond (32 x n px above its centre at 2x) and the diamond's
## front corner is inside the canvas, for the body and for the shadow (STYLE.md "Projection").
func test_every_canvas_and_anchor_is_pinned_and_the_anchor_is_the_back_corner() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var n: int = FOOTPRINTS[id]
		var want: Array = CANVAS[id]
		var hull: Vector2i = sheet.frame_size(&"hull")
		var shadow: Vector2i = sheet.frame_size(&"shadow")
		(
			assert_array([hull.x, hull.y, sheet.anchor(&"hull").y, shadow.x, shadow.y])
			. override_failure_message("%s canvas" % id)
			. is_equal(want)
		)
		assert_int(hull.x).override_failure_message("%s" % id).is_equal(128 * n)
		for part: StringName in [&"hull", &"shadow"]:
			var size: Vector2i = sheet.frame_size(part)
			var anchor: Vector2i = sheet.anchor(part)
			assert_int(anchor.x).override_failure_message("%s %s" % [id, part]).is_equal(64 * n)
			assert_vector(Vector2(sheet.origin(part) - anchor)).is_equal(Vector2(0, 32 * n))
			assert_bool(anchor.y >= 0 and anchor.y + 64 * n <= size.y).is_true()
			assert_bool(size.x >= 128 * n).override_failure_message("%s" % id).is_true()
			assert_str(_svg_size(sheet.path(part, -1))).is_equal("%d %d" % [size.x, size.y])
		# The shadow falls to the south-east, so it reaches at least as far east as the body.
		var east_body: int = hull.x - sheet.anchor(&"hull").x
		var east_shadow: int = shadow.x - sheet.anchor(&"shadow").x
		assert_int(east_shadow).override_failure_message("%s" % id).is_greater_equal(east_body)
		assert_bool(shadow.y > 64 * n).override_failure_message("%s shadow" % id).is_true()


## The Redoubt's head turns on the roof of its bunker: the pivot is a mount straight above the
## footprint's centre, every head frame has the canvas the sheet says, and only the head has a
## muzzle (a building without a gun has none).
func test_the_redoubts_head_mounts_on_its_roof_and_has_one_canvas_in_all_16_directions() -> void:
	var model: ArtModel = load(MODEL % &"defence_turret") as ArtModel
	var sheet: IsoSheetDef = _index.sheet(&"defence_turret")
	assert_int(sheet.mounts.size()).is_equal(1)
	assert_float(sheet.mount(0).x).is_equal_approx(0.0, 0.01)
	assert_float(sheet.mount(0).y).is_equal_approx(-model.mount.z * 78.38367, 0.1)
	assert_vector(sheet.mount(0)).is_equal_approx(ArtGen.mount_px(model, 6), Vector2(0.1, 0.1))
	var size: String = "%d %d" % [sheet.frame_size(&"head").x, sheet.frame_size(&"head").y]
	for dir: int in 16:
		(
			assert_str(_svg_size(sheet.path(&"head", dir)))
			. override_failure_message("d%d" % dir)
			. is_equal(size)
		)
	assert_int(sheet.muzzle_lift_px).is_greater(0)
	assert_float(float(sheet.muzzle_lift_px)).is_equal_approx(model.muzzle_z() * Z_PX, 1.0)
	for id: StringName in IDS:
		if id != &"defence_turret":
			(
				assert_int(_index.sheet(id).muzzle_lift_px)
				. override_failure_message("%s" % id)
				. is_equal(0)
			)


func test_each_type_is_as_tall_as_spec_05_says() -> void:
	for id: StringName in IDS:
		var top: float = _top(load(MODEL % id) as ArtModel) * Z_PX
		var band: Vector2 = HEIGHT_PX[id]
		(
			assert_float(top)
			. override_failure_message("%s is %.0f px tall, the band is %s" % [id, top, band])
			. is_between(band.x, band.y)
		)


func test_the_team_share_of_each_default_view_is_about_a_tenth() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % id) as ArtModel
		var picture: Image = _default_picture(model)
		var keys: Array[Color] = []
		for hex: String in ArtPalette.KEYS[&"fossil"]:
			keys.append(Color(hex))
		var team: int = 0
		var body: int = 0
		for y: int in picture.get_height():
			for x: int in picture.get_width():
				var pixel: Color = picture.get_pixel(x, y)
				if pixel.a < 0.95:
					continue
				body += 1
				for key: Color in keys:
					if (
						absf(pixel.r - key.r) + absf(pixel.g - key.g) + absf(pixel.b - key.b)
						< KEY_TOLERANCE
					):
						team += 1
						break
		var share: float = float(team) / body
		assert_float(share).override_failure_message("%s team share %.3f" % [id, share]).is_between(
			SHARE.x, SHARE.y
		)


## The data puts the dock of the refinery south of its middle column and the exits of the factory
## and the barracks south of their footprints (`BuildingDef.dock`, `exit`: col, row from the
## footprint's origin; STYLE.md "Buildings"). The art shows each where it is: a dark door or hopper
## mouth (iron) on the +y wall, in the cell's columns, so a unit leaves into the cell the sim uses.
func test_the_dock_and_the_exits_are_drawn_on_the_south_wall_in_the_cells_the_data_names() -> void:
	var cells: Dictionary[StringName, StringName] = {
		&"refinery": &"dock", &"vehicle_factory": &"exit", &"barracks": &"exit"
	}
	for id: StringName in cells:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		var cell: Vector2i = def.dock if cells[id] == &"dock" else def.exit
		var n: int = def.footprint.x
		assert_int(cell.y).override_failure_message("%s" % id).is_equal(n)
		var from_x: float = cell.x - n / 2.0
		var found: Array[String] = []
		for prim: ArtPrim in (load(MODEL % id) as ArtModel).primitives(&"hull"):
			var box: AABB = prim.aabb()
			var inside: bool = (
				box.get_center().x >= from_x
				and box.get_center().x <= from_x + 1.0
				and box.end.y >= n / 2.0 - 0.7
				and box.size.x >= 0.28
			)
			if prim.material == &"iron" and inside and prim.z0 < 0.5:
				found.append("%s %s" % [prim.shape, box])
		assert_bool(found.is_empty()).override_failure_message("%s has no mark" % id).is_false()


## No spire (STYLE.md "Palette per faction", CLAUDE.md Legal): a tall structure is an open lattice,
## a round stack or a slim pole, never one solid four-sided column that tapers to a point. The Deep
## Bore and the Signal Mast are lattices of legs and girders: at every height between the platform
## and the crown the members cover little of the box they stand in.
func test_the_deep_bore_and_the_signal_mast_are_open_lattices_and_nothing_is_a_solid_spire(
) -> void:
	for id: StringName in IDS:
		for prim: ArtPrim in (load(MODEL % id) as ArtModel).primitives(&"hull"):
			var spire: bool = (
				prim.shape == &"prism"
				and prim.sides == 4
				and prim.taper < 0.9
				and prim.size.z > 1.0
			)
			assert_bool(spire).override_failure_message("%s has a spire" % id).is_false()
	var strike: ArtModel = load(MODEL % &"fossil_strike") as ArtModel
	var mast: ArtModel = load(MODEL % &"fossil_radar") as ArtModel
	var checks: Array[Array] = [[strike, 0.62, 2.5], [mast, 0.62, 1.9]]
	for check: Array in checks:
		var model: ArtModel = check[0]
		var levels: Array[float] = []
		var z: float = check[1]
		while z <= float(check[2]):
			levels.append(_cross_section(model, z))
			z += 0.1
		assert_int(levels.size()).is_greater(10)
		var mean: float = 0.0
		var open: int = 0
		for ratio: float in levels:
			mean += ratio / levels.size()
			open += int(ratio < OPEN_LEVEL)
		(
			assert_float(mean)
			. override_failure_message("%s covers %.2f" % [model.art_id, mean])
			. is_less(OPEN_MEAN)
		)
		(
			assert_float(float(open) / levels.size())
			. override_failure_message(
				"%s is open at %d of %d levels" % [model.art_id, open, levels.size()]
			)
			. is_greater(OPEN_LEVELS)
		)
	# And the lattices are not empty: legs stand at every level.
	assert_int(_members_at(strike, 1.3)).is_greater_equal(5)
	assert_int(_members_at(mast, 1.0)).is_greater_equal(4)


func test_the_eight_default_views_read_apart_at_32_px_in_greyscale() -> void:
	var masks: Array[Image] = []
	for id: StringName in IDS:
		masks.append(_mask_32(load(MODEL % id) as ArtModel))
	for i: int in IDS.size():
		for j: int in range(i + 1, IDS.size()):
			var overlap: float = _overlap(masks[i], masks[j])
			(
				assert_float(overlap)
				. override_failure_message("%s and %s overlap %.2f" % [IDS[i], IDS[j], overlap])
				. is_less(MAX_OVERLAP)
			)


## The emblem (ADR 0023 section 6): an octagon, an I-beam and four rivets; no star, no letter, no
## flag. Grey, so the HUD tints it; 128 px at import scale 1.0.
func test_the_emblem_is_an_octagon_with_an_i_beam_and_four_rivets_in_greys_only() -> void:
	var text: String = FileAccess.get_file_as_string(EMBLEM)
	assert_bool(text.is_empty()).is_false()
	assert_str(text).contains('width="128" height="128" viewBox="0 0 128 128"')
	var lines: PackedStringArray = text.split("\n")
	assert_str(lines[1]).starts_with("<!-- Shape: ")
	var polygons: Array[int] = []
	var points: RegEx = RegEx.create_from_string('<polygon points="([^"]*)"')
	for found: RegExMatch in points.search_all(text):
		polygons.append(found.get_string(1).split(" ", false).size())
	# The rim, the face, the panel (octagons), the beam and the beam's three shades.
	assert_array(polygons.slice(0, 3)).is_equal([8, 8, 8])
	assert_int(polygons[3]).is_equal(12)
	assert_int(text.count("<circle")).is_equal(4)
	var hex: RegEx = RegEx.create_from_string("#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})")
	for found: RegExMatch in hex.search_all(text):
		assert_str(found.get_string(1)).override_failure_message(found.get_string()).is_equal(
			found.get_string(2)
		)
		assert_str(found.get_string(2)).is_equal(found.get_string(3))
	var texture: Texture2D = load(EMBLEM) as Texture2D
	assert_vector(texture.get_size()).is_equal(Vector2(128, 128))
	var image: Image = texture.get_image()
	for i: int in 128:
		for edge: Vector2i in [Vector2i(i, 0), Vector2i(i, 127), Vector2i(0, i), Vector2i(127, i)]:
			assert_float(image.get_pixelv(edge).a).override_failure_message("%s" % edge).is_less(
				0.05
			)
	# At 32 px in greyscale the white ring, the dark panel and the white beam are three levels.
	var small: Image = _raster(text, 0.25)
	assert_float(_grey(small, Vector2i(3, 16))).is_greater(0.8)  # The ring.
	assert_float(_grey(small, Vector2i(7, 16))).is_less(0.4)  # The panel.
	assert_float(_grey(small, Vector2i(16, 16))).is_greater(0.8)  # The web of the beam.
	assert_float(_grey(small, Vector2i(16, 10))).is_greater(0.8)  # Its top flange.


## The style guide catalogues each building by the silhouette its model says and the pages in which
## the buildings are judged.
func test_the_style_guide_names_the_eight_buildings_their_files_and_the_rules() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var start: int = style.find("## Buildings")
	assert_int(start).is_greater(-1)
	var section: String = style.substr(start, style.find("\n## ", start + 1) - start)
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % id) as ArtModel
		assert_str(section).override_failure_message("%s" % id).contains(model.silhouette)
		assert_str(section).contains("`%s`" % id)
	var flat: String = section.replace("\n", " ")
	for line: String in [
		"back corner",
		"128 x n",
		"no spire",
		"Deep Bore",
		"`emblem_fossil.svg`",
		"in front of and behind",
		"`BuildingDef.dock`",
		"about 8 to 12 %",
	]:
		assert_str(flat).override_failure_message(line).contains(line)


## The tallest point of a model in tiles, a head at its mount.
func _top(model: ArtModel) -> float:
	var top: float = 0.0
	for part: StringName in model.parts():
		for prim: ArtPrim in model.primitives(part):
			top = maxf(top, prim.aabb().end.z + (model.mount.z if part == &"head" else 0.0))
	return top


## The share of the box of the members at height `z` that they cover, summed over their own boxes
## (an overlap counts twice, so it is an upper bound): a lattice stays low, a solid column is 1.
func _cross_section(model: ArtModel, z: float) -> float:
	var area: float = 0.0
	var box: Rect2 = Rect2()
	var first: bool = true
	for prim: ArtPrim in model.primitives(&"hull"):
		var shape: AABB = prim.aabb()
		if shape.position.z <= z and z <= shape.end.z:
			var flat: Rect2 = Rect2(shape.position.x, shape.position.y, shape.size.x, shape.size.y)
			area += flat.get_area()
			box = flat if first else box.merge(flat)
			first = false
	return area / box.get_area() if not first else 0.0


func _members_at(model: ArtModel, z: float) -> int:
	var count: int = 0
	for prim: ArtPrim in model.primitives(&"hull"):
		var shape: AABB = prim.aabb()
		count += int(shape.position.z <= z and z <= shape.end.z)
	return count


## The distinct texts of the frames of a part, one entry per different file.
func _distinct(sheet: IsoSheetDef, part: StringName) -> Array[String]:
	var found: Array[String] = []
	for dir: int in sheet.directions(part):
		var text: String = FileAccess.get_file_as_string(sheet.path(part, dir))
		if not found.has(text):
			found.append(text)
	return found


## "width height" of the SVG in `path`, from its root element.
func _svg_size(path: String) -> String:
	var root: RegEx = RegEx.create_from_string('<svg[^>]* width="(\\d+)" height="(\\d+)"')
	var found: RegExMatch = root.search(FileAccess.get_file_as_string(path))
	return "%s %s" % [found.get_string(1), found.get_string(2)] if found != null else ""


## The default view of a building on a transparent page at zoom 1, its footprint's centre at
## GROUND_POINT: the body, and the head at its mount.
func _default_picture(model: ArtModel) -> Image:
	var sheet: IsoSheetDef = _index.sheet(model.art_id)
	var picture: Image = Image.create_empty(PAGE.x, PAGE.y, false, Image.FORMAT_RGBA8)
	var body: Image = _raster(FileAccess.get_file_as_string(sheet.path(&"hull", -1)), SCALE)
	picture.blend_rect(
		body,
		Rect2i(Vector2i.ZERO, body.get_size()),
		GROUND_POINT - Vector2i(Vector2(sheet.origin(&"hull")) * SCALE)
	)
	if sheet.has_part(&"head"):
		var head: Image = _raster(FileAccess.get_file_as_string(sheet.path(&"head", 6)), SCALE)
		var at: Vector2 = sheet.mount(0) - Vector2(sheet.origin(&"head"))
		picture.blend_rect(
			head, Rect2i(Vector2i.ZERO, head.get_size()), GROUND_POINT + Vector2i(at * SCALE)
		)
	return picture


## The silhouette of the default view scaled to fit 32 px and centred on a 32 px page.
func _mask_32(model: ArtModel) -> Image:
	var picture: Image = _default_picture(model)
	var box: Rect2i = picture.get_used_rect()
	var small: Image = picture.get_region(box)
	var factor: float = float(SIDE_PX) / maxi(box.size.x, box.size.y)
	small.resize(
		maxi(1, roundi(box.size.x * factor)),
		maxi(1, roundi(box.size.y * factor)),
		Image.INTERPOLATE_LANCZOS
	)
	var page: Image = Image.create_empty(SIDE_PX, SIDE_PX, false, Image.FORMAT_RGBA8)
	page.blend_rect(
		small,
		Rect2i(Vector2i.ZERO, small.get_size()),
		Vector2i((SIDE_PX - small.get_width()) / 2, (SIDE_PX - small.get_height()) / 2)
	)
	return page


## Intersection over union of the pixels with ink in two pages of one size.
func _overlap(a: Image, b: Image) -> float:
	var both: int = 0
	var either: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			var in_a: bool = a.get_pixel(x, y).a > 0.5
			var in_b: bool = b.get_pixel(x, y).a > 0.5
			both += int(in_a and in_b)
			either += int(in_a or in_b)
	return float(both) / maxi(either, 1)


func _raster(text: String, scale: float) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(text, scale)
	return image


func _grey(image: Image, at: Vector2i) -> float:
	var pixel: Color = image.get_pixelv(at)
	return 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b
