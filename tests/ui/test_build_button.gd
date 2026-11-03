extends GdUnitTestSuite
## BUILD (plan P120, ADR 0025 section 4) in the main scene: a 64 dp square at the safe rect's
## bottom right in both orientations, at the six sizes of ScreenSizes.ALL and at every profile, also
## with a cutout, where `HudCorners.place` puts it. The ring is the share of the queue head that
## finishes first (the least work left over the player's three queues), the badge the items in all
## of them; it redraws when either changes and not at rest; it hides while the drawer or the pause
## menu is open; a tap opens the drawer. Stalled and the Ready chip (plan P120c, ADR 0025 section
## 4):
## from crafted snapshots, the ring turns grey and an "!" badge shows when no queue head advanced
## between two snapshots while a queue is not empty (not on low power, not for a finished structure,
## which shows the Ready chip instead), redrawing only on a change and allocating nothing per
## snapshot; the chip stands left of BUILD where `HudCorners` puts it at every screen and its tap
## opens the drawer on Structures with the finished card in view.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const RadarRig: GDScript = preload("res://tests/ui/support/radar_rig.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 1.5
const BASE: Array[String] = ["headquarters", "power_plant", "barracks", "vehicle_factory"]

var _window_size_before: Vector2i
var _main: Node2D
var _button: BuildButton
var _feed: HudStateFeed
var _runner: MatchRunner


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func before_test() -> void:
	MenuRig.begin()


func test_build_is_64_dp_at_the_safe_rects_bottom_right_where_the_layout_puts_it() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		var rect: Rect2 = _button.get_global_rect()
		var side: float = UiScale.dp(64.0)
		var at: String = "%s: BUILD %s, safe %s" % [why, rect, safe]
		assert_bool(_button.visible).override_failure_message(at).is_true()
		assert_float(rect.size.x).override_failure_message(at).is_equal_approx(side, TOLERANCE_PX)
		assert_float(rect.size.y).override_failure_message(at).is_equal_approx(side, TOLERANCE_PX)
		assert_float(rect.end.x).override_failure_message(at).is_equal_approx(safe.end.x, 1.0)
		assert_float(rect.end.y).override_failure_message(at).is_equal_approx(safe.end.y, 1.0)
		assert_bool(safe.grow(TOLERANCE_PX).encloses(rect)).override_failure_message(at).is_true()
		for other: String in ["EconomyPill", "RadarScope"]:
			assert_bool(rect.intersects(_rect(other))).override_failure_message(at).is_false()


func test_the_ring_is_the_first_finishing_head_and_the_badge_counts_every_queue() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	assert_int(_button.count).is_equal(0)
	assert_float(_button.progress).is_equal(0.0)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var plant: int = Sw.type_of(world, "power_plant")
	var rifle: int = Sw.type_of(world, "rifle_squad")
	var plant_goal: int = world.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
	var rifle_goal: int = world.type_build_ticks[rifle] * Production.PROGRESS_PER_TICK
	# The plant is a fifth along; the rifle squads, with another queued behind, half way.
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], plant_goal / 5)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rifle_squad"], rifle_goal / 2)
	_publish(world, 1)
	var left_plant: int = plant_goal - plant_goal / 5
	var left_rifle: int = rifle_goal - rifle_goal / 2
	var expected: float = 0.2 if left_plant < left_rifle else 0.5
	assert_float(_button.progress).is_equal_approx(expected, 0.001)
	assert_int(_button.count).is_equal(3)
	# Now the plant is nearly done: it finishes first.
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], plant_goal - 10)
	_publish(world, 2)
	assert_float(_button.progress).is_equal_approx(float(plant_goal - 10) / plant_goal, 0.001)
	# Empty queues: no ring and no badge.
	Sw.enqueue(world, World.Tab.STRUCTURES, [])
	Sw.enqueue(world, World.Tab.INFANTRY, [])
	_publish(world, 3)
	assert_int(_button.count).is_equal(0)
	assert_float(_button.progress).is_equal(0.0)


func test_it_redraws_when_the_ring_or_the_badge_changes_and_not_at_rest() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_button.set_process(true)  # The game's frames read the published snapshot.
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_post(world, 1)
	await await_idle_frame()
	await await_idle_frame()
	_post(world, 2)  # The queue did not move: the stalled look draws once.
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_button.stalled).is_true()
	var drawn: int = _button.draws
	assert_int(drawn).is_greater(0)
	for tick: int in 3:  # The same queue on later ticks and over idle frames: nothing to redraw.
		_post(world, 2 + tick)
		await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_button.draws).is_equal(drawn)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 600)
	_post(world, 9)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_button.draws).is_equal(drawn + 1)


## The badge is a HUD number: 18 sp at the least (touch-ui-rules, ADR 0025 section 13), in the
## theme's number face; the word is the theme's 14 dp caps.
func test_the_badge_is_an_18_sp_number_and_the_word_a_14_dp_caps_face_from_the_theme() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var dp: float = UiScale.dp(1.0)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_publish(world, 1)  # A count above 0: the badge is drawn.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_button.count).is_greater(0)
	assert_object(_button.badge_font).is_not_null()  # What _draw really used for the digits.
	assert_object(_button.badge_font).is_same(
		_button.get_theme_font(&"font", BuildButton.NUMBER_FONT)
	)
	assert_float(float(_button.badge_font_size)).is_greater_equal(roundf(18.0 * dp) - 0.5)
	var word: int = _button.get_theme_font_size(&"font_size", BuildButton.WORD_FONT)
	assert_float(float(word)).is_greater_equal(roundf(14.0 * dp) - 0.5)
	assert_object(_button.badge_font).is_not_same(
		_button.get_theme_font(&"font", BuildButton.WORD_FONT)
	)


func test_it_hides_under_the_drawer_and_the_pause_menu_and_a_tap_opens_the_drawer() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		var why: String = str(size)
		assert_bool(_button.visible).override_failure_message(why).is_true()
		var at: Vector2 = _button.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(_feed.state.current).override_failure_message(why).is_equal(
			HudState.Unfold.DRAWER
		)
		assert_bool(_button.visible).override_failure_message(why).is_false()
		_feed.state.close(HudState.Unfold.DRAWER)
		assert_bool(_button.visible).override_failure_message(why).is_true()
		_feed.state.open(HudState.Unfold.PAUSE)
		assert_bool(_button.visible).override_failure_message(why).is_false()
		_feed.state.close(HudState.Unfold.PAUSE)
		assert_bool(_button.visible).override_failure_message(why).is_true()
		assert_bool(_button.visible).is_true()


## "Stalled" compares two snapshots: a head that did not advance with a queue not empty. The first
## snapshot of a queue, an advance, a finished item, low power, a finished structure waiting to be
## placed and an empty queue are not stalled; a unit queue at its goal (no room for the unit) is.
func test_stalled_is_no_head_advancing_between_two_snapshots_with_a_queue_not_empty() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var rifle: int = Sw.type_of(world, "rifle_squad")
	var goal: int = world.type_build_ticks[rifle] * Production.PROGRESS_PER_TICK
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_publish(world, 1)
	assert_bool(_button.stalled).override_failure_message("a first snapshot").is_false()
	# A queue that appears at progress 0 is no stall at its first snapshot (nothing to compare).
	Sw.enqueue(world, World.Tab.INFANTRY, [])
	_publish(world, 20)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 0)
	_publish(world, 21)
	assert_bool(_button.stalled).override_failure_message("appears at 0").is_false()
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_publish(world, 22)
	assert_bool(_button.stalled).override_failure_message("then moves").is_false()
	Sw.enqueue(world, World.Tab.INFANTRY, [])
	_publish(world, 23)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_publish(world, 24)
	_publish(world, 2)  # The same progress one tick later: stalled.
	assert_bool(_button.stalled).override_failure_message("no advance").is_true()
	_button.refresh(_runner.snapshot)  # The same snapshot again changes nothing.
	assert_bool(_button.stalled).override_failure_message("the same snapshot").is_true()
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 200)
	_publish(world, 3)
	assert_bool(_button.stalled).override_failure_message("advanced").is_false()
	_publish(world, 4)
	assert_bool(_button.stalled).override_failure_message("stopped again").is_true()
	# Low power slows the ring but the head still advances: not stalled. With the head not moving
	# (the producer blacked out or destroyed) it is a stall like any other.
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 250)
	_publish_low(world, 5)
	assert_bool(_button.stalled).override_failure_message("low power, advancing").is_false()
	_publish_low(world, 6)
	assert_bool(_button.stalled).override_failure_message("low power, no advance").is_true()
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 260)
	_publish_low(world, 7)
	assert_bool(_button.stalled).override_failure_message("low power, slow advance").is_false()
	_publish(world, 8)  # Power back: the queue has not moved since.
	assert_bool(_button.stalled).override_failure_message("power back").is_true()
	# An item that finished (the queue shorter, the next one at 0) is an advance.
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rifle_squad"], goal - 50)
	_publish(world, 7)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 0)
	_publish(world, 8)
	assert_bool(_button.stalled).override_failure_message("finished one").is_false()
	# A unit queue at its goal that goes no further (the unit cap, no free exit) is stalled.
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], goal)
	_publish(world, 9)
	_publish(world, 10)
	assert_bool(_button.stalled).override_failure_message("at the goal").is_true()
	# An empty queue is not.
	Sw.enqueue(world, World.Tab.INFANTRY, [])
	_publish(world, 11)
	_publish(world, 12)
	assert_bool(_button.stalled).override_failure_message("empty").is_false()
	assert_int(_button.count).is_equal(0)


## A structure that is still being built (a queue that runs, not finished) shows no chip; finished
## it does, and the chip goes when the queue empties.
func test_the_chip_is_hidden_while_the_structure_is_unfinished() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var chip: Control = _button.get_node("ReadyChip") as Control
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var plant: int = Sw.type_of(world, "power_plant")
	var goal: int = world.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
	for tick: int in 3:
		Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], goal - 100 + tick * 10)
		_publish(world, 1 + tick)
		assert_bool(chip.visible).is_false()
		assert_int(_button.ready_type).is_equal(-1)
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], goal)
	_publish(world, 5)
	assert_bool(chip.visible).is_true()
	assert_int(_button.ready_type).is_equal(plant)


## A finished structure waiting to be placed is no stall (the chip shows it); another queue that is
## stalled still is. A new match compares with nothing.
func test_a_finished_structure_is_not_stalled_but_a_stuck_unit_queue_beside_it_is() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var plant: int = Sw.type_of(world, "power_plant")
	var plant_goal: int = world.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], plant_goal)
	_publish(world, 1)
	_publish(world, 2)
	assert_bool(_button.stalled).is_false()
	assert_int(_button.ready_type).is_equal(plant)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_publish(world, 3)
	_publish(world, 4)
	assert_bool(_button.stalled).is_true()
	assert_int(_button.ready_type).is_equal(plant)
	var snap: MatchSnapshot = Sw.snapshot(world, 1)  # Another match.
	snap.tick = 5
	_runner.snapshot = snap
	_button.refresh(snap)
	assert_bool(_button.stalled).is_false()


## The look: a grey ring (the theme's `BuildButton` colour, not the faction's) and an "!" disc, a
## shape besides the grey; both go with the stall. Redrawn once when it starts and once when it
## ends, and not at all while a snapshot only repeats the state; a snapshot allocates nothing.
func test_the_stalled_look_redraws_once_per_change_and_nothing_per_snapshot() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 100)
	_publish(world, 1)
	_publish(world, 2)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_button.stalled).is_true()
	var grey: Color = _button.get_theme_color(&"ring_stalled", BuildButton.STALLED)
	var faction: Color = _button.get_theme_color(&"light", BuildButton.ACCENTS[0])
	assert_bool(grey.is_equal_approx(faction)).is_false()
	# What _draw really did: the grey arc and the "!" disc.
	assert_bool(_button.ring_drawn).is_true()
	assert_bool(_button.ring_color.is_equal_approx(grey)).is_true()
	assert_bool(_button.mark_drawn).is_true()
	var drawn: int = _button.draws
	for tick: int in range(3, 9):  # Stalled and staying so: nothing to redraw.
		_publish(world, tick)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_button.draws).is_equal(drawn)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"], 300)
	_publish(world, 9)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_button.stalled).is_false()
	assert_int(_button.draws).is_equal(drawn + 1)
	assert_bool(_button.ring_drawn).is_true()
	assert_bool(_button.ring_color.is_equal_approx(faction)).is_true()  # The faction's, no mark.
	assert_bool(_button.mark_drawn).is_false()
	# The comparison keeps its numbers in arrays made once: `refresh` makes nothing.
	var source: String = FileAccess.get_file_as_string("res://game/ui/BuildButton.gd")
	var body: String = _function(source, "refresh")
	assert_str(body).is_not_empty()
	var made: RegEx = RegEx.create_from_string(
		r"\.new\(|PackedInt32Array\(|Dictionary|\[\]|\bload\("
	)
	assert_object(made.search(body)).override_failure_message(body).is_null()


## The Ready chip is `READY_DP` (112 x 48 dp) a gap left of BUILD, centred on it, inside the safe
## rect and clear of the pill, the scope and the strike button, at every screen and in both
## orientations; it shows only while a structure is finished, with its word and its card, and
## hides with BUILD under the drawer.
func test_the_ready_chip_stands_left_of_build_where_the_layout_puts_it() -> void:
	var screens: Array[Dictionary] = _screens()
	var short: UiMetrics = RadarRig.short_landscape()
	screens.append({"label": "short landscape", "size": short.window_size, "metrics": short})
	for screen: Dictionary in screens:
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var chip: Button = _button.get_node("ReadyChip") as Button
		assert_bool(chip.visible).override_failure_message(why).is_false()
		var world: World = Sw.world()
		Sw.own(world, BASE)
		var plant: int = Sw.type_of(world, "power_plant")
		var goal: int = world.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
		Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], goal)
		_publish(world, 1)
		assert_bool(chip.visible).override_failure_message(why).is_true()
		assert_str(chip.text).is_equal("Ready")
		assert_object(chip.icon).override_failure_message(why).is_not_null()
		assert_str(chip.theme_type_variation).is_equal("ReadyBadge")
		var dp: float = UiScale.dp(1.0)
		var rect: Rect2 = chip.get_global_rect()
		var build: Rect2 = _button.get_global_rect()
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		var at: String = "%s: chip %s, BUILD %s" % [why, rect, build]
		assert_float(rect.size.x).override_failure_message(at).is_equal_approx(112.0 * dp, 1.5)
		assert_float(rect.size.y).override_failure_message(at).is_equal_approx(48.0 * dp, 1.5)
		assert_float(build.position.x - rect.end.x).override_failure_message(at).is_equal_approx(
			8.0 * dp, 1.5
		)
		assert_float(rect.get_center().y).override_failure_message(at).is_equal_approx(
			build.get_center().y, 1.5
		)
		assert_bool(safe.grow(TOLERANCE_PX).encloses(rect)).override_failure_message(at).is_true()
		for other: String in ["EconomyPill", "RadarScope", "StrikeControls"]:
			var control: Control = _main.get_node("Hud").find_child(other, true, false) as Control
			if control.is_visible_in_tree():
				var clash: String = "%s: %s" % [at, control.get_global_rect()]
				(
					assert_bool(rect.intersects(control.get_global_rect()))
					. override_failure_message(clash)
					. is_false()
				)
		_feed.state.open(HudState.Unfold.DRAWER)
		assert_bool(chip.is_visible_in_tree()).override_failure_message(why).is_false()
		_feed.state.close(HudState.Unfold.DRAWER)
		Sw.enqueue(world, World.Tab.STRUCTURES, [])  # Placed: the chip goes.
		_publish(world, 2)
		assert_bool(chip.visible).override_failure_message(why).is_false()


## A tap on the chip opens the drawer on the Structures tab, the finished card in view, at every
## size and in both orientations (the grid scrolls: upright the sheet holds few rows), even from
## another tab; it sends no Command and does not place anything.
func test_a_tap_on_the_ready_chip_opens_the_drawer_on_structures_with_the_card_in_view() -> void:
	var screens: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		screens.append({"label": str(size), "size": size, "metrics": null})
	for profile: StringName in [&"web_phone_small", &"web_phone", &"web_phone_portrait"]:
		var metrics: UiMetrics = UiProfiles.by_name(profile)
		screens.append({"label": str(profile), "size": metrics.window_size, "metrics": metrics})
	var scrolled: int = 0
	for screen: Dictionary in screens:
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var sidebar: BuildSidebar = _main.get_node("Hud/BuildSidebar")
		sidebar.runner = _runner
		var sent: Array[Command] = []
		var controller: PlayerController = _main.get_node("PlayerController")
		controller.command_sink = func(command: Command) -> void: sent.append(command)
		var world: World = Sw.world()
		Sw.own(world, BASE)
		_publish(world, 1)  # The tiles are made from the first snapshot.
		sidebar.refresh()
		# The last Structures card of the drawer: the one furthest down the grid.
		var last: ItemTile = null
		for tile: ItemTile in sidebar._tiles:
			if tile.tab == World.Tab.STRUCTURES and (tile.faction < 0 or tile.faction == 0):
				last = tile
		assert_object(last).override_failure_message(why).is_not_null()
		var id: String = last.name.trim_prefix("Tile_")
		var goal: int = world.type_build_ticks[Sw.type_of(world, id)] * Production.PROGRESS_PER_TICK
		Sw.enqueue(world, World.Tab.STRUCTURES, [id], goal)
		_publish(world, 2)
		sidebar.refresh()
		sidebar.select_tab(World.Tab.VEHICLES)  # Another tab was open.
		var chip: Control = _button.get_node("ReadyChip") as Control
		var at: Vector2 = chip.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		for frame: int in 3:
			await await_idle_frame()
		assert_int(_feed.state.current).override_failure_message(why).is_equal(
			HudState.Unfold.DRAWER
		)
		assert_int(sidebar.tab).override_failure_message(why).is_equal(World.Tab.STRUCTURES)
		assert_int(last.state).override_failure_message(why).is_equal(ItemTile.State.READY)
		var items: ScrollContainer = sidebar.find_child("Items", true, false) as ScrollContainer
		var seen: bool = items.get_global_rect().encloses(last.get_global_rect().grow(-1.0))
		var cards: String = (
			"%s: card %s, grid %s" % [why, last.get_global_rect(), items.get_global_rect()]
		)
		assert_bool(seen).override_failure_message(cards).is_true()
		scrolled += int(items.scroll_vertical > 0)
		assert_array(sent).override_failure_message(why).is_empty()
	assert_int(scrolled).override_failure_message("the scroll was never needed").is_greater(0)


## The snapshot of `world` at `tick`, published to the runner the button reads (its own frames
## pick it up).
func _post(world: World, tick: int) -> void:
	var snap: MatchSnapshot = Sw.snapshot(world, 0)
	snap.tick = tick
	_runner.snapshot = snap


## As `_publish`, on low power (the local player uses more than it makes).
func _publish_low(world: World, tick: int) -> void:
	var snap: MatchSnapshot = Sw.snapshot(world, 0)
	snap.tick = tick
	snap.power_used[1] = snap.power_made[1] + 10
	_runner.snapshot = snap
	_button.refresh(snap)


func _publish(world: World, tick: int) -> void:
	var snap: MatchSnapshot = Sw.snapshot(world, 0)
	snap.tick = tick
	_runner.snapshot = snap
	_button.refresh(snap)


func _rect(node_name: String) -> Rect2:
	return (_main.get_node("Hud").find_child(node_name, true, false) as Control).get_global_rect()


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}. Each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait).
func _screens() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append({"label": "size %s" % size, "size": size, "metrics": null})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, m.window_size.x - CUTOUT_PX, m.window_size.y)
		all.append({"label": str(profile_name), "size": m.window_size, "metrics": m})
		var with_cutout: UiMetrics = UiProfiles.with_safe_area(m, cut)
		all.append(
			{
				"label": "%s with a cutout" % profile_name,
				"size": m.window_size,
				"metrics": with_cutout
			}
		)
	return all


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, and BUILD reading a runner of its own (the snapshots a test publishes).
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
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _main.get_node("MatchRunner").scenario
	_button = _main.get_node("Hud/BuildButton")
	_button.runner = _runner
	_feed = _main.get_node("Hud/HudStateFeed")
	await await_idle_frame()


## The body of `func name` in `source` (up to the next top-level blank pair), "" for none.
func _function(source: String, name: String) -> String:
	var start: int = source.find("func %s(" % name)
	if start < 0:
		return ""
	var end: int = source.find("\n\n\n", start)
	return source.substr(start, (end if end >= 0 else source.length()) - start)
