extends GdUnitTestSuite
## The ground repair buildings of one faction serve the same move classes (ADR 0037 section 5): the
## command bar's Repair sends ONE REPAIR to the nearest building (`RepairRules.plan`), which is
## right only while they do. If the masks ever differ, Repair must send one REPAIR per building, as
## Home does.

const DIR: String = "res://data/units/"


func test_every_ground_repair_building_of_a_faction_serves_the_same_classes() -> void:
	var masks: Dictionary[StringName, int] = {}
	var count: int = 0
	for file: String in DirAccess.get_files_at(DIR):
		if not file.ends_with(".tres"):
			continue
		var def: BuildingDef = load(DIR + file) as BuildingDef
		if def == null or def.repair_classes == 0 or def.pads != 0:
			continue
		count += 1
		if masks.has(def.faction):
			assert_int(def.repair_classes).override_failure_message(file).is_equal(
				masks[def.faction]
			)
		masks[def.faction] = def.repair_classes
	assert_int(count).is_greater_equal(2)  # The Weld Shed and the Drone Dock.
