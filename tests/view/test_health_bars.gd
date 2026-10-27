extends GdUnitTestSuite
## What HealthBarLayer plans and draws (plan P45, assets/art/STYLE.md "Health bars"): the shape of
## an own and an enemy bar, the fill, the size in dp at every zoom and the place over the unit,
## which is the unit's projected ground point (P117, ADR 0023 section 1), lifted by the top of its
## frame (P117b, `SpriteLift`). STYLE.md's two overlap inequalities (P34b's sweep of neighbours at
## the formation spacing) were measured on the top-down view; the iso rule that replaces them is
## in test_health_bar_overlap.gd. Pixels cannot be read headless, so the tests
## read the layer's plan of rects (`rect_at`, `rect_color`), which `_draw` paints one for one
## (test_health_bar_frames.gd counts what it painted), and
## `test_the_draw_code_paints_nothing_but_filled_rects` reads the script (the filled rects, each in
## its own colour, in the plan's order, which puts a bar's edge rects before its fill rects). The
## fill of a damaged squad bar is in test_health_bar_squads.gd. When a bar shows and how a hit is
## seen are in test_health_bar_hits.gd (gdlint allows 20 public methods per file).
## On data/scenarios/controls_test.tres: ids 1-30 are blue light tanks (max hp 300), 31-40 red; the
## perf arena has tanks, rifle squads (max hp 100) and rocket squads, both sides. The runner is not
## in the tree: only the calls here move time, so alpha is 0 and a unit stands at its prev position.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const CONTROLS: String = "res://data/scenarios/controls_test.tres"
const ARENA: String = "res://data/scenarios/perf_arena.tres"
const SCRIPT_PATH: String = "res://game/view/HealthBarLayer.gd"
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
## STYLE.md "Health bars": the edge and the two fills, and the team tints that they must not be.
const EDGE: Color = Color("1C2127")
const OWN: Color = Color("30A46C")
const ENEMY: Color = Color("F5A524")
const TEAM_TINTS: Array[Color] = [Color("9AA5B1"), Color("2F80ED"), Color("E5484D")]
## STYLE.md, Class table: the box in dp, vehicle and infantry.
const WIDTH_DP: Dictionary[StringName, int] = {&"vehicle": 22, &"infantry": 16}
const HEIGHT_DP: int = 6
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
## The six screens of the shared list (ScreenSizes.ALL, entry by entry), each with its profile.
const SCREEN_PROFILES: Array[StringName] = [
	&"desktop",
	&"android_6in",
	&"web_tablet",
	&"desktop_portrait",
	&"android_6in_portrait",
	&"web_tablet_portrait",
]
## The lines of HealthBarLayer._draw: the painted count, then one draw_rect per planned rect, in the
## plan's order.
const DRAW_BODY: Array[String] = [
	"_drawn = 0",
	"for index: int in _rects:",
	"draw_rect(rect_at(index), rect_color(index))",
	"_drawn += 1",
]

var _window_size_before: Vector2i
var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _bars: HealthBarLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_build(CONTROLS)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_an_own_tank_bar_is_the_plain_box_and_an_enemy_tank_bar_has_the_notch() -> void:
	_units.set_selected(PackedInt32Array([2, 31]))  # Own tank 2 and enemy tank 31.
	_frame()
	var own: Array[Rect2i] = _dp_rects(1, EDGE)
	var enemy: Array[Rect2i] = _dp_rects(30, EDGE)
	assert_array(own).is_equal([Rect2i(0, 0, 22, 6)])
	# a = (22 - 4) / 2 = 9: two shoulders and the foot of a notch 4 dp wide, 2 dp deep.
	assert_array(enemy).is_equal([Rect2i(0, 0, 9, 6), Rect2i(13, 0, 9, 6), Rect2i(9, 2, 4, 4)])
	assert_array(_dp_rects(1, OWN)).is_equal([Rect2i(1, 1, 20, 4)])
	assert_array(_dp_rects(30, ENEMY)).is_equal(
		[Rect2i(1, 1, 7, 2), Rect2i(14, 1, 7, 2), Rect2i(1, 3, 20, 2)]
	)
	assert_int(_bars.rect_count()).is_equal(1 + 1 + 3 + 3)  # Filled rects, nothing else.


func test_an_infantry_bar_is_16_dp_wide_and_the_enemy_notch_is_the_same_4_dp() -> void:
	_rebuild(ARENA)
	var rifle: int = _first_row_of(&"rifle_squad", 1)
	var red_rifle: int = _first_row_of(&"rifle_squad", 2)
	_units.set_selected(_ids([rifle, red_rifle]))
	_frame()
	assert_array(_dp_rects(rifle, EDGE)).is_equal([Rect2i(0, 0, 16, 6)])
	assert_array(_dp_rects(rifle, OWN)).is_equal([Rect2i(1, 1, 14, 4)])
	# a = (16 - 4) / 2 = 6.
	assert_array(_dp_rects(red_rifle, EDGE)).is_equal(
		[Rect2i(0, 0, 6, 6), Rect2i(10, 0, 6, 6), Rect2i(6, 2, 4, 4)]
	)
	assert_array(_dp_rects(red_rifle, ENEMY)).is_equal(
		[Rect2i(1, 1, 4, 2), Rect2i(11, 1, 4, 2), Rect2i(1, 3, 14, 2)]
	)


func test_the_class_comes_from_type_armour_and_nothing_else() -> void:
	_rebuild(ARENA)
	var tank: int = _first_row_of(&"light_tank", 1)
	var rifle: int = _first_row_of(&"rifle_squad", 1)
	var rocket: int = _first_row_of(&"rocket_squad", 1)
	_units.set_selected(_ids([tank, rifle, rocket]))
	_frame()
	var armour: PackedInt32Array = _runner.snapshot.type_armour
	var types: PackedInt32Array = _runner.snapshot.type_index
	assert_int(armour[types[tank]]).is_equal(World.Armour.LIGHT)
	assert_int(armour[types[rifle]]).is_equal(World.Armour.INFANTRY)
	assert_int(armour[types[rocket]]).is_equal(World.Armour.INFANTRY)
	assert_that(_box(tank).size).is_equal_approx(_size_px(22), Vector2(0.01, 0.01))
	assert_that(_box(rifle).size).is_equal_approx(_size_px(16), Vector2(0.01, 0.01))
	assert_that(_box(rocket).size).is_equal_approx(_size_px(16), Vector2(0.01, 0.01))
	# The class is the armour column of the type, wherever the type has its name: a tank whose type
	# is made INFANTRY in the snapshot gets the infantry bar, and a squad made HEAVY the tank bar.
	_runner.snapshot.type_armour[types[tank]] = World.Armour.INFANTRY
	_runner.snapshot.type_armour[types[rifle]] = World.Armour.HEAVY
	_frame()
	assert_that(_box(tank).size).is_equal_approx(_size_px(16), Vector2(0.01, 0.01))
	assert_that(_box(rifle).size).is_equal_approx(_size_px(22), Vector2(0.01, 0.01))
	assert_that(_box(rocket).size).is_equal_approx(_size_px(16), Vector2(0.01, 0.01))  # Its type.


func test_the_fill_is_hp_over_max_hp_with_a_floor_of_one_dp() -> void:
	_units.set_selected(PackedInt32Array([2, 31]))
	# Interior 20 dp of max hp 300: 15 hp is 1 dp, 22 hp 1.47 and 23 hp 1.53 dp.
	var expected: Dictionary[int, int] = {300: 20, 150: 10, 225: 15, 23: 2, 22: 1, 15: 1, 1: 1}
	for hp: int in expected:
		_runner.snapshot.hp[1] = hp
		_runner.snapshot.hp[30] = hp
		_frame()
		var own: Array[Rect2i] = _dp_rects(1, OWN)
		assert_array(own).is_equal([Rect2i(1, 1, expected[hp], 4)])
		# The enemy fill is clipped at the same x: shoulders first, then the strip.
		var end: int = 1 + expected[hp]
		var enemy: Array[Rect2i] = []
		for rect: Rect2i in [Rect2i(1, 1, 7, 2), Rect2i(14, 1, 7, 2), Rect2i(1, 3, 20, 2)]:
			var right: int = mini(rect.end.x, end)
			if right > rect.position.x:
				enemy.append(Rect2i(rect.position.x, rect.position.y, right - rect.position.x, 2))
		assert_array(_dp_rects(30, ENEMY)).is_equal(enemy)


func test_a_bar_fills_from_the_left_and_a_living_unit_always_shows_a_dp() -> void:
	_units.set_selected(PackedInt32Array([31]))
	_runner.snapshot.hp[30] = 225  # 15 dp: the right shoulder (x 14..21) is cut at x 16.
	_frame()
	assert_array(_dp_rects(30, ENEMY)).is_equal(
		[Rect2i(1, 1, 7, 2), Rect2i(14, 1, 2, 2), Rect2i(1, 3, 15, 2)]
	)
	_runner.snapshot.hp[30] = 1  # Nearly dead: 1 dp on each rect that starts at x 1.
	_frame()
	assert_array(_dp_rects(30, ENEMY)).is_equal([Rect2i(1, 1, 1, 2), Rect2i(1, 3, 1, 2)])
	# The edge is the whole box whatever the hp.
	assert_array(_dp_rects(30, EDGE)).is_equal(
		[Rect2i(0, 0, 9, 6), Rect2i(13, 0, 9, 6), Rect2i(9, 2, 4, 4)]
	)


func test_fill_end_rounds_halves_up_and_keeps_a_dp_for_a_living_unit() -> void:
	# A rifle squad (max hp 100) on a 16 dp bar: interior 14 dp, so 25 hp is exactly 3.5 dp.
	assert_int(HealthBarLayer.fill_end_dp(25, 100, 16)).is_equal(1 + 4)
	assert_int(HealthBarLayer.fill_end_dp(24, 100, 16)).is_equal(1 + 3)
	assert_int(HealthBarLayer.fill_end_dp(100, 100, 16)).is_equal(1 + 14)
	assert_int(HealthBarLayer.fill_end_dp(1, 100, 16)).is_equal(1 + 1)
	assert_int(HealthBarLayer.fill_end_dp(0, 100, 16)).is_equal(1)  # Nothing to fill.
	assert_int(HealthBarLayer.fill_end_dp(150, 100, 16)).is_equal(1 + 14)  # Never past the box.
	assert_int(HealthBarLayer.fill_end_dp(5, 0, 16)).is_equal(1)  # No max hp, no fill.


func test_neither_fill_is_a_team_colour_and_the_colours_do_not_depend_on_the_owner() -> void:
	# Own bars of blue and red units, enemy bars of both: the owner picks the shape and the fill
	# by local player only, so a red unit that is the local player's own keeps the own colours.
	_units.set_selected(PackedInt32Array([2, 31]))
	_frame()
	for index: int in _bars.rect_count():
		var color: Color = _bars.rect_color(index)
		assert_bool([EDGE, OWN, ENEMY].has(color)).is_true()
		assert_bool(TEAM_TINTS.has(color)).is_false()
	assert_that(_bars.rect_color(0)).is_equal(EDGE)
	assert_that(_bars.rect_color(1)).is_equal(OWN)
	assert_that(_bars.rect_color(2)).is_equal(EDGE)
	assert_that(_bars.rect_color(5)).is_equal(ENEMY)
	var scenario: ScenarioDef = _runner.scenario.duplicate()  # Never the shared, cached resource.
	scenario.local_player = 2
	_runner.scenario = scenario
	_frame()
	assert_array(_dp_rects(1, EDGE)).is_equal(
		[Rect2i(0, 0, 9, 6), Rect2i(13, 0, 9, 6), Rect2i(9, 2, 4, 4)]
	)  # Blue tank 2 is the enemy now.
	assert_array(_dp_rects(30, EDGE)).is_equal([Rect2i(0, 0, 22, 6)])


func test_a_bar_is_a_dp_size_at_every_zoom() -> void:
	_units.set_selected(PackedInt32Array([2]))
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_frame()
		var box: Rect2 = _box(1)
		# On screen it is 22 x 6 dp whatever the zoom; in the world it is 1 / zoom of that.
		var on_screen: Vector2 = box.size * zoom
		assert_that(on_screen).is_equal_approx(Vector2(22.0, 6.0) * 1.75, Vector2(0.01, 0.01))
		assert_float(box.size.x).is_equal_approx(22.0 * 1.75 / zoom, 0.01)


func test_a_bar_is_centred_and_its_bottom_edge_is_l_zoom_plus_1_dp_above_the_unit() -> void:
	_rebuild(ARENA)
	var tank: int = _first_row_of(&"light_tank", 1)
	var rifle: int = _first_row_of(&"rifle_squad", 1)
	var red_tank: int = _first_row_of(&"light_tank", 2)
	_units.set_selected(_ids([tank, rifle, red_tank]))
	# Each of the six screens that every screen is tested at, with its own dp (the layer reads it
	# again when the window changes) and each zoom.
	for profile_name: StringName in SCREEN_PROFILES:
		var profile: UiMetrics = UiProfiles.by_name(profile_name)
		UiScale.set_override(profile)
		get_window().size = profile.window_size
		await await_idle_frame()  # size_changed: the layers read the dp again.
		var dp_px: float = UiScale.base_px_per_dp()
		for zoom: float in ZOOMS:
			_camera.zoom = Vector2(zoom, zoom)
			_frame()
			for row: int in [tank, rifle, red_tank]:
				var class_key: StringName = &"infantry" if row == rifle else &"vehicle"
				var type_id: StringName = &"rifle_squad" if row == rifle else &"light_tank"
				var at: Vector2 = _units.unit_screen_position(row)
				var top_left: Vector2 = _camera.world_to_screen(_box(row).position)
				var bottom_right: Vector2 = _camera.world_to_screen(_box(row).end)
				var note: String = "%s zoom %s row %d" % [profile_name, zoom, row]
				# Centred on the unit, to the sub-pixel.
				(
					assert_float((top_left.x + bottom_right.x) * 0.5)
					. override_failure_message("centre x, " + note)
					. is_equal_approx(at.x, 0.05)
				)
				# The bottom edge is l x zoom + 1 dp above the unit's ground point on screen.
				var gap: float = _lift(type_id) * zoom + dp_px
				(
					assert_float(at.y - bottom_right.y)
					. override_failure_message("bottom edge, " + note)
					. is_equal_approx(gap, 0.05)
				)
				assert_float(bottom_right.y - top_left.y).is_equal_approx(HEIGHT_DP * dp_px, 0.05)
				assert_float(bottom_right.x - top_left.x).is_equal_approx(
					WIDTH_DP[class_key] * dp_px, 0.05
				)


## The table pairs each profile with a size by position: it stays in step with the shared list.
func test_the_screen_profiles_are_the_six_sizes_of_the_shared_list() -> void:
	var sizes: Array[Vector2i] = []
	for profile_name: StringName in SCREEN_PROFILES:
		sizes.append(UiProfiles.by_name(profile_name).window_size)
	assert_array(sizes).is_equal(ScreenSizes.ALL)


func test_a_bar_stands_over_the_top_of_its_types_sheet_and_a_type_without_one_gets_its_class(
) -> void:
	# The lift comes from the type id of the snapshot's table: a light tank's sheet is taller than
	# a rifle squad's, and a type the match's atlas holds no sheet of has the default of its class,
	# 26 for a vehicle and 24 for infantry (the ids are the snapshot's, so the test renames the
	# tank's type).
	_rebuild(ARENA)  # Registers the light tank and both squads, the sheets the cases below use.
	var tank: int = _first_row_of(&"light_tank", 1)
	_units.set_selected(_ids([tank]))
	var type: int = _runner.snapshot.type_index[tank]
	var cases: Array = [
		[&"light_tank", World.Armour.LIGHT, _lift(&"light_tank")],
		[&"rifle_squad", World.Armour.INFANTRY, _lift(&"rifle_squad")],
		[&"rocket_squad", World.Armour.INFANTRY, _lift(&"rocket_squad")],
		[&"bullhead", World.Armour.HEAVY, 26.0],
		[&"flarejack", World.Armour.INFANTRY, 24.0],
	]
	assert_float(_lift(&"light_tank")).is_not_equal(_lift(&"rifle_squad"))
	for case: Array in cases:
		_runner.snapshot.type_ids[type] = case[0]
		_runner.snapshot.type_armour[type] = case[1]
		_frame()
		var at: Vector2 = _units.unit_screen_position(tank)
		var bottom: float = _camera.world_to_screen(_box(tank).end).y
		assert_float(at.y - bottom).override_failure_message(String(case[0])).is_equal_approx(
			case[2] * _camera.zoom.x + 1.75, 0.05
		)


func test_the_ring_does_not_place_the_bar() -> void:
	# Zoom 1.5 on the 6-inch phone: the tank's ring is a ground ellipse with a horizontal semi-axis
	# of 24.89 px x 1.5 = 37.3 px on screen (the selection radius 500 + 50 milli), and the bar's
	# bottom edge is l x 1.5 + 1.75 px above the unit's ground point, l the sheet's lift.
	_units.set_selected(PackedInt32Array([2]))
	_camera.zoom = Vector2(1.5, 1.5)
	_frame()
	var ring: Sprite2D = _units.rig(1).get_node("Ring")
	assert_float(ring.radius * 1.5).is_equal_approx(37.335, 0.01)
	var at: Vector2 = _units.unit_screen_position(1)
	var bottom: float = _camera.world_to_screen(_box(1).end).y
	assert_float(at.y - bottom).is_equal_approx(_lift(&"light_tank") * 1.5 + 1.75, 0.05)
	# A ring three times the size leaves the bar where it was: the bar is placed by the top of the
	# sprite's frame and not by the ring.
	ring.scale *= 3.0
	_frame()
	assert_float(at.y - _camera.world_to_screen(_box(1).end).y).is_equal_approx(
		_lift(&"light_tank") * 1.5 + 1.75, 0.05
	)


func test_the_draw_code_paints_nothing_but_filled_rects() -> void:
	# ADR 0011 section 3: one _draw(), filled rects only. Pixels cannot be read headless, so the
	# script is: every draw call it makes is draw_rect with a rect and a colour and nothing else
	# (a third argument would make it an outline), and there is one _draw().
	var source: String = ""
	for line: String in FileAccess.get_file_as_string(SCRIPT_PATH).split("\n"):
		source += line.get_slice("#", 0) + "\n"
	var calls: Array[String] = []
	var at: int = source.find("draw_")
	while at >= 0:
		var open: int = source.find("(", at)
		calls.append(source.substr(at, open - at))
		assert_int(_top_level_arguments(source, open)).is_equal(2)  # The rect and the colour.
		at = source.find("draw_", open)
	assert_array(calls).is_equal(["draw_rect"])
	assert_int(source.count("func _draw()")).is_equal(1)
	# Rect i is painted with rect i's colour: a draw with a fixed index (`rect_color(0)`) would
	# paint the whole plan in one colour, and the plan's colours cannot be told from the painted
	# ones without pixels.
	assert_int(source.count("draw_rect(rect_at(index), rect_color(index))")).is_equal(1)
	# Paint order: a later rect is painted over an earlier one, so the order of the picture is the
	# order of the plan (test_a_bars_edge_rects_come_before_its_fill_rects_in_the_plan), and
	# _draw is this loop and nothing else: up over the plan, once. Run backwards it would paint
	# every edge rect over the fill drawn before it and leave a dark box for each bar.
	assert_array(_body_lines(source, "_draw")).is_equal(DRAW_BODY)


func test_a_bars_edge_rects_come_before_its_fill_rects_in_the_plan() -> void:
	# _draw paints rect 0 first (see the test above), so the edge rects of a bar come before its
	# fill rects: the fill is then on top of the edge's box, and the notch of an enemy bar is not
	# painted over. The colours of the rects of a bar in plan order, full and nearly dead.
	_rebuild(ARENA)
	var rows: Dictionary[StringName, int] = {
		&"own_tank": _first_row_of(&"light_tank", 1),
		&"enemy_tank": _first_row_of(&"light_tank", 2),
		&"own_squad": _first_row_of(&"rifle_squad", 1),
		&"enemy_squad": _first_row_of(&"rifle_squad", 2),
	}
	var ids: Array[int] = []
	ids.assign(rows.values())
	_units.set_selected(_ids(ids))
	var full: Dictionary[StringName, Array] = {
		&"own_tank": [EDGE, OWN],
		&"enemy_tank": [EDGE, EDGE, EDGE, ENEMY, ENEMY, ENEMY],
		&"own_squad": [EDGE, OWN],
		&"enemy_squad": [EDGE, EDGE, EDGE, ENEMY, ENEMY, ENEMY],
	}
	# At 1 hp the fill is 1 dp wide: an enemy bar keeps the left shoulder and the strip, and the
	# right shoulder (which starts past the fill) is not planned. The edge still comes first.
	var nearly_dead: Dictionary[StringName, Array] = {
		&"own_tank": [EDGE, OWN],
		&"enemy_tank": [EDGE, EDGE, EDGE, ENEMY, ENEMY],
		&"own_squad": [EDGE, OWN],
		&"enemy_squad": [EDGE, EDGE, EDGE, ENEMY, ENEMY],
	}
	_frame()
	for key: StringName in rows:
		assert_array(_plan_colors(rows[key])).override_failure_message(str(key)).is_equal(full[key])
	for key: StringName in rows:
		_runner.snapshot.hp[rows[key]] = 1
	_frame()
	assert_int(_bars.bar_count()).is_equal(rows.size())
	for key: StringName in rows:
		var colors: Array[Color] = _plan_colors(rows[key])
		assert_array(colors).override_failure_message(str(key)).is_equal(nearly_dead[key])
	# The bars take the plan in turn, from rect 0 to the end, so a bar's range is its own rects.
	assert_int(_bars.bar_first_rect(0)).is_equal(0)
	for bar: int in _bars.bar_count() - 1:
		assert_int(_bars.bar_end_rect(bar)).is_equal(_bars.bar_first_rect(bar + 1))
	assert_int(_bars.bar_end_rect(_bars.bar_count() - 1)).is_equal(_bars.rect_count())


func test_the_main_scene_has_the_layer_at_z_30_between_the_units_and_the_markers() -> void:
	var main: Node = auto_free(load("res://scenes/main.tscn").instantiate())
	add_child(main)
	await await_idle_frame()  # _ready: every export is wired and the match runs.
	var layer: HealthBarLayer = main.get_node("HealthBarLayer") as HealthBarLayer
	assert_object(layer).is_not_null()
	assert_int(layer.z_index).is_equal(30)  # ADR 0023 section 2, over the sorted world at 10.
	assert_bool(layer.z_as_relative).is_false()
	assert_object(layer.runner).is_same(main.get_node("MatchRunner"))
	assert_object(layer.unit_layer).is_same(main.get_node("UnitLayer"))
	var order: Array[StringName] = []
	for child: Node in main.get_children():
		order.append(child.name)
	assert_int(order.find(&"BuildingLayer")).is_equal(order.find(&"UnitLayer") + 1)
	assert_int(order.find(&"HealthBarLayer")).is_equal(order.find(&"BuildingLayer") + 1)
	assert_object(layer.building_layer).is_same(main.get_node("BuildingLayer"))
	assert_int(order.find(&"MarkerLayer")).is_greater(order.find(&"HealthBarLayer"))
	assert_str(layer.get_script().resource_path).is_equal(SCRIPT_PATH)


## Builds the match of `scenario_path` with the camera, the unit layer and the bar layer, as the
## main scene wires them. Frames come only from _frame().
func _build(scenario_path: String) -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(scenario_path)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.reveal_enemies = true  # The enemy bars are the subject, not the fog (test_fog_hiding.gd).
	add_child(_units)
	_units.set_process(false)
	_bars = null
	_make_bars()


## A new match for the next scenario: the old nodes go.
func _rebuild(scenario_path: String) -> void:
	for node: Node in [_bars, _units, _camera, _runner]:
		node.free()
	_build(scenario_path)


## A fresh bar layer, which reads the dp that is in force now.
func _make_bars() -> void:
	if _bars != null:
		_bars.free()
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = _units
	add_child(_bars)
	_bars.set_process(false)


## One frame: the unit layer, then the bar layer, in the scene's order.
func _frame() -> void:
	_units._process(0.0)
	_bars._process(0.0)


## The unit ids of rows `rows`.
func _ids(rows: Array[int]) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in rows:
		ids.append(_runner.snapshot.unit_id[row])
	return ids


## The first row of type `type_id` owned by `owner_id`.
func _first_row_of(type_id: StringName, owner_id: int) -> int:
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		if snap.type_ids[snap.type_index[row]] == type_id and snap.owner[row] == owner_id:
			return row
	return -1


## World px of one dp: the base px per dp over the camera zoom.
func _unit_px() -> float:
	return UiScale.base_px_per_dp() / _camera.zoom.x


func _size_px(dp_width: int) -> Vector2:
	return Vector2(dp_width, HEIGHT_DP) * _unit_px()


## Bar `row`'s rects of colour `color` in world px, in the plan's order.
func _parts(row: int, color: Color) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for bar: int in _bars.bar_count():
		if _bars.bar_row(bar) == row:
			for index: int in range(_bars.bar_first_rect(bar), _bars.bar_end_rect(bar)):
				if _bars.rect_color(index) == color:
					found.append(_bars.rect_at(index))
	return found


## The box of bar `row` (the union of its edge rects) in world px.
func _box(row: int) -> Rect2:
	var edges: Array[Rect2] = _parts(row, EDGE)
	assert_int(edges.size()).is_greater(0)
	var box: Rect2 = edges[0]
	for rect: Rect2 in edges:
		box = box.merge(rect)
	return box


## Bar `row`'s rects of colour `color` in whole dp from the bar's top-left corner.
func _dp_rects(row: int, color: Color) -> Array[Rect2i]:
	var origin: Vector2 = _box(row).position
	var unit: float = _unit_px()
	var found: Array[Rect2i] = []
	for rect: Rect2 in _parts(row, color):
		var scaled: Rect2 = Rect2((rect.position - origin) / unit, rect.size / unit)
		for value: float in [scaled.position.x, scaled.position.y, scaled.size.x, scaled.size.y]:
			assert_float(value).is_equal_approx(roundf(value), 0.01)  # Whole dp.
		found.append(
			Rect2i(
				roundi(scaled.position.x),
				roundi(scaled.position.y),
				roundi(scaled.size.x),
				roundi(scaled.size.y)
			)
		)
	return found


## The colours of bar `row`'s rects in the plan's order, which is the order they are painted in.
func _plan_colors(row: int) -> Array[Color]:
	var colors: Array[Color] = []
	for bar: int in _bars.bar_count():
		if _bars.bar_row(bar) == row:
			for index: int in range(_bars.bar_first_rect(bar), _bars.bar_end_rect(bar)):
				colors.append(_bars.rect_color(index))
	return colors


## The lines of the function `name` in `source` (comments already cut): the indented lines after
## its "func" line, trimmed and without the blank ones, up to the next line that is not indented.
func _body_lines(source: String, name: String) -> Array[String]:
	var lines: Array[String] = []
	var inside: bool = false
	for line: String in source.split("\n"):
		if line.begins_with("func %s(" % name):
			inside = true
		elif inside and not line.is_empty() and not line.begins_with("\t"):
			break
		elif inside and not line.strip_edges().is_empty():
			lines.append(line.strip_edges())
	return lines


## The number of arguments of the call whose "(" is at `open` in `source`: the top-level commas,
## a trailing comma not counted.
func _top_level_arguments(source: String, open: int) -> int:
	var depth: int = 0
	var count: int = 1
	var last_comma: bool = false
	for index: int in range(open, source.length()):
		var character: String = source[index]
		if character == "(" or character == "[":
			depth += 1
		elif character == ")" or character == "]":
			depth -= 1
			if depth == 0:
				return count - 1 if last_comma else count
		elif character == "," and depth == 1:
			count += 1
			last_comma = true
			continue
		if not character.strip_edges().is_empty():
			last_comma = false
	return -1


## The lift l of the top of a unit's frame above its ground point, world px at zoom 1 (ADR 0023
## section 2): the `bar_lift_px` of the type's sheet. The sheets are generated data, so the number
## is read from the index and not typed here (test_sprite_lift.gd and test_lift_sheets.gd pin the
## rule on sheets with made-up numbers).
func _lift(type_id: StringName) -> float:
	return float((load(IsoIndex.PATH) as IsoIndex).sheet(type_id).bar_lift_px)
