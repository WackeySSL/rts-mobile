extends GdUnitTestSuite
## The six Derrick League unit models of plan row P101 (ADR 0023 sections 6 and 7, STYLE.md
## "Derrick League units"): each is named in its silhouette line, a squad is three figures, a
## vehicle has the wheels or tracks its line says and stands in its size class, the gun of an armed
## vehicle is the thing that reaches farthest forward, the team colour is 6 to 14 % of the default
## view (the art rows aim at 8 to 12 %, ADR 0023 section 5), and the top-down unit files are gone.
## Frames, sheets, shadows and the 32 px reading are pinned for every type in test_artgen*.gd.

const MODEL: String = "res://assets/art/models/fossil/%s.tres"
## Michael's display names (ADR 0023 answer 2, section 7), by art id.
const NAMES: Dictionary[String, String] = {
	"rifle_squad": "Roustabouts",
	"rocket_squad": "Wildcatters",
	"light_tank": "Flarejack",
	"heavy_tank": "Bullhead",
	"artillery": "Mortar Rig",
	"harvester": "Tanker",
}
const SQUADS: Array[String] = ["rifle_squad", "rocket_squad"]
const ARMED: Array[String] = ["light_tank", "heavy_tank", "artillery"]
## Wheels (a prism lying along y on the ground) by art id, as the silhouette lines count them.
const WHEELS: Dictionary[String, int] = {"light_tank": 4, "artillery": 6, "harvester": 6}
const FIGURE_LINK: float = 0.12  ## Tiles: two ground contacts this close are one figure's legs.
const TEAM_SHARE: Vector2 = Vector2(0.06, 0.14)
const KEY_TOLERANCE: float = 0.06  ## Summed difference of the three channels in 0 to 1.
const SCALE: float = 0.5  ## 2x art at zoom 1.
const PAGE: Vector2i = Vector2i(320, 320)
const GROUND_POINT: Vector2i = Vector2i(160, 200)


func test_each_model_is_the_unit_of_its_name_and_its_silhouette_line_starts_with_that_name(
) -> void:
	for id: String in NAMES:
		var model: ArtModel = _model(id)
		assert_str(model.art_id).is_equal(id)
		assert_str(model.faction).is_equal("fossil")
		assert_str(model.category).is_equal("inf" if SQUADS.has(id) else "veh")
		(
			assert_bool(model.silhouette.begins_with(NAMES[id] + ": "))
			. override_failure_message("%s: %s" % [id, model.silhouette])
			. is_true()
		)
		assert_array(model.problems()).override_failure_message(id).is_empty()
		var turret: bool = model.parts().has(&"turret")
		assert_bool(turret).override_failure_message(id).is_equal(ARMED.has(id))


## A squad is three figures: the prims that stand on the ground (the legs) fall into three groups
## that lie further apart than the two legs of one figure.
func test_a_squad_is_three_figures() -> void:
	for id: String in SQUADS:
		var feet: Array[Vector2] = []
		for prim: ArtPrim in _model(id).primitives(&"hull"):
			if is_zero_approx(prim.z0):
				feet.append(prim.centre)
		var groups: Array[int] = []
		for i: int in feet.size():
			groups.append(i)
		for i: int in feet.size():
			for j: int in range(i + 1, feet.size()):
				if feet[i].distance_to(feet[j]) <= FIGURE_LINK:
					var from: int = groups[j]
					for k: int in groups.size():
						groups[k] = groups[i] if groups[k] == from else groups[k]
		var figures: Dictionary[int, bool] = {}
		for group: int in groups:
			figures[group] = true
		assert_int(figures.size()).override_failure_message(id).is_equal(3)
		assert_int(feet.size()).override_failure_message(id).is_equal(6)


func test_the_wheels_are_the_ones_the_silhouette_line_counts_and_the_bullhead_has_two_tracks(
) -> void:
	for id: String in WHEELS:
		var wheels: int = 0
		for prim: ArtPrim in _model(id).primitives(&"hull"):
			var lies_along_y: bool = prim.shape == &"prism" and prim.axis == 1
			wheels += int(lies_along_y and is_zero_approx(prim.z0) and prim.size.x >= 0.2)
		assert_int(wheels).override_failure_message(id).is_equal(WHEELS[id])
	var tracks: int = 0
	for prim: ArtPrim in _model("heavy_tank").primitives(&"hull"):
		tracks += int(is_zero_approx(prim.z0) and prim.size.x >= 1.0 and prim.size.y < 0.3)
	assert_int(tracks).is_equal(2)


## STYLE.md "Scale": a figure is about 18 px tall at zoom 1 (0.46 tile), a vehicle fills about a
## tile and stands 16 to 30 px (0.4 to 0.77 tile) over its deck, a mast or a raised tube a little
## more; the whole picture of a vehicle, gun straight ahead, is between a tile and two long, the
## tanker longer than the mortar rig and the scout shorter than the heavy tank.
func test_each_unit_stands_in_its_size_class() -> void:
	var lengths: Dictionary[String, float] = {}
	for id: String in NAMES:
		var box: AABB = _extent(_model(id).shadow_prims())
		lengths[id] = box.size.x
		if SQUADS.has(id):
			assert_float(box.size.z).override_failure_message(id).is_between(0.36, 0.5)
			assert_float(box.size.y).override_failure_message(id).is_between(0.4, 0.8)
		else:
			assert_float(box.size.z).override_failure_message(id).is_between(0.4, 0.95)
			assert_float(box.size.y).override_failure_message(id).is_between(0.5, 1.1)
	assert_float(lengths["light_tank"]).is_between(0.9, 1.3)
	assert_float(lengths["heavy_tank"]).is_between(1.4, 2.0)
	assert_float(lengths["artillery"]).is_between(1.2, 1.6)
	assert_float(lengths["harvester"]).is_between(1.5, 1.9)
	assert_float(lengths["harvester"]).is_greater(lengths["artillery"])
	assert_float(lengths["light_tank"]).is_less(lengths["heavy_tank"])


## The muzzle is the centre of what reaches farthest along +x (STYLE.md "Generated art"), so the
## gun units need that to be a steel or iron barrel, not a hull plate; the Bullhead's barrel
## reaches at least a third of a tile past the front of its hull.
func test_the_gun_of_an_armed_vehicle_is_what_reaches_farthest_forward() -> void:
	for id: String in ARMED:
		var model: ArtModel = _model(id)
		var farthest: ArtPrim = null
		for prim: ArtPrim in model.primitives(&"turret"):
			if farthest == null or prim.aabb().end.x > farthest.aabb().end.x:
				farthest = prim
		(
			assert_bool([&"steel", &"iron"].has(farthest.material))
			. override_failure_message(id)
			. is_true()
		)
	var tank: ArtModel = _model("heavy_tank")
	var front: float = 0.0
	for prim: ArtPrim in tank.primitives(&"hull"):
		front = maxf(front, prim.aabb().end.x)
	var reach: float = 0.0
	for prim: ArtPrim in tank.primitives(&"turret"):
		reach = maxf(reach, prim.aabb().end.x)
	assert_float(reach).is_greater(front + 0.33)


func test_the_team_colour_is_6_to_14_percent_of_the_default_view() -> void:
	for id: String in NAMES:
		var share: float = _team_share(_model(id))
		assert_float(share).override_failure_message("%s %.3f" % [id, share]).is_between(
			TEAM_SHARE.x, TEAM_SHARE.y
		)


## Plan row P101 deleted the top-down unit layers with the gallery page that showed them: the
## folder is gone and no source, scene or data file names it.
func test_the_top_down_unit_files_are_gone_and_nothing_names_their_folder() -> void:
	var folder: String = "assets/art/" + "svg/units"
	assert_bool(DirAccess.dir_exists_absolute("res://" + folder)).is_false()
	var FileScan: GDScript = load("res://tests/support/file_scan.gd")
	var found: Array[String] = []
	for dir: String in ["res://game", "res://scenes", "res://data"]:
		for extension: String in [".gd", ".tscn", ".tres"]:
			for path: String in FileScan.list_files(dir, extension):
				if FileAccess.get_file_as_string(path).contains(folder):
					found.append(path)
	assert_array(found).is_empty()


func _model(id: String) -> ArtModel:
	return load(MODEL % id) as ArtModel


## The box that holds `prims`.
func _extent(prims: Array[ArtPrim]) -> AABB:
	var box: AABB = prims[0].aabb()
	for prim: ArtPrim in prims:
		box = box.merge(prim.aabb())
	return box


## The share of the default view's pixels that are the faction's key colours, counted as the
## readability suite counts it (a transparent page, the hull and the turret at its mount).
func _team_share(model: ArtModel) -> float:
	var files: Dictionary[String, String] = ArtGen.build(model)
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	var dir: int = model.default_dir()
	var picture: Image = Image.create_empty(PAGE.x, PAGE.y, false, Image.FORMAT_RGBA8)
	for part: StringName in [&"hull", &"turret"]:
		if not layouts.has(part):
			continue
		var frame: Image = Image.new()
		frame.load_svg_from_string(files[ArtGen.frame_path(model, part, dir)], SCALE)
		var offset: Vector2 = Vector2.ZERO if part == &"hull" else ArtGen.mount_px(model, dir)
		var at: Vector2i = GROUND_POINT + Vector2i((offset - Vector2(layouts[part].origin)) * SCALE)
		picture.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
	var keys: Array[Color] = []
	for hex: String in ArtPalette.KEYS[model.faction]:
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
				var gap: float = absf(pixel.r - key.r) + absf(pixel.g - key.g)
				if gap + absf(pixel.b - key.b) < KEY_TOLERANCE:
					team += 1
					break
	return float(team) / body
