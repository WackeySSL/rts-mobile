extends GdUnitTestSuite
## The drawer's queue row, the card words and the hold (plan P120b, ADR 0025 section 5), in the
## main scene: the row names the producer and the count, shows one 56 dp thumb per queue slot (the
## items, the head's bar, dashed empties), a tap on an item sends `CANCEL [tab, slot]` with the
## haptic and the row then takes no tap until another snapshot is published; a locked card says
## the missing building's name, a full queue's card "FULL". Layout at the six sizes of
## ScreenSizes.ALL and on the smallest web phone.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar
var _sent: Array[Command] = []
var _buzzed: Array[int] = []


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


func test_the_row_has_a_thumb_per_slot_inside_the_drawer_at_every_size() -> void:
	var screens: Array = []
	for size: Vector2i in ScreenSizes.ALL:
		screens.append([size, null, str(size)])
	var small: UiMetrics = UiProfiles.by_name(&"web_phone_small")
	screens.append([small.window_size, small, "web_phone_small"])
	for entry: Array in screens:
		await _open(entry[0], entry[1])
		var world: World = Sw.world()
		Sw.own(world, BASE)
		Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rocket_squad"], 100)
		await _publish(world)
		_sidebar.select_tab(World.Tab.INFANTRY)
		await _settle()
		var why: String = str(entry[2])
		var row: QueueRow = _row()
		var back: Rect2 = _sidebar.find_child("Backdrop", true, false).get_global_rect()
		var slots: int = BuildSidebar._queue_slots(Sw.snapshot(world))
		assert_int(row.thumb_count()).override_failure_message(why).is_equal(slots)
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		# The row fits the content: the backdrop is no wider than the drawer (it would be placed
		# short of the holder's edge and clip its padding otherwise).
		var wide: float = (
			_sidebar._rect.size.x + (0.0 if HudLayout.is_portrait() else _sidebar._edge)
		)
		(
			assert_float((_sidebar.find_child("Backdrop", true, false) as Control).size.x)
			. override_failure_message(why)
			. is_less_equal(wide + 0.5)
		)
		(
			assert_float(
				(
					(_sidebar.find_child("Backdrop", true, false) as Control)
					. get_combined_minimum_size()
					. x
				)
			)
			. override_failure_message(why)
			. is_less_equal(wide + 0.5)
		)
		for slot: int in slots:
			var rect: Rect2 = row.thumb(slot).get_global_rect()
			var least: float = UiScale.dp(QueueRow.THUMB_DP) - 0.5
			var narrow: float = UiScale.dp(QueueRow.THUMB_LEAST_DP) - 0.5
			assert_float(rect.size.x).override_failure_message(why).is_greater_equal(narrow)
			assert_float(rect.size.y).override_failure_message(why).is_greater_equal(least)
			assert_bool(back.grow(1.5).encloses(rect)).override_failure_message(why).is_true()
			assert_bool(safe.grow(1.5).encloses(rect)).override_failure_message(why).is_true()


func test_the_row_names_the_producer_and_counts_the_queue_and_shows_the_head() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rocket_squad", "rifle_squad"], 100)
	await _publish(world)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	var label: Label = _row().find_child("Label", true, false)
	var maker: String = world.type_names[Sw.type_of(world, "barracks")]
	assert_str(label.text).is_equal("%s  3 IN QUEUE" % maker)
	assert_bool(_row().thumb(0).head).is_true()
	assert_float(_row().thumb(0).share).is_greater(0.0)
	assert_bool(_row().thumb(1).head).is_false()
	assert_int(_row().thumb(3).type_index).is_equal(-1)  # An empty slot is dashed.
	assert_int(_row().thumb(2).type_index).is_equal(Sw.type_of(world, "rifle_squad"))
	_sidebar.select_tab(World.Tab.VEHICLES)  # Its own queue, empty.
	await _settle()
	assert_str(label.text).ends_with("0 IN QUEUE")
	assert_int(_row().thumb(0).type_index).is_equal(-1)


func test_a_tap_on_an_item_cancels_that_slot_and_the_row_waits_past_the_commands_tick() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rocket_squad", "rifle_squad"])
	await _publish(world, 10)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	_tap_thumb(1)
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.CANCEL)
	assert_int(_sent[0].player_id).is_equal(1)
	assert_array(_sent[0].payload).is_equal([World.Tab.INFANTRY, 1])
	assert_array(_buzzed).is_equal([15])
	assert_bool(_row().is_waiting()).is_true()
	_tap_thumb(0)  # A quick second tap: the first cancel has shifted the slots.
	_tap_thumb(1)
	assert_int(_sent.size()).is_equal(1)
	# The runner has not stamped the Command yet: no snapshot ends the wait.
	await _publish(world, 11)
	assert_bool(_row().is_waiting()).is_true()
	# Stamped with tick 12 (drained into job 12): the snapshot of tick 12 does not hold it yet
	# (WORKER mode publishes job N before it drains the queue into N + 1), the one past it does.
	_sent[0].tick = 12
	await _publish(world, 12)
	assert_bool(_row().is_waiting()).is_true()
	_tap_thumb(0)
	assert_int(_sent.size()).is_equal(1)
	await _publish(world, 13)
	assert_bool(_row().is_waiting()).is_false()
	_tap_thumb(0)
	assert_int(_sent.size()).is_equal(2)
	assert_array(_sent[1].payload).is_equal([World.Tab.INFANTRY, 0])
	await _publish(world, 14)
	_tap_thumb(4)  # An empty slot sends nothing.
	assert_int(_sent.size()).is_equal(2)


func test_a_tab_change_ends_the_wait_and_a_swipe_on_a_thumb_is_no_tap() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rocket_squad"])
	Sw.enqueue(world, World.Tab.VEHICLES, ["light_tank", "harvester"])
	await _publish(world, 10)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	_tap_thumb(0)
	assert_bool(_row().is_waiting()).is_true()
	_sidebar.select_tab(World.Tab.VEHICLES)  # Another queue: nothing there was shifted.
	await _settle()
	assert_bool(_row().is_waiting()).is_false()
	_tap_thumb(1)
	assert_array(_sent[-1].payload).is_equal([World.Tab.VEHICLES, 1])
	await _publish(world, 20)
	_sent[-1].tick = 5
	await _publish(world, 21)
	# A finger that moves beyond the slop across a thumb and lifts on it sends nothing.
	var count: int = _sent.size()
	var thumb: Control = _row().thumb(0)
	var at: Vector2 = thumb.get_global_rect().get_center()
	var by: float = UiScale.dp(20.0)
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.drag(get_viewport(), 0, at + Vector2(by, 0.0), Vector2(by, 0.0))
	TouchEvents.release(get_viewport(), 0, at)
	assert_int(_sent.size()).is_equal(count)


func test_the_row_follows_the_open_tab_and_every_queue_cancels() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"])
	Sw.enqueue(world, World.Tab.VEHICLES, ["light_tank", "harvester"])
	await _publish(world)
	assert_int(_row().thumb(0).type_index).is_equal(Sw.type_of(world, "power_plant"))
	_sidebar.select_tab(World.Tab.VEHICLES)
	await _settle()
	assert_int(_row().thumb(1).type_index).is_equal(Sw.type_of(world, "harvester"))
	_tap_thumb(1)
	assert_array(_sent[0].payload).is_equal([World.Tab.VEHICLES, 1])
	_sidebar.select_tab(World.Tab.STRUCTURES)  # Ends the wait: a different queue.
	await _settle()
	_tap_thumb(0)
	assert_array(_sent[1].payload).is_equal([World.Tab.STRUCTURES, 0])


func test_a_locked_card_says_what_it_needs_and_a_full_queue_says_full() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, ["headquarters", "power_plant", "barracks"])
	var rifles: Array[String] = ["rifle_squad", "rifle_squad", "rifle_squad", "rifle_squad"]
	Sw.enqueue(world, World.Tab.INFANTRY, rifles + ["rifle_squad"])
	await _publish(world)
	var refinery: String = world.type_names[Sw.type_of(world, "refinery")]
	assert_str(_tile("vehicle_factory").word()).is_equal(refinery)
	assert_str(_tile("power_plant").word()).is_equal("")
	_sidebar.select_tab(World.Tab.VEHICLES)  # Locked for a producer: no vehicle factory.
	await _settle()
	var factory: String = world.type_names[Sw.type_of(world, "vehicle_factory")]
	assert_str(_tile("light_tank").word()).is_equal(factory)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	assert_int(_tile("rocket_squad").state).is_equal(ItemTile.State.FULL)
	assert_str(_tile("rocket_squad").word()).is_equal("FULL")


## The words fit the card: at most two lines, none cut (no ellipsis), and
## inside the stage (over the price plate nothing may run). Every display name of the data stands
## in for the requirement, so both factions' rosters are covered.
func test_the_words_stay_inside_the_stage_of_every_card_with_every_name() -> void:
	var names: PackedStringArray = _display_names()
	assert_bool(names.has("Synthesis Works") and names.has("Cracking Plant")).is_true()
	for profile: StringName in [&"android_6in", &"android_6in_portrait", &"web_phone_small"]:
		await _open(profile)
		var world: World = Sw.world()
		Sw.own(world, ["headquarters"])
		await _publish(world)
		var shown: int = 0
		for tab: int in World.TABS:
			_sidebar.select_tab(tab)
			await _settle()
			for tile: ItemTile in _sidebar.find_children("Tile_*", "ItemTile", true, false):
				if not tile.visible or tile.state != ItemTile.State.LOCKED:
					continue
				for display: String in names:
					tile.set_needs(display)
					await await_idle_frame()
					var label: Label = tile.find_child("Word", true, false)
					var stage: Control = tile.find_child("Stage", true, false)
					var why: String = "%s %s: %s" % [profile, tile.name, tile.word()]
					assert_str(tile.word()).override_failure_message(why).is_equal(display)
					var lines: int = label.get_line_count()
					assert_int(lines).override_failure_message(why).is_between(1, 2)
					(
						assert_int(label.get_visible_line_count())
						. override_failure_message(why)
						. is_equal(lines)
					)
					assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
					var font: Font = label.get_theme_font(&"font")
					var font_size: int = label.get_theme_font_size(&"font_size")
					for part: String in display.split(" "):  # No single word is broken or cut.
						var wide: float = (
							font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
						)
						(
							assert_float(wide)
							. override_failure_message(
								"%s: %s is %s wide in %s" % [why, part, wide, label.size.x]
							)
							. is_less_equal(label.size.x + 0.5)
						)
					var inside: bool = stage.get_global_rect().grow(1.0).encloses(
						label.get_global_rect()
					)
					assert_bool(inside).override_failure_message(why).is_true()
					(
						assert_float(label.get_minimum_size().y)
						. override_failure_message(why)
						. is_less_equal(stage.size.y + 0.5)
					)
					shown += 1
		assert_int(shown).override_failure_message(str(profile)).is_greater(0)


## The padlock stands where the card's history does not matter: a card locked after its first
## layout has the lock of a card locked from the start, clear of the count badge's corner.
func test_the_padlock_is_in_the_same_place_however_the_card_came_to_be_locked() -> void:
	var held: Array[String] = ["headquarters", "power_plant", "barracks"]
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, held)  # No refinery: the vehicle factory is locked from the start.
	await _publish(world)
	var start: ItemTile = _tile("vehicle_factory")
	assert_int(start.state).is_equal(ItemTile.State.LOCKED)
	var plan: Rect2 = _lock_rect(start)
	var plan_at: Vector2 = plan.position - start.get_global_rect().position
	_assert_worded_lock(start)
	await _open(&"android_6in")  # A new scene: a card laid out open, locked afterwards.
	world = Sw.world()
	Sw.own(world, held + ["refinery"])
	await _publish(world)
	var late: ItemTile = _tile("vehicle_factory")
	assert_int(late.state).is_equal(ItemTile.State.AVAILABLE)
	world = Sw.world()
	Sw.own(world, held)
	await _publish(world)
	assert_int(late.state).is_equal(ItemTile.State.LOCKED)
	var now: Rect2 = _lock_rect(late)
	var now_at: Vector2 = now.position - late.get_global_rect().position
	_assert_worded_lock(late)
	assert_float(now_at.x).is_equal_approx(plan_at.x, 0.5)
	assert_float(now_at.y).is_equal_approx(plan_at.y, 0.5)
	assert_float(now.size.x).is_equal_approx(plan.size.x, 0.5)
	# Top left, so the count badge (top right) never covers it.
	var badge: Control = late.find_child("Badge", true, false)
	assert_bool(now.intersects(badge.get_global_rect())).is_false()


## The worded padlock is in the stage's top left corner and `LOCK_WORDED_DP` in size (not wherever
## a centred lock's old offsets left it).
func _assert_worded_lock(tile: ItemTile) -> void:
	var stage: Control = tile.find_child("Stage", true, false)
	var lock: Rect2 = _lock_rect(tile)
	var at: Vector2 = lock.position - stage.get_global_rect().position
	var near: float = UiScale.dp(4.0)
	assert_float(absf(at.x)).override_failure_message("lock at %s" % at).is_less_equal(near)
	assert_float(absf(at.y)).override_failure_message("lock at %s" % at).is_less_equal(near)
	var edge: float = UiScale.dp(ItemTile.LOCK_WORDED_DP)
	assert_float(lock.size.x).override_failure_message("lock %s" % lock).is_equal_approx(edge, near)
	assert_float(lock.size.y).override_failure_message("lock %s" % lock).is_equal_approx(edge, near)


## A tile made on its own: locked first (a centred padlock), then told what it needs.
func test_a_standalone_tile_locked_before_it_is_told_its_need_has_the_corner_padlock() -> void:
	await _open(&"android_6in")
	var holder: Control = Control.new()
	_sidebar.add_child(holder)
	var tile: ItemTile = ItemTile.new()
	tile.setup(0, World.Tab.STRUCTURES, null, 100, "Name")
	tile.set_card(ItemTile.CARD_DP)
	holder.add_child(tile)
	tile.size = UiScale.dp_vec(ItemTile.CARD_DP.x, ItemTile.CARD_DP.y)
	tile.show_state(ItemTile.State.LOCKED, 0, 0.0)
	await _settle()
	tile.set_needs("Cracking Plant")
	await _settle()
	_assert_worded_lock(tile)
	holder.queue_free()


## The first line of the word clears the padlock, whatever the name.
func test_the_first_line_of_the_word_clears_the_padlock() -> void:
	for profile: StringName in [&"android_6in", &"android_6in_portrait", &"web_phone_small"]:
		await _open(profile)
		var world: World = Sw.world()
		Sw.own(world, ["headquarters"])
		await _publish(world)
		var tile: ItemTile = _tile("vehicle_factory")
		assert_int(tile.state).is_equal(ItemTile.State.LOCKED)
		for display: String in _display_names():
			tile.set_needs(display)
			await await_idle_frame()
			var label: Label = tile.find_child("Word", true, false)
			var box: Rect2 = label.get_global_rect()
			var high: float = float(label.get_line_height())
			var wide: float = _first_line_width(label, display)
			var first: Rect2 = Rect2(
				box.position.x + (box.size.x - wide) / 2.0,
				box.end.y - high * label.get_line_count(),
				wide,
				high
			)
			var why: String = (
				"%s: %s, line %s, lock %s" % [profile, display, first, _lock_rect(tile)]
			)
			assert_bool(first.intersects(_lock_rect(tile))).override_failure_message(why).is_false()


## A match that starts again in the scene forgets the cancel in flight (its tick is the old one's).
func test_a_new_match_releases_the_queue_row() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rocket_squad"])
	await _publish(world, 50)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	_tap_thumb(0)
	_sent[0].tick = 500
	assert_bool(_row().is_waiting()).is_true()
	_runner.snapshot = Sw.snapshot(world, 1)  # Another match serial.
	_runner.snapshot.tick = 2
	_sidebar.refresh()
	assert_bool(_row().is_waiting()).is_false()


## The width of the first line of `text` wrapped at the label's width (words kept whole).
func _first_line_width(label: Label, text: String) -> float:
	var font: Font = label.get_theme_font(&"font")
	var font_size: int = label.get_theme_font_size(&"font_size")
	var line: String = ""
	for word: String in text.split(" "):
		var tried: String = word if line.is_empty() else line + " " + word
		var wide: float = font.get_string_size(tried, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		if wide > label.size.x and not line.is_empty():
			break
		line = tried
	return font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func _lock_rect(tile: ItemTile) -> Rect2:
	return (tile.find_child("Lock", true, false) as Control).get_global_rect()


## Every display name of the units and buildings in the data.
func _display_names() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open("res://data/units")
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			var def: Resource = load("res://data/units/" + file)
			var shown: Variant = def.get("display_name")
			if shown is String and not (shown as String).is_empty():
				found.append(shown as String)
	return found


func _row() -> QueueRow:
	return _sidebar.find_child("QueueRow", true, false) as QueueRow


func _tile(id: String) -> ItemTile:
	return _sidebar.find_child("Tile_" + id, true, false) as ItemTile


## A tap on the thumb of `slot`, through the button's own signal.
func _tap_thumb(slot: int) -> void:
	_row().thumb(slot).pressed.emit()


func _publish(world: World, tick: int = 0) -> void:
	_runner.snapshot = Sw.snapshot(world)
	_runner.snapshot.tick = tick
	_sidebar.refresh()
	await _settle()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene (a profile name, or a size and metrics), the drawer open, the Commands caught.
func _open(target: Variant, metrics: UiMetrics = null) -> void:
	var size: Vector2i
	var used: UiMetrics = metrics
	if target is StringName:
		used = UiProfiles.by_name(target as StringName)
		size = used.window_size
	else:
		size = target as Vector2i
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if used != null:
		UiScale.set_override(used)
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
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_sidebar.open()
	await await_idle_frame()
	_sidebar.runner = _runner
	var controller: PlayerController = _main.get_node("PlayerController")
	_sent.clear()
	_buzzed.clear()
	controller.command_sink = func(command: Command) -> void: _sent.append(command)
	controller.vibrate = func(ms: int) -> void: _buzzed.append(ms)
	var world: World = Sw.world()
	Sw.own(world, BASE)
	_runner.snapshot = Sw.snapshot(world)
	_sidebar.refresh()
	await _settle()
