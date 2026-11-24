extends SceneTree
## P601 style prototype driver (exploration, never merged). Renders the richer models with
## `ArtDetail` at four levels, writes SVG frames, the geometry for the PNG bake, rasterised PNGs of
## the SVGs (current art too) and `stats.json`, all under the scratch directory given after `--`.
##
##   godot --headless --path . --script res://tools/artgen/gen_proto_p601.gd -- /abs/scratch/dir
## Committed samples (default direction, level 3) go to res://docs/proto/p601/svg/.

const DOCS: String = "res://docs/proto/p601"
const SCALES: Array[float] = [0.75, 1.0, 1.5, 2.25, 2.5]
const TEAM_DEMO: Array[String] = ["#8CEBFF", "#2FC4E8", "#1B8FB5"]
const BLUE: Array[String] = ["#68A8F2", "#2F6FD0", "#1B4A9C"]
const JOBS: Array[Dictionary] = [
	{
		"id": "tank",
		"proto": "res://docs/proto/p601/models/heavy_tank_p601.tres",
		"current": "res://assets/art/models/fossil/heavy_tank.tres",
		"dir": 6,
	},
	{
		"id": "hq",
		"proto": "res://docs/proto/p601/models/helix_hq_p601.tres",
		"current": "res://assets/art/models/renew/renew_hq.tres",
		"dir": -1,
	},
	{
		"id": "tank2",
		"proto": "res://docs/proto/p601/models/heavy_tank_p601b.tres",
		"current": "res://assets/art/models/fossil/heavy_tank.tres",
		"dir": 6,
		"levels": [3, 4],
		"final": 4,
		"skip_current": true,
		"docs": "round2/svg",
	},
]

var _scratch: String = ""
var _stats: Dictionary = {}


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- /abs/scratch/dir")
		quit(2)
		return
	_scratch = args[0]
	for tile: String in ["sand_a", "sand_b", "rock_a", "rock_b"]:
		var text: String = FileAccess.get_file_as_string(
			"res://assets/art/svg/ground/%s.svg" % tile
		)
		for scale: float in SCALES:
			_raster(
				text,
				scale,
				_scratch.path_join("png/ground/%s_s%d.png" % [tile, roundi(scale * 100.0)])
			)
	for job: Dictionary in JOBS:
		_job(job)
	_write(_scratch.path_join("stats.json"), JSON.stringify(_stats, "  "))
	quit(0)


func _job(job: Dictionary) -> void:
	var id: String = job["id"]
	var proto: ArtModel = load(job["proto"]) as ArtModel
	var current: ArtModel = load(job["current"]) as ArtModel
	var problems: PackedStringArray = proto.problems()
	if not problems.is_empty():
		print("proto %s problems: %s" % [id, problems])
	var parts: Array[StringName] = [&"hull"]
	if not proto.primitives(&"turret").is_empty():
		parts.append(&"turret")
	var dirs: Array[int] = proto.directions(&"hull")
	var turret_dirs: Array[int] = []
	if parts.size() > 1:
		turret_dirs = proto.directions(&"turret")
	var manifest: Dictionary = {"id": id, "dir": job["dir"], "parts": parts}
	# 1. Current art: rasterise the committed frames, record layouts and sizes.
	if not job.get("skip_current", false):
		_current(current, id, manifest, parts)
	# 2. Prototype at each level.
	if proto.faction == &"renew":
		ArtPalette.key_override = {&"renew": BLUE}
	elif id == "tank2":
		ArtPalette.key_override = {&"fossil": TEAM_DEMO}
	var level_stats: Dictionary = {}
	var levels: Array = job.get("levels", [0, 1, 2, 3])
	for level: int in levels:
		level_stats[str(level)] = _proto_level(
			proto, id, level, parts, dirs, turret_dirs, manifest, job
		)
	ArtPalette.key_override = {}
	_stats[id] = {"levels": level_stats}
	_write(_scratch.path_join("%s_manifest.json" % id), JSON.stringify(manifest, "  "))


func _current(model: ArtModel, id: String, manifest: Dictionary, parts: Array[StringName]) -> void:
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	var bytes: int = 0
	var polys: int = 0
	var frames: int = 0
	var cur: Dictionary = {"layouts": {}, "mount": {}}
	for part: StringName in layouts:
		cur["layouts"][str(part)] = _lay(layouts[part])
	var all_parts: Array[StringName] = [&"hull", &"turret", ArtModel.SHADOW]
	for part: StringName in all_parts:
		if part == &"turret" and parts.size() < 2:
			continue
		for dir: int in model.directions(part):
			var path: String = ArtGen.frame_path(model, part, dir)
			var text: String = FileAccess.get_file_as_string(path)
			bytes += text.length()
			polys += text.count("<polygon")
			frames += 1
			for scale: float in _scales_for(dir, int(manifest["dir"])):
				_raster(text, scale, _png("cur", id, part, maxi(dir, 0), scale))
	for dir: int in model.directions(&"hull"):
		var m: Vector2 = ArtGen.mount_px(model, dir)
		cur["mount"][str(dir)] = [m.x, m.y]
	manifest["cur"] = cur
	_stats[id + "_current"] = {
		"bytes": bytes,
		"polys": polys,
		"frames": frames,
		"sizes": _sizes(layouts),
	}


func _proto_level(
	model: ArtModel,
	id: String,
	level: int,
	parts: Array[StringName],
	dirs: Array[int],
	turret_dirs: Array[int],
	manifest: Dictionary,
	job: Dictionary
) -> Dictionary:
	var final: int = job.get("final", 3)
	var shadow_prims: Array[ArtPrim] = model.shadow_prims()
	var shots: Dictionary = {}
	var box_all: Dictionary = {}
	for part: StringName in [&"hull", &"turret", ArtModel.SHADOW]:
		if part == &"turret" and parts.size() < 2:
			continue
		var list: Array[int] = turret_dirs if part == &"turret" else dirs
		var union: Rect2 = Rect2()
		var first: bool = true
		var polys_by_dir: Dictionary = {}
		for dir: int in list:
			var turn: float = ArtGen.yaw(dir) if dir >= 0 else 0.0
			var polys: Array[ArtDetail.DPoly] = []
			if part == ArtModel.SHADOW:
				polys = ArtDetail.shadow(shadow_prims, turn, 10 if level >= 4 else 6)
			else:
				polys = ArtDetail.render(model.primitives(part), turn, model.faction, level)
			polys_by_dir[dir] = polys
			var b: Rect2 = ArtDetail.bounds(polys)
			union = b if first else union.merge(b)
			first = false
		var fp: int = model.footprint if part in [&"hull", ArtModel.SHADOW] else 0
		var lay: ArtGen.Layout = ArtGen._layout(union, fp)
		shots[part] = {"layout": lay, "polys": polys_by_dir, "dirs": list}
		box_all[str(part)] = _lay(lay)
	var bytes: int = 0
	var poly_count: int = 0
	var frames: int = 0
	var kinds: Dictionary = {}
	for part: StringName in shots:
		var shot: Dictionary = shots[part]
		var lay: ArtGen.Layout = shot["layout"]
		for dir: int in shot["dirs"]:
			var polys: Array[ArtDetail.DPoly] = []
			polys.assign(shot["polys"][dir])
			var comment: String = (
				"%s %s d%02d level %d: P601 prototype, do not edit" % [id, part, dir, level]
			)
			var text: String = ArtDetail.svg(
				comment,
				lay.size,
				lay.origin,
				polys,
				0.4 if part == ArtModel.SHADOW else 1.0,
				level >= 4
			)
			bytes += text.length()
			poly_count += polys.size()
			frames += 1
			for p: ArtDetail.DPoly in polys:
				kinds[str(p.kind)] = int(kinds.get(str(p.kind), 0)) + 1
			var is_default: bool = dir == int(manifest["dir"]) or (dir < 0)
			if level == final:
				if is_default:
					_write(
						ProjectSettings.globalize_path(DOCS).path_join(
							"%s/%s_%s_d%02d.svg" % [job.get("docs", "svg"), id, part, maxi(dir, 0)]
						),
						text
					)
				else:
					_write(_scratch.path_join("svg3/%s_%s_d%02d.svg" % [id, part, dir]), text)
				if part != ArtModel.SHADOW:
					_geometry(
						polys,
						lay,
						_scratch.path_join("geom/%s_%s_d%02d.json" % [id, part, maxi(dir, 0)])
					)
			var wanted: Array[float] = []
			if level == final:
				wanted = _scales_for(dir, int(manifest["dir"]))
			elif is_default:
				wanted = [1.5]
			for scale: float in wanted:
				_raster(text, scale, _png("L%d" % level, id, part, maxi(dir, 0), scale))
	if level == final:
		var mounts: Dictionary = {}
		for dir: int in dirs:
			var m: Vector2 = ArtGen.mount_px(model, dir)
			mounts[str(dir)] = [m.x, m.y]
		manifest["proto"] = {"layouts": box_all, "mount": mounts}
	var sizes: Dictionary = {}
	for part: StringName in shots:
		sizes[str(part)] = _lay(shots[part]["layout"])["size"]
	return {"bytes": bytes, "polys": poly_count, "frames": frames, "kinds": kinds, "sizes": sizes}


## The faces of a frame for the PNG bake: screen points (origin applied), 3D points, normal, albedo.
func _geometry(polys: Array[ArtDetail.DPoly], lay: ArtGen.Layout, path: String) -> void:
	var faces: Array = []
	for p: ArtDetail.DPoly in polys:
		if p.kind != &"face":
			continue
		var pts: Array = []
		for v: Vector2 in p.points:
			pts.append([v.x + lay.origin.x, v.y + lay.origin.y])
		var p3: Array = []
		for v3: Vector3 in p.pts3:
			p3.append([v3.x, v3.y, v3.z])
		(
			faces
			. append(
				{
					"pts": pts,
					"p3": p3,
					"n": [p.normal.x, p.normal.y, p.normal.z],
					"mat": str(p.material),
					"prim": p.prim,
					"top": p.top,
					"albedo": ArtPalette.mid_hex(_faction(), p.material),
				}
			)
		)
	_write(path, JSON.stringify({"size": [lay.size.x, lay.size.y], "faces": faces}))


func _faction() -> StringName:
	if ArtPalette.key_override.has(&"renew"):
		return &"renew"
	return &"fossil"


func _scales_for(dir: int, default_dir: int) -> Array[float]:
	if dir == default_dir or dir < 0:
		return SCALES
	return [1.0]


func _lay(lay: ArtGen.Layout) -> Dictionary:
	return {"size": [lay.size.x, lay.size.y], "origin": [lay.origin.x, lay.origin.y]}


func _sizes(layouts: Dictionary[StringName, ArtGen.Layout]) -> Dictionary:
	var out: Dictionary = {}
	for part: StringName in layouts:
		out[str(part)] = [layouts[part].size.x, layouts[part].size.y]
	return out


func _png(variant: String, id: String, part: StringName, dir: int, scale: float) -> String:
	return _scratch.path_join(
		"png/%s/%s_%s_d%02d_s%d.png" % [variant, id, part, dir, roundi(scale * 100.0)]
	)


func _raster(svg: String, scale: float, path: String) -> void:
	var img: Image = Image.new()
	var err: int = img.load_svg_from_string(svg, scale)
	if err != OK:
		print("svg load failed for %s: %d" % [path, err])
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("cannot write %s" % path)
		return
	file.store_string(text)
