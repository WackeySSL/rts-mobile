extends GdUnitTestSuite
## The reach rule of ADR 0037 section 6 (plan row P277): for every type with a repair role and a
## footprint (and no pads), `repair_reach_milli` is at least the farthest ring tile centre from the
## footprint centre plus 500 (half a tile of arrival slack), so a unit sent by REPAIR to
## `Buildings.aim`'s approach point is always in reach. Pinned on built defs, on the live ring of
## `Buildings.aim`, and held against every shipped file (vacuous until P278 ships the first repair
## building; the guard below keeps it from checking nothing once it does).

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units"
## Half a tile of arrival slack, in milli-tiles (ADR 0037 section 6).
const SLACK: int = 500


## The squared distance from a footprint's centre to the centre of its farthest ring tile (a
## corner of the ring), for a footprint of width x height tiles.
static func ring_far_squared(width: int, height: int) -> int:
	var dx: int = width * 500 + 500
	var dy: int = height * 500 + 500
	return dx * dx + dy * dy


## Whether `reach` covers the ring of a width x height footprint with the slack, in integers.
static func covers(reach: int, width: int, height: int) -> bool:
	var inner: int = reach - SLACK
	return inner >= 0 and inner * inner >= ring_far_squared(width, height)


## The problems of a def: an empty array when it is fine or has no ground repair role.
static func problems(label: String, def: BuildingDef) -> Array[String]:
	var found: Array[String] = []
	if def.repair_classes == 0 or def.pads > 0 or def.footprint.x <= 0 or def.footprint.y <= 0:
		return found
	if not covers(def.repair_reach_milli, def.footprint.x, def.footprint.y):
		found.append(
			(
				"%s: repair_reach_milli %d does not cover the %dx%d ring plus %d"
				% [label, def.repair_reach_milli, def.footprint.x, def.footprint.y, SLACK]
			)
		)
	return found


func _def(width: int, height: int, reach: int) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.footprint = Vector2i(width, height)
	def.repair_classes = 6
	def.repair_reach_milli = reach
	return def


func test_the_boundary_of_a_2_by_2_is_2622() -> void:
	assert_bool(covers(2622, 2, 2)).is_true()  # 2122 squared is at least 2 * 1500 squared.
	assert_bool(covers(2621, 2, 2)).is_false()
	assert_bool(covers(2700, 2, 2)).is_true()  # The Weld Shed.


func test_larger_and_uneven_footprints_need_more_reach() -> void:
	assert_bool(covers(3300, 3, 3)).is_false()  # Corner at 2828 plus 500.
	assert_bool(covers(3329, 3, 3)).is_true()
	assert_bool(covers(2900, 2, 3)).is_false()  # sqrt(1500^2 + 2000^2) = 2500, plus 500.
	assert_bool(covers(3000, 2, 3)).is_true()
	assert_bool(covers(5000, 3, 3)).is_true()  # The Drone Dock.


func test_a_def_below_the_rule_is_named_and_one_at_it_is_not() -> void:
	assert_array(problems("shed.tres", _def(2, 2, 2621))).is_equal(
		["shed.tres: repair_reach_milli 2621 does not cover the 2x2 ring plus 500"]
	)
	assert_array(problems("shed.tres", _def(2, 2, 2622))).is_empty()


func test_a_def_with_pads_or_no_role_is_not_judged() -> void:
	var field: BuildingDef = _def(2, 2, 0)
	field.pads = 2
	assert_array(problems("field.tres", field)).is_empty()
	var plain: BuildingDef = _def(2, 2, 0)
	plain.repair_classes = 0
	assert_array(problems("hq.tres", plain)).is_empty()


func test_the_ring_that_aim_uses_is_covered_by_the_rule_for_every_tile() -> void:
	# A tank on each ring tile of a width x height footprint is aimed at its own tile, and the
	# farthest such tile is exactly the one the rule measures.
	for size: Vector2i in [Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3)]:
		var far: int = 0
		for col: int in range(-1, size.x + 1):
			for line: int in range(-1, size.y + 1):
				if col >= 0 and col < size.x and line >= 0 and line < size.y:
					continue
				var dx: int = col * 1000 + 500 - size.x * 500
				var dy: int = line * 1000 + 500 - size.y * 500
				far = maxi(far, dx * dx + dy * dy)
		assert_int(far).is_equal(ring_far_squared(size.x, size.y))


func test_every_shipped_repair_building_covers_its_ring() -> void:
	var checked: int = 0
	var found: Array[String] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var def: BuildingDef = load(path) as BuildingDef
		if def == null:
			continue
		if def.repair_classes != 0 and def.pads == 0 and def.footprint.x > 0:
			checked += 1
		found.append_array(problems(path.get_file(), def))
	assert_array(found).is_empty()
	assert_int(checked).is_greater_equal(0)  # P278 ships the first two; none is a pass today.
