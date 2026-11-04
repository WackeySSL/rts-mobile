extends GdUnitTestSuite
## The command bar's chips (plan P122c, ADR 0025 section 9): one chip per selected type while they
## fit in the bar's room, then a "+N" chip for the rest (the fit rule of the old SelectionPanel),
## and an enemy building's chip in the amber frame with a notch in its top edge. The freeze of
## section 1 holds while the selection changes during placement.
## Player 1 has a Deep Bore (id 1, an own building), a light tank (2), a rifle squad (4), a heavy
## tank (5), a rocket squad (6) and a harvester (7); the enemy Headquarters is id 3.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const PlacementRig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BORE: int = 1
const TANK: int = 2
const ENEMY_HQ: int = 3
const RIFLE: int = 4
const HEAVY: int = 5
const ROCKET: int = 6
const HARVESTER: int = 7
const SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6],
	[1, "light_tank", 14, 14],
	[2, "renew_hq", 20, 20],
	[1, "rifle_squad", 15, 15],
	[1, "heavy_tank", 17, 14],
	[1, "rocket_squad", 18, 17],
	[1, "harvester", 12, 18],
]
## Five own unit types, in the order a selection of the first n holds them.
const TYPES: Array[int] = [TANK, RIFLE, HEAVY, ROCKET, HARVESTER]
const AMBER: Color = Color("F5A524")  ## The enemy health bar's colour (HealthBarLayer.enemy_color).
const TOLERANCE_PX: float = 0.5
const FROZEN: Array[String] = ["BuildButton", "StrikeControls"]
## The narrowest web phones, held sideways and upright.
const NARROW: Array[StringName] = [&"web_phone_small", &"web_phone_portrait"]

var _window_size_before: Vector2i
var _main: Node2D
var _placement: PlacementController
var _controller: PlayerController
var _bar: CommandBar
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func before_test() -> void:
	MenuRig.begin()


## 1, 2, 3 and 5 types: the chips that fit show, then "+N" counts the types left out; no chip is
## cut by the bar, and one more chip would not have fitted.
func test_the_chips_that_fit_then_plus_n_at_the_narrowest_phones_in_both_orientations() -> void:
	var left_out_seen: bool = false
	for profile: StringName in NARROW:
		await _open(UiProfiles.by_name(profile))
		for types: int in [1, 2, 3, 5]:
			await _select(TYPES.slice(0, types))
			var why: String = "%s, %d types" % [profile, types]
			var shown: int = _shown_chips()
			assert_int(shown).override_failure_message(why).is_between(1, types)
			var more: Control = _bar.find_child("More", true, false) as Control
			assert_bool(more.visible).override_failure_message(why).is_equal(shown < types)
			if shown < types:
				left_out_seen = true
				var number: Label = more.get_child(0) as Label
				assert_str(number.text).override_failure_message(why).is_equal(
					"+%d" % (types - shown)
				)
			_assert_nothing_cut(why)
			_assert_none_would_fit(why, shown, types)
	assert_bool(left_out_seen).override_failure_message("no case needed a +N chip").is_true()


## Where the room is wide, every type has its chip and there is no "+N".
func test_every_type_has_a_chip_where_the_bar_has_room() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	await _select(TYPES.slice(0, 2))
	assert_int(_shown_chips()).is_equal(2)
	assert_bool((_bar.find_child("More", true, false) as Control).visible).is_false()
	await _select([])
	assert_int(_shown_chips()).is_equal(0)


## Each shown chip is one type of the selection, in the order first seen, with its own count.
func test_each_chip_holds_one_type_with_its_count() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	await _select([RIFLE, TANK])
	assert_str(_chip(0).label.text).is_equal("×1")
	assert_str(_chip(1).label.text).is_equal("×1")
	assert_object(_chip(0).card.texture).is_not_null()
	assert_bool(_chip(0).type != _chip(1).type).is_true()
	var types: Array[String] = [str(_chip(0).type), str(_chip(1).type)]
	types.sort()
	assert_array(types).is_equal(["light_tank", "rifle_squad"])


## An enemy building's chip wears the amber frame and a notch in its top edge; an own building's
## and a unit's do not.
func test_an_enemy_building_shows_the_amber_frame_and_notch_and_an_own_one_does_not() -> void:
	for profile: StringName in NARROW + [&"android_6in"]:
		await _open(UiProfiles.by_name(profile))
		await _select([ENEMY_HQ])
		var why: String = str(profile)
		var chip: CommandBar.Chip = _chip(0)
		assert_str(str(chip.theme_type_variation)).override_failure_message(why).is_equal(
			str(CommandBar.ENEMY_CHIP)
		)
		var frame: StyleBoxFlat = chip.get_theme_stylebox(&"panel") as StyleBoxFlat
		assert_that(frame.border_color).override_failure_message(why).is_equal(AMBER)
		assert_int(frame.border_width_top).override_failure_message(why).is_greater(0)
		var notch: Rect2 = chip.notch_rect()
		assert_float(notch.position.y).override_failure_message(why).is_equal(0.0)
		assert_float(notch.size.x).override_failure_message(why).is_greater(0.0)
		assert_float(notch.size.y).override_failure_message(why).is_greater_equal(
			float(frame.border_width_top)
		)
		(
			assert_bool(Rect2(Vector2.ZERO, chip.size).encloses(notch))
			. override_failure_message(why)
			. is_true()
		)
		assert_float(notch.get_center().x).override_failure_message(why).is_equal_approx(
			chip.size.x / 2.0, 1.0
		)
		var cut: Color = chip.get_theme_color(&"notch")
		assert_float(cut.a).override_failure_message(why).is_equal(1.0)
		assert_bool(cut != AMBER).override_failure_message(why).is_true()
		for ids: Array in [[BORE], [TANK], [TANK, RIFLE]]:
			await _select(ids)
			var plain: CommandBar.Chip = _chip(0)
			var own: String = "%s %s" % [why, ids]
			assert_str(str(plain.theme_type_variation)).override_failure_message(own).is_equal(
				str(CommandBar.CHIP)
			)
			assert_that(plain.notch_rect()).override_failure_message(own).is_equal(Rect2())
			var box: StyleBoxFlat = plain.get_theme_stylebox(&"panel") as StyleBoxFlat
			assert_int(box.border_width_top).override_failure_message(own).is_equal(0)


## The frame costs the chip no room: the enemy box has the backdrop's content margins and colour.
func test_the_amber_frame_adds_no_size_to_the_chip() -> void:
	await _open(UiProfiles.by_name(&"web_phone_small"))
	var plain: StyleBoxFlat = _chip_box(CommandBar.CHIP)
	var framed: StyleBoxFlat = _chip_box(CommandBar.ENEMY_CHIP)
	assert_that(framed.get_minimum_size()).is_equal(plain.get_minimum_size())
	assert_that(framed.bg_color).is_equal(plain.bg_color)


## An enemy building the fog hides keeps its frame but shows no health; seen, it shows both.
func test_a_fogged_enemy_building_shows_no_health_and_keeps_its_frame() -> void:
	await _open(UiProfiles.by_name(&"web_phone_small"))
	await _select([ENEMY_HQ])
	var fog: FogGrid = _main.get_node("MatchRunner").snapshot.fog
	for seen: bool in [true, false]:
		for cell: int in fog.cells:
			fog.visible[cell] = 1 if seen else 0
		_bar._fill(_controller.selection.selected)
		var why: String = "seen %s" % seen
		assert_bool(_chip(0).health.visible).override_failure_message(why).is_equal(seen)
		assert_str(str(_chip(0).theme_type_variation)).override_failure_message(why).is_equal(
			str(CommandBar.ENEMY_CHIP)
		)


## Placement keeps the slot: a selection that grows from one type to five and shrinks again moves
## neither BUILD, the strike button nor the group column, and the bar holds its place.
func test_the_freeze_holds_while_the_selection_changes_during_placement() -> void:
	for profile: StringName in [&"android_6in", &"web_phone_small", &"web_phone_portrait"]:
		await _open(UiProfiles.by_name(profile))
		await _select([TANK])
		_make_ready()
		var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
		assert_bool(_placement.begin(PlacementRig.plant(snap))).is_true()
		await await_idle_frame()
		await await_idle_frame()
		var before: Dictionary[String, Rect2] = _frozen_rects()
		var column: Vector2 = _column_anchor()
		var origin: Vector2 = _bar.get_global_rect().position
		for ids: Array in [TYPES, [ENEMY_HQ], [TANK, RIFLE], TYPES.slice(0, 3), [TANK]]:
			await _select(ids)
			var why: String = "%s, %d ids" % [profile, ids.size()]
			assert_bool(_bar.has_slot()).override_failure_message(why).is_true()
			assert_that(_frozen_rects()).override_failure_message(why).is_equal(before)
			assert_that(_column_anchor()).override_failure_message(why).is_equal(column)
			var at: Vector2 = _bar.get_global_rect().position
			assert_float(at.y).override_failure_message(why).is_equal_approx(origin.y, 1.5)
			assert_float(at.x).override_failure_message(why).is_equal_approx(origin.x, 1.5)
		assert_array(_sent).is_empty()


## The shown chips and "+N" lie inside the bar, and the row asks no more than the bar's room.
func _assert_nothing_cut(why: String) -> void:
	var bar: Rect2 = _bar.get_global_rect()
	for chip: Control in _shown_controls():
		var cut: String = "%s: %s %s in %s" % [why, chip.name, chip.get_global_rect(), bar]
		(
			assert_bool(bar.grow(TOLERANCE_PX).encloses(chip.get_global_rect()))
			. override_failure_message(cut)
			. is_true()
		)
		assert_float(chip.size.x).override_failure_message(cut).is_greater_equal(
			chip.get_combined_minimum_size().x - TOLERANCE_PX
		)
	assert_float(_room()).override_failure_message(why + ": row against room").is_greater_equal(
		_row_ask() - TOLERANCE_PX
	)


## One more chip would not have fitted in the room (the rule shows as many as fit).
func _assert_none_would_fit(why: String, shown: int, types: int) -> void:
	if shown >= types:
		return
	var more: Control = _bar.find_child("More", true, false) as Control
	var gap: float = roundf(UiScale.dp(HudCorners.GAP_DP))
	var ask: float = _row_ask() + gap + _chip(shown).get_combined_minimum_size().x
	if shown + 1 == types:  # The last chip takes the place of "+N".
		ask -= gap + more.get_combined_minimum_size().x
	assert_float(ask).override_failure_message(why + ": another chip").is_greater(_room())


## What the row asks for: Deselect, the shown chips, "+N" and the gaps, and the orders.
func _row_ask() -> float:
	var row: Control = _bar.get_node("Row")
	var orders: Control = _bar.find_child("Orders", true, false).get_child(0)
	return row.get_combined_minimum_size().x + orders.get_combined_minimum_size().x


## The room the bar may take at the most.
func _room() -> float:
	var rects: Dictionary[StringName, Rect2] = _bar._rects(true)
	return rects[HudCorners.BAR].size.x


func _shown_controls() -> Array[Control]:
	var out: Array[Control] = []
	for index: int in _bar._types:
		if _chip(index).visible:
			out.append(_chip(index))
	var more: Control = _bar.find_child("More", true, false) as Control
	if more.visible:
		out.append(more)
	return out


func _shown_chips() -> int:
	var count: int = 0
	for index: int in _bar._types:
		count += 1 if _chip(index).visible else 0
	return count


func _chip(index: int) -> CommandBar.Chip:
	return _bar._chips[index]


## The box the theme gives a chip of `variation`, scaled as the HUD's theme is at this dp.
func _chip_box(variation: StringName) -> StyleBoxFlat:
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = variation
	_bar.add_child(chip)
	var box: StyleBoxFlat = chip.get_theme_stylebox(&"panel") as StyleBoxFlat
	chip.free()
	return box


func _frozen_rects() -> Dictionary[String, Rect2]:
	var out: Dictionary[String, Rect2] = {}
	for node_name: String in FROZEN:
		var node: Control = _hud(node_name) as Control
		if node != null and node.is_visible_in_tree():
			out[node_name] = node.get_global_rect()
	return out


## The group column's fixed corner: its start sideways (it grows downwards with its items), its
## foot upright (it grows upwards from the bar). Its size follows the selection (the "+" item).
func _column_anchor() -> Vector2:
	var rect: Rect2 = (_hud("GroupColumn") as Control).get_global_rect()
	return Vector2(rect.position.x, rect.end.y if HudLayout.is_portrait() else rect.position.y)


func _make_ready() -> void:
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	PlacementRig.make_ready(snap)
	snap.tick += 1
	(_hud("BuildButton") as BuildButton).refresh(snap)


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()  # The bar publishes its slot on a deferred call, then places.
	await await_idle_frame()
	await await_idle_frame()


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## A new scene under `metrics`, its match paused, the Commands caught.
func _open(metrics: UiMetrics) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var scenario: ScenarioDef = Rig.scenario(spawns)
	for unit: String in ["power_plant", "barracks"]:
		scenario.roster.append(load("res://data/units/%s.tres" % unit) as UnitDef)
	(_main.get_node("MatchRunner") as MatchRunner).scenario = scenario
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_placement = _main.get_node("PlacementController")
	_controller = _main.get_node("PlayerController")
	_bar = _hud("CommandBar") as CommandBar
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	await await_idle_frame()
