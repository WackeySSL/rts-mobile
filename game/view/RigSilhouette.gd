class_name RigSilhouette
extends RefCounted
## The silhouettes of one unit rig behind a raised rock wall (ADR 0053 section 7, amendment A7,
## plan P656d3): two hidden Sprite2D children of the rig, copies of its Hull and its Turret, made
## with the rig and pooled with it, so nothing is allocated per frame. They stand at the rig's own
## origin (the shader reads the unit's ground point from it) at the absolute z of
## `WorldSort.Z_SILHOUETTE`, all with the one material of `WorldSort.silhouette_material`.
## `step` runs once a frame for each rig: it reads the near-wall byte of the rig's cell only when
## the tick moved or the walls were rebuilt, and shows the sprites while the rig is shown and near
## a wall. A shown silhouette copies the part's texture, region, scale and place, so it follows
## whatever writes the part
## (heading, recoil, shake, a squad's pose). Enemy and neutral rigs hide with the fog (`shown`).

const NAMES: Array[String] = ["SilHull", "SilTurret"]  ## The Hull (0) and the Turret (1).

var sprites: Array[Sprite2D] = [null, null]  ## At index 0 (Hull) and 1 (Turret).
var parts: Array[Sprite2D] = [null, null]  ## The rig's own Hull and Turret they copy.
var on: bool = false  ## Whether the silhouettes show.
var near: bool = false  ## Whether the rig's cell is a near-wall cell, as of `tick`.
var tick: int = -1  ## The tick `near` was read at.
var cover: int = -1  ## The `WallLayer.cover_version` it was read from.


## The silhouettes of the Hull `hull` and the Turret `turret` (null for a part the rig lacks) of
## `rig`, as children of it, all drawn with `material`.
static func make(
	rig: Node2D, hull: Sprite2D, turret: Sprite2D, material: ShaderMaterial
) -> RigSilhouette:
	var made: RigSilhouette = RigSilhouette.new()
	for part: int in NAMES.size():
		var from: Sprite2D = hull if part == 0 else turret
		if from == null:
			continue
		var sil: Sprite2D = Sprite2D.new()
		sil.name = NAMES[part]
		sil.centered = false
		sil.region_enabled = true
		sil.visible = false
		sil.z_index = WorldSort.Z_SILHOUETTE
		sil.z_as_relative = false
		sil.material = material
		rig.add_child(sil)
		made.sprites[part] = sil
		made.parts[part] = from
	return made


## For a rig out of the pool: read the cell again, hidden.
func reset() -> void:
	tick = -1
	cover = -1
	near = false
	_hide()


## Brings the silhouettes of the rig of row `row` up to `snap` (see the class comment).
func step(snap: MatchSnapshot, row: int, walls: WallLayer, shown: bool) -> void:
	if snap.tick != tick or walls.cover_version() != cover:
		tick = snap.tick
		cover = walls.cover_version()
		near = walls.is_near(snap.cell_of(snap.pos_x[row], snap.pos_y[row]))
	if not (near and shown):
		if on:
			_hide()
		return
	on = true
	for part: int in NAMES.size():
		var sil: Sprite2D = sprites[part]
		if sil == null:
			continue
		var from: Sprite2D = parts[part]
		sil.visible = from.visible
		sil.texture = from.texture
		sil.region_rect = from.region_rect
		sil.scale = from.scale
		# At the rig's origin: the part's place folds into the offset (in the part's own texels).
		sil.offset = from.offset + from.position / from.scale


func _hide() -> void:
	on = false
	for sil: Sprite2D in sprites:
		if sil != null:
			sil.visible = false
