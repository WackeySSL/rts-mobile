extends GdUnitTestSuite
## The card words and the padlock (plan P120b, ADR 0025 section 5), in the main scene: a locked card
## says the missing building's name after an inline padlock, a full queue's card "FULL", the
## words stay inside the card whatever the name, and the padlock stands in one place.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
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


## The words fit the card: at most two lines, none cut (no ellipsis), inside the stage, and the
## padlock inline or in the corner by the fit rule, at the widths the drawer really gives. Every
## display name of the data stands in for the requirement, so both factions' rosters are covered.
func test_the_words_stay_inside_the_stage_of_every_card_with_every_name() -> void:
	var names: PackedStringArray = _display_names()
	assert_bool(names.has("Synthesis Works") and names.has("Cracking Plant")).is_true()
	for profile: StringName in [&"android_6in", &"android_6in_portrait", &"web_phone_small"]:
		await _open(profile)
		var world: World = Sw.world()
		Sw.own(world, ["headquarters"])
		await _publish(world)
		var bad: PackedStringArray = PackedStringArray()
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
					bad.append_array(_problems(tile, display, "%s %s" % [profile, tile.name]))
					shown += 1
				break  # One card per tab: the drawer gives all its cards one width.
		assert_int(shown).override_failure_message(str(profile)).is_greater(0)
		_assert_none(bad, str(profile))


## The floor: a card of `CARD_DP` (sideways) or `CARD_PORTRAIT_DP` (upright) is the narrowest the
## sidebar makes, in every profile's scale. Whatever the name, it is whole in at most 2 lines, and
## the padlock is inline only when the name and the padlock share line one.
func test_every_name_is_whole_at_the_narrowest_card_of_every_profile() -> void:
	var names: PackedStringArray = _display_names()
	for profile: StringName in _floor_profiles():
		await _open(profile)
		var bad: PackedStringArray = PackedStringArray()
		for card: Vector2 in [ItemTile.CARD_DP, ItemTile.CARD_PORTRAIT_DP]:
			var tile: ItemTile = await _lone_tile(card, 0)
			for display: String in names:
				tile.set_needs(display)
				await await_idle_frame()
				var tag: String = "%s %s" % [profile, card]
				bad.append_array(_problems(tile, display, tag))
		_assert_none(bad, str(profile))


## A count on a locked card (a queue waits without a producer): the card is main's (the padlock in
## the corner, the bare name), never the inline one that would lengthen line one under the badge.
func test_a_count_badge_on_a_locked_card_keeps_the_corner_padlock_and_covers_no_letter() -> void:
	var names: PackedStringArray = _display_names()
	for profile: StringName in [&"android_6in", &"android_6in_portrait", &"web_phone_small"]:
		await _open(profile)
		var bad: PackedStringArray = PackedStringArray()
		for count: int in [1, 12]:
			for card: Vector2 in [ItemTile.CARD_DP, ItemTile.CARD_PORTRAIT_DP]:
				var tile: ItemTile = await _lone_tile(card, count)
				for display: String in names:
					tile.set_needs(display)
					await await_idle_frame()
					var tag: String = "%s %s x%d" % [profile, card, count]
					bad.append_array(_problems(tile, display, tag))
		_assert_none(bad, str(profile))


## The padlock inline is tinted like the name; in the corner, or alone, it has the lock colour.
func test_the_padlock_is_tinted_like_the_name_inline_and_the_lock_colour_elsewhere() -> void:
	await _open(&"android_6in")
	var wide: Vector2 = Vector2(120.0, 96.0)
	var tile: ItemTile = await _lone_tile(wide, 0)
	var label: Label = tile.find_child("Word", true, false)
	var lock: Control = tile.find_child("Lock", true, false)
	var lock_color: Color = tile.get_theme_color(&"lock", ItemTile.VARIATION)
	tile.set_needs("Turbine Hall")
	await await_idle_frame()
	assert_bool(label.text != "Turbine Hall").is_true()  # Inline.
	assert_object(lock.modulate).is_equal(label.get_theme_color(&"font_color"))
	tile.show_state(ItemTile.State.LOCKED, 1, 0.0)  # A count: the corner.
	await await_idle_frame()
	assert_str(label.text).is_equal("Turbine Hall")
	assert_object(lock.modulate).is_equal(lock_color)
	tile.show_state(ItemTile.State.LOCKED, 0, 0.0)
	tile.set_needs("")  # Alone: the big padlock.
	await await_idle_frame()
	assert_object(lock.modulate).is_equal(lock_color)


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
	# Inline at the name's start, so the count badge (top right) never covers it.
	var badge: Control = late.find_child("Badge", true, false)
	assert_bool(now.intersects(badge.get_global_rect())).is_false()


## The worded padlock is `LOCK_WORDED_DP` in size (not what a centred lock's old offsets left).
func _assert_worded_lock(tile: ItemTile) -> void:
	var lock: Rect2 = _lock_rect(tile)
	var near: float = UiScale.dp(4.0)
	var edge: float = UiScale.dp(ItemTile.LOCK_WORDED_DP)
	assert_float(lock.size.x).override_failure_message("lock %s" % lock).is_equal_approx(edge, near)
	assert_float(lock.size.y).override_failure_message("lock %s" % lock).is_equal_approx(edge, near)


## A tile made on its own: locked first (a centred padlock), then told what it needs.
func test_a_standalone_tile_locked_before_it_is_told_its_need_has_the_inline_padlock() -> void:
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


func _tile(id: String) -> ItemTile:
	return _sidebar.find_child("Tile_" + id, true, false) as ItemTile


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


## A card on its own, `card_dp` big, locked, with a count of `count`.
func _lone_tile(card_dp: Vector2, count: int) -> ItemTile:
	var holder: Control = Control.new()
	_sidebar.add_child(holder)
	var tile: ItemTile = ItemTile.new()
	tile.setup(0, World.Tab.STRUCTURES, null, 100, "Name")
	tile.set_card(card_dp)
	holder.add_child(tile)
	tile.size = UiScale.dp_vec(card_dp.x, card_dp.y)
	tile.show_state(ItemTile.State.LOCKED, count, 0.0)
	await _settle()
	return tile


func _assert_none(bad: PackedStringArray, what: String) -> void:
	var shown: String = (
		"%s: %d problems, first:\n%s" % [what, bad.size(), "\n".join(bad.slice(0, 6))]
	)
	assert_int(bad.size()).override_failure_message(shown).is_equal(0)


## What is wrong with a locked card that says `display`, read from the label's own layout
## (`get_character_bounds`), not from a copy of the card's math.
func _problems(tile: ItemTile, display: String, tag: String) -> PackedStringArray:
	var bad: PackedStringArray = PackedStringArray()
	var label: Label = tile.find_child("Word", true, false)
	var stage: Control = tile.find_child("Stage", true, false)
	var badge: Control = tile.find_child("Badge", true, false)
	var why: String = "%s %s" % [tag, display]
	var text: String = label.text
	var lines: int = label.get_line_count()
	if tile.word() != display or not text.ends_with(display):
		bad.append("%s: text '%s'" % [why, text])
	if lines > 2 or label.get_visible_line_count() != lines:
		bad.append("%s: %d lines, %d visible" % [why, lines, label.get_visible_line_count()])
	if label.get_minimum_size().y > stage.size.y + 0.5:
		bad.append("%s: %s high in a stage of %s" % [why, label.get_minimum_size().y, stage.size.y])
	if not stage.get_global_rect().grow(1.0).encloses(label.get_global_rect()):
		bad.append("%s: the label leaves the stage" % why)
	var start: int = text.length() - display.length()
	var origin: Vector2 = label.get_global_rect().position
	var top: Rect2 = label.get_character_bounds(0)
	var cut: bool = false  # A word is cut when two of its letters stand on different lines.
	var word_y: float = -1.0
	for index: int in display.length():
		if display[index] == " ":
			word_y = -1.0
			continue
		var y: float = label.get_character_bounds(start + index).position.y
		if word_y >= 0.0 and absf(y - word_y) > 1.0:
			cut = true
		word_y = y
	if cut:
		bad.append("%s: a word is cut" % why)
	var lock: Rect2 = (tile.find_child("Lock", true, false) as Control).get_global_rect()
	var inline: bool = start > 0
	if inline:
		var first: Rect2 = label.get_character_bounds(start)
		var line: Rect2 = Rect2(origin + top.position, top.size)
		var same: Array[float] = []
		var end: int = display.find(" ")
		end = display.length() if end < 0 else end
		for index: int in [start, start + end - 1]:
			same.append(label.get_character_bounds(index).position.y)
		if badge.visible:
			bad.append("%s: inline with a count showing" % why)
		if absf(same[0] - top.position.y) > 1.0 or absf(same[1] - top.position.y) > 1.0:
			bad.append("%s: the name's first word is not on the padlock's line" % why)
		var gap: float = origin.x + first.position.x - lock.end.x
		if (
			gap < UiScale.dp(ItemTile.LOCK_GAP_DP) - 0.5
			or gap > UiScale.dp(ItemTile.LOCK_GAP_DP) + 0.5
		):
			bad.append("%s: the gap to the first glyph is %s" % [why, gap])
		if absf(lock.get_center().y - line.get_center().y) > 1.0:
			bad.append(
				(
					"%s: padlock centre %s, line centre %s"
					% [why, lock.get_center().y, line.get_center().y]
				)
			)
		if lock.position.x < line.position.x - 0.5:
			bad.append("%s: the padlock is left of the line" % why)
	else:
		var at: Vector2 = lock.position - stage.get_global_rect().position
		var near: float = UiScale.dp(4.0)
		if absf(at.x) > near or absf(at.y) > near:
			bad.append("%s: the corner padlock is at %s" % [why, at])
	return bad


## Every profile, sideways and upright, so the floor is checked at every scale the game meets.
static func _floor_profiles() -> Array[StringName]:
	var names: Array[StringName] = []
	names.append_array(UiProfiles.all().keys())
	names.append_array(UiProfiles.portrait().keys())
	return names
