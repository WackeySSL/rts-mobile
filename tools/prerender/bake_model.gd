extends SceneTree
## The bake scene entry (ADR 0053 section 5): renders one `_detail.tres` model to raw frames, one
## PNG per part and direction, at `--scale` texels per art px, with no post-processing. Run it
## through `bash scripts/prerender.sh`, which checks the pinned image first and starts it under
## xvfb on Forward+ over Vulkan.
##   --model res://.../<id>_detail.tres   --sheet res://.../<id>_sheet.tres   --out DIR
##   [--dirs all|6,7,..]  [--scale 8]  [--team #D234D2]  [--composite]  [--no-ssao]
## --composite also writes `<id>_both_dNN.png`: the hull with its turret or head seated at the
## sheet's mount, on the union of the two canvases. Exit 0 done, 1 a model or frame failed, 2 a
## wrong argument.

var _rig: BakeRig
var _opts: Dictionary = {"dirs": "all", "scale": "8", "team": ArtPalette.SENTINEL[1]}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i].begins_with("--"):
			var flag: bool = i + 1 >= args.size() or args[i + 1].begins_with("--")
			_opts[args[i].trim_prefix("--")] = "" if flag else args[i + 1]
	if not (_opts.has("model") and _opts.has("sheet") and _opts.has("out")):
		printerr("bake_model: --model, --sheet and --out are required")
		quit(2)
		return
	var model: DetailModel = DetailModel.read(_opts.model)
	var sheet: IsoSheetDef = load(_opts.sheet) as IsoSheetDef
	var problems: PackedStringArray = model.problems() if model != null else ["no model"]
	if sheet == null or not problems.is_empty():
		printerr("bake_model: ", ", ".join(problems))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_opts.out)
	_rig = BakeRig.new()
	root.add_child(_rig)
	_rig.setup(not _opts.has("no-ssao"))
	var made: int = await _bake(model, sheet)
	_rig.free()
	BakeMaterials.release()
	print("bake_model: renderer ", stamp())
	print("bake_model: %s, %d frames in %s" % [model.art_id, made, _opts.out])
	quit(0 if made > 0 else 1)


## The renderer line of the manifest stamp, "Vulkan 1.4.318 - Forward+ - llvmpipe".
static func stamp() -> String:
	var method: String = RenderingServer.get_current_rendering_method()
	var names: Dictionary = {"forward_plus": "Forward+", "mobile": "Mobile"}
	var device: String = RenderingServer.get_video_adapter_name().get_slice(" (", 0)
	return (
		"%s %s - %s - %s"
		% [
			"Vulkan",
			RenderingServer.get_video_adapter_api_version(),
			names.get(method, method),
			device
		]
	)


func _bake(model: DetailModel, sheet: IsoSheetDef) -> int:
	var materials: Dictionary = BakeMaterials.for_model(model, Color(_opts.team))
	var nodes: Dictionary = {}
	for part: StringName in model.part_names():
		var mesh: BakeMesh = BakeMesh.new(model.art_id)
		model.build(part, mesh)
		nodes[part] = mesh.to_node(materials)
		if nodes[part] == null:
			push_error("bake_model refuses " + mesh.cap_error())
			return 0
		print("bake_model: %s %s %d triangles" % [model.art_id, part, mesh.triangles])
	var made: int = 0
	var seat: StringName = &"turret" if nodes.has(&"turret") else &"head"
	for part: StringName in nodes:
		if sheet.has_part(part):
			made += await _frames(model.art_id, sheet, part, nodes[part])
	if _opts.has("composite") and nodes.has(&"hull") and nodes.has(seat):
		made += await _composite(model.art_id, sheet, nodes[&"hull"], nodes[seat], seat)
	for node: Node3D in nodes.values():
		node.free()
	return made


func _dirs(sheet: IsoSheetDef, part: StringName) -> Array[int]:
	var wanted: PackedStringArray = String(_opts.dirs).split(",")
	var found: Array[int] = []
	for d: int in sheet.directions(part):
		if _opts.dirs == "all" or str(d) in wanted or d < 0:
			found.append(d)
	return found


func _frames(id: StringName, sheet: IsoSheetDef, part: StringName, node: Node3D) -> int:
	var size: Vector2i = sheet.frame_size(part)
	var origin: Vector2i = sheet.origin(part)
	var made: int = 0
	_rig.set_node(node)
	for d: int in _dirs(sheet, part):
		node.rotation.y = -deg_to_rad(ArtGen.yaw(6 if d < 0 else d))
		var image: Image = await _rig.render(size.x, size.y, origin.x, origin.y, _scale())
		made += _save(image, id, part, d)
	return made


func _composite(
	id: StringName, sheet: IsoSheetDef, hull: Node3D, top: Node3D, seat: StringName
) -> int:
	_rig.clear()
	var both: Node3D = Node3D.new()
	both.add_child(hull)
	both.add_child(top)
	_rig.set_node(both)
	var hull_at: Vector2 = Vector2(sheet.origin(&"hull"))
	var hull_size: Vector2 = Vector2(sheet.frame_size(&"hull"))
	var top_size: Vector2 = Vector2(sheet.frame_size(seat))
	var made: int = 0
	for d: int in _dirs(sheet, &"hull"):
		# The seat's canvas corner from the hull's ground point, art px.
		var corner: Vector2 = sheet.mount(maxi(d, 0)) - Vector2(sheet.origin(seat))
		var low: Vector2 = Vector2(minf(-hull_at.x, corner.x), minf(-hull_at.y, corner.y)).floor()
		var high: Vector2 = Vector2(
			maxf(hull_size.x - hull_at.x, corner.x + top_size.x),
			maxf(hull_size.y - hull_at.y, corner.y + top_size.y)
		)
		var yaw: float = -deg_to_rad(ArtGen.yaw(6 if d < 0 else d))
		hull.rotation.y = yaw
		top.rotation.y = yaw
		top.position = BakeRig.seat(sheet.mount(maxi(d, 0)))
		var canvas: Vector2 = (high - low).ceil()
		var image: Image = await _rig.render(int(canvas.x), int(canvas.y), -low.x, -low.y, _scale())
		made += _save(image, id, &"both", d)
	return made


func _scale() -> float:
	return float(_opts.scale)


func _save(image: Image, id: StringName, part: StringName, d: int) -> int:
	var name: String = "%s_%s%s.png" % [id, part, "" if d < 0 else "_d%02d" % d]
	return 1 if image.save_png(String(_opts.out).path_join(name)) == OK else 0
