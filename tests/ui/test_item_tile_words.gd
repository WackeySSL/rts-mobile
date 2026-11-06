extends GdUnitTestSuite
## The card words and the sash (plan P120b, P120j, ADR 0025 section 5), in the main scene: a locked
## card is crossed by a band with the missing building's name in one line, never cut or wrapped,
## clear of the padlock seal and the count badge, with its price hidden; a full queue's card says
## "FULL". Every other state is as it was.

const DisplayNames: GDScript = preload("res://tests/ui/support/display_names.gd")
const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]
const NEAR_PX: float = 1.5
const CAP_SHARE: float = 0.7  ## Chakra Petch's capitals, as a share of the font size.

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


## The sash fits the card at every profile, both ways up, for every name a locked card can show: one
## line (a name is never wrapped or cut), the whole tilted box inside the stage, clear of the seal
## and of the count badge, the price hidden and the caption still there.
func test_the_sash_holds_every_requirement_name_in_one_line_clear_of_the_seal_and_badge() -> void:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	var needed: Dictionary[String, String] = DisplayNames.requirements()
	for profile: StringName in profiles:
		await _open(profile)
		var world: World = Sw.world()
		Sw.own(world, ["headquarters"])
		await _publish(world)
		var tile: ItemTile = _tile("vehicle_factory")
		assert_int(tile.state).is_equal(ItemTile.State.LOCKED)
		tile.show_state(ItemTile.State.LOCKED, 2, 0.0)  # A count shows: the badge is on.
		for id: String in needed:
			tile.set_needs(needed[id])
			await await_idle_frame()
			var why: String = "%s: %s on %s" % [profile, needed[id], tile.get_global_rect()]
			assert_str(tile.word()).override_failure_message(why).is_equal(needed[id])
			_assert_sash_fits(tile, why)
		assert_bool(_part(tile, "Cost").visible).is_false()
		assert_bool(_part(tile, "Caption").visible).is_true()


## One tile's sash: read from the nodes, the way it is drawn.
func _assert_sash_fits(tile: ItemTile, why: String) -> void:
	var label: Label = _part(tile, "SashText") as Label
	var stage: Rect2 = _part(tile, "Stage").get_global_rect().grow(NEAR_PX)
	assert_bool(_part(tile, "Sash").visible).override_failure_message(why).is_true()
	assert_int(label.get_line_count()).override_failure_message(why).is_equal(1)
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)
	assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	var font: Font = label.get_theme_font(&"font")
	var wide: float = (
		font
		. get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size(&"font_size")
		)
		. x
	)
	var room: float = ItemTile.sash_room_px(tile.size)
	why += " [label %s, sash %s, tile %s]" % [label.size, _part(tile, "Sash").size, tile.size]
	assert_float(label.size.x).override_failure_message(why).is_equal_approx(room, NEAR_PX)
	assert_float(wide).override_failure_message("%s: %s of %s" % [why, wide, room]).is_less_equal(
		room
	)
	var box: PackedVector2Array = _tilted(label)
	for corner: Vector2 in box:
		assert_bool(stage.has_point(corner)).override_failure_message(why + str(box)).is_true()
	var lock: Rect2 = _lock_rect(tile)
	var seal: Rect2 = _seal_rect(tile)
	assert_bool(seal.grow(NEAR_PX).encloses(lock)).override_failure_message(why).is_true()
	assert_bool(_overlaps(box, seal)).override_failure_message(why + " seal").is_false()
	var badge: Control = _part(tile, "Badge")
	if badge.visible:  # The glyphs (width, cap height) stay clear of the count, to a hairline.
		var cap: float = CAP_SHARE * label.get_theme_font_size(&"font_size")
		var glyphs: Rect2 = Rect2((label.size - Vector2(wide, cap)) / 2.0, Vector2(wide, cap))
		var turn: Transform2D = label.get_global_transform()
		var ink: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in [
			glyphs.position,
			Vector2(glyphs.end.x, glyphs.position.y),
			glyphs.end,
			Vector2(glyphs.position.x, glyphs.end.y)
		]:
			ink.append(turn * corner)
		(
			assert_bool(_overlaps(ink, badge.get_global_rect().grow(-2.0 * NEAR_PX)))
			. override_failure_message("%s badge %s ink %s" % [why, badge.get_global_rect(), ink])
			. is_false()
		)


## The sash stands apart from every other state: only a LOCKED card that knows its need has it, and
## then the price is hidden (a READY card hides it too); all others keep price, and no band.
func test_only_a_named_lock_has_the_sash_and_hides_the_price() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	await _publish(world)
	var tile: ItemTile = _tile("barracks")
	tile.set_needs("Turbine Hall")  # A name set on a card that is not locked changes nothing.
	for state: int in [
		ItemTile.State.AVAILABLE,
		ItemTile.State.UNAFFORDABLE,
		ItemTile.State.FULL,
		ItemTile.State.READY
	]:
		tile.show_state(state, 1, 0.0)
		await _settle()
		var why: String = "state %d" % state
		assert_bool(_part(tile, "Sash").visible).override_failure_message(why).is_false()
		assert_bool(_part(tile, "Cost").visible).override_failure_message(why).is_equal(
			state != ItemTile.State.READY
		)
	tile.show_state(ItemTile.State.LOCKED, 0, 0.0)
	await _settle()
	assert_bool(_part(tile, "Sash").visible).is_true()
	assert_bool(_part(tile, "Cost").visible).is_false()
	tile.set_needs("")  # A lock with no name known keeps the big padlock in the middle.
	await _settle()
	assert_bool(_part(tile, "Sash").visible).is_false()
	assert_bool(_part(tile, "Lock").visible).is_true()
	assert_float(_lock_rect(tile).size.x).is_equal_approx(UiScale.dp(ItemTile.LOCK_DP), NEAR_PX)


## The band rises to the right at 27 degrees and crosses the card edge to edge: the name is turned
## by that angle, and the stage clips the band to the card.
func test_the_band_rises_across_the_card() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, ["headquarters"])
	await _publish(world)
	var tile: ItemTile = _tile("vehicle_factory")
	var label: Label = _part(tile, "SashText") as Label
	assert_float(label.rotation).is_equal_approx(-deg_to_rad(27.0), 0.001)
	assert_bool((_part(tile, "Stage") as Control).clip_contents).is_true()
	var box: PackedVector2Array = _tilted(label)
	var tile_rect: Rect2 = tile.get_global_rect()
	var sides: Array[float] = [box[0].x, box[1].x, box[2].x, box[3].x]
	assert_float(sides.min() - tile_rect.position.x).is_less(UiScale.dp(4.0))
	assert_float(tile_rect.end.x - sides.max()).is_less(UiScale.dp(4.0))


## A turn of the phone or a new size lays the sash out again: the room, the name's place and the
## seal follow the card.
func test_the_sash_follows_a_turn_and_a_resize() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, ["headquarters"])
	await _publish(world)
	var tile: ItemTile = _tile("vehicle_factory")
	tile.set_needs("Turbine Hall")
	await _settle()
	var before_room: float = (_part(tile, "SashText") as Label).size.x
	for target: StringName in [&"android_6in_portrait", &"web_tablet", &"desktop"]:
		var metrics: UiMetrics = UiProfiles.by_name(target)
		UiScale.set_override(metrics)
		get_window().size = metrics.window_size
		await _settle()
		await _settle()
		tile = _tile("vehicle_factory")
		var why: String = "after the change to %s" % target
		assert_bool(tile.is_inside_tree()).is_true()
		_assert_sash_fits(tile, why)
		(
			assert_float((_part(tile, "SashText") as Label).size.x)
			. override_failure_message(why)
			. is_equal_approx(ItemTile.sash_room_px(tile.size), NEAR_PX)
		)
	assert_float(before_room).is_greater(0.0)


## The theme refits the sash: a new dp factor changes the room, the font and the seal at once, and
## the name still stands in one line.
func test_the_sash_follows_a_theme_refit() -> void:
	await _open(&"android_6in")
	var holder: Control = Control.new()
	_sidebar.add_child(holder)
	var tile: ItemTile = ItemTile.new()
	tile.setup(0, World.Tab.STRUCTURES, null, 100, "Name")
	tile.set_card(ItemTile.CARD_DP)
	holder.add_child(tile)
	tile.show_state(ItemTile.State.LOCKED, 0, 0.0)
	tile.set_needs("Turbine Hall")
	for factor: float in [1.0, 2.0, 1.25]:
		var theme: Theme = HudTheme.scaled(HudThemes.source(), factor)
		holder.theme = theme
		tile.size = Vector2(ItemTile.CARD_DP.x, ItemTile.CARD_DP.y) * factor
		await _settle()
		var label: Label = _part(tile, "SashText") as Label
		var why: String = "factor %s: label %s" % [factor, label.size]
		assert_int(label.get_theme_font_size(&"font_size")).override_failure_message(why).is_equal(
			roundi(14.0 * factor)
		)
		assert_float(label.size.x).override_failure_message(why).is_equal_approx(
			ItemTile.sash_room_px(tile.size), NEAR_PX
		)
		assert_int(label.get_line_count()).override_failure_message(why).is_equal(1)
	holder.queue_free()


## The seal stands where the card's history does not matter: a card locked after its first layout
## has the seal of a card locked from the start, in the stage's top left corner and clear of the
## count badge's corner.
func test_the_seal_is_in_the_same_place_however_the_card_came_to_be_locked() -> void:
	var held: Array[String] = ["headquarters", "power_plant", "barracks"]
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, held)  # No refinery: the vehicle factory is locked from the start.
	await _publish(world)
	var start: ItemTile = _tile("vehicle_factory")
	assert_int(start.state).is_equal(ItemTile.State.LOCKED)
	var plan: Rect2 = _lock_rect(start)
	var plan_at: Vector2 = plan.position - start.get_global_rect().position
	_assert_seal(start)
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
	_assert_seal(late)
	assert_float(now_at.x).is_equal_approx(plan_at.x, 0.5)
	assert_float(now_at.y).is_equal_approx(plan_at.y, 0.5)
	assert_float(now.size.x).is_equal_approx(plan.size.x, 0.5)


## The padlock is `SEAL_GLYPH_DP` in size and in the middle of the seal's disc.
func _assert_seal(tile: ItemTile) -> void:
	var lock: Rect2 = _lock_rect(tile)
	var seal: Rect2 = _seal_rect(tile)
	var edge: float = UiScale.dp(ItemTile.SEAL_GLYPH_DP)
	assert_float(lock.size.x).override_failure_message("lock %s" % lock).is_equal_approx(
		edge, NEAR_PX
	)
	var off: Vector2 = lock.get_center() - seal.get_center()
	assert_float(off.length()).override_failure_message("lock %s seal %s" % [lock, seal]).is_less(
		NEAR_PX
	)


## A tile made on its own: locked first (a big centred padlock), then told what it needs.
func test_a_standalone_tile_locked_before_it_is_told_its_need_has_the_seal() -> void:
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
	assert_float(_lock_rect(tile).size.x).is_equal_approx(UiScale.dp(ItemTile.LOCK_DP), NEAR_PX)
	tile.set_needs("Turbine Hall")
	await _settle()
	_assert_seal(tile)
	_assert_sash_fits(tile, "standalone")
	holder.queue_free()


## The floor card (88 dp) holds Turbine Hall's width in one line: the room is at least 83 dp.
func test_the_sash_room_at_the_floor_card_is_at_least_83_dp() -> void:
	for profile_name: StringName in UiProfiles.all():
		UiScale.set_override(UiProfiles.by_name(profile_name))
		var card: Vector2 = UiScale.dp_vec(ItemTile.CARD_DP.x, ItemTile.CARD_DP.y)
		var room_dp: float = ItemTile.sash_room_px(card) / UiScale.dp(1.0)
		assert_float(room_dp).override_failure_message(str(profile_name)).is_greater_equal(83.0)
		var wide: Vector2 = UiScale.dp_vec(ItemTile.CARD_PORTRAIT_DP.x, ItemTile.CARD_PORTRAIT_DP.y)
		assert_float(ItemTile.sash_room_px(wide)).is_greater(ItemTile.sash_room_px(card))


func _part(node: Node, part: String) -> Control:
	return node.find_child(part, true, false) as Control


## The tilted box of the name's label in global coordinates, corner by corner.
func _tilted(label: Label) -> PackedVector2Array:
	var turn: Transform2D = label.get_global_transform()
	var box: Vector2 = label.size
	return PackedVector2Array(
		[turn * Vector2.ZERO, turn * Vector2(box.x, 0.0), turn * box, turn * Vector2(0.0, box.y)]
	)


func _overlaps(polygon: PackedVector2Array, rect: Rect2) -> bool:
	var corners: PackedVector2Array = PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]
	)
	return not Geometry2D.intersect_polygons(polygon, corners).is_empty()


## The seal's disc in global coordinates.
func _seal_rect(tile: ItemTile) -> Rect2:
	var stage: Rect2 = _part(tile, "Stage").get_global_rect()
	var edge: float = UiScale.dp(ItemTile.SEAL_DP)
	var inset: float = UiScale.dp(ItemTile.SEAL_INSET_DP)
	return Rect2(stage.position + Vector2(inset, inset), Vector2(edge, edge))


func _lock_rect(tile: ItemTile) -> Rect2:
	return _part(tile, "Lock").get_global_rect()


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
