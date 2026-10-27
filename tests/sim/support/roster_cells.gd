extends RefCounted
## The cell rule of a building's dock and exit (plan row P68c, ADR 0018 section 3), shared by the
## roster suites of the two factions (test_defs_roster and test_defs_roster_renew). Offsets are
## tiles from the footprint's top-left tile. Not a test suite.

## The cell the plan gives a dock or an exit: the middle column of the footprint, the row below it.
@warning_ignore("integer_division")
static func south_middle(footprint: Vector2i) -> Vector2i:
	return Vector2i(footprint.x / 2, footprint.y)


## Whether `cell` (an offset from the footprint's top-left tile) is outside the footprint and
## 8-adjacent to it: the ring of cells around it, corners included.
static func touches_footprint(footprint: Vector2i, cell: Vector2i) -> bool:
	var in_ring: bool = (
		cell.x >= -1 and cell.x <= footprint.x and cell.y >= -1 and cell.y <= footprint.y
	)
	var inside: bool = cell.x >= 0 and cell.x < footprint.x and cell.y >= 0 and cell.y < footprint.y
	return in_ring and not inside
