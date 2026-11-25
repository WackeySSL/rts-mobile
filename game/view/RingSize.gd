class_name RingSize
extends RefCounted
## How big a selection ring is (P651), the one answer of `UnitLayer`, `AirLayer` and `TankerCargo`.
## The ring is the 2:1 ground ellipse of `selection_ellipse.svg`, drawn under the sprites, so a ring
## no wider than the hull's footprint hides behind the hull. Its horizontal semi-axis is therefore
## the largest of three: the selection radius's ellipse (padded), `UnitLayer.RING_MIN_DP`, and the
## drawn footprint of the unit's art plus `HULL_MARGIN_DP`, so that the whole band shows clear of
## the hull. The footprint is read from the sheet's frame boxes (`IsoSheetDef.frame_box`), not
## tuned by unit; the selection radius (sim data, picking) is not touched.

## Clear ground, in dp on the screen at any zoom, between the hull's widest point and the inner edge
## of the ring's band (its dark outline).
const HULL_MARGIN_DP: float = 4.0
## The ring texture's centre line is 72 px from the middle and the band's inner outline edge 62 px
## (12 px band plus 4 px outline each side, STYLE.md): the centre line lies this much farther out.
const INNER_EDGE_RATIO: float = 62.0 / 72.0
## The parts that draw the body on the ground: not the turret (it sits on the hull), the shadow or
## an building's `anim`.
const BODY_PARTS: Array[StringName] = [&"hull", &"walk", &"idle"]

static var _footprints: Dictionary[String, float] = {}


## The half width, world px at zoom 1, of the widest drawn body frame of `sheet` over every heading
## and pose, from its ground point; a body that reaches below the ground point by `b` counts as
## `2 * b` wide, for the ground ellipse is half as tall as wide. 0 for no sheet.
static func footprint_px(sheet: IsoSheetDef) -> float:
	if sheet == null:
		return 0.0
	var key: String = "%s/%s/%s" % [sheet.faction, sheet.category, sheet.art_id]
	if _footprints.has(key):
		return _footprints[key]
	var widest: float = 0.0
	for part: StringName in BODY_PARTS:
		if not sheet.has_part(part):
			continue
		for dir: int in sheet.directions(part):
			for frame: int in sheet.frame_count(part):
				widest = maxf(widest, frame_half_px(sheet, part, dir, frame))
	_footprints[key] = widest
	return widest


## The half width of one frame as `footprint_px` counts it, world px at zoom 1.
static func frame_half_px(sheet: IsoSheetDef, part: StringName, dir: int, frame: int) -> float:
	var box: Rect2i = sheet.frame_box(part, dir, frame)
	var origin: Vector2i = sheet.origin(part)
	var side: int = maxi(origin.x - box.position.x, box.end.x - origin.x)
	var below: int = box.end.y - origin.y
	return float(maxi(side, 2 * below)) * WorldSort.ART_SCALE


## The ring's horizontal semi-axis, world px, for a type of `radius_milli` selection radius and
## `sheet` (null for none), where one dp is `unit` world px.
static func semi_px(radius_milli: int, sheet: IsoSheetDef, unit: float) -> float:
	var semi: float = IsoProjection.ellipse_px(radius_milli + UnitLayer.RING_PAD_MILLI).x
	var clear: float = (footprint_px(sheet) + HULL_MARGIN_DP * unit) / INNER_EDGE_RATIO
	return maxf(maxf(semi, clear), UnitLayer.RING_MIN_DP * unit)


## Sets `ring` to the size of `semi_px`; `unit` is the world px of one dp.
static func apply(ring: UnitLayer.Ring, semi: float, unit: float) -> void:
	ring.radius = semi
	ring.unit = unit
	ring.scale = Vector2.ONE * (semi / UnitLayer.RING_TEX_RX_PX)
