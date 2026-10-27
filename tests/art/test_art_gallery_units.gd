extends GdUnitTestSuite
## The Units page of the art gallery (plan rows P101 and P102, ADR 0023): the six Derrick League
## units and the six Lumen Accord units as the generator draws them, a line for team A (the Signal
## triad) and one for team B (Arktisk) of each faction on each ground with the names under team B's
## line, the Derrick League's two lines above the Lumen Accord's two, and the Flarejack in the
## scene's zoom row at the camera zoom levels, sharp at each. The page keeps the effects atlas and
## the terrain patch (tests/art/test_art_assets.gd); the pages after it are in
## test_art_gallery_pages.gd and test_art_gallery_icon_pages.gd.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const IDS: Array[String] = [
	"rifle_squad", "rocket_squad", "light_tank", "heavy_tank", "artillery", "harvester"
]
const NAMES: Array[String] = [
	"Roustabouts", "Wildcatters", "Flarejack", "Bullhead", "Mortar Rig", "Tanker"
]
const ACCORD_IDS: Array[String] = [
	"renew_rifle", "renew_rocket", "renew_scout", "renew_tank", "renew_artillery", "renew_tanker"
]
const ACCORD_NAMES: Array[String] = [
	"Linemen", "Breakers", "Swift", "Torque", "Arcline", "Fuel Runner"
]
## The four lines of a ground, top to bottom: the Derrick League's for team A and team B, then the
## Lumen Accord's (the names of a faction are under its team B line).
const ROWS: Array[String] = ["RosterA", "RosterB", "AccordA", "AccordB"]
const ARMED: Array[String] = [
	"light_tank", "heavy_tank", "artillery", "renew_scout", "renew_tank", "renew_artillery"
]
## The key triads of ADR 0023 section 5: team A's units carry the first, team B's the second.
const SIGNAL: Array[String] = ["#FF9446", "#E8681F", "#B04B12"]
const ARKTISK: Array[String] = ["#62D6EE", "#1FA6C8", "#137C99"]
const TOLERANCE: float = 0.05  ## Summed difference of the three channels in 0 to 1.
const LEVELS: Array[float] = [0.75, 1.0, 1.5]


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_rosters_are_the_six_units_of_each_faction_by_their_names_in_role_order() -> void:
	assert_array(Gallery.ROSTER_IDS).is_equal(IDS)
	assert_array(Gallery.ROSTER_NAMES).is_equal(NAMES)
	assert_array(Gallery.ACCORD_IDS).is_equal(ACCORD_IDS)
	assert_array(Gallery.ACCORD_NAMES).is_equal(ACCORD_NAMES)
	for id: String in IDS:
		var model: ArtModel = load("res://assets/art/models/fossil/%s.tres" % id) as ArtModel
		assert_str(model.faction).is_equal("fossil")
		assert_bool(model.silhouette.begins_with(NAMES[IDS.find(id)] + ": ")).is_true()
	for id: String in ACCORD_IDS:
		var model: ArtModel = load("res://assets/art/models/renew/%s.tres" % id) as ArtModel
		assert_str(model.faction).is_equal("renew")
		(
			assert_bool(model.silhouette.begins_with(ACCORD_NAMES[ACCORD_IDS.find(id)] + ": "))
			. is_true()
		)
		# A column is one role: the Lumen Accord's unit under the Derrick League's has its category.
		var twin: ArtModel = load(
			"res://assets/art/models/fossil/%s.tres" % IDS[ACCORD_IDS.find(id)]
		)
		assert_str(model.category).override_failure_message(id).is_equal(twin.category)
		assert_array(model.parts()).override_failure_message(id).is_equal(twin.parts())


func test_each_ground_has_a_line_of_each_factions_six_units_for_team_a_and_one_for_team_b() -> void:
	var gallery: Control = await _open_gallery()
	for ground: String in ["Grass", "Sand"]:
		for row_name: String in ROWS:
			var is_a: bool = row_name.ends_with("A")
			var ids: Array[String] = ACCORD_IDS if row_name.begins_with("Accord") else IDS
			var shown: Array[String] = ACCORD_NAMES if row_name.begins_with("Accord") else NAMES
			var row: Node = gallery.get_node("%s/%s" % [ground, row_name])
			var path: String = "%s %s" % [ground, row_name]
			var rigs: Array[Node] = row.get_children().filter(
				func(node: Node) -> bool: return node is Node2D
			)
			assert_array(rigs.map(_node_name)).override_failure_message(path).is_equal(
				ids.map(func(id: String) -> String: return id.to_pascal_case())
			)
			var group: StringName = Gallery.TEAM_A_GROUP if is_a else Gallery.TEAM_B_GROUP
			for rig: Node2D in rigs:
				var id: String = String(rig.name).to_snake_case()
				var parts: Array[String] = ["Shadow", "Hull"]
				if ARMED.has(id):
					parts.append("Gun")
				(
					assert_array(rig.get_children().map(_node_name))
					. override_failure_message(path + " " + id)
					. is_equal(parts)
				)
				assert_bool(rig.is_in_group(group)).override_failure_message(path).is_true()
				assert_vector(rig.scale).is_equal(Vector2.ONE)
			var names: Array[String] = []
			for label: Node in row.find_children("Label*", "Label", false, false):
				names.append((label as Label).text)
			assert_array(names).override_failure_message(path).is_equal([] if is_a else shown)
		assert_bool(gallery.get_node(ground).has_node("SlotA")).is_false()


## The team colour is in the SVG text, replaced per player as the match-start bake does: a unit of
## team A holds the Signal colours and none of Arktisk, a unit of team B the other way round.
func test_team_a_is_drawn_in_the_signal_triad_and_team_b_in_arktisk() -> void:
	var gallery: Control = await _open_gallery()
	for ground: String in ["Grass", "Sand"]:
		for row_name: String in ROWS:
			var is_a: bool = row_name.ends_with("A")
			for rig: Node in gallery.get_node("%s/%s" % [ground, row_name]).get_children():
				if rig is Node2D:
					var hull: Image = (
						((rig as Node2D).get_node("Hull") as Sprite2D).texture.get_image()
					)
					var path: String = "%s %s %s" % [ground, row_name, rig.name]
					var own: int = _pixels_of(hull, SIGNAL if is_a else ARKTISK)
					var other: int = _pixels_of(hull, ARKTISK if is_a else SIGNAL)
					assert_int(own).override_failure_message(path).is_greater(0)
					assert_int(other).override_failure_message(path).is_equal(0)


## The zoom row is in the scene (tests/project pins its scales to the camera levels): the Flarejack
## at 0.75, 1 and 1.5, team A on grass and team B on sand, each drawn at the sharpness the zoom asks
## for (the texture holds one texel per screen px and the sprite is scaled back by the zoom).
func test_the_zoom_row_shows_the_flarejack_at_each_camera_zoom_in_its_grounds_team() -> void:
	var gallery: Control = await _open_gallery()
	var model: ArtModel = load("res://assets/art/models/fossil/light_tank.tres") as ArtModel
	var canvas: Vector2 = Vector2(ArtGen.layouts(model)[&"hull"].size)
	for ground: String in ["Grass", "Sand"]:
		var scales: Array[float] = []
		for node: Node in gallery.get_node(ground + "/ZoomRow").get_children():
			if not node is Node2D:
				continue
			var rig: Node2D = node as Node2D
			var zoom: float = rig.scale.x
			scales.append(zoom)
			assert_array(rig.get_children().map(_node_name)).is_equal(["Shadow", "Hull", "Gun"])
			var hull: Sprite2D = rig.get_node("Hull")
			assert_vector(hull.scale).is_equal_approx(Vector2.ONE / zoom, Vector2.ONE * 1e-6)
			assert_vector(Vector2(hull.texture.get_size())).is_equal_approx(
				canvas * 0.5 * zoom, Vector2.ONE * 1.0
			)
			var image: Image = hull.texture.get_image()
			var own: Array[String] = SIGNAL if ground == "Grass" else ARKTISK
			assert_int(_pixels_of(image, own)).override_failure_message(ground).is_greater(0)
			assert_int(_pixels_of(image, ARKTISK if ground == "Grass" else SIGNAL)).is_equal(0)
		scales.sort()
		assert_array(scales).is_equal(LEVELS)


## A frame cannot turn (the view picks one of 16), and the gallery turns every sprite named
## `Turret`: the generated parts are not called that, so `_process` leaves them alone.
func test_generated_units_do_not_turn_with_the_gallery_turrets() -> void:
	var gallery: Control = await _open_gallery()
	gallery.call("_process", 0.5)
	for gun: Node in gallery.find_children("Gun", "Sprite2D", true, false):
		assert_float((gun as Sprite2D).rotation).is_equal(0.0)
	for row_name: String in ROWS:
		for rig: Node in gallery.get_node("Grass/" + row_name).get_children():
			if rig is Node2D:
				assert_float((rig as Node2D).rotation).is_equal(0.0)
	for turret: Node in gallery.find_children("Turret", "Sprite2D", true, false):
		var path: String = str(turret.get_path())
		for line: String in ["Roster", "Accord", "ZoomRow"]:
			assert_bool(path.contains(line)).override_failure_message(path).is_false()


## Every unit is inside its ground, clear of the two corner buttons, the effects atlas and the
## terrain patch, and no two units of a ground cover each other, whichever line they stand in or
## whether they stand in the zoom row; every name is inside its ground, is as narrow as its slot,
## and covers no unit of another line and no other name. On the phone that is tightest in height,
## a wider one and a tablet.
func test_the_roster_fits_each_half_and_keeps_clear_of_the_buttons_atlas_patch_and_zoom_row(
) -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		var problems: Array[String] = []
		var avoid: Array[Rect2] = [
			(gallery.get_node("%BackButton") as Control).get_global_rect(),
			(gallery.get_node("%PageButton") as Control).get_global_rect(),
			(gallery.get_node("TerrainRow/Frame") as Control).get_global_rect(),
		]
		for ground_name: String in ["Grass", "Sand"]:
			var ground: Control = gallery.get_node(ground_name)
			var half: Rect2 = ground.get_global_rect()
			var atlas: Rect2 = (ground.get_node("EffectsAtlas") as Control).get_global_rect()
			var seen: Dictionary[String, Rect2] = {}
			var names: Dictionary[String, Rect2] = {}
			for row_name: String in ROWS:
				var row: Node = ground.get_node(row_name)
				for rig: Node in row.get_children():
					if rig is Node2D:
						seen["%s %s" % [row_name, rig.name]] = _box(
							(rig as Node2D).get_node("Hull")
						)
					elif rig is Label:
						var label: Label = rig as Label
						names["%s %s" % [row_name, label.text]] = label.get_global_rect()
						assert_float(label.size.x).is_less_equal(Gallery.ROSTER_GAP_PX + 0.5)
			for node: Node in ground.get_node("ZoomRow").get_children():
				if node is Node2D:
					seen["ZoomRow " + node.name] = _box((node as Node2D).get_node("Hull"))
				elif node is Label:
					names["ZoomRow " + (node as Label).text] = (node as Label).get_global_rect()
			assert_int(seen.size()).is_equal(2 * (IDS.size() + ACCORD_IDS.size()) + 3)
			# The zoom row's three labels are on the grass half only.
			var labels: int = IDS.size() + ACCORD_IDS.size() + (3 if ground_name == "Grass" else 0)
			assert_int(names.size()).is_equal(labels)
			for unit: String in seen:
				var box: Rect2 = seen[unit]
				if not half.encloses(box):
					problems.append("%s %s is outside its half" % [ground_name, unit])
				for other: Rect2 in avoid + [atlas]:
					if box.intersects(other):
						problems.append("%s %s is over %s" % [ground_name, unit, other])
				for other_unit: String in seen:
					if other_unit < unit and box.intersects(seen[other_unit]):
						problems.append("%s %s covers %s" % [ground_name, unit, other_unit])
			for text: String in names:
				var rect: Rect2 = names[text]
				if not half.encloses(rect):
					problems.append("%s name %s is outside its half" % [ground_name, text])
				for other_text: String in names:
					if other_text < text and rect.intersects(names[other_text]):
						problems.append("%s name %s covers %s" % [ground_name, text, other_text])
				for unit: String in seen:
					# A name sits under its own unit, which may reach into its box: only the units
					# of another line and the zoom row count.
					var same_line: bool = unit.split(" ")[0] == text.split(" ")[0]
					if not same_line and rect.intersects(seen[unit]):
						problems.append("%s name %s is over %s" % [ground_name, text, unit])
		assert_array(problems).override_failure_message(str(base)).is_empty()
		# One at a time: galleries alive together restore quit_on_go_back in a bad order.
		gallery.get_parent().free()


## The pixels of `image` that are within `TOLERANCE` of one of the three colours of a triad.
func _pixels_of(image: Image, triad: Array[String]) -> int:
	var keys: Array[Color] = []
	for hex: String in triad:
		keys.append(Color(hex))
	var found: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.95:
				continue
			for key: Color in keys:
				var gap: float = absf(pixel.r - key.r) + absf(pixel.g - key.g)
				if gap + absf(pixel.b - key.b) < TOLERANCE:
					found += 1
					break
	return found


## The bounding box of a sprite on screen.
func _box(sprite: Node) -> Rect2:
	var node: Sprite2D = sprite as Sprite2D
	return node.get_global_transform() * node.get_rect()


func _node_name(node: Node) -> String:
	return String(node.name)


func _assert_quit_on_go_back_restored() -> void:
	var restored: bool = get_tree().quit_on_go_back
	assert_bool(restored).override_failure_message("quit_on_go_back leaked").is_true()


## The gallery in a parent of `base_size`, the base size of a 16:9 phone unless given.
func _open_gallery(base_size: Vector2 = Vector2(1280, 720)) -> Control:
	var gallery: Control = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	var parent: Control = auto_free(Control.new())
	parent.size = base_size
	add_child(parent)
	parent.add_child(gallery)
	await await_idle_frame()
	return gallery
