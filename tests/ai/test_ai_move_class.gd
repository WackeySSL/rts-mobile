extends GdUnitTestSuite
## The move class the intel manager gives the scout's goal key (plan row P177b, ADR 0030 section
## 4) is the tab's: vehicles tracked, the rest on foot. `PlayerView` has no `type_move_class`, so
## this walks the shipped and the frozen rosters and pins the rule it rests on.

const DIRS: Array[String] = ["res://data/units/", "res://data/dev/arena/units/"]
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")


func test_the_constants_are_the_worlds() -> void:
	assert_int(AiIntel.FOOT).is_equal(World.MoveClass.FOOT)
	assert_int(AiIntel.TRACKED).is_equal(World.MoveClass.TRACKED)


func test_every_vehicle_is_tracked_and_every_infantry_unit_walks() -> void:
	var seen: Dictionary[int, int] = {}
	for dir: String in DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"):
				continue
			var def: UnitDef = load(dir + file) as UnitDef
			if def == null:
				continue
			seen[def.tab] = seen.get(def.tab, 0) + 1
			var expected: int = -1
			if def.tab == World.Tab.VEHICLES:
				expected = AiIntel.TRACKED
			elif def.tab == World.Tab.INFANTRY:
				expected = AiIntel.FOOT
			if expected >= 0:
				(
					assert_int(def.move_class)
					. override_failure_message("%s%s: move class %d" % [dir, file, def.move_class])
					. is_equal(expected)
				)
	# Both kinds are in the rosters, so the walk is not empty.
	assert_bool(seen.has(World.Tab.VEHICLES) and seen.has(World.Tab.INFANTRY)).is_true()


func test_each_scout_type_is_a_tracked_vehicle() -> void:
	for faction: String in Rig.FACTIONS:
		var scout: StringName = Rig.def_of(faction).scout_type
		var found: int = 0
		for dir: String in DIRS:
			for file: String in DirAccess.get_files_at(dir):
				if not file.ends_with(".tres"):
					continue
				var def: UnitDef = load(dir + file) as UnitDef
				if def != null and def.type_id == scout:
					found += 1
					assert_int(def.tab).is_equal(World.Tab.VEHICLES)
					assert_int(def.move_class).is_equal(AiIntel.TRACKED)
		assert_int(found).is_greater(0)
