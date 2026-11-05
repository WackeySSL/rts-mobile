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
const GAP_DP: int = 2  ## Between the lower edge of the selection ring and the track.
const STEPS: int = 8  ## The fill's resolution: the interior width in dp is divided into this.

## The look: exports of this world-space node like `HealthBarLayer`'s, so a new palette edits them
## here. The load is the economy's credits gold (STYLE.md's tint of `glyph_credits`), not the
## health bar's ok green and warning amber, so it never reads as health.
@export var edge_color: Color = Color("1C2127")
@export var track_color: Color = Color("3A434D")
@export var load_color: Color = Color("F2B705")  ## The fill, partly or full.
@export var full_edge_color: Color = Color("FFFFFF")  ## The edge of a full bar.

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
			var type: int = snap.type_index[row]
			var semi: float = (
				IsoProjection
				. ellipse_px(snap.type_selection_radius[type] + UnitLayer.RING_PAD_MILLI)
				. y
			)
			var ring: float = maxf(
				semi, UnitLayer.RING_MIN_DP * unit * IsoProjection.GROUND_FLATTEN
			)
			rig.cargo.follow(snap.cargo[row], snap.type_harvest[type], unit, ring + GAP_DP * unit)


## Shows `cargo` of `capacity` at `unit` world px a dp. Writes only what changed.
func follow(cargo: int, capacity: int, unit: float, drop: float) -> void:
	if scale.x != unit:
		scale = Vector2(unit, unit)
	if position.y != drop:
		position.y = drop
	var wanted: int = steps_of(cargo, capacity)
	if wanted != steps:
		steps = wanted
		draws += 1
		queue_redraw()


func _draw() -> void:
	draw_rect(outer_rect(), edge_now())
	draw_rect(track_rect(), track_color)
	if steps > 0:
		draw_rect(fill_rect(), load_color)


## The rects and colours `_draw` paints, in dp from the node's origin (the ring's lower edge, the
## bar centred on it), as functions so a test reads what is drawn.
func outer_rect() -> Rect2:
	return Rect2(-WIDTH_DP / 2.0, 0.0, WIDTH_DP, HEIGHT_DP)


func track_rect() -> Rect2:
	return outer_rect().grow(-EDGE_DP)


## The fill: the track's left part, `steps` of STEPS of its width.
func fill_rect() -> Rect2:
	var track: Rect2 = track_rect()
	return Rect2(track.position, Vector2(track.size.x * steps / STEPS, track.size.y))


func edge_now() -> Color:
	return full_edge_color if steps >= STEPS else edge_color


## Back to the empty bar, for a rig that is dressed for another unit. Null-safe (a rig that holds
## no bar).
static func clear(bar: TankerCargo) -> void:
	if bar != null and bar.steps != 0:
		bar.steps = 0
		bar.draws += 1
		bar.queue_redraw()
