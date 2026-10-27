extends GdUnitTestSuite
## The Lumen Accord's eight buildings (plan row P104, ADR 0023 sections 5 to 7, STYLE.md
## "Buildings"): the models that replaced P99's blockouts under the same art ids, and the frames and
## sheets they generate. It pins what the art row promises: every footprint square and the data's,
## one view and one cast shadow each and the Rail Battery's 16 heads, the canvas of every frame and
## its anchor at the footprint's back corner (Spec 03), the height each type has in Spec 05, the
## team share of about a twelfth, the dock and the exits where the data puts them, the white ceramic
## on graphite look with its mint lights, the Blackout Array as an open frame that is neither a
## spire nor a dish, and eight silhouettes that read apart at 32 px in greyscale. That the frames
## are the generator's bytes, the key band and the shadows' rules are in test_artgen*.gd, the
## Derrick League's twin is test_fossil_buildings.gd, the emblem is in test_renew_emblem.gd and the
## Build page is in test_art_gallery_build.gd.

const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const STYLE_PATH: String = "res://assets/art/STYLE.md"
const MODEL: String = "res://assets/art/models/renew/%s.tres"
const DATA: String = "res://data/units/%s.tres"
const IDS: Array[StringName] = [
	&"renew_hq",
	&"renew_power",
	&"renew_refinery",
	&"renew_barracks",
	&"renew_factory",
	&"renew_radar",
	&"renew_defence",
	&"renew_strike",
]
## ADR 0023 section 7's names, which the data's display names agree with.
const NAMES: Dictionary[StringName, String] = {
	&"renew_hq": "Grid Hub",
	&"renew_power": "Wind Park",
	&"renew_refinery": "Synthesis Works",
	&"renew_barracks": "Crew Hall",
	&"renew_factory": "Motor Works",
	&"renew_radar": "Relay Tower",
	&"renew_defence": "Rail Battery",
	&"renew_strike": "Blackout Array",
}
const FOOTPRINTS: Dictionary[StringName, int] = {
	&"renew_hq": 3,
	&"renew_power": 2,
	&"renew_refinery": 3,
	&"renew_barracks": 2,
	&"renew_factory": 3,
	&"renew_radar": 2,
	&"renew_defence": 1,
	&"renew_strike": 3,
}
## The tallest point of each type in px at zoom 1, the band of Spec 05 ("Hovedkvarter, fabrik,
## supervaaben 80-150, raffinaderi 60-80, kraftvaerk, kaserne, radar 50-100, forsvarstaarn 40-60").
const HEIGHT_PX: Dictionary[StringName, Vector2] = {
	&"renew_hq": Vector2(80, 150),
	&"renew_factory": Vector2(80, 150),
	&"renew_strike": Vector2(80, 150),
	&"renew_refinery": Vector2(60, 80),
	&"renew_power": Vector2(50, 100),
	&"renew_barracks": Vector2(50, 100),
	&"renew_radar": Vector2(50, 100),
	&"renew_defence": Vector2(40, 60),
}
## Canvas and anchor in px of the 2x art: hull width, hull height, hull anchor y, shadow width,
## shadow height. The anchor x is half the width, the shadow's anchor is the same back corner at
## the top of its own canvas (y 0, pinned). When the art changes on purpose, run
## `bash scripts/gen-art.sh` and read the new numbers from the sheets.
const CANVAS: Dictionary[StringName, Array] = {
	&"renew_hq": [384, 358, 165, 384, 194],
	&"renew_power": [256, 268, 139, 316, 134],
	&"renew_refinery": [384, 294, 101, 398, 202],
	&"renew_barracks": [256, 236, 107, 258, 154],
	&"renew_factory": [384, 332, 139, 454, 216],
	&"renew_radar": [256, 258, 130, 260, 132],
	&"renew_defence": [128, 104, 39, 184, 94],
	&"renew_strike": [384, 388, 195, 480, 242],
}
## The Rail Battery's head frames, px of the 2x art: canvas width, canvas height, pivot x, pivot y
## (the anchor of a head is its pivot, which the sheet's mount puts on the plinth's turntable).
const HEAD_CANVAS: Array = [204, 114, 102, 70]
const MUZZLE_LIFT_PX: int = 33  ## Where a shot leaves the Rail Battery at zoom 1.
const HEAD_DIR: int = 10  ## The Lumen Accord's default view (Spec 04): south-west.
## The team share of a default view, about a twelfth (STYLE.md "Light"; the generator's own pin is 3
## to 20 %).
const SHARE: Vector2 = Vector2(0.065, 0.125)
const MAX_OVERLAP: float = 0.85  ## Silhouettes of two types at 32 px: intersection over union.
## The Blackout Array is an open frame: between the plate and the ring beam its members cover at
## most `FRAME_MEAN` of the box they stand in on average and `FRAME_MAX` at any height (the core's
## drums), and above the core the four columns cover under `ABOVE_CORE` of it.
const FRAME_MEAN: float = 0.35
const FRAME_MAX: float = 0.42
const ABOVE_CORE: float = 0.1

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_each_model_is_a_lumen_accord_building_with_a_square_footprint_and_one_silhouette_line(
) -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % id) as ArtModel
		var shown: String = "%s" % id
		assert_array(Array(model.problems())).override_failure_message(shown).is_empty()
		assert_str(String(model.art_id)).is_equal(shown)
		assert_str(String(model.faction)).override_failure_message(shown).is_equal("renew")
		assert_str(String(model.category)).override_failure_message(shown).is_equal("bld")
		assert_int(model.footprint).override_failure_message(shown).is_equal(FOOTPRINTS[id])
		# One line, a sentence, in words (svg-art-style: describe the silhouette first).
		assert_bool(model.silhouette.contains("\n")).override_failure_message(shown).is_false()
		assert_int(model.silhouette.length()).override_failure_message(shown).is_greater(90)
		assert_bool(model.silhouette.ends_with(".")).override_failure_message(shown).is_true()


## The art's footprint is the data's: BuildingDef.footprint is square, the same for the type's
## model, and the data's display name is ADR 0023 section 7's.
func test_every_footprint_is_the_data_footprint_and_square_and_the_name_is_the_adrs() -> void:
	for id: StringName in IDS:
		var def: BuildingDef = load(DATA % id) as BuildingDef
		assert_object(def).override_failure_message("%s" % id).is_not_null()
		assert_int(def.footprint.x).override_failure_message("%s" % id).is_equal(def.footprint.y)
		assert_int(def.footprint.x).override_failure_message("%s" % id).is_equal(FOOTPRINTS[id])
		assert_str(String(def.faction)).override_failure_message("%s" % id).is_equal("renew")
		assert_str(def.display_name).override_failure_message("%s" % id).is_equal(NAMES[id])


func test_a_building_has_one_view_and_a_cast_shadow_and_the_rail_battery_has_16_heads() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_object(sheet).override_failure_message("%s" % id).is_not_null()
		var armed: bool = id == &"renew_defence"
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
			if part == &"shadow":
				# The same back corner, at the top of the shadow's own canvas.
				assert_int(anchor.y).override_failure_message("%s shadow" % id).is_equal(0)
			assert_vector(Vector2(sheet.origin(part) - anchor)).is_equal(Vector2(0, 32 * n))
			assert_bool(anchor.y >= 0 and anchor.y + 64 * n <= size.y).is_true()
			assert_bool(size.x >= 128 * n).override_failure_message("%s" % id).is_true()
			var text: String = "%d %d" % [size.x, size.y]
			assert_str(Support.svg_size(sheet.path(part, -1))).is_equal(text)
		# The shadow falls to the south-east, so it reaches at least as far east as the body.
		var east_body: int = hull.x - sheet.anchor(&"hull").x
		var east_shadow: int = shadow.x - sheet.anchor(&"shadow").x
		assert_int(east_shadow).override_failure_message("%s" % id).is_greater_equal(east_body)
		assert_bool(shadow.y > 64 * n).override_failure_message("%s shadow" % id).is_true()


## The Rail Battery's head turns on the plinth's turntable: the pivot is a mount straight above the
## footprint's centre, every head frame has the canvas the sheet says, and only the head has a
## muzzle (a building without a gun has none).
func test_the_rail_batterys_head_mounts_on_its_plinth_and_has_one_canvas_in_all_16_directions(
) -> void:
	var model: ArtModel = load(MODEL % &"renew_defence") as ArtModel
	var sheet: IsoSheetDef = _index.sheet(&"renew_defence")
	assert_int(sheet.mounts.size()).is_equal(1)
	assert_float(sheet.mount(0).x).is_equal_approx(0.0, 0.01)
	assert_float(sheet.mount(0).y).is_equal_approx(-model.mount.z * 78.38367, 0.1)
	assert_vector(sheet.mount(0)).is_equal_approx(ArtGen.mount_px(model, 6), Vector2(0.1, 0.1))
	var head: Vector2i = sheet.frame_size(&"head")
	var pivot: Vector2i = sheet.anchor(&"head")
	(
		assert_array([head.x, head.y, pivot.x, pivot.y])
		. override_failure_message("head canvas and pivot")
		. is_equal(HEAD_CANVAS)
	)
	assert_vector(sheet.mount(0)).is_equal_approx(Vector2(0.0, -51.7), Vector2(0.1, 0.1))
	assert_int(sheet.muzzle_lift_px).is_equal(MUZZLE_LIFT_PX)
	var size: String = "%d %d" % [head.x, head.y]
	for dir: int in 16:
		var path: String = sheet.path(&"head", dir)
		assert_str(Support.svg_size(path)).override_failure_message("d%d" % dir).is_equal(size)
	assert_float(float(sheet.muzzle_lift_px)).is_equal_approx(model.muzzle_z() * Support.Z_PX, 1.0)
	for id: StringName in IDS:
		if id != &"renew_defence":
			var lift: int = _index.sheet(id).muzzle_lift_px
			assert_int(lift).override_failure_message("%s" % id).is_equal(0)


## The Rail Battery has one rail: a sleeve that starts inside the head, one long thin barrel that
## starts inside the sleeve, three collars along that barrel and a muzzle ring that starts inside
## its end and reaches farthest along +x (the sheet's muzzle), all on one axis height. An `axis=x`
## prism is `length width height`, so the pieces are checked by where they begin and end. Drawn at
## 2x, every one of the 16 head frames is one connected shape.
func test_the_rail_batterys_barrel_is_one_connected_rail_and_every_head_frame_is_one_shape(
) -> void:
	var model: ArtModel = load(MODEL % &"renew_defence") as ArtModel
	var along: Array[ArtPrim] = []
	var housing: ArtPrim = null
	var reach: float = 0.0
	for prim: ArtPrim in model.primitives(&"head"):
		reach = maxf(reach, prim.aabb().end.x)
		if prim.axis == 0:
			along.append(prim)
		elif housing == null or prim.aabb().end.x > housing.aabb().end.x:
			housing = prim
	assert_object(housing).is_not_null()
	along.sort_custom(
		func(a: ArtPrim, b: ArtPrim) -> bool: return a.aabb().position.x < b.aabb().position.x
	)
	# Sleeve, barrel, three collars and the muzzle ring; exactly one of them is a long barrel.
	assert_int(along.size()).is_equal(6)
	var barrels: Array[ArtPrim] = along.filter(func(p: ArtPrim) -> bool: return p.size.x >= 0.6)
	assert_int(barrels.size()).override_failure_message("one barrel, not twin").is_equal(1)
	var sleeve: ArtPrim = along[0]
	var barrel: ArtPrim = barrels[0]
	var muzzle: ArtPrim = along[along.size() - 1]
	assert_float(sleeve.aabb().position.x).is_less(housing.aabb().end.x)
	assert_float(barrel.aabb().position.x).is_less(sleeve.aabb().end.x)
	assert_float(muzzle.aabb().position.x).is_less(barrel.aabb().end.x)
	assert_float(muzzle.aabb().end.x).is_equal_approx(reach, 0.0001)
	for prim: ArtPrim in along:
		var level: float = prim.aabb().get_center().z
		assert_float(level).is_equal_approx(barrel.aabb().get_center().z, 0.005)
		if prim != sleeve and prim != barrel and prim != muzzle:
			assert_float(prim.aabb().position.x).is_greater(barrel.aabb().position.x)
			assert_float(prim.aabb().end.x).is_less(barrel.aabb().end.x)
	var sheet: IsoSheetDef = _index.sheet(&"renew_defence")
	for dir: int in 16:
		var picture: Image = Support.raster(
			FileAccess.get_file_as_string(sheet.path(&"head", dir)), 1.0
		)
		var shapes: int = Support.pieces(picture)
		(
			assert_int(shapes)
			. override_failure_message("head d%02d is %d shapes" % [dir, shapes])
			. is_equal(1)
		)


func test_each_type_is_as_tall_as_spec_05_says() -> void:
	for id: StringName in IDS:
		var top: float = Support.top(load(MODEL % id) as ArtModel) * Support.Z_PX
		var band: Vector2 = HEIGHT_PX[id]
		(
			assert_float(top)
			. override_failure_message("%s is %.0f px tall, the band is %s" % [id, top, band])
			. is_between(band.x, band.y)
		)


func test_the_team_share_of_each_default_view_is_about_a_twelfth() -> void:
	for id: StringName in IDS:
		var picture: Image = Support.default_picture(_index.sheet(id), HEAD_DIR)
		var share: float = Support.team_share(picture, &"renew")
		assert_float(share).override_failure_message("%s team share %.3f" % [id, share]).is_between(
			SHARE.x, SHARE.y
		)


## The data puts the dock of the refinery south of its middle column and the exits of the factory
## and the barracks south of their footprints (`BuildingDef.dock`, `exit`: col, row from the
## footprint's origin; STYLE.md "Buildings"). The art shows each where it is: one dark door or
## mouth (graphite, a thin face as tall as a door) on the +y wall, in the cell's column, so a unit
## leaves into the cell the sim uses. The graphite plate under every building is not a door: it is
## low, and the plinths are too.
func test_the_dock_and_the_exits_are_drawn_on_the_south_wall_in_the_cells_the_data_names() -> void:
	var cells: Dictionary[StringName, StringName] = {
		&"renew_refinery": &"dock", &"renew_factory": &"exit", &"renew_barracks": &"exit"
	}
	for id: StringName in cells:
		var def: BuildingDef = load(DATA % id) as BuildingDef
		var cell: Vector2i = def.dock if cells[id] == &"dock" else def.exit
		var n: int = def.footprint.x
		assert_int(cell.y).override_failure_message("%s" % id).is_equal(n)
		var from_x: float = cell.x - n / 2.0
		var found: Array[String] = []
		for prim: ArtPrim in (load(MODEL % id) as ArtModel).primitives(&"hull"):
			var box: AABB = prim.aabb()
			var in_cell: bool = (
				box.get_center().x >= from_x
				and box.get_center().x <= from_x + 1.0
				and box.end.y >= n / 2.0 - 0.7
			)
			var is_door: bool = box.size.x >= 0.28 and box.size.y <= 0.1 and box.size.z >= 0.25
			if prim.material == &"graphite" and in_cell and is_door and prim.z0 < 0.5:
				found.append("%s %s" % [prim.shape, box])
		assert_array(found).override_failure_message("%s marks: %s" % [id, found]).has_size(1)


## The look (ADR 0023 section 6, STYLE.md "Palette per faction"): white ceramic on a graphite
## plate, a team zone and a mint status light on every building, and hexagons or rounded drums
## where a building is not a plain box.
func test_every_building_is_white_ceramic_on_graphite_with_a_team_zone_a_mint_light_and_hexagons(
) -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % id) as ArtModel
		var used: Dictionary[StringName, int] = {}
		var rounded: int = 0
		for part: StringName in model.parts():
			for prim: ArtPrim in model.primitives(part):
				used[prim.material] = used.get(prim.material, 0) + 1
				rounded += int(prim.shape == &"prism" and prim.sides in [6, 8, 12, 16])
		for material: StringName in [&"ceramic", &"graphite", &"team", &"mint"]:
			(
				assert_bool(used.has(material))
				. override_failure_message("%s has no %s" % [id, material])
				. is_true()
			)
		assert_int(used[&"team"]).override_failure_message("%s team zones" % id).is_greater(1)
		assert_int(rounded).override_failure_message("%s has no hexagon" % id).is_greater(1)
		# The plate under the footprint is graphite, and the top of the first primitive says so.
		var plate: ArtPrim = model.primitives(&"hull")[0]
		assert_str(String(plate.material)).is_equal("graphite")
		assert_float(plate.size.z).is_less_equal(0.06)


## No spire (STYLE.md "Palette per faction", CLAUDE.md Legal): nothing is one solid four-sided
## column that tapers to a point, and the Blackout Array is an open frame, not a crystal, not a
## dish and not a coil: four columns and a ring beam round a core that stays lower than the ring, no
## sphere, no wedge, no taper and no big upright disc.
func test_nothing_is_a_spire_and_the_blackout_array_is_an_open_frame_that_is_no_dish() -> void:
	for id: StringName in IDS:
		for prim: ArtPrim in (load(MODEL % id) as ArtModel).primitives(&"hull"):
			var spire: bool = (
				prim.shape == &"prism"
				and prim.sides == 4
				and prim.taper < 0.9
				and prim.size.z > 1.0
			)
			assert_bool(spire).override_failure_message("%s has a spire" % id).is_false()
	var strike: ArtModel = load(MODEL % &"renew_strike") as ArtModel
	var columns: int = 0
	var beams: int = 0
	var core_top: float = 0.0
	var ring: float = INF
	for prim: ArtPrim in strike.primitives(&"hull"):
		(
			assert_bool(prim.shape in [&"box", &"prism"])
			. override_failure_message("%s is not a box or a prism" % prim.shape)
			. is_true()
		)
		assert_float(prim.taper).override_failure_message("a tapered prism").is_equal(1.0)
		assert_bool(_is_upright_disc(prim)).override_failure_message("an upright disc").is_false()
		var box: AABB = prim.aabb()
		columns += int(prim.shape == &"prism" and prim.sides == 6 and box.size.z > 0.8)
		if prim.material == &"graphite" and box.size.x * box.size.y > 0.3 and box.position.z > 2.0:
			beams += 1
			ring = minf(ring, box.position.z)
		elif prim.material != &"graphite" and _near_the_middle(box):
			core_top = maxf(core_top, box.end.z)
	# Four beams make the ring, and eight tall hexagonal shafts the four columns, two a column.
	assert_int(columns).is_greater_equal(8)
	assert_int(beams).is_equal(4)
	assert_float(core_top).override_failure_message("the core is the tallest thing").is_less(ring)
	var levels: Array[float] = []
	var z: float = 0.3
	var mean: float = 0.0
	var worst: float = 0.0
	while z <= 2.5:
		var ratio: float = Support.cross_section(strike, z)
		levels.append(ratio)
		worst = maxf(worst, ratio)
		if z > core_top + 0.05:
			(
				assert_float(ratio)
				. override_failure_message("covers %.2f at %.1f" % [ratio, z])
				. is_less(ABOVE_CORE)
			)
		z += 0.1
	for ratio: float in levels:
		mean += ratio / levels.size()
	assert_float(mean).override_failure_message("covers %.2f" % mean).is_less(FRAME_MEAN)
	assert_float(worst).override_failure_message("covers %.2f at most" % worst).is_less(FRAME_MAX)


## The rule itself: a thin dish standing on its edge, along x or y and of any thickness, is an
## upright disc; a hexagonal column, a ring beam lying flat and a slim lying rod are not. Without
## this the test above would pass for a rule that finds nothing (the first one measured the disc's
## thickness times its diameter, and 2.2 tiles across and 0.13 thick got through).
func test_the_rule_finds_an_upright_dish_of_any_thickness_and_lets_a_column_and_a_rod_pass(
) -> void:
	for line: String in [
		"prism hull ceramic 0 0 1.5 0.1 2 2 sides=16 axis=x",
		"prism hull ceramic 0 0 1.5 2.2 0.13 2.2 sides=16 axis=y",
		"prism hull ceramic 0 0 1.5 2 0.1 2 sides=8 axis=y",
		"prism hull ceramic 0 0 1.5 0.5 0.6 0.6 sides=12 axis=x",
	]:
		assert_bool(_is_upright_disc(_prims([line])[0])).override_failure_message(line).is_true()
	for line: String in [
		"prism hull ceramic 0 0 0 0.3 0.3 1.2 sides=6",
		"prism hull graphite 0 0 2.4 1.6 1.6 0.2 sides=4",
		"prism hull graphite 0 0 1.5 1.5 0.12 0.12 sides=8 axis=x",
		"prism hull graphite 0 0 1.5 0.12 1.5 0.12 sides=8 axis=y",
		"box hull team 0 0 1.5 0.1 2 2",
	]:
		assert_bool(_is_upright_disc(_prims([line])[0])).override_failure_message(line).is_false()


## Two wind turbines of different heights, each a tower with a team ring and four tapered blades
## that end in a team tip (eight blades, eight tips), the rotor's hub a prism along y.
func test_the_wind_park_has_two_four_bladed_turbines_of_different_heights() -> void:
	var model: ArtModel = load(MODEL % &"renew_power") as ArtModel
	var hubs: Array[float] = []
	var blades: int = 0
	var tips: int = 0
	var rings: int = 0
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.shape == &"prism" and prim.axis == 1 and prim.sides == 8:
			hubs.append(prim.aabb().get_center().z)
		blades += int(prim.shape == &"prism" and prim.sides == 4 and prim.taper != 1.0)
		tips += int(prim.material == &"team" and prim.shape == &"box" and prim.size.y <= 0.05)
		rings += int(prim.material == &"team" and prim.shape == &"prism" and prim.sides == 12)
	assert_int(hubs.size()).is_equal(2)
	assert_float(absf(hubs[0] - hubs[1])).is_greater(0.2)
	assert_int(blades).is_equal(8)
	assert_int(tips).is_equal(8)
	assert_int(rings).is_equal(2)


## The Relay Tower carries three upright hexagonal phased-array faces (a blue-grey panel in a team
## frame), turned alternately to +y and to +x, on one slim pole of three segments.
func test_the_relay_tower_carries_three_array_faces_on_one_slim_pole() -> void:
	var model: ArtModel = load(MODEL % &"renew_radar") as ArtModel
	var faces: Array[int] = []
	var frames: int = 0
	var pole: int = 0
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.shape == &"prism" and prim.axis != 2 and prim.sides == 6:
			if prim.material == &"bluegrey":
				faces.append(prim.axis)
			frames += int(prim.material == &"team")
		pole += int(prim.shape == &"prism" and prim.sides == 12 and prim.material == &"titanium")
	assert_array(faces).has_size(3)
	assert_int(faces.count(1)).is_equal(2)
	assert_int(faces.count(0)).is_equal(1)
	assert_int(frames).is_equal(3)
	assert_int(pole).is_equal(3)


func test_the_eight_default_views_read_apart_at_32_px_in_greyscale() -> void:
	var masks: Array[Image] = []
	for id: StringName in IDS:
		var picture: Image = Support.default_picture(_index.sheet(id), HEAD_DIR)
		masks.append(Support.mask_32(picture))
	for i: int in IDS.size():
		for j: int in range(i + 1, IDS.size()):
			var overlap: float = Support.overlap(masks[i], masks[j])
			(
				assert_float(overlap)
				. override_failure_message("%s and %s overlap %.2f" % [IDS[i], IDS[j], overlap])
				. is_less(MAX_OVERLAP)
			)


## The style guide catalogues each building by the silhouette its model says, by its name and its
## art id, and the pages in which the buildings are judged.
func test_the_style_guide_names_the_eight_buildings_their_files_and_the_rules() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var start: int = style.find("## Buildings")
	assert_int(start).is_greater(-1)
	var section: String = style.substr(start, style.find("\n## ", start + 1) - start)
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % id) as ArtModel
		assert_str(section).override_failure_message("%s" % id).contains(model.silhouette)
		assert_str(section).contains("`%s`" % id)
		assert_str(section).contains(NAMES[id])
	var flat: String = section.replace("\n", " ")
	for line: String in [
		"Lumen Accord",
		"`emblem_renew.svg`",
		"white ceramic on graphite",
		"Blackout Array",
		"neither a spire nor a dish",
		"graphite door",
		"about 7 to 11 %",
	]:
		assert_str(flat).override_failure_message(line).contains(line)
	var catalogue: String = style.substr(style.find("## Catalogue"))
	for id: StringName in IDS:
		var files: String = "iso/renew/bld/%s_{hull,shadow}.svg" % id
		assert_str(catalogue).override_failure_message("%s" % id).contains(files)


## The distinct texts of the frames of a part, one entry per different file.
func _distinct(sheet: IsoSheetDef, part: StringName) -> Array[String]:
	var found: Array[String] = []
	for dir: int in sheet.directions(part):
		var text: String = FileAccess.get_file_as_string(sheet.path(part, dir))
		if not found.has(text):
			found.append(text)
	return found


## True for a prism that lies along x or y with a face of more than 0.3 square tiles: the face is
## the ring, the box's other two sides, so the length (a rod's, a barrel's) does not count.
func _is_upright_disc(prim: ArtPrim) -> bool:
	if prim.shape != &"prism" or prim.axis == 2:
		return false
	var box: AABB = prim.aabb()
	var face: float = box.size.y * box.size.z if prim.axis == 0 else box.size.x * box.size.z
	return face > 0.3


func _prims(lines: Array[String]) -> Array[ArtPrim]:
	var prims: Array[ArtPrim] = []
	for line: String in lines:
		var prim: ArtPrim = ArtPrim.parse(line)
		assert_object(prim).override_failure_message(line).is_not_null()
		prims.append(prim)
	return prims


## True for a box whose centre is within 0.7 tile of the footprint's centre along both axes: the
## core, not a column, a bar or a node under a bar.
func _near_the_middle(box: AABB) -> bool:
	var at: Vector3 = box.get_center()
	return absf(at.x) < 0.7 and absf(at.y) < 0.7
