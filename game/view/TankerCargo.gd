class_name TankerCargo
extends Node2D
## The cargo cue of a tanker's rig (plan P84b revision 5): a small bar under the tanker's foot that
## shows how full it is, read from the snapshot's `cargo` against the type's `type_harvest`. It is
## drawn in dp, so the node's scale is the world px of one dp (`UnitLayer` sets it from the dp and
## the camera zoom), and it redraws only when the filled step changes, so a rig that is followed
## every frame allocates nothing. Empty is the bare outlined track, partly is an amber fill of 1 to
## STEPS - 1 steps (never read as empty or full), full is the whole track in green with a bright
## edge. The step, and the width, say it as well as the colour. The bar is a child of the rig that
## `UnitLayer` makes for a type with a cargo capacity (`UnitLayer.CARGO_KIND`), so both factions'
## tankers have it and a squad or a tank has none.

const WIDTH_DP: int = 22  ## The track's outer width, as a vehicle's health bar.
const HEIGHT_DP: int = 5  ## And height, with the edge.
const EDGE_DP: int = 1
const DROP_DP: int = 4  ## From the rig's ground point to the track's top edge.
const STEPS: int = 8  ## The fill's resolution: the interior width in dp is divided into this.
const EDGE: Color = Color("1C2127")
const TRACK: Color = Color("3A434D")
const PARTLY: Color = Color("F5A524")  ## STYLE.md warning amber.
const FULL: Color = Color("30A46C")  ## STYLE.md ok green.
const FULL_EDGE: Color = Color("FFFFFF")

var steps: int = 0  ## 0 empty, STEPS full, in between partly.
var draws: int = 0  ## Redraws asked for (a test hook).


## The filled steps of `cargo` credits of `capacity`: 0 only for an empty load and STEPS only for a
## full one, so a load never reads as the other two.
static func steps_of(cargo: int, capacity: int) -> int:
	if capacity <= 0 or cargo <= 0:
		return 0
	if cargo >= capacity:
		return STEPS
	return clampi(cargo * STEPS / capacity, 1, STEPS - 1)


## The bar of a rig of a type with a cargo capacity, its child after the sprites, empty.
static func make(rig: Node2D) -> TankerCargo:
	var bar: TankerCargo = TankerCargo.new()
	bar.name = "Cargo"
	rig.add_child(bar)
	return bar


## Brings the bar of every tanker rig of `rigs` (null for a building) up to the snapshot `snap`, at
## the world px of a dp (`dp_px` base px over the zoom of `camera`, if any). A rig that was pooled
## and taken by another tanker shows that tanker's load in the frame it is taken, so no bar keeps
## the last unit's. Writes only what changed.
static func follow_all(
	snap: MatchSnapshot, rigs: Array[Node2D], dp_px: float, camera: Camera2D
) -> void:
	var unit: float = dp_px / (camera.zoom.x if camera != null else 1.0)
	for row: int in rigs.size():
		var rig: UnitLayer.Rig = rigs[row] as UnitLayer.Rig
		if rig != null and rig.cargo != null:
			rig.cargo.follow(snap.cargo[row], snap.type_harvest[snap.type_index[row]], unit)


## Shows `cargo` of `capacity` at `unit` world px a dp. Writes only what changed.
func follow(cargo: int, capacity: int, unit: float) -> void:
	if scale.x != unit:
		scale = Vector2(unit, unit)
	var wanted: int = steps_of(cargo, capacity)
	if wanted != steps:
		steps = wanted
		draws += 1
		queue_redraw()


func _draw() -> void:
	var inner: int = WIDTH_DP - 2 * EDGE_DP
	var full: bool = steps >= STEPS
	var edge: Color = FULL_EDGE if full else EDGE
	draw_rect(Rect2(-WIDTH_DP / 2.0, DROP_DP, WIDTH_DP, HEIGHT_DP), edge)
	var left: float = -WIDTH_DP / 2.0 + EDGE_DP
	var top: float = DROP_DP + EDGE_DP
	var high: float = HEIGHT_DP - 2.0 * EDGE_DP
	draw_rect(Rect2(left, top, inner, high), TRACK)
	if steps > 0:
		draw_rect(Rect2(left, top, float(inner * steps) / STEPS, high), FULL if full else PARTLY)
