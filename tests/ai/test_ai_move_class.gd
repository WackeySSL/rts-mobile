extends GdUnitTestSuite
## The move class the intel manager gives the scout's goal key (plan row P177b, ADR 0030 section
## 4) is the unit's own class (P295), and the tab's (vehicles tracked, the rest on foot) when the
## view has none. This walks the shipped and the frozen rosters and pins the rule the fallback rests on.

const DIRS: Array[String] = ["res://data/units/", "res://data/dev/arena/units/"]
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
## The wheeled vehicles (the Shot Truck, the Linecar, the Seeder), sorted.
const WHEELED_VEHICLES: Array[String] = ["fossil_shot_truck", "renew_linecar", "renew_seeder"]


func test_the_constants_are_the_worlds() -> void:
	assert_int(AiIntel.FOOT).is_equal(World.MoveClass.FOOT)
	assert_int(AiIntel.TRACKED).is_equal(World.MoveClass.TRACKED)


func test_every_vehicle_is_tracked_but_the_wheeled_three_and_every_infantry_unit_walks() -> void:
	var seen: Dictionary[int, int] = {}
	var wheeled: Array[String] = []
	for dir: String in DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"):
				continue
			var def: UnitDef = load(dir + file) as UnitDef
			if def == null:
				continue
			seen[def.tab] = seen.get(def.tab, 0) + 1
			# The drone squads (P264) are AIR on the Infantry tab. `AiMemory.class_of` (reads the
			# tab only, AiMemory.gd:161-164) must handle them before P250 or P267 lets the AI build
			# them.
			if def.low_flying:
				continue
			var expected: int = -1
			if def.tab == World.Tab.VEHICLES:
				expected = AiIntel.TRACKED
				# Three vehicles are wheeled (ADR 0037 sections 7 and 8), the rest tracked.
				if String(def.type_id) in WHEELED_VEHICLES:
					expected = World.MoveClass.WHEELED
					wheeled.append(String(def.type_id))
			elif def.tab == World.Tab.INFANTRY:
				expected = AiIntel.FOOT
			if expected >= 0:
				(
					assert_int(def.move_class)
					. override_failure_message("%s%s: move class %d" % [dir, file, def.move_class])
					. is_equal(expected)
				)
	# Exactly the listed vehicles are wheeled: a fourth, or one changed, fails.
	wheeled.sort()
	assert_array(wheeled).is_equal(WHEELED_VEHICLES)
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


## `PlayerView` copies `type_move_class` (P295), and `AiMemory.class_of` reads it, so the wheeled three
## key WHEELED; a view with no class column falls back to the tab (vehicles tracked).
func test_class_of_keys_the_wheeled_vehicles_wheeled() -> void:
	for id: String in WHEELED_VEHICLES:
		var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
		var view: PlayerView = PlayerView.new()
		view.type_tab = PackedInt32Array([def.tab])
		assert_int(AiMemory.class_of(view, 0)).override_failure_message(id).is_equal(
			AiIntel.TRACKED
		)
		view.type_move_class = PackedInt32Array([def.move_class])
		assert_int(AiMemory.class_of(view, 0)).override_failure_message(id).is_equal(
			AiMemory.WHEELED
		)
		assert_int(def.move_class).is_equal(World.MoveClass.WHEELED)
	assert_int(AiMemory.WHEELED).is_equal(World.MoveClass.WHEELED)
