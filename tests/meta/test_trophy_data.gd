extends GdUnitTestSuite
## The trophy data (ADR 0054 section 2, plan P673a): the catalog loads and is sound, every kind
## has its fields, the references (lessons, maps, levels, factions, glyphs) resolve, the
## Headquarters rule behind `unbroken` holds, and a broken catalog reports a problem.

const ICON_DIR: String = "res://assets/art/svg/icons/"
const DIFFICULTY_DIR: String = "res://data/ai/difficulty/"
const FACTION_DIR: String = "res://data/factions/"


func _catalog() -> TrophyCatalog:
	var catalog: TrophyCatalog = TrophyCatalog.load_default()
	assert_object(catalog).is_not_null()
	return catalog


func _stems(dir: String) -> Array[StringName]:
	var stems: Array[StringName] = []
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.ends_with(".tres"):
			stems.append(StringName(file_name.get_basename()))
	return stems


func _def(kind: TrophyDef.Kind, id: StringName) -> TrophyDef:
	var def: TrophyDef = TrophyDef.new()
	def.id = id
	def.name = "N"
	def.hint = "H"
	def.glyph = &"glyph_check"
	def.kind = kind
	def.lesson_ids = [&"basics"]
	return def


func _broken(def: TrophyDef) -> String:
	var catalog: TrophyCatalog = TrophyCatalog.new()
	catalog.hq_type_ids = [&"headquarters"]
	var list: Array[TrophyDef] = [def]
	catalog.trophies = list
	return catalog.problem()


func test_catalog_loads_sound_with_sixteen_in_order() -> void:
	var catalog: TrophyCatalog = _catalog()
	assert_str(catalog.problem()).is_empty()
	assert_int(catalog.trophies.size()).is_equal(16)
	assert_str(String(catalog.ids()[0])).is_equal("briefed")
	assert_str(String(catalog.ids()[15])).is_equal("long_haul")
	assert_object(catalog.find(&"short_work")).is_not_null()
	assert_object(catalog.find(&"nope")).is_null()


func test_ids_unique_and_names_and_hints_set() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for trophy: TrophyDef in _catalog().trophies:
		assert_bool(seen.has(trophy.id)).is_false()
		seen[trophy.id] = true
		assert_str(trophy.name).is_not_empty()
		assert_str(trophy.hint).is_not_empty()


func test_each_kind_has_its_fields() -> void:
	var kinds: Dictionary[int, int] = {}
	for trophy: TrophyDef in _catalog().trophies:
		kinds[trophy.kind] = int(kinds.get(trophy.kind, 0)) + 1
		match trophy.kind:
			TrophyDef.Kind.LESSONS:
				assert_bool(trophy.lesson_ids.is_empty()).is_false()
			TrophyDef.Kind.COUNT:
				assert_bool(TrophyCatalog.COUNTERS.has(trophy.counter)).is_true()
				assert_int(trophy.count).is_greater(0)
			TrophyDef.Kind.WIN_GRID:
				assert_bool(trophy.map_ids.is_empty() and trophy.levels.is_empty()).is_false()
			TrophyDef.Kind.MATCH:
				var filtered: bool = (
					not trophy.levels.is_empty()
					or trophy.max_ticks > 0
					or trophy.hq_standing
					or trophy.max_buildings_lost >= 0
				)
				assert_bool(filtered).is_true()
	assert_int(kinds[TrophyDef.Kind.LESSONS]).is_equal(2)
	assert_int(kinds[TrophyDef.Kind.COUNT]).is_equal(6)
	assert_int(kinds[TrophyDef.Kind.WIN_GRID]).is_equal(5)
	assert_int(kinds[TrophyDef.Kind.MATCH]).is_equal(3)


func test_lessons_maps_levels_and_factions_resolve() -> void:
	var levels: Array[StringName] = _stems(DIFFICULTY_DIR)
	var factions: Array[StringName] = _stems(FACTION_DIR)
	var maps: Array[StringName] = (load(MapCatalog.DEFAULT_PATH) as MapCatalog).map_ids()
	for trophy: TrophyDef in _catalog().trophies:
		for lesson: StringName in trophy.lesson_ids:
			assert_bool(TutorialStart.ORDER.has(lesson)).is_true()
		for level: StringName in trophy.levels:
			assert_bool(levels.has(level)).is_true()
		for map_id: StringName in trophy.map_ids:
			assert_bool(maps.has(map_id)).is_true()
		if trophy.key != &"":
			assert_bool(factions.has(trophy.key)).is_true()
	var drilled: TrophyDef = _catalog().find(&"fully_drilled")
	assert_array(drilled.lesson_ids).is_equal(TutorialStart.ORDER)
	assert_array(_catalog().find(&"flats_fords_crags").map_ids).is_equal(maps)
	assert_array(_catalog().find(&"no_easy_ground").map_ids).is_equal(maps)


func test_thresholds_are_data() -> void:
	var catalog: TrophyCatalog = _catalog()
	assert_int(catalog.find(&"short_work").max_ticks).is_equal(9000)
	assert_int(catalog.find(&"seasoned").count).is_equal(10)
	assert_int(catalog.find(&"long_haul").count).is_equal(25)
	assert_int(catalog.find(&"clean_sheet").max_buildings_lost).is_equal(0)


func test_glyph_files_exist_and_pips_in_range() -> void:
	for trophy: TrophyDef in _catalog().trophies:
		assert_int(trophy.pips).is_between(0, TrophyCatalog.MAX_PIPS)
		assert_bool(FileAccess.file_exists(ICON_DIR + "%s.svg" % trophy.glyph)).is_true()


func test_headquarters_types_are_unbuildable_and_spawned_once() -> void:
	var catalog: TrophyCatalog = _catalog()
	var catalogue: MapCatalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	var scenarios: int = 0
	for entry: Dictionary in catalogue.entries:
		for row: Dictionary in entry[MapCatalog.KEY_SCENARIOS] as Array:
			var scenario: ScenarioDef = load(str(row[MapCatalog.KEY_PATH])) as ScenarioDef
			var spawned: int = 0
			for spawn: SpawnDef in scenario.spawns:
				if spawn.owner != scenario.local_player:
					continue
				if catalog.hq_type_ids.has(spawn.unit.type_id):
					spawned += spawn.count
			assert_int(spawned).is_equal(1)
			scenarios += 1
	assert_int(scenarios).is_greater(0)
	for type_id: StringName in catalog.hq_type_ids:
		var def: UnitDef = load("res://data/units/%s.tres" % type_id) as UnitDef
		assert_object(def).is_not_null()
		assert_int(def.tab).is_equal(-1)


func test_broken_catalogs_report_a_problem() -> void:
	assert_str(_broken(_def(TrophyDef.Kind.LESSONS, &"ok"))).is_empty()
	assert_str(_broken(_def(TrophyDef.Kind.LESSONS, &""))).is_not_empty()
	assert_str(_broken(_def(TrophyDef.Kind.LESSONS, &"a=b"))).is_not_empty()
	assert_str(_broken(_def(TrophyDef.Kind.LESSONS, &" pad"))).is_not_empty()
	assert_str(_broken(_def(99 as TrophyDef.Kind, &"odd"))).is_not_empty()
	var counter: TrophyDef = _def(TrophyDef.Kind.COUNT, &"c")
	counter.counter = &"wins"
	assert_str(_broken(counter)).is_not_empty()  # count 0
	var pips: TrophyDef = _def(TrophyDef.Kind.LESSONS, &"p")
	pips.pips = 4
	assert_str(_broken(pips)).is_not_empty()
	var twin: TrophyCatalog = _catalog().duplicate() as TrophyCatalog
	var list: Array[TrophyDef] = twin.trophies.duplicate()
	list.append(list[0])
	twin.trophies = list
	assert_str(twin.problem()).contains("duplicate")
