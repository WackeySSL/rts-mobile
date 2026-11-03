extends GdUnitTestSuite
## The neutral damage sheet in the bake (plan P157, ADR 0028 section 4). The real file does not
## exist before row P160, so a crafted sheet and its frames are written to `user://` and
## `WorldSort.neutral_path` is pointed at it: absent, the bake is today's with no error and no slot;
## present, it is added after the art-id filter and after `_player_arts`, collected for every
## player as shared slots, with its bases resolved once per bake.

const DIR: String = "user://p157_neutral"
const SHEET: String = "user://p157_neutral/sheet.tres"
const MISSING: String = "user://p157_neutral/none.tres"
const SVG: String = (
	'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="4">'
	+ '<polygon points="0,0 8,0 8,4" fill="#808080"/></svg>'
)
const SCAR: StringName = &"scar"
const LOOSE: StringName = &"loose"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"damage"
	sheet.faction = IsoAtlas.NEUTRAL
	sheet.category = &"dmg"
	sheet.root = DIR
	sheet.parts = PackedStringArray(["scar", "loose"])
	sheet.counts = PackedInt32Array([1, 1])
	sheet.frames = PackedInt32Array([2, 4])
	sheet.sizes = PackedInt32Array([8, 4, 8, 4])
	sheet.anchors = PackedInt32Array([0, 0, 0, 0])
	assert_int(ResourceSaver.save(sheet, SHEET)).is_equal(OK)
	for path: String in ["damage_scar_f0", "damage_scar_f1"] + _loose_names():
		var file: FileAccess = FileAccess.open("%s/%s.svg" % [DIR, path], FileAccess.WRITE)
		file.store_string(SVG)


func after_test() -> void:
	for name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute("%s/%s" % [DIR, name])
	DirAccess.remove_absolute(DIR)


func test_while_the_file_is_absent_the_bake_is_todays_with_no_slot() -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = MISSING
	var atlas: IsoAtlas = sort.bake(_scenario(true))
	assert_object(sort.neutral_sheet()).is_null()
	assert_object(IsoAtlas.load_neutral_sheet(MISSING)).is_null()
	assert_int(sort.neutral_base(SCAR, 1)).is_equal(-1)
	assert_bool(atlas.region(&"light_tank", &"hull", 6, 0).has_area()).is_true()
	# The page is the one of the type sheets alone.
	var plain: WorldSort = auto_free(WorldSort.new())
	plain.neutral_path = MISSING
	assert_that(atlas.page_px()).is_equal(plain.bake(_scenario(true)).page_px())


func test_the_sheet_is_collected_for_every_player_as_shared_slots() -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = SHEET
	var atlas: IsoAtlas = sort.bake(_scenario(true))
	assert_object(sort.neutral_sheet()).is_not_null()
	for owner_id: int in [1, 2]:
		assert_int(atlas.frame_count_at(sort.neutral_base(SCAR, owner_id))).is_equal(2)
		assert_int(atlas.frame_count_at(sort.neutral_base(LOOSE, owner_id))).is_equal(4)
	# Each player has its own group, but no key colour is in a frame: both groups read one slot.
	assert_int(sort.neutral_base(SCAR, 1)).is_not_equal(sort.neutral_base(SCAR, 2))
	for frame: int in 4:
		var first: Rect2i = atlas.frame_region(sort.neutral_base(LOOSE, 1), frame)
		assert_bool(first.has_area()).is_true()
		assert_that(atlas.frame_region(sort.neutral_base(LOOSE, 2), frame)).is_equal(first)
	# The six distinct frames are the only slots it adds, whatever the number of players.
	assert_that(_distinct_neutral_regions(sort, atlas)).is_equal(6)


func test_a_scenario_with_no_vehicle_and_no_factions_still_bakes_it_and_finds_its_factions(
) -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = SHEET
	var atlas: IsoAtlas = sort.bake(_scenario(false))
	assert_bool(atlas.is_empty()).is_false()  # Two players, no unit: the neutral frames only.
	assert_int(sort.neutral_base(SCAR, 2)).is_greater_equal(0)
	# Factions come from the type sheets alone: the second player wears the Lumen Accord's art.
	var other: WorldSort = auto_free(WorldSort.new())
	other.neutral_path = SHEET
	var both: IsoAtlas = other.bake(_scenario(true))
	assert_bool(both.region(&"renew_tank", &"hull", 6, 1).has_area()).is_true()
	assert_bool(both.region(&"renew_tank", &"hull", 6, 0).has_area()).is_false()


func test_the_bases_are_resolved_once_per_bake_and_a_read_builds_no_key() -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = SHEET
	var atlas: IsoAtlas = sort.bake(_scenario(true))
	var built: int = IsoAtlas.keys_built()
	for _i: int in 50:
		atlas.frame_region(sort.neutral_base(LOOSE, 2), 3)
	assert_int(IsoAtlas.keys_built()).is_equal(built)
	assert_object(sort.bake(_scenario(true))).is_same(atlas)  # Same art: nothing is baked again.
	assert_int(IsoAtlas.keys_built()).is_equal(built)


func _loose_names() -> Array[String]:
	var names: Array[String] = []
	for frame: int in 4:
		names.append("damage_loose_f%d" % frame)
	return names


func _distinct_neutral_regions(sort: WorldSort, atlas: IsoAtlas) -> int:
	var seen: Dictionary[Rect2i, bool] = {}
	for part: StringName in [SCAR, LOOSE]:
		for owner_id: int in [1, 2]:
			var base: int = sort.neutral_base(part, owner_id)
			for frame: int in atlas.frame_count_at(base):
				seen[atlas.frame_region(base, frame)] = true
	return seen.size()


## Two players; with `units`, a Derrick League tank and a Lumen Accord tank, else none.
func _scenario(units: bool) -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.player_count = 2
	if units:
		var types: Array[String] = ["light_tank", "renew_tank"]
		for owner_id: int in 2:
			var spawn: SpawnDef = SpawnDef.new()
			spawn.owner = owner_id + 1
			spawn.unit = load("res://data/units/%s.tres" % types[owner_id])
			scenario.spawns.append(spawn)
	return scenario
