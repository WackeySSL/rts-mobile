extends GdUnitTestSuite
## The Repair order of the command bar (plan P282, ADR 0037 section 9) in the main scene at the six
## sizes of ScreenSizes.ALL: it shows while a complete own repair building serves a selected own
## ground unit, dimmed and not tappable until one is damaged (P282b), at least 56 x 64 dp, and one
## tap sends one REPAIR with the damaged units that building serves to the nearest, with no
## aim. A mixed selection shows Home and Repair side by side, each sending its own rows; medics
## and an attack:
## the unarmed rows get an ATTACK_MOVE beside the hitters' ATTACK.
## Own: light tank 1, fighter 2, airfield 3, near Weld Shed 4, far Weld Shed 5, Patchers 6, a
## second light tank 7 (undamaged); enemy light tank 8; tanker 9.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const TANK: int = 1
const FIGHTER: int = 2
const FIELD: int = 3
const NEAR_SHED: int = 4
const FAR_SHED: int = 5
const PATCHERS: int = 6
const FIT_TANK: int = 7
const ENEMY_TANK: int = 8
const TANKER: int = 9
const SPAWNS: Array[Array] = [
	[1, "light_tank", 14, 14],
	[1, "fossil_fighter", 10, 10],
	[1, "fossil_airfield", 6, 6],
	[1, "fossil_weld_shed", 16, 14],
	[1, "fossil_weld_shed", 30, 30],
	[1, "fossil_patchers", 14, 16],
	[1, "light_tank", 15, 14],
	[2, "light_tank", 17, 15],
	[1, "renew_tanker", 12, 12],
]

var _window_size_before: Vector2i
var _main: Node2D
var _controller: PlayerController
var _bar: CommandBar
var _runner: MatchRunner
var _sent: Array[Command] = []
var _buzzes: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


func test_repair_shows_for_a_unit_a_building_serves_and_is_a_full_size_order() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		var why: String = str(size)
		await _select([TANK])  # Undamaged: shown, dimmed.
		assert_bool(_repair().visible).override_failure_message(why).is_true()
		assert_bool(_repair().disabled).override_failure_message(why).is_true()
		_hurt([TANK])
		_runner.ticked.emit(1)  # The next tick refreshes the same selection.
		await await_idle_frame()
		assert_bool(_repair().is_visible_in_tree()).override_failure_message(why).is_true()
		assert_bool(_repair().disabled).override_failure_message(why).is_false()
		assert_bool(_home().visible).is_false()
		_assert_whole_or_cue(why)
		await _select([])
		assert_bool(_repair().visible).is_false()


func test_repair_is_dim_and_sends_nothing_while_no_served_unit_is_damaged() -> void:
	await _open(ScreenSizes.ALL[0], null)
	await _select([TANK, FIT_TANK])
	assert_bool(_repair().is_visible_in_tree()).is_true()
	assert_bool(_repair().disabled).is_true()
	_tap(_repair())
	assert_int(_sent.size()).is_equal(0)
	assert_int(_buzzes).is_equal(0)
	_hurt([TANK])  # Damage makes it tappable again on the next tick's refresh.
	_runner.ticked.emit(1)
	await await_idle_frame()
	assert_bool(_repair().disabled).is_false()
	_tap(_repair())
	assert_int(_sent.size()).is_equal(1)
	assert_array(_sent[0].unit_ids).is_equal([TANK])
	_sent.clear()
	var snap: MatchSnapshot = _runner.snapshot  # Fully repaired: dim again.
	var row: int = snap.index_of(TANK)
	snap.hp[row] = snap.type_max_hp[snap.type_index[row]]
	_runner.ticked.emit(2)
	await await_idle_frame()
	assert_bool(_repair().is_visible_in_tree()).is_true()
	assert_bool(_repair().disabled).is_true()
	_tap(_repair())
	assert_int(_sent.size()).is_equal(0)


func test_a_hurt_unit_no_building_serves_leaves_repair_dim_for_the_served_one() -> void:
	await _open(ScreenSizes.ALL[0], null)
	_hurt([PATCHERS])  # Medics are not served; the tank is, undamaged.
	await _select([TANK, PATCHERS])
	assert_bool(_repair().is_visible_in_tree()).is_true()
	assert_bool(_repair().disabled).is_true()


func test_repair_never_shows_where_it_would_do_nothing() -> void:
	await _open(ScreenSizes.ALL[0], null)
	_hurt([FIGHTER, PATCHERS, NEAR_SHED])
	await _select([FIGHTER])  # An aircraft is Home's, never a Repair row.
	assert_bool(_repair().visible).is_false()
	await _select([PATCHERS])  # The sheds serve wheels and tracks, not feet.
	assert_bool(_repair().visible).is_false()
	await _select([NEAR_SHED])  # A building is no Repair row.
	assert_bool(_repair().visible).is_false()
	_hurt([FIGHTER, PATCHERS])
	await _select([FIGHTER, PATCHERS])  # Only aircraft and infantry: no served row.
	assert_bool(_repair().visible).is_false()
	_hurt([TANK])
	_runner.snapshot.owner[_runner.snapshot.index_of(NEAR_SHED)] = 2
	_runner.snapshot.owner[_runner.snapshot.index_of(FAR_SHED)] = 2
	await _select([TANK])  # No repair building of the player's.
	assert_bool(_repair().visible).is_false()


func test_a_mixed_selection_shows_home_and_repair_each_for_its_own_rows() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		var why: String = str(size)
		_hurt([TANK, FIGHTER])
		_runner.snapshot.home[_runner.snapshot.index_of(FIGHTER)] = FIELD
		await _select([TANK, FIGHTER, FIT_TANK])
		assert_bool(_home().is_visible_in_tree()).override_failure_message(why).is_true()
		assert_bool(_repair().is_visible_in_tree()).override_failure_message(why).is_true()
		_assert_whole_or_cue(why, _home())
		_assert_whole_or_cue(why, _repair())
		_tap(_repair())
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_int(_sent[0].player_id).is_equal(_runner.scenario.local_player)
		assert_int(_sent[0].type).is_equal(Command.Type.REPAIR)
		assert_array(_sent[0].unit_ids).is_equal([TANK])
		assert_int(_buzzes).is_equal(1)
		_tap(_home())
		assert_int(_sent.size()).is_equal(2)
		assert_int(_sent[1].player_id).is_equal(_runner.scenario.local_player)
		assert_int(_sent[1].target_id).is_equal(FIELD)
		assert_array(_sent[1].unit_ids).is_equal([FIGHTER])
		assert_array(_controller.selection.selected).is_equal([TANK, FIGHTER, FIT_TANK])


func test_repair_goes_to_the_nearest_serving_building_not_one_that_cannot_serve() -> void:
	await _open(ScreenSizes.ALL[0], null)
	_hurt([TANK])
	await _select([TANK])
	_tap(_repair())
	assert_int(_sent[0].target_id).is_equal(NEAR_SHED)
	_sent.clear()
	_runner.snapshot.build_left[_runner.snapshot.index_of(NEAR_SHED)] = 5  # Still a site.
	await _select([TANK])
	_tap(_repair())
	assert_int(_sent[0].target_id).is_equal(FAR_SHED)


func test_a_tie_in_distance_goes_to_the_lower_id_and_the_centre_of_two_units_decides() -> void:
	await _open(ScreenSizes.ALL[0], null)
	var snap: MatchSnapshot = _runner.snapshot
	var near: int = snap.index_of(NEAR_SHED)
	var far: int = snap.index_of(FAR_SHED)
	var tank: int = snap.index_of(TANK)
	# The far shed mirrored through the tank: the same distance as the near one.
	snap.pos_x[far] = 2 * snap.pos_x[tank] - snap.pos_x[near]
	snap.pos_y[far] = 2 * snap.pos_y[tank] - snap.pos_y[near]
	_hurt([TANK])
	await _select([TANK])
	_tap(_repair())
	assert_int(_sent[0].target_id).is_equal(NEAR_SHED)
	# Two units whose centre lies nearer the far shed, though one stands at the near shed.
	_sent.clear()
	snap.pos_x[far] = 30000
	snap.pos_y[far] = 30000
	snap.pos_x[tank] = snap.pos_x[near]
	snap.pos_y[tank] = snap.pos_y[near]
	var second: int = snap.index_of(FIT_TANK)
	snap.pos_x[second] = 40000
	snap.pos_y[second] = 40000
	_hurt([FIT_TANK])
	await _select([TANK, FIT_TANK])
	_tap(_repair())
	assert_int(_sent[0].target_id).is_equal(FAR_SHED)
	assert_array(_sent[0].unit_ids).is_equal([TANK, FIT_TANK])


func test_a_damaged_medic_is_left_out_of_repair_and_only_the_tank_is_sent() -> void:
	await _open(ScreenSizes.ALL[0], null)
	_hurt([TANK, PATCHERS])
	await _select([TANK, PATCHERS])
	_tap(_repair())
	assert_array(_sent[0].unit_ids).is_equal([TANK])


func test_an_attack_sends_the_unarmed_medics_an_attack_move_but_never_a_tanker() -> void:
	await _open(ScreenSizes.ALL[0], null)
	await _select([TANK, PATCHERS, TANKER])
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(ENEMY_TANK)
	_tap_enemy(ENEMY_TANK)
	var player: int = _runner.scenario.local_player
	assert_int(_sent.size()).is_equal(2)
	assert_int(_sent[0].type).is_equal(Command.Type.ATTACK)
	assert_int(_sent[0].player_id).is_equal(player)
	assert_array(_sent[0].unit_ids).is_equal([TANK])
	assert_int(_sent[1].type).is_equal(Command.Type.ATTACK_MOVE)
	assert_int(_sent[1].player_id).is_equal(player)
	assert_array(_sent[1].unit_ids).is_equal([PATCHERS])
	assert_int(_sent[1].target_x).is_equal(snap.pos_x[row])
	assert_int(_sent[1].target_y).is_equal(snap.pos_y[row])
	_sent.clear()
	await _select([PATCHERS])  # Medics alone: nothing can hit, nothing is ordered.
	_tap_enemy(ENEMY_TANK)
	assert_int(_sent.size()).is_equal(0)


func test_repair_is_whole_or_a_cut_cue_in_the_bar_on_every_profile() -> void:
	var profiles: Array[UiMetrics] = []
	profiles.append_array(UiProfiles.all().values())
	profiles.append_array(UiProfiles.portrait().values())
	profiles.append_array(UiProfiles.notch_design().values())
	for metrics: UiMetrics in profiles:
		await _open(metrics.window_size, metrics)
		_hurt([TANK])
		await _select([TANK])
		var why: String = "%s %s" % [metrics.os_name, metrics.window_size]
		assert_bool(_repair().is_visible_in_tree()).override_failure_message(why).is_true()
		_assert_whole_or_cue(why)


## A tap on the enemy `id` where the picker draws it, through the controller's gesture entry.
func _tap_enemy(id: int) -> void:
	var pick: PickSnapshot = PickSnapshot.new()
	_controller.fill_pick(pick)
	var at: int = pick.ids.find(id)
	assert_int(at).is_greater_equal(0)
	var gesture: GestureEvent = GestureEvent.new()
	gesture.kind = GestureEvent.Kind.TAP
	gesture.position = pick.screen_pos[at] + Vector2(0.0, pick.lift_of(at))
	_controller.handle_gesture(gesture)


func _repair() -> Button:
	return _bar.order_button(&"repair")


func _home() -> Button:
	return _bar.order_button(&"home")


## Takes half the hit points off each row of `ids` in the published snapshot.
func _hurt(ids: Array) -> void:
	for id: int in ids:
		var row: int = _runner.snapshot.index_of(id)
		_runner.snapshot.hp[row] = _runner.snapshot.hp[row] / 2


## Repair is 56 x 64 dp at least and inside the safe area; inside the order scroll, or cut by it
## with part of it showing (the scroll takes touches then: the rule's cue that orders go on).
func _assert_whole_or_cue(why: String, button: Button = null) -> void:
	var rect: Rect2 = (button if button != null else _repair()).get_global_rect()
	assert_float(rect.size.x).override_failure_message(why).is_greater_equal(UiScale.dp(56.0) - 0.5)
	assert_float(rect.size.y).override_failure_message(why).is_greater_equal(UiScale.dp(64.0) - 0.5)
	var scroll: ScrollContainer = _bar.find_child("Orders", true, false) as ScrollContainer
	var clip: Rect2 = scroll.get_global_rect()
	var detail: String = "%s: repair %s, orders %s" % [why, rect, clip]
	if not clip.grow(0.5).encloses(rect):
		assert_bool(clip.intersects(rect)).override_failure_message(detail).is_true()
		assert_int(scroll.mouse_filter).override_failure_message(detail).is_equal(
			Control.MOUSE_FILTER_PASS
		)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 0.0)
	assert_bool(safe.grow(0.5).encloses(clip)).override_failure_message(detail).is_true()


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()  # The bar publishes its slot on a deferred call, then places.
	await await_idle_frame()


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


func _open(size: Vector2i, metrics: UiMetrics) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario(spawns)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_controller = _main.get_node("PlayerController")
	_bar = _main.get_node("Hud").find_child("CommandBar", true, false) as CommandBar
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_buzzes = 0
	_controller.vibrate = func(_ms: int) -> void: _buzzes += 1
	await await_idle_frame()
