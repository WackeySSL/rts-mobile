class_name BuildingGeometry
extends RefCounted
## The arithmetic of ADR 0022 sections 1 and 2 on a snapshot's building rows, in one place for the
## layers, the bars and (P84d) the picking. A building is a row whose type has a footprint
## (`type_foot_w` above 0) and whose position is the footprint centre (ADR 0017 section 1), so its
## origin tile is derived. The sprite box is the footprint plus the texture's rise, anchored on the
## footprint's south edge: `(origin_col * 64, (origin_row + foot_h) * 64 - tex_h, foot_w * 64,
## tex_h)` in world px. The middle line is the horizontal line through the footprint's centre;
## the part of the sprite south of it is drawn under the unit bands and the part north of it over
## them. No constant holds the rise: it is `tex_h - foot_h * 64`.


## Whether type `type` of `snap` has a footprint. A snapshot with no type table has none.
static func is_building(snap: MatchSnapshot, type: int) -> bool:
	return type >= 0 and type < snap.type_foot_w.size() and snap.type_foot_w[type] > 0


## The footprint of `type` in tiles (width, height), (0, 0) for a mobile type.
static func footprint(snap: MatchSnapshot, type: int) -> Vector2i:
	if not is_building(snap, type):
		return Vector2i.ZERO
	return Vector2i(snap.type_foot_w[type], snap.type_foot_h[type])


## The top-left tile of building row `row`: its position is the footprint centre.
@warning_ignore("integer_division")
static func origin_tile(snap: MatchSnapshot, row: int) -> Vector2i:
	var foot: Vector2i = footprint(snap, snap.type_index[row])
	var half: int = World.MILLI_PER_TILE / 2
	return Vector2i(
		(snap.pos_x[row] - foot.x * half) / World.MILLI_PER_TILE,
		(snap.pos_y[row] - foot.y * half) / World.MILLI_PER_TILE
	)


## The sprite box in world px of a footprint at `origin` (tiles) whose texture is `tex_height` px
## tall: the footprint plus the rise above it.
static func sprite_box(origin: Vector2i, foot: Vector2i, tex_height: float) -> Rect2:
	var px: int = ViewScale.PX_PER_TILE
	return Rect2(origin.x * px, (origin.y + foot.y) * px - tex_height, foot.x * px, tex_height)


## `y_mid` in world px: the line through the footprint's centre that cuts the building in its two
## parts.
static func middle_line(origin: Vector2i, foot: Vector2i) -> float:
	return (origin.y * 2 + foot.y) * ViewScale.PX_PER_TILE / 2.0
