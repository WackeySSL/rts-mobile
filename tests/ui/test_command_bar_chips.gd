extends GdUnitTestSuite
## The command bar's chips (plan P122c, ADR 0025 section 9): one chip per selected type while they
## fit in the bar's room, then a "+N" chip for the rest (the fit rule of the old SelectionPanel),
## and an enemy building's chip in P115b's look (amber corner brackets round its picture, an amber
## health bar with a notch). The freeze of section 1 holds while the selection changes during
## placement and the strike aim, the bar's width included.
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
const TOLERANCE_PX: float = 0.5
const FROZEN: Array[String] = ["BuildButton", "StrikeControls"]
## The narrowest web phones, held sideways and upright.
const NARROW: Array[StringName] = [&"web_phone_small", &"web_phone_portrait"]

var _window_size_before: Vector2i
var _main: Node2D
var _placement: PlacementController
var _aim: StrikeAim
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
## cut by the bar, one more chip would not have fitted, and the row runs Deselect, the chips in
## selection order, "+N", the orders: plain and mirrored.
func test_the_chips_that_fit_then_plus_n_at_the_narrowest_phones_in_both_orientations() -> void:
	for profile: StringName in [&"web_phone_portrait"]:  # Sideways every type fits: see below.
		await _open(UiProfiles.by_name(profile))
		var left_out_seen: bool = false
		for types: int in [1, 2, 3, 5]:
			await _select(TYPES.slice(0, types))
			var why: String = "%s, %d types" % [profile, types]
			left_out_seen = _assert_fit(why, types) or left_out_seen
			_assert_order(why, false)
		_bar.mirror = true
		_bar.place()
		await await_idle_frame()
		await await_idle_frame()
		_assert_order("%s mirrored" % profile, true)
		assert_bool(left_out_seen).override_failure_message(str(profile) + ": no +N").is_true()
	await _open(UiProfiles.by_name(&"web_phone_small"))
	for types: int in [1, 2, 3, 5]:
		await _select(TYPES.slice(0, types))
		_assert_fit("web_phone_small, %d types" % types, types)
		_assert_order("web_phone_small, %d types" % types, false)
	_bar.mirror = true
	_bar.place()
	await await_idle_frame()
	await await_idle_frame()
	_assert_order("web_phone_small mirrored", true)


## The room shrinks under a selection that filled it (the Ready chip, the open drawer, the phone
## turned): the chips are fitted again, "+N" counts the rest, and Stop stays.
func test_the_chips_are_fitted_again_when_the_room_shrinks() -> void:
	await _open(UiProfiles.by_name(&"web_phone_small"))
	await _select(TYPES)
	assert_int(_shown_chips()).is_equal(5)  # Sideways, five fit.
	assert_bool(_more().visible).is_false()
	_make_ready()  # The Ready chip takes room beside BUILD.
	await await_idle_frame()
	await await_idle_frame()
	var after_ready: int = _shown_chips()
	assert_int(after_ready).is_less(5)
	assert_bool(_assert_fit("ready chip", 5)).is_true()
	_assert_stop_inside("ready chip")
	(_hud("BuildSidebar") as BuildSidebar).open()  # The drawer takes more.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_shown_chips()).is_less_equal(after_ready)
	assert_bool(_assert_fit("drawer", 5)).is_true()
	_assert_stop_inside("drawer")
	(_hud("BuildSidebar") as BuildSidebar).collapse()
	await _turn(UiProfiles.portrait()[&"web_phone_portrait"])  # Turned upright: narrower again.
	assert_int(_shown_chips()).is_less(5)
	assert_bool(_assert_fit("turned", 5)).is_true()
	_assert_stop_inside("turned")


## The selection shrinking hides every chip it no longer needs, and "+N" with them.
func test_a_smaller_selection_leaves_no_stale_chip_or_plus_n() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	for count: int in [5, 2, 1]:
		await _select(TYPES.slice(0, count))
		assert_int(_shown_chips()).override_failure_message("%d types" % count).is_equal(count)
		assert_bool(_more().visible).is_false()
	await _select([])
	assert_int(_shown_chips()).is_equal(0)
	assert_bool(_more().visible).is_false()
	await _open(UiProfiles.portrait()[&"web_phone_portrait"])
	await _select(TYPES)
	assert_bool(_more().visible).is_true()
	await _select([TANK])
	assert_int(_shown_chips()).is_equal(1)
	assert_bool(_more().visible).is_false()


## Each shown chip is one type of the selection in selection order, with its own count and its
## own health (not the selection's).
func test_each_chip_holds_one_type_with_its_count_and_its_own_health() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	await _select([RIFLE, TANK, HEAVY])
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	var damage: Dictionary[int, float] = {TANK: 0.25, RIFLE: 0.5}
	for id: int in damage:
		var row: int = snap.index_of(id)
		snap.hp[row] = roundi(snap.type_max_hp[snap.type_index[row]] * damage[id])
	_bar._fill(_controller.selection.selected)
	var ids: PackedInt32Array = _controller.selection.selected
	for index: int in ids.size():
		var chip: CommandBar.Chip = _chip(index)
		var row: int = snap.index_of(ids[index])
		assert_str(str(chip.type)).is_equal(str(snap.type_ids[snap.type_index[row]]))
		assert_str(chip.label.text).is_equal("×1")
		assert_object(chip.card.texture).is_not_null()
		var ratio: float = chip.health.value / chip.health.max_value
		assert_float(ratio).override_failure_message("chip %d" % index).is_equal_approx(
			damage.get(ids[index], 1.0), 0.05
		)
	assert_str(str(_chip(0).type)).is_equal("light_tank")  # Selection order: id 2 before 4.
	assert_str(str(_chip(1).type)).is_equal("rifle_squad")


## An enemy building's chip is P115b's look: amber corner brackets round its picture and an amber
## health bar with a notch; the colours are those of the map's enemy bars. An own building's and a
## unit's chip has neither, and the look costs no size.
func test_an_enemy_building_shows_amber_brackets_and_a_notched_amber_bar() -> void:
	for profile: StringName in NARROW + [&"android_6in"]:
		await _open(UiProfiles.by_name(profile))
		var bars: HealthBarLayer = _main.find_child("HealthBarLayer", true, false) as HealthBarLayer
		await _select([ENEMY_HQ])
		var why: String = str(profile)
		var chip: CommandBar.Chip = _chip(0)
		var dp: float = UiScale.base_px_per_dp()
		var rects: Array[Rect2] = chip.frame_rects()
		assert_int(rects.size()).override_failure_message(why).is_equal(16)
		var card: Rect2 = Rect2(Vector2.ZERO, chip.card.size)  # The frame is in card coordinates.
		assert_float(chip.card.size.x).override_failure_message(why).is_equal_approx(
			UiScale.dp(CommandBar.CARD_DP), TOLERANCE_PX
		)
		assert_float(chip.card.size.y).override_failure_message(why).is_equal_approx(
			UiScale.dp(CommandBar.CARD_DP), TOLERANCE_PX
		)
		# Painted by the card after its picture, not by the chip before its children.
		assert_bool(chip.card.is_connected(&"draw", chip._paint_frame)).is_true()
		assert_bool(chip.has_method(&"_draw")).override_failure_message(why).is_false()
		var outer: Rect2 = card.grow(HealthBarLayer.EDGE_DP * dp + TOLERANCE_PX)
		for index: int in rects.size():
			var out: String = "%s: rect %d %s outside %s" % [why, index, rects[index], outer]
			assert_bool(outer.encloses(rects[index])).override_failure_message(out).is_true()
		# The arms: 2 dp thick, at most 12 dp long, one pair in each corner of the picture.
		var arm: Rect2 = rects[8]
		assert_that(arm.position).override_failure_message(why).is_equal(card.position)
		var last: Rect2 = rects[15]  # The bottom right corner's arm ends at the card's corner.
		assert_that(last.end).override_failure_message(why).is_equal(card.end)
		assert_float(minf(arm.size.x, arm.size.y)).override_failure_message(why).is_equal_approx(
			HealthBarLayer.FRAME_THICK_DP * dp, TOLERANCE_PX
		)
		assert_float(maxf(arm.size.x, arm.size.y)).override_failure_message(why).is_less_equal(
			HealthBarLayer.FRAME_ARM_DP * dp + TOLERANCE_PX
		)
		var corners: Dictionary[Vector2, bool] = {}
		for index: int in range(8, 16):
			var at: Vector2 = rects[index].get_center() - card.get_center()
			corners[Vector2(signf(at.x), signf(at.y))] = true
		assert_int(corners.size()).override_failure_message(why).is_equal(4)
		var amber: Color = chip.get_theme_color(&"enemy", CommandBar.FRAME)
		assert_bool(amber.is_equal_approx(bars.enemy_color)).override_failure_message(why).is_true()
		var dark: Color = chip.get_theme_color(&"edge", CommandBar.FRAME)
		assert_bool(dark.is_equal_approx(bars.edge_color)).override_failure_message(why).is_true()
		# The health bar: amber, with the notch of the enemy bar in its top edge.
		var bar: CommandBar.HealthBar = chip.health
		assert_str(str(bar.theme_type_variation)).override_failure_message(why).is_equal(
			str(CommandBar.ENEMY_BAR)
		)
		var fill: StyleBoxFlat = bar.get_theme_stylebox(&"fill") as StyleBoxFlat
		assert_that(fill.bg_color).override_failure_message(why).is_equal(bars.enemy_color)
		var notch: Rect2 = bar.notch_rect()
		assert_float(notch.size.x).is_equal_approx(HealthBarLayer.NOTCH_WIDTH_DP * dp, 0.01)
		assert_float(notch.size.y).is_equal_approx(HealthBarLayer.NOTCH_DEPTH_DP * dp, 0.01)
		assert_float(notch.position.y).is_equal(0.0)
		assert_float(notch.get_center().x).is_equal_approx(bar.size.x / 2.0, 1.0)
		assert_bool(Rect2(Vector2.ZERO, bar.size).encloses(notch)).is_true()
		# No size: the same chip without the look asks the same.
		var asks: Vector2 = chip.get_combined_minimum_size()
		chip.enemy = false
		chip.health.set_enemy(false)
		assert_that(chip.get_combined_minimum_size()).override_failure_message(why).is_equal(asks)
		for ids: Array in [[BORE], [TANK], [TANK, RIFLE]]:
			await _select(ids)
			var plain: CommandBar.Chip = _chip(0)
			var own: String = "%s %s" % [why, ids]
			assert_array(plain.frame_rects()).override_failure_message(own).is_empty()
			assert_that(plain.health.notch_rect()).override_failure_message(own).is_equal(Rect2())
			var variation: String = str(plain.health.theme_type_variation)
			assert_str(variation).override_failure_message(own).is_empty()
			var plain_fill: StyleBoxFlat = plain.health.get_theme_stylebox(&"fill") as StyleBoxFlat
			assert_bool(plain_fill == null or plain_fill.bg_color != bars.enemy_color).is_true()


## An enemy building the fog hides keeps its brackets but shows no health; seen, it shows both.
func test_a_fogged_enemy_building_shows_no_health_and_keeps_its_brackets() -> void:
	await _open(UiProfiles.by_name(&"web_phone_small"))
	await _select([ENEMY_HQ])
	var fog: FogGrid = _main.get_node("MatchRunner").snapshot.fog
	for seen: bool in [true, false]:
		for cell: int in fog.cells:
			fog.visible[cell] = 1 if seen else 0
		_bar._fill(_controller.selection.selected)
		var why: String = "seen %s" % seen
		assert_bool(_chip(0).health.visible).override_failure_message(why).is_equal(seen)
		assert_int(_chip(0).frame_rects().size()).override_failure_message(why).is_equal(16)


## Placement keeps the slot and the bar's width: a selection that grows from one type to five and
## shrinks again moves neither BUILD, the strike button, the group column's corner, the bar nor
## the ghost's check mark and X; the extra types go into "+N". After the mode the bar fits again.
func test_the_freeze_holds_while_the_selection_changes_during_placement() -> void:
	for profile: StringName in [&"android_6in", &"web_phone_small", &"web_phone_portrait"]:
		await _open(UiProfiles.by_name(profile))
		await _select([TANK])
		_make_ready()
		var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
		assert_bool(_placement.begin(PlacementRig.plant(snap))).is_true()
		await await_idle_frame()
		await await_idle_frame()
		await _assert_selection_changes_freeze(profile, ["PlaceConfirm", "PlaceCancel"])
		_placement.cancel()
		await await_idle_frame()
		await await_idle_frame()
		await _select(TYPES)
		var why: String = "%s after the mode" % profile
		_assert_fit(why, 5)
		if not HudLayout.is_portrait():  # Sideways the bar grows with the chips again.
			assert_int(_shown_chips()).override_failure_message(why).is_greater(1)


func test_the_freeze_holds_while_the_selection_changes_during_the_strike_aim() -> void:
	for profile: StringName in [&"android_6in", &"web_phone_small", &"web_phone_portrait"]:
		await _open(UiProfiles.by_name(profile))
		await _select([TANK])
		var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
		snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
		_aim.refresh()
		assert_bool(_aim.begin()).is_true()
		await await_idle_frame()
		await await_idle_frame()
		await _assert_selection_changes_freeze(profile, ["StrikeConfirm", "StrikeCancel"])
		_aim.cancel()


## A building was selected before the mode: "All army" adds Stop (and "+N" alone counts the
## types), so the bar widens by Stop and its gap at the most.
func test_a_building_selected_before_the_mode_widens_the_bar_by_stop_at_the_most() -> void:
	for profile: StringName in [&"android_6in", &"web_phone_small"]:
		await _open(UiProfiles.by_name(profile))
		await _select([BORE])
		assert_bool(_bar.order_button(&"stop").is_visible_in_tree()).is_false()
		_make_ready()
		var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
		assert_bool(_placement.begin(PlacementRig.plant(snap))).is_true()
		await await_idle_frame()
		await await_idle_frame()
		var stop: float = _bar.order_button(&"stop").get_combined_minimum_size().x
		var gap: float = roundf(UiScale.dp(HudCorners.GAP_DP))
		await _assert_selection_changes_freeze(profile, ["PlaceConfirm", "PlaceCancel"], stop + gap)
		_placement.cancel()


## The reviewer's run: one tank, placement, the ghost dragged low and left near the bar's end, then
## "All army": the check mark and X stay where they are.
func test_all_army_does_not_move_the_ghosts_check_mark_and_x_next_to_the_bar() -> void:
	await _open(UiProfiles.by_name(&"web_phone_small"))
	await _select([TANK])
	_make_ready()
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	assert_bool(_placement.begin(PlacementRig.plant(snap))).is_true()
	await await_idle_frame()
	var bar: Rect2 = _bar.get_global_rect()
	var dp: float = UiScale.base_px_per_dp()
	var grab: float = _placement.controller.settings.ghost_grab_dp + GhostControls.RING_GAP_DP
	var found: bool = false
	for y: int in range(31, -1, -1):  # Low first.
		for x: int in 32:
			_placement._move_to(Vector2i(x, y))
			var box: Rect2 = _placement.silhouette_rect()
			var column_x: float = box.end.x + grab * dp
			var reaches: bool = box.get_center().y + 72.0 * dp > bar.position.y
			# Its column clear of the bar as it is, but over it if the bar grew a "+N" plate.
			if reaches and column_x >= bar.end.x and column_x < bar.end.x + 30.0 * dp:
				found = true
				break
		if found:
			break
	assert_bool(found).override_failure_message("no tile near the bar's end").is_true()
	await await_idle_frame()
	await await_idle_frame()
	var confirm: Vector2 = (_hud("PlaceConfirm") as Control).global_position
	var cancel: Vector2 = (_hud("PlaceCancel") as Control).global_position
	_controller.select_all_army()
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_more().visible).is_true()
	assert_that((_hud("PlaceConfirm") as Control).global_position).is_equal(confirm)
	assert_that((_hud("PlaceCancel") as Control).global_position).is_equal(cancel)
	assert_float(_bar.get_global_rect().size.x).is_less_equal(bar.size.x + 1.5)


## 1, then 5 types, 2, 3, 1 and 5 again: nothing under the thumb moves and the bar
## keeps the width it had.
func _assert_selection_changes_freeze(
	profile: StringName, extra: Array[String], extra_px: float = 0.0
) -> void:
	var before: Dictionary[String, Rect2] = _frozen_rects(extra)
	var column: Vector2 = _column_anchor()
	var plate: Rect2 = _bar.get_global_rect()
	assert_float(_bar._held_px).override_failure_message(str(profile)).is_equal_approx(
		plate.size.x, 1.5
	)
	for ids: Array in [TYPES, [TANK, RIFLE], TYPES.slice(0, 3), [RIFLE], TYPES]:
		await _select(ids)
		var why: String = "%s, %d ids" % [profile, ids.size()]
		assert_bool(_bar.has_slot()).override_failure_message(why).is_true()
		assert_that(_frozen_rects(extra)).override_failure_message(why).is_equal(before)
		assert_that(_column_anchor()).override_failure_message(why).is_equal(column)
		var now: Rect2 = _bar.get_global_rect()
		assert_float(now.position.x).override_failure_message(why).is_equal_approx(
			plate.position.x, 1.5
		)
		assert_float(now.position.y).override_failure_message(why).is_equal_approx(
			plate.position.y, 1.5
		)
		assert_float(now.size.x).override_failure_message(why + ": widened").is_less_equal(
			plate.size.x + extra_px + 1.5
		)
		_assert_nothing_cut(why)
	assert_array(_sent).is_empty()


## Checks the fit of the shown chips for `types` selected; true when "+N" shows.
func _assert_fit(why: String, types: int) -> bool:
	var shown: int = _shown_chips()
	assert_int(shown).override_failure_message(why).is_between(0 if _bar._frozen else 1, types)
	var more: Control = _more()
	assert_bool(more.visible).override_failure_message(why).is_equal(shown < types)
	if shown < types:
		var number: Label = more.get_child(0) as Label
		assert_str(number.text).override_failure_message(why).is_equal("+%d" % (types - shown))
	_assert_nothing_cut(why)
	_assert_none_would_fit(why, shown, types)
	return shown < types


## The row from Deselect: the shown chips in selection order, "+N", then Stop, strictly left to
## right (right to left when mirrored).
func _assert_order(why: String, mirrored: bool) -> void:
	var xs: Array[float] = [(_hud("Deselect") as Control).get_global_rect().get_center().x]
	for control: Control in _shown_controls():
		xs.append(control.get_global_rect().get_center().x)
	var stop: Button = _bar.order_button(&"stop")
	if stop.is_visible_in_tree():
		xs.append(stop.get_global_rect().get_center().x)
	for index: int in range(1, xs.size()):
		var ordered: bool = xs[index] < xs[index - 1] if mirrored else xs[index] > xs[index - 1]
		assert_bool(ordered).override_failure_message("%s: order %s" % [why, xs]).is_true()


func _assert_stop_inside(why: String) -> void:
	var stop: Button = _bar.order_button(&"stop")
	assert_bool(stop.is_visible_in_tree()).override_failure_message(why + ": Stop").is_true()
	var bar: Rect2 = _bar.get_global_rect().grow(TOLERANCE_PX)
	assert_bool(bar.encloses(stop.get_global_rect())).override_failure_message(why).is_true()
	assert_float(stop.size.x).override_failure_message(why + ": Stop width").is_greater_equal(
		UiScale.dp(CommandBar.ORDER_DP.x) - TOLERANCE_PX
	)


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
	# The box layout rounds sizes up to whole px, a px or two over the sum of the parts.
	assert_float(_room()).override_failure_message(why + ": row against room").is_greater_equal(
		_row_ask() - 2.0
	)


## One more chip would not have fitted in the room (the rule shows as many as fit).
func _assert_none_would_fit(why: String, shown: int, types: int) -> void:
	if shown >= types:
		return
	var gap: float = roundf(UiScale.dp(HudCorners.GAP_DP))
	var ask: float = _row_ask() + gap + _chip(shown).get_combined_minimum_size().x
	if shown + 1 == types:  # The last chip takes the place of "+N".
		ask -= gap + _more().get_combined_minimum_size().x
	assert_float(ask).override_failure_message(why + ": another chip").is_greater(_room())


## What the row asks for: Deselect, the shown chips, "+N" and the gaps, and the orders.
func _row_ask() -> float:
	var row: Control = _bar.get_node("Row")
	var orders: Control = _bar.find_child("Orders", true, false).get_child(0)
	return row.get_combined_minimum_size().x + orders.get_combined_minimum_size().x


## The room the bar may take at the most (while a mode runs: the width it had as the mode began).
func _room() -> float:
	var rects: Dictionary[StringName, Rect2] = _bar._rects(true)
	var room: float = rects[HudCorners.BAR].size.x
	return minf(room, _bar._held_px) if _bar._frozen else room


func _shown_controls() -> Array[Control]:
	var out: Array[Control] = []
	for chip: Control in _bar._chips:
		if chip.visible:
			out.append(chip)
	if _more().visible:
		out.append(_more())
	return out


## The visible chips, every one of them (a chip past the selection's types must be hidden).
func _shown_chips() -> int:
	var count: int = 0
	for index: int in _bar._chips.size():
		if _chip(index).visible:
			assert_int(index).is_less(_bar._types)
			count += 1
	return count


func _chip(index: int) -> CommandBar.Chip:
	return _bar._chips[index]


func _more() -> Control:
	return _bar.find_child("More", true, false) as Control


func _frozen_rects(extra: Array[String]) -> Dictionary[String, Rect2]:
	var out: Dictionary[String, Rect2] = {}
	for node_name: String in FROZEN + extra:
		var node: Control = _hud(node_name) as Control
		if node != null and node.is_visible_in_tree():
			out[node_name] = node.get_global_rect()
	return out


## The group column's fixed corner: its start sideways (it grows downwards with its items), its
## foot upright (it grows upwards from the bar). Its size follows the selection (the "+" item).
func _column_anchor() -> Vector2:
	var rect: Rect2 = (_hud("GroupColumn") as Control).get_global_rect()
	return Vector2(rect.position.x, rect.end.y if HudLayout.is_portrait() else rect.position.y)


## The phone turns (or changes) to `metrics` with the scene open.
func _turn(metrics: UiMetrics) -> void:
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()


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
	_aim = _main.get_node("StrikeAim")
	_controller = _main.get_node("PlayerController")
	_bar = _hud("CommandBar") as CommandBar
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	await await_idle_frame()
