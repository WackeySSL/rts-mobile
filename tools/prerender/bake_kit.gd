extends "res://tools/prerender/bake_model.gd"
## The terrain kit's bake entry (ADR 0053 sections 5 and 7, plan row P656c): renders every part of
## one `assets/art/models/terrain/<id>_detail.tres` as one piece, with the rig of `bake_model.gd`,
## into `<out>/<id>_<part>.png`. A ground piece is its 128 x 64 diamond, whatever rises above it is
## cut. A wall piece (a part named `wall_*`, amendment A3) is the whole 128 x 136 canvas whose
## ground centre, the model's origin, is at (64, 104): the cell's prism, a cell raised `RISE_MAX`
## texels, and at most `RIM_MAX` rows over it. A wall casts no baked shadow.
##   --model res://assets/art/models/terrain/<id>_detail.tres  --out DIR  [--scale 8] [--no-ssao]
## Exit 0 done, 1 a model or a piece failed, 2 usage.

const KitDef: GDScript = preload("res://game/view/TerrainKitDef.gd")
## One ground tile and the wall canvas, texels at 1x (ADR 0053 sections 3 and 7), read from the
## kit's schema so the bake and the kit tests can't drift apart.
const DIAMOND: Vector2i = KitDef.TILE
## The ground canvas's headroom over the diamond: what P656c baked with, kept so that the ground
## pieces stay byte-identical (the rows above the diamond are cut).
const GROUND_HEADROOM: int = 36
## What reaches less than this (tiles) lies on the ground and casts no baked shadow.
const SHADOW_MIN_TOP: float = 0.02


func _run() -> void:
	_read_args()
	if not (_opts.has("model") and _opts.has("out")):
		printerr("bake_kit: --model and --out are required")
		quit(2)
		return
	var model: DetailModel = DetailModel.read(_opts.model)
	var problems: PackedStringArray = model.problems() if model != null else ["no model"]
	if not problems.is_empty():
		printerr("bake_kit: ", ", ".join(problems))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_opts.out)
	_rig = BakeRig.new()
	root.add_child(_rig)
	_rig.setup(not _opts.has("no-ssao"))
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	var made: int = await _pieces(model)
	_rig.free()
	BakeMaterials.release()
	_write_info()
	print("bake_model: renderer ", stamp())
	print("bake_model: %s, %d frames in %s" % [model.art_id, made, _opts.out])
	quit(0 if made > 0 else 1)


func _pieces(model: DetailModel) -> int:
	var materials: Dictionary = BakeMaterials.for_model(model, Color.WHITE)
	var made: int = 0
	for part: StringName in model.part_names():
		var mesh: BakeMesh = BakeMesh.new(model.art_id)
		model.build(part, mesh)
		var node: Node3D = mesh.to_node(materials)
		if node == null:
			push_error("bake_kit refuses " + mesh.cap_error())
			return 0
		var wall: bool = String(part).begins_with("wall_")
		var raw: Image = await _render(node, wall)
		node.free()
		var piece: Image = raw
		if not wall:
			piece = _cut(_under(raw, await _shadow_of(model, part)))
		var name: String = "%s_%s.png" % [model.art_id, part]
		made += 1 if piece.save_png(String(_opts.out).path_join(name)) == OK else 0
		print("bake_kit: %s %d triangles, %s" % [name, mesh.triangles, piece.get_size()])
	return made


## The wall canvas, or the ground one: the diamond at the foot with `GROUND_HEADROOM` rows above it.
## The canvas's point (ax, ay) is the model's origin.
func _render(node: Node3D, wall: bool = false) -> Image:
	_rig.set_node(node)
	if wall:
		var o: Vector2i = KitDef.WALL_ORIGIN
		return await _rig.render(KitDef.WALL_CANVAS.x, KitDef.WALL_CANVAS.y, o.x, o.y, _scale())
	var h: int = GROUND_HEADROOM
	return await _rig.render(DIAMOND.x, DIAMOND.y + h, DIAMOND.x / 2, DIAMOND.y / 2 + h, _scale())


## The part's solids flattened along +gx by `ArtShadow.REACH`, unlit black and opaque, as
## `bake_model.gd`'s shadow frame; null when nothing in it reaches `SHADOW_MIN_TOP`.
func _shadow_of(model: DetailModel, part: StringName) -> Image:
	var flat: BakeMesh = BakeMesh.new(model.art_id)
	flat.reach = ArtShadow.REACH
	model.build(part, flat, SHADOW_MIN_TOP)
	var black: StandardMaterial3D = StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	var materials: Dictionary = {}
	for name: StringName in flat.batches:
		materials[name] = black
	var node: Node3D = flat.to_node(materials, false)
	if node == null:
		return null
	var image: Image = await _render(node)
	node.free()
	return image


## The piece over its shadow at the same-scene band's alpha (`bake_info.json`'s), where the
## geometry leaves the ground bare, so a lip's shadow lands on the rock beside it.
func _under(piece: Image, shade: Image) -> Image:
	if shade == null or shade.is_invisible():
		return piece
	var alpha: float = _shadow_alpha()
	var box: Rect2i = shade.get_used_rect()
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			if shade.get_pixel(x, y).a > 0.0:
				shade.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha * shade.get_pixel(x, y).a))
	shade.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i.ZERO)
	return shade


## The piece's diamond: the canvas without its headroom rows.
func _cut(raw: Image) -> Image:
	var scale: int = int(_scale())
	return raw.get_region(Rect2i(0, GROUND_HEADROOM * scale, DIAMOND.x * scale, DIAMOND.y * scale))
