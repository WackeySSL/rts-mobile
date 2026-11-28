class_name DetailPart
extends Resource
## One piece of a `_detail.tres` model: a shape, where it is and what it is made of. Coordinates
## are the model's grid frame, tiles (x forward, y right-down, z up), as `ArtModel` has them.
## Shapes and the fields each reads:
##   box      `a` centre, `size`
##   bar      `a` to `b`, `size.y` across, `size.z` tall
##   cylinder `a` to `b`, `radius`, `radius2` (a cone when 0 or more), `segs`, `bevel` (chamfer)
##   dome     `a` centre, `b` the way it faces, `radius`, `segs`
##   torus    `a` centre, `b` the axis, `radius` (ring), `radius2` (tube), `segs`, `sides`
##   solid    `planes` (nx, ny, nz, d) outward, `bevel`
##   cliff    a wall face: `a` to `b` the foot, `size.z` tall, `radius` the groove depth,
##            `radius2` the noise seed (see `BakeShapes.cliff`)
##   tongue   the top piece's lip over a face: `a` to `b` the front edge at the top's height,
##            `radius2` the seed (the face's; see `BakeShapes.tongue`)
##   trim     `a` to `b` on a raised top's back edge, `size.z` the most it reaches past the edge,
##            tiles, `radius` and `size.x` its reach at `a` and at `b` (shares; a ragged bump
##            between when equal, a ramp when not), `radius2` the seed: flat, at the top's height
##   quad     `a` centre, `size.x` and `size.y` across: one flat face facing up, no sides (ground)
## `mirror` adds the copy across y = 0; `count` repeats along `step`, each copy moved by up to
## `jitter` of a step from the model's variation seed.

const SHAPES: Array[StringName] = [
	&"box", &"bar", &"cylinder", &"dome", &"torus", &"solid", &"quad", &"cliff", &"trim", &"tongue"
]

@export var part: StringName = &"hull"  ## The sheet part it belongs to: hull, turret or head.
@export var shape: StringName = &"box"
@export var material: StringName = &""
@export var a: Vector3 = Vector3.ZERO
@export var b: Vector3 = Vector3.ZERO
@export var size: Vector3 = Vector3.ONE
@export var radius: float = 0.1
@export var radius2: float = -1.0
@export var segs: int = 16
@export var sides: int = 6
@export var bevel: float = BakeMesh.BEVEL
@export var planes: PackedVector4Array = PackedVector4Array()
@export var mirror: bool = false
@export var count: int = 1
@export var step: Vector3 = Vector3.ZERO
@export_range(0.0, 1.0) var jitter: float = 0.0


## The highest z the piece reaches, tiles, so a shadow can skip what lies flat on the ground.
func top() -> float:
	var above: float = 1.0
	match shape:
		&"quad":
			above = 0.0
		&"box", &"bar":
			above = size.z * 0.5
		&"cylinder":
			above = maxf(b.z - a.z, 0.0)
		&"dome":
			above = radius * BakeShapes.DOME_RISE
		&"torus":
			above = radius2
		&"cliff":
			above = size.z
		&"tongue", &"trim":
			above = 0.0
	return a.z + above


## Adds the piece to `m`; `flip` is the mirrored copy.
func emit(m: BakeMesh, flip: bool) -> void:
	var s: Vector3 = Vector3(1.0, -1.0 if flip else 1.0, 1.0)
	match shape:
		&"box":
			BakeShapes.box(m, material, a * s, size, bevel)
		&"bar":
			BakeShapes.bar(m, material, a * s, b * s, size.y, size.z, bevel)
		&"cylinder":
			BakeShapes.cylinder(m, material, a * s, b * s, radius, segs, bevel, radius2)
		&"dome":
			BakeShapes.dome(m, material, a * s, b * s, radius, segs)
		&"torus":
			BakeShapes.torus(m, material, a * s, b * s, radius, radius2, segs, sides)
		&"quad":
			BakeShapes.quad(m, material, a * s, Vector2(size.x, size.y))
		&"cliff":
			BakeShapes.cliff(m, material, a * s, b * s, size.z, radius, int(radius2))
		&"tongue":
			BakeShapes.tongue(m, material, a * s, b * s, int(radius2))
		&"trim":
			BakeShapes.trim(m, material, a * s, b * s, size.z, radius, size.x, int(radius2))
		&"solid":
			var found: Array[Plane] = []
			for v: Vector4 in planes:
				found.append(Plane(Vector3(v.x, v.y, v.z) * s, v.w))
			m.solid(material, found, bevel)
