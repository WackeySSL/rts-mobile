extends GdUnitTestSuite
## The placement ghost's view (plan P86 and P86b, ADR 0023 section 3, STYLE.md "Ghosts"): the cells
## it marks are the footprint's cells at every zoom and every screen, it is green where the plant
## fits and red with the glyph of its reason where it does not (all six reasons), its sprite is the
## building's body on the match's atlas (as `BuildingLayer` draws it) with the picture's rise the
## sheet's, and a defence's ghost has its head too, its pivot on the sheet's mount. A ghost the sim
## refused is red with the occupied glyph and the word "Blocked", and the glyph and the word keep
## their dp size at every screen and zoom. It redraws every frame while the mode is on, once more
## when it ends and never otherwise. `GhostMarks` makes the three marks of a cell from one texture:
## the wash and the frame as diamonds, the hatch cut from the art director's file twice, so that its
## bands run straight across the cells of a footprint.

const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const AT: Vector2i = Vector2i(11, 7)  ## The tile that holds the middle of the plant at (10, 6).
const HATCH_PERIOD: int = 32  ## The hatch art's bands repeat every 32 px of x + y.

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _placement: PlacementController
var _layer: GhostLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open(Rig.scenario(), Rig.PLANT)


## A new main scene in `scenario`, paused, the previous one freed, with the structure of type id
## `ready` finished in the published snapshot and the ground explored.
func _open(scenario: ScenarioDef, ready: StringName) -> void:
	if is_instance_valid(_main):
		_main.free()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	(_main.get_node("MatchRunner") as MatchRunner).scenario = scenario
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true
	Rig.make_ready(_runner.snapshot, _runner.snapshot.type_ids.find(ready))
	Rig.explore(_runner.snapshot)
	_camera = _main.get_node("Camera")
	_placement = _main.get_node("PlacementController")
	_layer = _main.get_node("GhostLayer")


func test_the_marked_diamonds_are_the_footprints_cells_at_every_zoom_and_screen() -> void:
	var levels: PackedFloat32Array = (_camera.settings as InputSettings).zoom_levels
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		for zoom: float in levels:
			_camera.zoom = Vector2(zoom, zoom)
			_camera.centre_on(IsoProjection.cell_centre_px(AT.x, AT.y))
			_placement.begin(Rig.plant(_runner.snapshot))
			var note: String = "%s at zoom %s" % [size, zoom]
			# The footprint the ghost stands on: the plant's 2 x 2 cells from FITS, nothing else.
			assert_vector(_placement.origin()).override_failure_message(note).is_equal(Rig.FITS)
			var cells: Array[Vector2i] = _layer.cells()
			var expected: Array[Vector2i] = []
			for row: int in Rig.FOOT.y:
				for col: int in Rig.FOOT.x:
					expected.append(Rig.FITS + Vector2i(col, row))
			assert_array(cells).override_failure_message(note).contains_exactly(expected)
			for cell: Vector2i in cells:
				# The quad the layer draws for that cell: its diamond's four corners, the middles
				# of the quad's edges, are on screen the cell's four corners on the ground.
				var quad: Rect2 = GhostLayer.quad_rect(cell, 0)
				var middle: Vector2 = quad.get_center()
				var seen: Array[Vector2i] = []
				for corner: Vector2 in [
					Vector2(middle.x, quad.position.y),
					Vector2(quad.end.x, middle.y),
					Vector2(middle.x, quad.end.y),
					Vector2(quad.position.x, middle.y),
				]:
					var on_screen: Vector2 = _camera.world_to_screen(corner)
					var ground: Vector2i = IsoProjection.px_to_ground(
						_camera.screen_to_world(on_screen)
					)
					seen.append(Vector2i(roundi(ground.x / 1000.0), roundi(ground.y / 1000.0)))
				assert_array(seen).override_failure_message("%s: %s" % [note, cell]).is_equal(
					[cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)]
				)
				# The frame's quad is the same quad, wider by its margin on every side.
				var frame: Rect2 = GhostLayer.quad_rect(cell, GhostMarks.FRAME_MARGIN)
				assert_that(frame).override_failure_message(note).is_equal(
					quad.grow(GhostMarks.FRAME_MARGIN)
				)


func test_no_cells_while_the_mode_is_off_and_a_bigger_footprint_marks_more() -> void:
	assert_array(_layer.cells()).is_empty()
	_placement.begin(Rig.plant(_runner.snapshot))
	assert_array(_layer.cells()).has_size(4)
	_placement.cancel()
	assert_array(_layer.cells()).is_empty()
	_placement.foot = Vector2i(3, 2)  # As the Headquarters' 3 x 3 would, and a wider one.
	_placement.active = true
	_layer.refresh()  # What `changed` does.
	assert_array(_layer.cells()).has_size(6)
	_placement.active = false
	_layer.refresh()
	assert_array(_layer.cells()).is_empty()


func test_the_ghost_is_green_where_it_fits_and_red_with_the_reason_where_it_does_not() -> void:
	_camera.centre_on(IsoProjection.cell_centre_px(AT.x, AT.y))
	_placement.begin(Rig.plant(_runner.snapshot))
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)
	assert_that(_layer.tint()).is_equal(GhostLayer.FITS)
	assert_that(GhostLayer.FITS).is_equal(Color("30A46C"))
	assert_that(GhostLayer.DANGER).is_equal(Color("E5484D"))
	for key: String in Placement.Reason.keys():
		if Placement.Reason[key] == Placement.Reason.OK:
			continue
		_placement.reason = Placement.Reason[key]
		_layer.refresh()  # What `changed` does.
		await await_idle_frame()
		await await_idle_frame()
		assert_that(_layer.tint()).override_failure_message(key).is_equal(GhostLayer.DANGER)
		# Every reason that can fail has its glyph drawn, with the hatch on every cell.
		var drawn: Texture2D = _layer.last_glyph
		var path: String = "" if drawn == null else drawn.resource_path
		assert_str(path).override_failure_message(key).is_equal(
			GhostLayer.GLYPH_ART % key.to_lower()
		)
		assert_int(_layer.last_marks).override_failure_message(key).is_equal(12)


## The word and the glyph of a refused ghost: danger red, the occupied glyph when the snapshot still
## calls the tile a fit, the reason's own otherwise, and "Blocked" under it. Moving the ghost, which
## clears `blocked`, takes them away. Each is the same size in dp at every screen and zoom (so the
## cached dp follows a resize): the glyph 32 dp across, the word 18 dp high.
func test_a_blocked_ghost_has_the_word_and_the_glyph_at_their_dp_size_on_every_screen() -> void:
	var levels: PackedFloat32Array = (_camera.settings as InputSettings).zoom_levels
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		for zoom: float in levels:
			var note: String = "%s at zoom %s" % [size, zoom]
			_camera.zoom = Vector2(zoom, zoom)
			_camera.centre_on(IsoProjection.cell_centre_px(AT.x, AT.y))
			_placement.begin(Rig.plant(_runner.snapshot))
			await await_idle_frame()
			await await_idle_frame()
			assert_str(_layer.last_word).override_failure_message(note).is_empty()  # It fits.
			assert_that(_layer.tint()).override_failure_message(note).is_equal(GhostLayer.FITS)
			_placement.blocked = true
			_layer.refresh()  # What `changed` does.
			await await_idle_frame()
			await await_idle_frame()
			assert_str(_layer.last_word).override_failure_message(note).is_equal("Blocked")
			assert_that(_layer.tint()).override_failure_message(note).is_equal(GhostLayer.DANGER)
			assert_int(_layer.last_marks).override_failure_message(note).is_equal(12)
			var glyph: Texture2D = _layer.last_glyph
			var path: String = "" if glyph == null else glyph.resource_path
			assert_str(path).override_failure_message(note).is_equal(
				GhostLayer.GLYPH_ART % "occupied"
			)
			var glyph_px: float = UiScale.dp(GhostLayer.GLYPH_DP)
			assert_float(_layer.last_glyph_px).override_failure_message(note).is_equal_approx(
				glyph_px, 0.01
			)
			# A whole font size in world px: within half a px of the exact one on the screen.
			assert_float(_layer.last_word_px).override_failure_message(note).is_equal_approx(
				UiScale.dp(GhostLayer.WORD_DP), zoom * 0.5 + 0.01
			)
			_placement.blocked = false
			_layer.refresh()
			await await_idle_frame()
			await await_idle_frame()
			assert_str(_layer.last_word).override_failure_message(note).is_empty()
			assert_that(_layer.tint()).override_failure_message(note).is_equal(GhostLayer.FITS)
		_placement.cancel()


## A defence has a head over its body (STYLE.md "Ghosts": the whole sprite): the east-facing frame
## of the head part, its pivot on the sheet's mount, drawn after the body (two parts). A plant has
## no head and draws one part.
func test_a_defences_ghost_draws_its_head_on_the_mount_and_a_plant_draws_none() -> void:
	_camera.centre_on(IsoProjection.cell_centre_px(AT.x, AT.y))
	_placement.begin(Rig.plant(_runner.snapshot))
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_layer.head_region().has_area()).is_false()
	assert_bool(_layer.head_rect().has_area()).is_false()
	assert_int(_layer.last_parts).is_equal(1)
	_placement.cancel()
	var roster: ScenarioDef = Rig.scenario_for(
		1, "headquarters", [["barracks", 2, 10]], ["defence_turret"]
	)
	await _open(roster, &"defence_turret")
	var turret: int = _runner.snapshot.type_ids.find(&"defence_turret")
	_camera.centre_on(IsoProjection.cell_centre_px(AT.x, AT.y))
	assert_bool(_placement.begin(turret)).is_true()
	await await_idle_frame()
	await await_idle_frame()
	var sort: WorldSort = _main.get_node("WorldSort")
	var sheet: IsoSheetDef = (load(IsoIndex.PATH) as IsoIndex).sheet(&"defence_turret")
	var east: Rect2i = sort.atlas.region(sheet.art_id, &"head", UnitLayer.D_EAST, sort.slot_of(1))
	assert_bool(east.has_area()).is_true()
	assert_that(_layer.head_region()).is_equal(east)
	assert_int(_layer.last_parts).is_equal(2)
	# Its pivot is on the mount: the box's top left plus the pivot is the mount from the centre.
	var ground: Vector2i = _placement.centre_ground()
	var centre: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
	var pivot: Vector2 = (
		_layer.head_rect().position + Vector2(sheet.origin(&"head")) * WorldSort.ART_SCALE
	)
	assert_vector(pivot).is_equal_approx(
		centre + sheet.mount(UnitLayer.D_EAST) * WorldSort.ART_SCALE, Vector2.ONE * 0.01
	)
	var drawn: Vector2 = Vector2(east.size) * (WorldSort.ART_SCALE / sort.atlas.bake_scale())
	assert_vector(_layer.head_rect().size).is_equal_approx(drawn, Vector2.ONE * 0.01)
	_placement.cancel()
	assert_bool(_layer.head_region().has_area()).is_false()


func test_the_sprite_is_the_buildings_body_on_the_atlas_and_the_rise_is_the_sheets() -> void:
	assert_array([_layer.body_region().has_area(), _layer.rise_px()]).is_equal([false, 0.0])
	_placement.begin(Rig.plant(_runner.snapshot))
	var sort: WorldSort = _main.get_node("WorldSort")
	var sheet: IsoSheetDef = (load(IsoIndex.PATH) as IsoIndex).sheet(Rig.PLANT)
	var region: Rect2i = sort.atlas.region(Rig.PLANT, &"hull", -1, sort.slot_of(1))
	assert_bool(region.has_area()).is_true()
	assert_that(_layer.body_region()).is_equal(region)  # What BuildingLayer cuts for a plant of 1.
	assert_float(_layer.rise_px()).is_equal_approx(sheet.origin(&"hull").y * 0.5, 0.001)
	_layer.world_sort = null  # No atlas: the marks alone.
	_layer.refresh()
	assert_array([_layer.body_region().has_area(), _layer.rise_px()]).is_equal([false, 0.0])


func test_the_layer_draws_every_frame_while_the_mode_is_on_and_once_more_when_it_ends() -> void:
	assert_int(_layer.z_index).is_equal(60)
	assert_bool(_layer.z_as_relative).is_false()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_layer.draws).is_equal(0)  # Never drawn while nothing is placed.
	_placement.begin(Rig.plant(_runner.snapshot))
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	var drawn: int = _layer.draws
	assert_int(drawn).is_greater_equal(2)
	# What a frame draws was read when the mode began, not by the frames.
	assert_int(_layer.refreshes).is_equal(1)
	_placement.cancel()
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	var after_end: int = _layer.draws
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_layer.draws).is_equal(after_end)  # Over: nothing more is drawn.
	assert_int(_layer.refreshes).is_equal(2)  # The end was read once.


func test_the_marks_are_one_texture_with_a_wash_a_hatch_and_a_frame_diamond() -> void:
	var marks: RuntimeAtlas = GhostMarks.build()
	assert_object(marks.texture()).is_not_null()
	var image: Image = marks.image()
	var wash: Rect2i = marks.region(GhostMarks.WASH)
	var hatch: Rect2i = marks.region(GhostMarks.hatch_for(Vector2i.ZERO))
	var frame: Rect2i = marks.region(GhostMarks.FRAME)
	assert_that(wash.size).is_equal(GhostMarks.TILE)
	assert_that(hatch.size).is_equal(GhostMarks.TILE)
	assert_that(frame.size).is_equal(GhostMarks.TILE + Vector2i.ONE * 2 * GhostMarks.FRAME_MARGIN)
	for region: Rect2i in [wash, hatch, frame]:
		assert_bool(Rect2i(Vector2i.ZERO, image.get_size()).encloses(region)).is_true()
	# The wash: solid in the middle, clear in the corners of the box, part way on the edge.
	var middle: Vector2i = GhostMarks.TILE / 2
	assert_float(image.get_pixelv(wash.position + middle).a).is_equal(1.0)
	assert_float(image.get_pixelv(wash.position).a).is_equal(0.0)
	assert_float(image.get_pixelv(wash.position + GhostMarks.TILE - Vector2i.ONE).a).is_equal(0.0)
	var edge: float = image.get_pixelv(wash.position + Vector2i(16, 7)).a  # Astride the NW edge.
	assert_float(edge).is_between(0.05, 0.95)
	# The frame: clear in the middle, solid on the edge, and clear of the box's corner.
	var centre: Vector2i = frame.position + frame.size / 2
	assert_float(image.get_pixelv(centre).a).is_equal(0.0)
	assert_float(image.get_pixelv(frame.position + Vector2i(16 + 4, 8 + 4)).a).is_greater(0.8)
	assert_float(image.get_pixelv(frame.position).a).is_equal(0.0)
	# The hatch: bands (opaque and clear pixels both) kept inside the diamond, white and grey only.
	var opaque: int = 0
	var clear: int = 0
	for y: int in hatch.size.y:
		for x: int in hatch.size.x:
			var pixel: Color = image.get_pixelv(hatch.position + Vector2i(x, y))
			opaque += 1 if pixel.a > 0.9 else 0
			clear += 1 if pixel.a < 0.1 else 0
			if pixel.a > 0.9:
				assert_float(pixel.r).is_equal_approx(pixel.g, 0.01)
				assert_float(pixel.g).is_equal_approx(pixel.b, 0.01)
	assert_int(opaque).is_greater(200)
	assert_int(clear).is_greater(200)
	assert_float(image.get_pixelv(hatch.position).a).is_equal(0.0)


## The hatch's bands are lines of x + y = const on the screen. Every pixel well inside the diamond
## of a 3 x 3 footprint's cells, each as its quad shows it (the region `hatch_for` names), is looked
## at by its place on the screen: pixels with the same x + y, modulo the art's period of 32, have
## the same alpha, whichever cell they are in. A band that breaks at a cell edge would not.
func test_the_hatch_bands_run_straight_across_the_cells_of_a_footprint() -> void:
	var marks: RuntimeAtlas = GhostMarks.build()
	var image: Image = marks.image()
	var lows: Dictionary[int, float] = {}
	var highs: Dictionary[int, float] = {}
	for row: int in range(6, 9):
		for col: int in range(10, 13):
			var cell: Vector2i = Vector2i(col, row)
			var region: Rect2i = marks.region(GhostMarks.hatch_for(cell))
			var corner: Vector2i = Vector2i(GhostLayer.quad_rect(cell, 0).position)
			for y: int in GhostMarks.TILE.y:
				for x: int in GhostMarks.TILE.x:
					var reach: float = absf(x + 0.5 - 32.0) / 32.0 + absf(y + 0.5 - 16.0) / 16.0
					if (1.0 - reach) * GhostMarks.EDGE_PX < 1.0:
						continue  # Near the edge, where the pixel is only partly this cell's.
					var phase: int = posmod(corner.x + x + corner.y + y, HATCH_PERIOD)
					var alpha: float = image.get_pixelv(region.position + Vector2i(x, y)).a
					lows[phase] = minf(lows.get(phase, alpha), alpha)
					highs[phase] = maxf(highs.get(phase, alpha), alpha)
	assert_int(lows.size()).is_equal(HATCH_PERIOD)  # Every place in the period is seen.
	var broken: Array[int] = []
	for phase: int in lows:
		if highs[phase] - lows[phase] > 0.05:
			broken.append(phase)
	(
		assert_array(broken)
		. override_failure_message("x + y mod 32 where cells differ: %s" % [broken])
		. is_empty()
	)
