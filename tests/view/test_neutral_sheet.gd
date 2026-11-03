extends GdUnitTestSuite
## The neutral damage sheet in the bake (plan P157, ADR 0028 section 4). The real file does not
## exist before row P160, so a crafted sheet and its frames are written to `user://` and
## `WorldSort.neutral_path` is pointed at it: absent, the bake is today's with no error and no slot;
## present, it is added after the art-id filter and after `_player_arts`, collected for every
## player as shared slots, with its bases resolved once per bake.

const NEUTRAL_PATH: String = "res://assets/art/svg/damage/damage_sheet.tres"
const SVG: String = (
	'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="4">'
	+ '<polygon points="0,0 8,0 8,4" fill="#808080"/></svg>'
)
const SCAR: StringName = &"scar"
const LOOSE: StringName = &"loose"

var _dir: String = "user://p157_neutral_%d" % OS.get_process_id()  ## Apart for parallel runs.
var _sheet: String = _dir + "/sheet.tres"
var _missing: String = _dir + "/none.tres"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"damage"
	sheet.faction = IsoAtlas.NEUTRAL
	sheet.category = &"dmg"
	sheet.root = _dir
	sheet.parts = PackedStringArray(["scar", "loose"])
	sheet.counts = PackedInt32Array([1, 1])
	sheet.frames = PackedInt32Array([2, 4])
	sheet.sizes = PackedInt32Array([8, 4, 8, 4])
	sheet.anchors = PackedInt32Array([0, 0, 0, 0])
	assert_int(ResourceSaver.save(sheet, _sheet)).is_equal(OK)
	for path: String in ["damage_scar_f0", "damage_scar_f1"] + _loose_names():
		var file: FileAccess = FileAccess.open("%s/%s.svg" % [_dir, path], FileAccess.WRITE)
		file.store_string(SVG)


func after_test() -> void:
	for name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute("%s/%s" % [_dir, name])
	DirAccess.remove_absolute(_dir)


func test_the_path_is_the_one_of_the_adr() -> void:
	assert_str(IsoAtlas.NEUTRAL_SHEET).is_equal(NEUTRAL_PATH)
	assert_str(auto_free(WorldSort.new()).neutral_path).is_equal(NEUTRAL_PATH)


func test_while_the_file_is_absent_the_bake_is_mains_bake() -> void:
	var scenario: ScenarioDef = _scenario(true)
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = _missing
	var atlas: IsoAtlas = sort.bake(scenario)
	assert_object(sort.neutral_sheet()).is_null()
	assert_object(IsoAtlas.load_neutral_sheet(_missing)).is_null()
	assert_int(sort.neutral_base(SCAR, 1)).is_equal(-1)
	# Main's bake, built directly: the scenario's type sheets and its players, nothing else.
	var sheets: Array[IsoSheetDef] = []
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if sheet.art_id in [&"light_tank", &"renew_tank"]:
			sheets.append(sheet)
	var arts: Array[IsoPlayerArt] = WorldSort._player_arts(scenario, sheets)
	var want: IsoAtlas = IsoAtlas.build(sheets, arts, 1.0)
	assert_that(atlas.page_px()).is_equal(want.page_px())
	assert_float(atlas.bake_scale()).is_equal(want.bake_scale())
	var compared: int = 0
	for sheet: IsoSheetDef in sheets:
		for part_name: String in sheet.parts:
			var part: StringName = StringName(part_name)
			for dir: int in sheet.directions(part):
				for player: int in arts.size():
					for frame: int in maxi(sheet.frame_count(part), 1):
						var got: Rect2i = atlas.region(sheet.art_id, part, dir, player, frame)
						assert_that(got).is_equal(
							want.region(sheet.art_id, part, dir, player, frame)
						)
						compared += 1
	assert_int(compared).is_greater(100)


func test_a_sheet_of_another_faction_is_no_neutral_sheet() -> void:
	# The error paths are not run (they print "ERROR:", which verify.sh fails on, and its allowlist
	# holds only the icon): the pure checks behind them are.
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.faction = &"fossil"
	assert_str(IsoAtlas.neutral_problem(sheet, "a.tres")).is_equal(
		"IsoAtlas: a.tres is no neutral IsoSheetDef"
	)
	assert_str(IsoAtlas.neutral_problem(null, "a.tres")).is_not_empty()
	sheet.faction = IsoAtlas.NEUTRAL
	assert_str(IsoAtlas.neutral_problem(sheet, "a.tres")).is_empty()
	assert_object(IsoAtlas.load_neutral_sheet(_sheet)).is_not_null()  # A real one loads.


func test_the_sheet_is_collected_for_every_player_as_shared_slots() -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = _sheet
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


func test_a_type_with_the_neutral_art_id_and_a_key_colour_are_found() -> void:
	var sheet: IsoSheetDef = IsoAtlas.load_neutral_sheet(_sheet)
	var ids: Dictionary[StringName, bool] = {&"light_tank": true}
	assert_bool(WorldSort.neutral_clash(ids, sheet)).is_false()
	ids[&"damage"] = true
	assert_bool(WorldSort.neutral_clash(ids, sheet)).is_true()
	var renew: FactionDef = load(WorldSort.FACTION_FILE % "renew") as FactionDef
	var arts: Array[IsoPlayerArt] = [
		IsoPlayerArt.make(&"renew", renew.key_triad, PackedStringArray(WorldSort.TRIADS[0]))
	]
	var keyed: String = SVG.replace("#808080", renew.key_triad[0])
	assert_bool(WorldSort.has_key_colour(SVG, arts)).is_false()
	assert_bool(WorldSort.has_key_colour(keyed, arts)).is_true()


func test_a_scenario_with_no_vehicle_and_no_factions_still_bakes_it_and_finds_its_factions(
) -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = _sheet
	var atlas: IsoAtlas = sort.bake(_scenario(false))
	assert_bool(atlas.is_empty()).is_false()  # Two players, no unit: the neutral frames only.
	assert_int(sort.neutral_base(SCAR, 2)).is_greater_equal(0)
	# Factions come from the type sheets alone: the second player wears the Lumen Accord's art.
	var other: WorldSort = auto_free(WorldSort.new())
	other.neutral_path = _sheet
	var both: IsoAtlas = other.bake(_scenario(true))
	assert_bool(both.region(&"renew_tank", &"hull", 6, 1).has_area()).is_true()
	assert_bool(both.region(&"renew_tank", &"hull", 6, 0).has_area()).is_false()


func test_the_bases_are_resolved_once_per_bake_and_a_read_builds_no_key() -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.neutral_path = _sheet
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
