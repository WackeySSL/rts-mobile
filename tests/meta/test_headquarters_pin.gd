extends GdUnitTestSuite
## The data rule behind "Headquarters never destroyed" (ADR 0054 section 3): a Headquarters cannot
## be built (tab -1), cannot be sold (no price) and each skirmish scenario spawns exactly one for
## its local player. If a later ADR makes one buildable, this fails first.

const HQ_PATHS: Array[String] = [
	"res://data/units/headquarters.tres", "res://data/units/renew_hq.tres"
]
const SCENARIO_DIR: String = "res://data/scenarios/"


func test_a_headquarters_is_neither_buildable_nor_sellable() -> void:
	for path: String in HQ_PATHS:
		var def: BuildingDef = load(path) as BuildingDef
		assert_object(def).override_failure_message(path).is_not_null()
		assert_int(def.tab).override_failure_message(path + " tab").is_equal(-1)
		assert_int(def.cost).override_failure_message(path + " cost").is_equal(0)


func test_each_skirmish_spawns_one_headquarters_for_the_local_player() -> void:
	var hq_ids: Array[StringName] = [&"headquarters", &"renew_hq"]
	var checked: int = 0
	for file_name: String in DirAccess.get_files_at(SCENARIO_DIR):
		if not file_name.begins_with("skirmish_") or not file_name.ends_with(".tres"):
			continue
		var scenario: ScenarioDef = load(SCENARIO_DIR + file_name) as ScenarioDef
		var count: int = 0
		for spawn: SpawnDef in scenario.spawns:
			if spawn.owner == scenario.local_player and hq_ids.has(spawn.unit.type_id):
				count += spawn.count
		assert_int(count).override_failure_message(file_name).is_equal(1)
		checked += 1
	assert_int(checked).is_greater(0)
