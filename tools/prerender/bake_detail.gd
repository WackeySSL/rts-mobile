extends SceneTree
## P655: bakes the detailed tank (hull and turret, 16 directions). Usage:
## godot ... --script bake_detail.gd -- <job> [hex]  ; jobs: tank (all 16 dirs), truth (dirs 3 and 9 with hex),
## one <dir> (a single direction, for quick looks), stats.
const OUT: String = "/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p655/raw/"
const SCALE: float = 8.0
const SENT: String = "#D234D2"

var rig: ProtoRig
var log_lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	run.call_deferred()


func _part(sheet: IsoSheetDef, part: String) -> Dictionary:
	var i: int = sheet.parts.find(part)
	return {"w": sheet.sizes[i * 2], "h": sheet.sizes[i * 2 + 1], "ax": sheet.anchors[i * 2], "ay": sheet.anchors[i * 2 + 1]}


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var job: String = args[0]
	rig = ProtoRig.new()
	root.add_child(rig)
	rig.setup(true)
	var sheet: IsoSheetDef = load("res://assets/art/iso/fossil/veh/heavy_tank_sheet.tres")
	match job:
		"tank":
			await bake(sheet, SENT, range(16), "", SCALE)
		"tank2":
			await bake(sheet, SENT, range(16), "", SCALE)
		"one":
			await bake(sheet, SENT, [int(args[1])], "one_", SCALE)
		"svgall":
			svg_others()
		"truth":
			await bake(sheet, args[1], [3, 9], "truth_" + args[2] + "_", SCALE)
	var f: FileAccess = FileAccess.open(OUT + "log_%s.txt" % job, FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	quit()


func bake(sheet: IsoSheetDef, hex: String, dirs: Array, prefix: String, scale: float) -> void:
	var t_all: int = Time.get_ticks_msec()
	var tris: Dictionary = {}
	var t_mesh: int = Time.get_ticks_msec()
	var builders: Dictionary = {"hull": DetailTank.make("hull", hex), "turret": DetailTank.make("turret", hex)}
	var nodes: Dictionary = {}
	for part: String in builders:
		nodes[part] = (builders[part] as DetailTank).to_node()
		tris[part] = (builders[part] as DetailTank).tris
	log_lines.append("mesh build ms=%d tris hull=%d turret=%d" % [Time.get_ticks_msec() - t_mesh, tris.hull, tris.turret])
	var t_r: int = Time.get_ticks_msec()
	var n: int = 0
	for d: int in dirs:
		var yaw: float = ArtGen.yaw(d)
		for part: String in ["hull", "turret"]:
			var info: Dictionary = _part(sheet, part)
			var node: Node3D = nodes[part]
			node.rotation.y = -deg_to_rad(yaw)
			rig.set_node(node.duplicate() if false else node)
			var img: Image = await rig.render(info.w, info.h, info.ax, info.ay, scale)
			img.save_png(OUT + "%sheavy_tank_%s_d%02d.png" % [prefix, part, d])
			n += 1
			# set_node frees the old child: rebuild so the next frame has its node
			var b: DetailTank = DetailTank.make(part, hex)
			nodes[part] = b.to_node()
	log_lines.append("frames=%d render ms=%d total ms=%d" % [n, Time.get_ticks_msec() - t_r, Time.get_ticks_msec() - t_all])


## Today's other Nordvaern ground vehicles, rasterised from their generator SVG (Signal), for the readability sheet.
func svg_others() -> void:
	var key: PackedStringArray = ArtPalette.SENTINEL
	var sig: PackedStringArray = ["#FF9446", "#E8681F", "#B04B12"]
	var meta: Dictionary = {}
	var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", key, sig)
	for id: String in ["artillery", "light_tank", "harvester", "fossil_bunk_wagon", "fossil_shot_truck", "heavy_tank"]:
		var sh: IsoSheetDef = load("res://assets/art/iso/fossil/veh/%s_sheet.tres" % id)
		meta[id] = {"parts": Array(sh.parts), "sizes": Array(sh.sizes), "anchors": Array(sh.anchors), "mounts": []}
		for m: Vector2 in sh.mounts:
			meta[id].mounts.append([m.x, m.y])
		for d: int in [2, 5, 9, 10, 13]:
			for part: String in sh.parts:
				if part not in ["hull", "turret"]:
					continue
				var path: String = "res://assets/art/iso/fossil/veh/%s_%s_d%02d.svg" % [id, part, d]
				var text: String = FileAccess.get_file_as_string(path)
				if text == "":
					continue
				var img: Image = Image.new()
				img.load_svg_from_string(art.recolour(text), 1.0)
				img.save_png(OUT + "svg_%s_%s_d%02d.png" % [id, part, d])
	var f: FileAccess = FileAccess.open(OUT + "svg_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
