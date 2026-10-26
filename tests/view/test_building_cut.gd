extends GdUnitTestSuite
## The middle-line cut seen from the units' side (plan P84, ADR 0022 section 2): units north,
## south and beside a 1x1, a 2x2 and a 3x3 footprint, with the reach of every sprite class
## (Rig.REACHES: a squad, a light tank, the harvester along an axis, a canvas corner). A unit north
## of a building has its centre at or north of the footprint's north edge and a unit south of it at
## or south of the south edge, so the worst case is the centre on the edge. The unit bands lie
## between the two parts, so the part of a unit over the base part is what shows in front of the
## wall and the part of it under the roof part is what the roof hides. For 2x2 and 3x3 a unit north
## never shows over the base part and a unit south is never under the roof part, whatever it is;
## for the 1x1 turret (32 px to the middle line) a unit of reach `r` is wrong by `r - 32` px on
## both sides, which the ADR accepts. The rects are the parts' rects the layers draw
## (`part_dst`), on the base match (Rig).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")

var _runner: MatchRunner
var _buildings: BuildingLayer
var _list: Array[Dictionary] = []


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_list = Rig.buildings()
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	add_child(_buildings)
	_buildings.set_process(false)
	_buildings.sync()


func after_test() -> void:
	CommandQueue.clear()


func test_a_unit_north_of_a_2x2_or_3x3_building_never_shows_over_its_base_part() -> void:
	for id: StringName in [&"headquarters", &"power_plant"]:
		var building: Dictionary = _own(id)
		var b: int = building[&"index"]
		var foot: Rect2 = Rig.footprint_rect(building[&"data"])
		for reach: float in Rig.REACHES:
			var unit: Rect2 = _extent(Vector2(foot.get_center().x, foot.position.y), reach)
			var label: String = "%s r %s" % [id, reach]
			(
				assert_float(_height(unit, _buildings.part_dst(b, false)))
				. override_failure_message(label)
				. is_equal(0.0)
			)
			# Behind the roof instead: its north half is under the overhang.
			(
				assert_float(_height(unit, _buildings.part_dst(b, true)))
				. override_failure_message(label)
				. is_greater(0.0)
			)


func test_a_unit_south_of_a_2x2_or_3x3_building_is_never_under_its_roof_part() -> void:
	for id: StringName in [&"headquarters", &"power_plant"]:
		var building: Dictionary = _own(id)
		var b: int = building[&"index"]
		var foot: Rect2 = Rig.footprint_rect(building[&"data"])
		for reach: float in Rig.REACHES:
			var unit: Rect2 = _extent(Vector2(foot.get_center().x, foot.end.y), reach)
			var label: String = "%s r %s" % [id, reach]
			(
				assert_float(_height(unit, _buildings.part_dst(b, true)))
				. override_failure_message(label)
				. is_equal(0.0)
			)
			# In front of the wall instead: all of it over the base part, as far as it reaches up.
			(
				assert_float(_height(unit, _buildings.part_dst(b, false)))
				. override_failure_message(label)
				. is_greater(0.0)
			)


func test_the_1x1_turret_is_wrong_by_the_reach_over_32_px_on_both_sides() -> void:
	var building: Dictionary = _own(&"defence_turret")
	var b: int = building[&"index"]
	var foot: Rect2 = Rig.footprint_rect(building[&"data"])
	assert_that(foot.size).is_equal(Vector2(64.0, 64.0))
	# A squad (14) and a light tank (26) along the axes are right; the harvester (40) is wrong by
	# 8 px and a canvas corner (57) by 25.
	var wrong: Dictionary[float, float] = {14.0: 0.0, 26.0: 0.0, 40.0: 8.0, 57.0: 25.0}
	assert_array(Rig.REACHES).is_equal(wrong.keys())
	for reach: float in Rig.REACHES:
		var north: Rect2 = _extent(Vector2(foot.get_center().x, foot.position.y), reach)
		var south: Rect2 = _extent(Vector2(foot.get_center().x, foot.end.y), reach)
		# North: the unit's tail shows over the lower facade, the base part.
		(
			assert_float(_height(north, _buildings.part_dst(b, false)))
			. override_failure_message("north r %s" % reach)
			. is_equal(wrong[reach])
		)
		assert_float(_height(north, _buildings.part_dst(b, false))).is_equal(
			maxf(reach - 32.0, 0.0)
		)
		# South: the roof part paints over the unit's nose.
		(
			assert_float(_height(south, _buildings.part_dst(b, true)))
			. override_failure_message("south r %s" % reach)
			. is_equal(wrong[reach])
		)


func test_a_unit_beside_a_building_is_cut_at_the_middle_line_where_it_overlaps_the_columns(
) -> void:
	for id: StringName in [&"headquarters", &"power_plant", &"defence_turret"]:
		var building: Dictionary = _own(id)
		var b: int = building[&"index"]
		var foot: Rect2 = Rig.footprint_rect(building[&"data"])
		var y_mid: float = foot.get_center().y
		var base: Rect2 = _buildings.part_dst(b, false)
		var roof: Rect2 = _buildings.part_dst(b, true)
		for reach: float in Rig.REACHES:
			for east: bool in [true, false]:
				var wall: float = foot.end.x if east else foot.position.x
				var unit: Rect2 = _extent(Vector2(wall, y_mid), reach)
				var label: String = "%s r %s east %s" % [id, reach, east]
				# The half of the unit inside the columns: its north quarter is under the roof and
				# its south quarter over the base part, split exactly at the middle line.
				var under: Rect2 = unit.intersection(roof)
				var over: Rect2 = unit.intersection(base)
				assert_float(under.end.y).override_failure_message(label).is_equal(y_mid)
				assert_float(over.position.y).override_failure_message(label).is_equal(y_mid)
				# Its width is what lies in the columns, its height what the part is tall.
				var width: float = minf(reach, foot.size.x)
				assert_float(under.get_area()).override_failure_message(label).is_equal(
					width * minf(reach, roof.size.y)
				)
				assert_float(over.get_area()).override_failure_message(label).is_equal(
					width * minf(reach, base.size.y)
				)
				# A unit a full reach off the wall does not touch the sprite box at all.
				var clear: Rect2 = _extent(
					Vector2(wall + (reach if east else -reach), y_mid), reach
				)
				(
					assert_bool(clear.intersects(_buildings.sprite_box(b)))
					. override_failure_message(label)
					. is_false()
				)


## The own building `id` as {index in the building list, its Rig.buildings() entry}.
func _own(id: StringName) -> Dictionary:
	var index: int = Rig.find(_list, id, 1)
	return {&"index": index, &"data": _list[index]}


## The square a unit of reach `reach` covers when its centre is at `centre`.
func _extent(centre: Vector2, reach: float) -> Rect2:
	return Rect2(centre - Vector2(reach, reach), Vector2(reach, reach) * 2.0)


## The height of the part of `unit` that lies inside `part`, 0 when they do not overlap.
func _height(unit: Rect2, part: Rect2) -> float:
	var shared: Rect2 = unit.intersection(part)
	return shared.size.y if shared.has_area() else 0.0
