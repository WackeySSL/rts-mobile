extends GdUnitTestSuite
## Facts that live in two files and would drift apart without a word: the camera's zoom levels
## (data/input_settings.tres) and the art gallery's zoom row, the licence credit for the debug APKs'
## default launcher icon (ADR 0005, plan risk 12), the selection ring's texture radius that the unit
## layer and the art gallery each hold (P56d), and the error scan's allowlist, which hides engine
## errors from verify.sh and both export scripts: a new or widened entry must show up here. Phase 2
## adds (plan P52) the perf budget's unit count and the arena's, the explored fog alpha of STYLE.md,
## `FogLayer` and the gallery, the terrain colours and tiles of `MapView` and the gallery (and every
## terrain id of the data), the gate's numbers and the ADRs that give them (ADR 0012 section 4 less
## the rows ADR 0014 replaces, and the fields ADR 0014 adds), and the ABI version of the kernels.

const SETTINGS_PATH: String = "res://data/input_settings.tres"
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
const ALLOWLIST_PATH: String = "res://scripts/verify-allowlist.txt"
const ZOOM_ROWS: Array[String] = ["Grass/ZoomRow", "Sand/ZoomRow"]
const STYLE_PATH: String = "res://assets/art/STYLE.md"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const TERRAIN_DIR: String = "res://data/terrain"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const ADR_0012_PATH: String = "res://docs/adr/0012-worker-thread-tick-snapshot-and-revised-gate.md"
const ADR_0014_PATH: String = "res://docs/adr/0014-frame-pacing-and-cpu-limits.md"
const KERNELS_HEADER: String = "res://native/sim_kernels/src/bind/sim_kernels.h"
## The rows of ADR 0012 section 4's table that ADR 0014 section 4 drops from `PerfGateDef`, and the
## ratios: printed estimates that the lead sets in the file alone (plan exception 5), not
## thresholds. The ratios of ADR 0013 section 15 (`ci_ratio_native_*`) are not in that table.
const REPLACED: Array[String] = ["on_time_ms", "on_time_share_pct"]
const RATIOS: Array[String] = ["ci_ratio_mean", "ci_ratio_p95"]
## ADR 0014 section 1's table, and the fields that its prose gives (sections 2 and 4).
const PACING_ROWS: Array[String] = [
	"drop_slots", "dropped_pct_max", "cadence_pct_min", "hitches_max", "jitter_ms"
]
const PROSE_FIELDS: Array[String] = [
	"refresh_tolerance_pct", "median_tolerance_pct", "ref_iterations", "ref_burst_ms"
]
## The gallery has no class_name: a preloaded script gives its constants.
const ArtGallery: GDScript = preload("res://game/view/art_gallery.gd")
const PerfBudget: GDScript = preload("res://tests/perf/support/perf_budget.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")


func test_the_gallery_zoom_row_shows_the_camera_zoom_levels() -> void:
	var levels: Array[float] = []
	for level: float in (load(SETTINGS_PATH) as InputSettings).zoom_levels:
		levels.append(level)
	assert_array(levels).is_not_empty()
	var gallery: Node = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	for row_path: String in ZOOM_ROWS:
		var scales: Array[float] = []
		for rig: Node in gallery.get_node(row_path).get_children():
			if rig is Node2D:  # The labels under the rigs are Controls.
				var rig_scale: Vector2 = (rig as Node2D).scale
				assert_float(rig_scale.y).override_failure_message(row_path).is_equal(rig_scale.x)
				scales.append(rig_scale.x)
		scales.sort()
		assert_array(scales).override_failure_message(row_path).is_equal(levels)


## Both scale a ring by `radius / RING_TEX_RADIUS_PX`, so the gallery (art-director's) shows the
## ring sizes of the game (touch-ux-dev's UnitLayer) only while the two constants agree. The
## texture itself is pinned to the same 72 px by tests/art.
func test_the_unit_layer_and_the_art_gallery_scale_the_ring_texture_by_the_same_radius() -> void:
	assert_float(ArtGallery.RING_TEX_RADIUS_PX).is_equal(UnitLayer.RING_TEX_RADIUS_PX)


## Whitespace is normalised, so a re-wrapped line does not break the check.
func test_credits_name_the_debug_launcher_icon_and_the_licence_file() -> void:
	var credits: String = FileAccess.get_file_as_string(CREDITS_PATH)
	assert_str(credits).is_not_empty()
	var flat: String = RegEx.create_from_string("\\s+").sub(credits, " ", true)
	assert_str(flat).contains("default launcher icon of the debug APKs")
	assert_str(flat).contains("THIRD_PARTY_LICENSES.txt")
	assert_str(flat).contains("Andrea Calabró")  # CC BY: the author and the licence are the credit.
	assert_str(flat).contains("CC BY 4.0")


func test_the_allowlist_holds_only_the_icon_entry() -> void:
	var entries: Array[String] = []
	for line: String in FileAccess.get_file_as_string(ALLOWLIST_PATH).split("\n"):
		if not line.strip_edges().is_empty() and not line.begins_with("#"):
			entries.append(line)
	assert_array(entries).is_equal(["^ERROR: No project icon specified\\.[ ]"])


## The perf budget (tests/perf/budget.cfg) is calibrated on the units that the arena scene plays:
## the sum of the spawns of the scenario that its scene holds, which tests/perf times.
func test_the_budget_units_are_the_units_of_the_perf_arena() -> void:
	var arena: Node = auto_free((load(DevRoutes.PERF_ARENA_SCENE) as PackedScene).instantiate())
	var scenario: ScenarioDef = arena.get("scenario") as ScenarioDef
	assert_str(scenario.resource_path).is_equal(ARENA_PATH)
	var units: int = 0
	for spawn: SpawnDef in scenario.spawns:
		units += spawn.count
	assert_int(units).is_greater(0)
	assert_int(PerfBudget.read()["units"]).is_equal(units)


func test_the_explored_fog_alpha_is_the_style_value_in_the_fog_layer_and_the_gallery() -> void:
	var flat: String = _flat(FileAccess.get_file_as_string(STYLE_PATH))
	var rule: RegEx = RegEx.create_from_string(
		"alpha 255 where unexplored, (\\d+) where explored but not visible, 0 where visible"
	)
	var named: RegEx = RegEx.create_from_string(
		"`FogLayer\\.explored_alpha` and the gallery's `explored_fog_alpha` are (\\d+)"
	)
	var rule_hit: RegExMatch = rule.search(flat)
	var named_hit: RegExMatch = named.search(flat)
	assert_object(rule_hit).override_failure_message("STYLE.md: the alpha rule").is_not_null()
	assert_object(named_hit).override_failure_message("STYLE.md: the named alpha").is_not_null()
	var style: int = rule_hit.get_string(1).to_int()
	assert_int(named_hit.get_string(1).to_int()).is_equal(style)
	assert_int(style).is_between(1, 254)  # Between visible (0) and never seen (255).
	var arena: Node = auto_free((load(DevRoutes.PERF_ARENA_SCENE) as PackedScene).instantiate())
	var layers: Array[FogLayer] = [auto_free(FogLayer.new())]
	layers.append(_main_scene().get_node("FogLayer") as FogLayer)
	layers.append(arena.get_node("FogLayer") as FogLayer)
	for layer: FogLayer in layers:
		assert_int(layer.explored_alpha).is_equal(style)
	var gallery: Node = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	assert_int(gallery.get("explored_fog_alpha")).is_equal(style)


## Both `MapView`s are read: the script's `@export` defaults (where the merged P36 keeps the
## STYLE.md values) and the node of main.tscn, which sets no override. The gallery's copies are
## pinned to STYLE.md and to every texel by tests/art.
func test_map_view_colors_and_tiles_equal_the_gallerys_terrain_colors_and_tiles() -> void:
	for view: MapView in _map_views():
		assert_array(view.colors.keys()).is_equal(ArtGallery.TERRAIN_COLORS.keys())
		for key: StringName in ArtGallery.TERRAIN_COLORS:
			assert_that(view.colors[key]).override_failure_message(key).is_equal(
				ArtGallery.TERRAIN_COLORS[key]
			)
		assert_array(view.tiles.keys()).is_equal(ArtGallery.TERRAIN_TILES.keys())
		for id: StringName in ArtGallery.TERRAIN_TILES:
			assert_str(view.tiles[id]).override_failure_message(id).is_equal(
				ArtGallery.TERRAIN_TILES[id]
			)


## A terrain id without its base colour bakes magenta, and one without a tile has no pattern to
## bake; a rect that names a colour the map has not bakes magenta as well (P26l docs, 2026-10-13).
func test_every_terrain_id_in_the_data_has_a_base_colour_and_a_tile_in_both_map_views() -> void:
	var ids: Array[StringName] = []
	for path: String in FileScan.list_files(TERRAIN_DIR, ".tres"):
		var kinds: TerrainSetDef = load(path) as TerrainSetDef
		for terrain: TerrainDef in kinds.terrains:
			ids.append(terrain.id)
	assert_array(ids).is_not_empty()
	for view: MapView in _map_views():
		for id: StringName in ids:
			assert_bool(view.colors.has(id)).override_failure_message("colour " + id).is_true()
			assert_bool(view.tiles.has(id)).override_failure_message("tile " + id).is_true()
		for id: StringName in view.tiles:
			for rect: String in view.tiles[id].split(" "):
				var key: StringName = StringName(rect.split(",")[4])
				assert_bool(view.colors.has(key)).override_failure_message(rect).is_true()


## The thresholds of ADR 0012 section 4's table, less the rows that ADR 0014 replaces (an accepted
## ADR keeps its text) and the ratios. The data file and the script's defaults both hold them.
func test_the_gate_thresholds_equal_the_table_of_adr_0012_section_4_less_the_replaced_rows(
) -> void:
	var table: Dictionary[String, String] = _rows(_section(_adr(ADR_0012_PATH), "### 4."))
	for skipped: String in REPLACED + RATIOS:
		assert_bool(table.has(skipped)).override_failure_message(skipped).is_true()
		table.erase(skipped)
	assert_int(table.size()).is_greater_equal(10)
	_assert_gate_holds(table)


## ADR 0014 section 1's table, section 2's `refresh_tolerance_pct` and the `PerfGateDef` list of
## section 4, where three of the fields appear only in prose (and `refresh_tolerance_pct` again).
func test_the_gate_holds_the_fields_that_adr_0014_adds() -> void:
	var adr: String = _adr(ADR_0014_PATH)
	var fields: Dictionary[String, String] = _rows(_section(adr, "### 1."))
	assert_array(fields.keys()).is_equal(PACING_ROWS)
	for field: String in PROSE_FIELDS:
		var from_rule: String = _number_after(_section(adr, "### 2."), field)
		var from_list: String = _number_after(_section(adr, "### 4."), field)
		var text: String = from_rule if not from_rule.is_empty() else from_list
		assert_str(text).override_failure_message(field).is_not_empty()
		if not from_list.is_empty():
			assert_str(from_list).override_failure_message(field).is_equal(text)
		fields[field] = text
	_assert_gate_holds(fields)


## The two fields of ADR 0012 that ADR 0014 drops are in neither file, and `pin_busy_pct` (the
## fallback of ADR 0014 section 5, not taken: the acceptance note of 2026-10-13) does not enter.
func test_the_gate_drops_the_replaced_fields_and_takes_no_pin_busy_pct() -> void:
	var text: String = FileAccess.get_file_as_string(GATE_PATH)
	assert_str(text).is_not_empty()
	for field: String in REPLACED + ["pin_busy_pct"]:
		assert_bool(text.contains(field)).override_failure_message(field).is_false()
		for gate: PerfGateDef in [load(GATE_PATH), PerfGateDef.new()]:
			assert_bool(gate.get(field) == null).override_failure_message(field).is_true()


## One number in three places: the boundary's constant in NativeKernels.gd, the C++ constant in
## sim_kernels.h and the answer of the loaded library's `SimKernels::abi_version()`. The library is
## required, not skipped (verify.sh builds it).
func test_the_abi_version_is_the_same_in_native_kernels_the_header_and_the_library() -> void:
	var line: RegEx = RegEx.create_from_string("constexpr int64_t ABI_VERSION = (\\d+);")
	var found: RegExMatch = line.search(FileAccess.get_file_as_string(KERNELS_HEADER))
	assert_object(found).is_not_null()
	var kernels: Object = ClassDB.instantiate(NativeKernels.CLASS_NAME)
	(
		assert_object(kernels)
		. override_failure_message("run bash scripts/build-native.sh")
		. is_not_null()
	)
	assert_int(kernels.call(&"abi_version")).is_equal(NativeKernels.ABI_VERSION)
	assert_int(found.get_string(1).to_int()).is_equal(NativeKernels.ABI_VERSION)


## Whether the data file and the script's defaults both hold every `fields` entry (field to the
## number the ADR gives it).
func _assert_gate_holds(fields: Dictionary[String, String]) -> void:
	for gate: PerfGateDef in [load(GATE_PATH), PerfGateDef.new()]:
		for field: String in fields:
			var text: String = fields[field]
			var why: String = "%s is %s in the ADR" % [field, text]
			var actual: Variant = gate.get(field)
			if typeof(actual) == TYPE_BOOL:
				assert_bool(actual).override_failure_message(why).is_equal(text == "true")
			elif typeof(actual) == TYPE_INT:
				assert_bool(text.is_valid_int()).override_failure_message(why).is_true()
				assert_int(actual).override_failure_message(why).is_equal(text.to_int())
			elif typeof(actual) == TYPE_FLOAT:
				assert_bool(text.is_valid_float()).override_failure_message(why).is_true()
				assert_float(actual).override_failure_message(why).is_equal(text.to_float())
			else:
				assert_bool(false).override_failure_message(why + ": not a number field").is_true()


## The text of the ADR at `path`, which must not be empty.
func _adr(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message(path).is_not_empty()
	return text


## `text` from the line that begins with `heading` up to the next heading of any level.
func _section(text: String, heading: String) -> String:
	var start: int = text.find("\n" + heading)
	assert_int(start).override_failure_message("no section " + heading).is_greater_equal(0)
	var end: int = text.find("\n##", start + 1)
	return text.substr(start, end - start) if end >= 0 else text.substr(start)


## The rows `| `field` | value | ... |` of the tables in `text`: field to value.
func _rows(text: String) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	var row: RegEx = RegEx.create_from_string("(?m)^\\| `(\\w+)` \\| ([^|]*?) \\|")
	for hit: RegExMatch in row.search_all(text):
		found[hit.get_string(1)] = hit.get_string(2).strip_edges()
	return found


## The number that follows `field` in backticks in the prose of `text`, as in "`field` 2.0" and in
## "`field` (1.0)"; empty when there is none.
func _number_after(text: String, field: String) -> String:
	var number: RegEx = RegEx.create_from_string("`%s` \\(?(\\d+(?:\\.\\d+)?)" % field)
	var hit: RegExMatch = number.search(_flat(text))
	return "" if hit == null else hit.get_string(1)


## `text` with every run of whitespace as one space, so a re-wrapped line does not break a match.
func _flat(text: String) -> String:
	return RegEx.create_from_string("\\s+").sub(text, " ", true)


## The `MapView` that `new()` makes (the script's defaults) and the one of main.tscn.
func _map_views() -> Array[MapView]:
	var fresh: MapView = auto_free(MapView.new())
	return [fresh, _main_scene().get_node("MapView") as MapView]


## main.tscn in the tree: its SelectionPanel makes two nodes of its own when it is built, and only
## the tree frees them with the scene.
func _main_scene() -> Node:
	var root: Node = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	add_child(root)
	return root
