extends GdUnitTestSuite
## The tutorial conditions (plan row P541, ADR 0044 section 2): each kind is true exactly when its
## context says so, a type the roster lacks matches nothing, a missing snapshot matches nothing.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")


func _check(beat: TutorialBeatDef, ctx: TutorialContext, start: TutorialContext = null) -> bool:
	return TutorialConditions.check(beat, ctx, start if start != null else ctx.baseline())


func test_next_is_never_true_here() -> void:
	var ctx: TutorialContext = Lesson.context(Rig.start())
	assert_bool(_check(Lesson.beat("a", TutorialConditions.Kind.NEXT), ctx)).is_false()


func test_selected_counts_the_selected_rows_of_a_type() -> void:
	var world: World = Rig.start()
	var ctx: TutorialContext = Lesson.context(world)
	var squad: int = Lesson.row_id(world, 1, "rifle_squad")
	var hq: int = Lesson.row_id(world, 1, "headquarters")
	var two: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.SELECTED, {"type_id": &"rifle_squad", "count": 2}
	)
	assert_bool(_check(two, ctx)).is_false()
	ctx.selection.set_ids(PackedInt32Array([squad, hq]))
	assert_bool(_check(two, ctx)).is_false()
	var any: TutorialBeatDef = Lesson.beat("b", TutorialConditions.Kind.SELECTED, {"count": 2})
	assert_bool(_check(any, ctx)).is_true()
	var all_squads: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_index[row] == Rig.type_of(world, "rifle_squad"):
			all_squads.append(world.unit_id[row])
	ctx.selection.set_ids(all_squads)
	assert_bool(_check(two, ctx)).is_true()


func test_units_in_area_counts_own_units_by_tile() -> void:
	var world: World = Rig.start()
	var ctx: TutorialContext = Lesson.context(world)
	var here: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.UNITS_IN_AREA, {"count": 2, "area": Rect2i(0, 8, 8, 6)}
	)
	assert_bool(_check(here, ctx)).is_true()
	var far: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.UNITS_IN_AREA, {"count": 1, "area": Rect2i(30, 0, 5, 5)}
	)
	assert_bool(_check(far, ctx)).is_false()
	# The Headquarters stands in the first area's reach but is a building, not a unit.
	var hq_area: TutorialBeatDef = Lesson.beat(
		"c", TutorialConditions.Kind.UNITS_IN_AREA, {"count": 1, "area": Rect2i(5, 5, 5, 5)}
	)
	assert_bool(_check(hq_area, ctx)).is_false()


func test_building_placed_and_done_differ_by_construction() -> void:
	var world: World = Rig.start()
	var placed: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.BUILDING_PLACED, {"type_id": &"barracks"}
	)
	var done: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.BUILDING_DONE, {"type_id": &"barracks"}
	)
	assert_bool(_check(placed, Lesson.context(world))).is_false()
	Rig.give(world, 1, "barracks", 12, 12)
	var row: int = world.index_of(Lesson.row_id(world, 1, "barracks"))
	world.build_left[row] = 40
	var building: TutorialContext = Lesson.context(world)
	assert_bool(_check(placed, building)).is_true()
	assert_bool(_check(done, building)).is_false()
	world.build_left[row] = 0
	assert_bool(_check(done, Lesson.context(world))).is_true()
	# Another player's barracks is no one's of the local player.
	var theirs: World = Rig.start()
	Rig.give(theirs, 2, "barracks", 31, 26)
	assert_bool(_check(placed, Lesson.context(theirs))).is_false()


func test_own_at_least_counts_rows_of_a_type() -> void:
	var world: World = Rig.start()
	var three: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.OWN_AT_LEAST, {"type_id": &"rifle_squad", "count": 3}
	)
	assert_bool(_check(three, Lesson.context(world))).is_false()
	Rig.add_unit_of(world, 1, "rifle_squad", 5000, 11000)
	assert_bool(_check(three, Lesson.context(world))).is_true()


func test_a_type_the_roster_lacks_matches_nothing() -> void:
	var world: World = Rig.start()
	var ghost: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.OWN_AT_LEAST, {"type_id": &"no_such_type"}
	)
	assert_bool(_check(ghost, Lesson.context(world))).is_false()
	var ctx: TutorialContext = Lesson.context(world)
	ctx.placement_type = 0
	var placing: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.PLACING, {"type_id": &"no_such_type"}
	)
	assert_bool(_check(placing, ctx)).is_false()


func test_harvested_and_enemy_losses_read_the_players_stats() -> void:
	var world: World = Rig.start()
	var harvested: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.HARVESTED, {"count": 500}
	)
	var losses: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.ENEMY_LOSSES, {"count": 3}
	)
	assert_bool(_check(harvested, Lesson.context(world))).is_false()
	world.stat_harvested[1] = 500
	world.stat_lost_units[2] = 2
	world.stat_lost_buildings[2] = 1
	world.stat_lost_units[1] = 9  # Own losses are not the enemy's.
	var ctx: TutorialContext = Lesson.context(world)
	assert_bool(_check(harvested, ctx)).is_true()
	assert_bool(_check(losses, ctx)).is_true()
	world.stat_lost_buildings[2] = 0
	assert_bool(_check(losses, Lesson.context(world))).is_false()


func test_the_camera_conditions() -> void:
	var ctx: TutorialContext = Lesson.context(Rig.start())
	var start: TutorialContext = ctx.baseline()
	var zoom: TutorialBeatDef = Lesson.beat("a", TutorialConditions.Kind.ZOOM_LEVEL, {"value": 2})
	var pan: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.CAMERA_PANNED, {"count": 100}
	)
	assert_bool(_check(zoom, ctx, start)).is_false()
	assert_bool(_check(pan, ctx, start)).is_false()
	ctx.zoom_level = 2
	ctx.camera_centre = Vector2(60, 80)
	assert_bool(_check(zoom, ctx, start)).is_true()
	assert_bool(_check(pan, ctx, start)).is_true()
	ctx.camera_centre = Vector2(30, 40)
	assert_bool(_check(pan, ctx, start)).is_false()


func test_the_hud_conditions() -> void:
	var ctx: TutorialContext = Lesson.context(Rig.start())
	var radar: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.UNFOLD_OPEN, {"value": HudState.Unfold.RADAR}
	)
	var tab: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.DRAWER_TAB, {"value": World.Tab.INFANTRY}
	)
	assert_bool(_check(radar, ctx)).is_false()
	ctx.hud.open(HudState.Unfold.RADAR)
	assert_bool(_check(radar, ctx)).is_true()
	ctx.drawer_tab = World.Tab.INFANTRY
	assert_bool(_check(tab, ctx)).is_false()  # The tab is chosen but the drawer is not open.
	ctx.hud.open(HudState.Unfold.DRAWER)
	assert_bool(_check(tab, ctx)).is_true()
	assert_bool(_check(radar, ctx)).is_false()
	ctx.drawer_tab = World.Tab.STRUCTURES
	assert_bool(_check(tab, ctx)).is_false()


func test_unfold_closed_holds_once_the_pause_menu_is_gone() -> void:
	var ctx: TutorialContext = Lesson.context(Rig.start())
	var resumed: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.UNFOLD_CLOSED, {"value": HudState.Unfold.PAUSE}
	)
	assert_bool(_check(resumed, ctx)).is_true()  # Nothing is open.
	ctx.hud.open(HudState.Unfold.PAUSE)
	assert_bool(_check(resumed, ctx)).is_false()
	ctx.hud.close(HudState.Unfold.PAUSE)
	assert_bool(_check(resumed, ctx)).is_true()
	assert_bool(TutorialConditions.needs_ticks(TutorialConditions.Kind.UNFOLD_CLOSED)).is_false()


func test_placing_and_the_strike_aim() -> void:
	var world: World = Rig.start()
	var ctx: TutorialContext = Lesson.context(world)
	var any: TutorialBeatDef = Lesson.beat("a", TutorialConditions.Kind.PLACING)
	var barracks: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.PLACING, {"type_id": &"barracks"}
	)
	var aimed: TutorialBeatDef = Lesson.beat("c", TutorialConditions.Kind.STRIKE_AIMED)
	assert_bool(_check(any, ctx)).is_false()
	ctx.placement_type = Rig.type_of(world, "power_plant")
	assert_bool(_check(any, ctx)).is_true()
	assert_bool(_check(barracks, ctx)).is_false()
	ctx.placement_type = Rig.type_of(world, "barracks")
	assert_bool(_check(barracks, ctx)).is_true()
	ctx.strike_aiming = true
	assert_bool(_check(aimed, ctx)).is_false()
	ctx.strike_has_point = true
	assert_bool(_check(aimed, ctx)).is_true()


func test_strike_pending_group_saved_and_match_won() -> void:
	var world: World = Rig.start()
	var pending: TutorialBeatDef = Lesson.beat("a", TutorialConditions.Kind.STRIKE_PENDING)
	var group: TutorialBeatDef = Lesson.beat(
		"b", TutorialConditions.Kind.GROUP_SAVED, {"value": 2, "count": 2}
	)
	var won: TutorialBeatDef = Lesson.beat("c", TutorialConditions.Kind.MATCH_WON)
	assert_bool(_check(pending, Lesson.context(world))).is_false()
	world.strike_tick[1] = 120
	assert_bool(_check(pending, Lesson.context(world))).is_true()
	var ctx: TutorialContext = Lesson.context(world)
	ctx.selection.set_ids(PackedInt32Array([Lesson.row_id(world, 1, "rifle_squad")]))
	assert_bool(_check(group, ctx)).is_false()
	ctx.selection.assign_group(2)
	assert_bool(_check(group, ctx)).is_false()  # One unit in the group, two asked.
	world.match_end_tick = 500
	world.winner = 2
	assert_bool(_check(won, Lesson.context(world))).is_false()
	world.winner = 1
	assert_bool(_check(won, Lesson.context(world))).is_true()


func test_a_sim_condition_with_no_snapshot_is_false() -> void:
	var ctx: TutorialContext = TutorialContext.new()
	for kind: TutorialConditions.Kind in TutorialConditions.NEEDS_TICKS:
		assert_bool(_check(Lesson.beat("a", kind, {"count": 0}), ctx)).is_false()


func test_only_the_tick_driven_kinds_need_ticks() -> void:
	assert_bool(TutorialConditions.needs_ticks(TutorialConditions.Kind.BUILDING_DONE)).is_true()
	assert_bool(TutorialConditions.needs_ticks(TutorialConditions.Kind.NEXT)).is_false()
	assert_bool(TutorialConditions.needs_ticks(TutorialConditions.Kind.ZOOM_LEVEL)).is_false()
	assert_bool(TutorialConditions.needs_ticks(TutorialConditions.Kind.SELECTED)).is_false()


func test_group_saved_holds_with_two_units_in_the_group() -> void:
	var world: World = Rig.start()
	var ctx: TutorialContext = Lesson.context(world)
	var two: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.GROUP_SAVED, {"value": 2, "count": 2}
	)
	var squads: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_index[row] == Rig.type_of(world, "rifle_squad"):
			squads.append(world.unit_id[row])
	assert_int(squads.size()).is_equal(2)
	ctx.selection.set_ids(squads)
	ctx.selection.assign_group(2)
	assert_bool(_check(two, ctx)).is_true()
	var other: TutorialBeatDef = Lesson.beat("b", TutorialConditions.Kind.GROUP_SAVED, {"value": 3})
	assert_bool(_check(other, ctx)).is_false()


func test_a_pinch_about_a_point_is_no_pan() -> void:
	var ctx: TutorialContext = Lesson.context(Rig.start())
	var start: TutorialContext = ctx.baseline()
	var pan: TutorialBeatDef = Lesson.beat(
		"a", TutorialConditions.Kind.CAMERA_PANNED, {"count": 50}
	)
	ctx.camera_centre = Vector2(200, 0)  # A pinch moved the centre ...
	ctx.camera_zoom = 2.0  # ... and changed the zoom.
	assert_bool(_check(pan, ctx, start)).is_false()
	ctx.camera_zoom = start.camera_zoom
	assert_bool(_check(pan, ctx, start)).is_true()
