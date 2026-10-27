extends GdUnitTestSuite
## The twelve unit models of plan rows P101 and P102 (ADR 0023 sections 6 and 7, STYLE.md "Derrick
## League units" and "Lumen Accord units"): each is named in its silhouette line, a squad is three
## figures, a vehicle has the wheels or tracks its line says and stands in its size class, the gun
## of an armed vehicle is the thing that reaches farthest forward and stands on the centre line (one
## barrel), the team colour is 6 to 14 % of the default view (the art rows aim at 8 to 12 %, ADR
## 0023 section 5), each Lumen Accord unit carries the faction's hexagon and mint light, and the
## top-down unit files are gone. Frames, sheets, shadows and the 32 px reading are pinned for every
## type in test_artgen*.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
## Michael's display names (ADR 0023 answer 2, section 7), by art id.
const NAMES: Dictionary[String, String] = {
	"rifle_squad": "Roustabouts",
	"rocket_squad": "Wildcatters",
	"light_tank": "Flarejack",
	"heavy_tank": "Bullhead",
	"artillery": "Mortar Rig",
	"harvester": "Tanker",
	"renew_rifle": "Linemen",
	"renew_rocket": "Breakers",
	"renew_scout": "Swift",
	"renew_tank": "Torque",
	"renew_artillery": "Arcline",
	"renew_tanker": "Fuel Runner",
}
const ACCORD: Array[String] = [
	"renew_rifle", "renew_rocket", "renew_scout", "renew_tank", "renew_artillery", "renew_tanker"
]
const SQUADS: Array[String] = ["rifle_squad", "rocket_squad", "renew_rifle", "renew_rocket"]
const ARMED: Array[String] = [
	"light_tank", "heavy_tank", "artillery", "renew_scout", "renew_tank", "renew_artillery"
]
## What a gun is made of, by faction.
const GUN_MATERIALS: Dictionary[String, Array] = {
	"fossil": [&"steel", &"iron"], "renew": [&"titanium", &"graphite"]
}
## The length of a vehicle's whole picture, gun straight ahead, by art id: the size classes of
## STYLE.md "Scale" (a Lumen Accord unit stands in the class of its Derrick League twin).
const LENGTHS: Dictionary[String, Vector2] = {
	"light_tank": Vector2(0.9, 1.3),
	"heavy_tank": Vector2(1.4, 2.0),
	"artillery": Vector2(1.2, 1.6),
	"harvester": Vector2(1.5, 1.9),
	"renew_scout": Vector2(0.9, 1.3),
	"renew_tank": Vector2(1.4, 2.0),
	"renew_artillery": Vector2(1.2, 1.6),
	"renew_tanker": Vector2(1.5, 1.9),
}
## Each faction's scout, tank, artillery and tanker: the tanker is longer than the artillery and the
## scout shorter than the tank.
const ROLES: Array[Array] = [
	["light_tank", "heavy_tank", "artillery", "harvester"],
	["renew_scout", "renew_tank", "renew_artillery", "renew_tanker"],
]
## Wheels (a prism lying along y on the ground) by art id, as the silhouette lines count them.
const WHEELS: Dictionary[String, int] = {
	"light_tank": 4,
	"artillery": 6,
	"harvester": 6,
	"renew_scout": 4,
	"renew_artillery": 4,
	"renew_tanker": 4,
}
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
		assert_str(model.faction).is_equal("renew" if ACCORD.has(id) else "fossil")
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


func test_the_wheels_are_the_ones_the_silhouette_line_counts_and_the_tanks_have_their_tracks(
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
	# The Torque stands on one long continuous track a side, as long as its hull, like any ordinary
	# tank, and not on separate pods at the corners: exactly two ground boxes of any length, one on
	# each side of the centre line, each covering most of the way from the rear of the hull to its
	# nose.
	var hull_from: float = INF
	var hull_to: float = -INF
	var runs: Array[ArtPrim] = []
	for prim: ArtPrim in _model("renew_tank").primitives(&"hull"):
		if prim.material == &"bluegrey":
			hull_from = minf(hull_from, prim.aabb().position.x)
			hull_to = maxf(hull_to, prim.aabb().end.x)
		if is_zero_approx(prim.z0) and prim.shape == &"box" and prim.size.x >= 0.4:
			runs.append(prim)
	assert_int(runs.size()).is_equal(2)
	assert_float(signf(runs[0].centre.y) * signf(runs[1].centre.y)).is_equal(-1.0)
	for run: ArtPrim in runs:
		assert_float(run.size.x).is_greater_equal((hull_to - hull_from) * 0.85)


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
	for id: String in LENGTHS:
		assert_float(lengths[id]).override_failure_message(id).is_between(
			LENGTHS[id].x, LENGTHS[id].y
		)
	for roles: Array in ROLES:
		var scout: float = lengths[roles[0] as String]
		var tank: float = lengths[roles[1] as String]
		var artillery: float = lengths[roles[2] as String]
		var tanker: float = lengths[roles[3] as String]
		assert_float(tanker).is_greater(artillery)
		assert_float(scout).is_less(tank)


## The muzzle is the centre of what reaches farthest along +x (STYLE.md "Generated art"), so the
## gun units need that to be a barrel (steel or iron for the Derrick League, titanium or graphite
## for the Lumen Accord), not a hull plate; a tank's barrel reaches at least a third of a tile past
## the front of its hull.
func test_the_gun_of_an_armed_vehicle_is_what_reaches_farthest_forward() -> void:
	for id: String in ARMED:
		var model: ArtModel = _model(id)
		var farthest: ArtPrim = null
		for prim: ArtPrim in model.primitives(&"turret"):
			if farthest == null or prim.aabb().end.x > farthest.aabb().end.x:
				farthest = prim
		var made_of: Array = GUN_MATERIALS[model.faction]
		assert_bool(made_of.has(farthest.material)).override_failure_message(id).is_true()
	for id: String in ["heavy_tank", "renew_tank"]:
		var tank: ArtModel = _model(id)
		var front: float = 0.0
		for prim: ArtPrim in tank.primitives(&"hull"):
			front = maxf(front, prim.aabb().end.x)
		var reach: float = 0.0
		for prim: ArtPrim in tank.primitives(&"turret"):
			reach = maxf(reach, prim.aabb().end.x + tank.mount.x)
		assert_float(reach).override_failure_message(id).is_greater(front + 0.33)


## One barrel, never a pair (ADR 0023 section 6 on originality: no twin-barrelled tank): the
## farthest-reaching piece of the Lumen Accord's armed vehicles stands on the centre line.
func test_the_lumen_accord_guns_are_single_barrels_on_the_centre_line() -> void:
	for id: String in ARMED:
		if not ACCORD.has(id):
			continue
		var farthest: ArtPrim = null
		for prim: ArtPrim in _model(id).primitives(&"turret"):
			if farthest == null or prim.aabb().end.x > farthest.aabb().end.x:
				farthest = prim
		assert_float(farthest.centre.y).override_failure_message(id).is_equal(0.0)
		var long_pieces: int = 0
		for prim: ArtPrim in _model(id).primitives(&"turret"):
			var is_barrel: bool = prim.shape == &"prism" and prim.axis == 0 and prim.size.x >= 0.3
			long_pieces += int(is_barrel and GUN_MATERIALS["renew"].has(prim.material))
		# The Swift and the Torque have one long rail; the Arcline's is a stair of short steps.
		assert_int(long_pieces).override_failure_message(id).is_equal(
			0 if id == "renew_artillery" else 1
		)


## Three details that were lost at 32 px in greyscale and are pinned so they stay (P102 fix round):
## the Torque's barrel is graphite, not titanium (titanium is the grey of the hull), and a thicker
## graphite block stands at its muzzle; the Fuel Runner's glass tank is round, not a hexagonal
## box, with a hatch dome standing above its top, so it is a tanker and not a white van; and the
## Linemen's cable-reel hub is wider than its team flanges, so a dark rim shows round each.
func test_the_torque_barrel_the_fuel_runner_tank_and_the_linemen_reel_read_at_32_px() -> void:
	var torque: ArtModel = _model("renew_tank")
	var barrel: ArtPrim = null
	var muzzle: ArtPrim = null
	for prim: ArtPrim in torque.primitives(&"turret"):
		if prim.shape == &"prism" and prim.axis == 0 and prim.size.x >= 0.3:
			barrel = prim
		if muzzle == null or prim.aabb().end.x > muzzle.aabb().end.x:
			muzzle = prim
	assert_bool(barrel.material == &"graphite").is_true()
	assert_bool(muzzle.material == &"graphite").is_true()
	assert_float(barrel.size.y).is_greater_equal(0.08)
	assert_float(muzzle.size.y).is_greater_equal(barrel.size.y + 0.05)
	assert_float(muzzle.size.z).is_greater_equal(barrel.size.z + 0.03)
	var tanker: ArtModel = _model("renew_tanker")
	var tanks: int = 0
	var tank_top: float = 0.0
	var dome_top: float = 0.0
	for prim: ArtPrim in tanker.primitives(&"hull"):
		if prim.material == &"glass" and prim.shape == &"prism" and prim.axis == 0:
			tanks += int(prim.sides >= 8)
			tank_top = maxf(tank_top, prim.aabb().end.z)
	for prim: ArtPrim in tanker.primitives(&"hull"):
		if prim.shape == &"prism" and prim.axis == 2 and prim.sides >= 8 and prim.z0 > 0.4:
			dome_top = maxf(dome_top, prim.aabb().end.z)
	assert_int(tanks).is_equal(2)
	assert_float(dome_top).is_greater_equal(tank_top + 0.08)
	var hub: float = INF
	var flange: float = 0.0
	for prim: ArtPrim in _model("renew_rifle").primitives(&"hull"):
		if prim.shape == &"prism" and prim.axis == 1:
			if prim.material == &"graphite":
				hub = minf(hub, prim.size.x)
			if prim.material == &"team":
				flange = maxf(flange, prim.size.x)
	assert_float(hub - flange).is_greater_equal(0.05)


## The Lumen Accord's form language (ADR 0023 section 6): hexagons (a helmet, a turret ring, the
## tank) and a mint status light on every unit, and none of the Derrick League's materials.
func test_every_lumen_accord_unit_has_a_hexagon_and_a_mint_light() -> void:
	for id: String in ACCORD:
		var hexagons: int = 0
		var mint: int = 0
		for part: StringName in _model(id).parts():
			for prim: ArtPrim in _model(id).primitives(part):
				hexagons += int(prim.shape == &"prism" and prim.sides == 6)
				mint += int(prim.material == &"mint")
		assert_int(hexagons).override_failure_message(id).is_greater(0)
		assert_int(mint).override_failure_message(id).is_greater(0)


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
	return load(MODEL % ["renew" if ACCORD.has(id) else "fossil", id]) as ArtModel


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
