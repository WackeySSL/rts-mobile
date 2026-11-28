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
## What a ground piece may reach above its diamond, texels: the bleed past the corners (ADR 0053
## section 7). Higher is refused, as is a wall piece that touches the canvas's top row.
const BLEED_MAX: int = 3
## A texel's distance in from the diamond's edge is `(1 - |dx| - |dy|)` times this: the edge's
## length 2 x 32 x 64 over its normal factor, `sqrt(64 ^ 2 + 32 ^ 2)`.
const EDGE_TEXELS: float = 28.6
const SHADOW_CLEAR: float = 4.0  ## The shadow is gone this close to the edge, texels.
const SHADOW_FULL: float = 9.0  ## and whole this far in.
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
		if not _fits(raw, wall):
			push_error("bake_kit: %s_%s rises over its limit" % [model.art_id, part])
			return 0
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
				var fade: float = _edge_fade(x, y, shade.get_size())
				shade.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha * shade.get_pixel(x, y).a * fade))
	shade.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i.ZERO)
	return shade


## How much of the shadow stays at raw texel (`x`, `y`) of the ground canvas: none outside the
## diamond or within `SHADOW_CLEAR` texels (1x) of its edge, full from `SHADOW_FULL` in. A shadow
## that reaches the edge would show over the neighbouring cell as a dashed seam line.
func _edge_fade(x: int, y: int, size: Vector2i) -> float:
	var scale: float = _scale()
	var dx: float = absf(float(x) + 0.5 - size.x * 0.5) / (DIAMOND.x * 0.5 * scale)
	var dy: float = (
		absf(float(y) + 0.5 - (size.y - DIAMOND.y * 0.5 * scale)) / (DIAMOND.y * 0.5 * scale)
	)
	var inside: float = (1.0 - dx - dy) * EDGE_TEXELS  # texels (1x) inside the diamond's edge
	return smoothstep(SHADOW_CLEAR, SHADOW_FULL, inside)


## Whether the render stays in its limit: a wall piece must leave the canvas's top row empty (its
## rim may be taller than `RIM_MAX`, which would be cut), a ground piece may rise `BLEED_MAX` above
## its diamond's top corner.
func _fits(raw: Image, wall: bool) -> bool:
	if raw.is_invisible():
		return true
	var top: int = raw.get_used_rect().position.y
	var limit: int = 1 if wall else (GROUND_HEADROOM - BLEED_MAX) * int(_scale())
	return top >= limit


## The piece's diamond: the canvas without its headroom rows.
func _cut(raw: Image) -> Image:
	var scale: int = int(_scale())
	return raw.get_region(Rect2i(0, GROUND_HEADROOM * scale, DIAMOND.x * scale, DIAMOND.y * scale))
