extends GdUnitTestSuite
## The reach rule of ADR 0037 section 5 (plan row P277): for every type with a repair role and a
## footprint (and no pads), `repair_reach_milli` is at least the farthest approach point of
## `Buildings.approach_point` from the footprint centre plus 500 (half a tile of arrival slack), so
## a unit sent by REPAIR is always in reach. The farthest point is read from the live ring (units
## on every ring tile and far out in eight directions), not from a copy of its geometry, and the
## rule is held against every shipped file.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units"
## Half a tile of arrival slack, in milli-tiles (ADR 0037 section 5).
const SLACK: int = 500
## The footprint's top-left tile in the probe world (the ring lies inside the map).
const AT: Vector2i = Vector2i(5, 5)


## The squared distance from a width x height footprint's centre to the farthest approach point
## `Buildings.approach_point` gives to a ground unit placed on each ring tile and far out in the
## eight directions.
func live_far_squared(width: int, height: int) -> int:
	var shed: BuildingDef = BuildingDef.new()
	shed.type_id = &"shed"
	shed.max_hp = 100
	shed.footprint = Vector2i(width, height)
	shed.repair_classes = 6
	var tank: UnitDef = Rig.unit(&"tank", 6000, 5000, 0, 0, [])
	tank.move_class = World.MoveClass.TRACKED
	var units: Array[UnitDef] = [shed, tank]
	var world: World = Rig.world_of(units, 16, 16, true, 2)
	world.add_building(1, 0, AT.x, AT.y)
	var kind: int = world.type_ids.find(&"tank")
	var centre: Vector2i = Vector2i(AT.x * 1000 + width * 500, AT.y * 1000 + height * 500)
	var spots: Array[Vector2i] = []
	for col: int in range(AT.x - 1, AT.x + width + 1):
		for line: int in range(AT.y - 1, AT.y + height + 1):
			spots.append(Vector2i(col * 1000 + 500, line * 1000 + 500))
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			spots.append(centre + Vector2i(dx, dy) * 7000)
	var far: int = 0
	var building: int = world.index_of(world.unit_id[0])
	for spot: Vector2i in spots:
		world.add_unit(1, kind, spot.x, spot.y)
		var point: Vector2i = Buildings.approach_point(world, world.unit_count() - 1, building)
		var gap: Vector2i = point - centre
		far = maxi(far, gap.x * gap.x + gap.y * gap.y)
	return far


## Whether `reach` covers the live ring of a width x height footprint plus the slack.
func covers(reach: int, width: int, height: int) -> bool:
	var inner: int = reach - SLACK
	return inner >= 0 and inner * inner >= live_far_squared(width, height)


## The problems of a def: an empty array when it is fine or has no ground repair role.
func problems(label: String, def: BuildingDef) -> Array[String]:
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


func test_the_live_ring_of_a_2_by_2_reaches_a_corner_tile_centre() -> void:
	assert_int(live_far_squared(2, 2)).is_equal(2 * 1500 * 1500)
	assert_int(live_far_squared(3, 3)).is_equal(2 * 2000 * 2000)
	assert_int(live_far_squared(2, 3)).is_equal(1500 * 1500 + 2000 * 2000)


func test_the_boundary_of_a_2_by_2_is_2622() -> void:
	assert_bool(covers(2622, 2, 2)).is_true()
	assert_bool(covers(2621, 2, 2)).is_false()
	assert_bool(covers(2700, 2, 2)).is_true()  # The Weld Shed.


func test_larger_and_uneven_footprints_need_more_reach() -> void:
	assert_bool(covers(3328, 3, 3)).is_false()  # Corner at 2829 (rounded up) plus 500.
	assert_bool(covers(3329, 3, 3)).is_true()
	assert_bool(covers(2900, 2, 3)).is_false()  # 2500 plus 500 is the floor.
	assert_bool(covers(3000, 2, 3)).is_true()


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


func test_every_shipped_repair_building_covers_its_ring() -> void:
	var loaded: int = 0
	var found: Array[String] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var def: BuildingDef = load(path) as BuildingDef
		if def == null:
			continue
		loaded += 1
		found.append_array(problems(path.get_file(), def))
	assert_array(found).is_empty()
	# The scan must see the shipped buildings (it would pass on nothing if the load broke).
	assert_int(loaded).is_greater(0)
	# TODO(P278): the Weld Shed and the Drone Dock ship there; count the judged defs (repair role,
	# no pads, a footprint) here and assert at least 2.
