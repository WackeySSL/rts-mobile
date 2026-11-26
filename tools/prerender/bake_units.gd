extends SceneTree
## P653: bakes the prototype frames of one unit (hull, turret and shadow, 16 directions) or of one
## building. Usage: godot ... --script bake_units.gd -- <job> ; jobs: tank, bld, truth, svg.

const OUT: String = "/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p653/raw/"
const SCALE: float = 8.0  ## texels per art px (the 2x-density bake is a 4:1 box filter of it).
const SIGNAL: PackedStringArray = ["#FF9446", "#E8681F", "#B04B12"]
const KOBOLT: PackedStringArray = ["#7AA2F7", "#3F6FE0", "#27479E"]

var rig: ProtoRig
var log_lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	run.call_deferred()


func _sheet(art_id: String, faction: String, cat: String) -> IsoSheetDef:
	return load("res://assets/art/iso/%s/%s/%s_sheet.tres" % [faction, cat, art_id])


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var job: String = OS.get_cmdline_user_args()[0]
	rig = ProtoRig.new()
	root.add_child(rig)
	rig.setup(true)
	match job:
		"tank":
			await bake_tank("heavy_tank", "")
		"det":
			await bake_tank("heavy_tank", "", [3], "det_")
		"truth":
			await bake_tank("heavy_tank", KOBOLT[1], [3, 9], "truthB_")
			await bake_tank("heavy_tank", SIGNAL[1], [3, 9], "truthO_")
		"bld":
			await bake_building("vehicle_factory", "")
			await bake_building("vehicle_factory", KOBOLT[1], "truthB_")
		"svg":
			svg_rasterise()
	var f: FileAccess = FileAccess.open(OUT + "log_%s.txt" % job, FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	quit()


func _part(sheet: IsoSheetDef, part: String) -> Dictionary:
	var i: int = sheet.parts.find(part)
	return {
		"w": sheet.sizes[i * 2], "h": sheet.sizes[i * 2 + 1],
		"ax": sheet.anchors[i * 2], "ay": sheet.anchors[i * 2 + 1],
	}


func bake_tank(art_id: String, team_hex: String, only: Array = [], prefix: String = "") -> void:
	var model: ArtModel = load("res://assets/art/models/fossil/%s.tres" % art_id)
	var sheet: IsoSheetDef = _sheet(art_id, "fossil", "veh")
	var t_all: int = Time.get_ticks_msec()
	var n: int = 0
	for d: int in 16:
		if not only.is_empty() and d not in only:
			continue
		var yaw: float = ArtGen.yaw(d)
		for part: String in ["hull", "turret", "shadow"]:
			var info: Dictionary = _part(sheet, part)
			var node: Node3D
			if part == "shadow":
				node = ProtoBuild.build(model, &"hull", &"fossil", 0.8, true, "", model.mount)
			else:
				node = ProtoBuild.build(model, StringName(part), &"fossil", 0.0, false, team_hex)
			node.rotation.y = -deg_to_rad(yaw)
			rig.set_node(node)
			var img: Image = await rig.render(info.w, info.h, info.ax, info.ay, SCALE)
			img.save_png(OUT + "%s%s_%s_d%02d.png" % [prefix, art_id, part, d])
			n += 1
	log_lines.append("%s%s frames=%d ms=%d" % [prefix, art_id, n, Time.get_ticks_msec() - t_all])


func bake_building(art_id: String, team_hex: String, prefix: String = "") -> void:
	var model: ArtModel = load("res://assets/art/models/fossil/%s.tres" % art_id)
	var sheet: IsoSheetDef = _sheet(art_id, "fossil", "bld")
	var t_all: int = Time.get_ticks_msec()
	for part: String in ["hull", "shadow"]:
		var info: Dictionary = _part(sheet, part)
		var node: Node3D
		if part == "shadow":
			node = ProtoBuild.build(model, &"hull", &"fossil", 0.8, true, "", Vector3.ZERO)
		else:
			node = ProtoBuild.build(model, &"hull", &"fossil", 0.0, false, team_hex)
		rig.set_node(node)
		var img: Image = await rig.render(info.w, info.h, info.ax, info.ay + 32 * model.footprint, 4.0)
		img.save_png(OUT + "%s%s_%s.png" % [prefix, art_id, part])
	log_lines.append("%s%s ms=%d" % [prefix, art_id, Time.get_ticks_msec() - t_all])


func svg_rasterise() -> void:
	var dir: String = OUT + "svg/"
	DirAccess.make_dir_recursive_absolute(dir)
	var key: PackedStringArray = ArtPalette.SENTINEL
	var jobs: Array[String] = []
	for d: int in 16:
		for part: String in ["hull", "turret", "shadow"]:
			jobs.append("res://assets/art/iso/fossil/veh/heavy_tank_%s_d%02d.svg" % [part, d])
	jobs.append("res://assets/art/iso/fossil/bld/vehicle_factory_hull.svg")
	jobs.append("res://assets/art/iso/fossil/bld/vehicle_factory_shadow.svg")
	for gname: String in ["grass_a", "grass_b", "sand_a", "sand_b", "rock_a", "rock_b", "scrub_a", "scrub_b", "ore_a", "water_a", "water_b"]:
		jobs.append("res://assets/art/svg/ground/%s.svg" % gname)
	for path: String in jobs:
		var text: String = FileAccess.get_file_as_string(path)
		if text == "":
			log_lines.append("MISSING " + path)
			continue
		for pair: Array in [["O", SIGNAL], ["B", KOBOLT]]:
			var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", key, pair[1])
			var img: Image = Image.new()
			img.load_svg_from_string(art.recolour(text), 1.0)
			img.save_png(dir + "%s_%s.png" % [path.get_file().get_basename(), pair[0]])
