extends "res://tests/ui/support/building_orders_suite.gd"
## The selection chip of a building shows its item card and its health and no name (Michael,
## 2026-11-18, P310: in portrait the name pushed Mend and Sell off the screen) and stacks its health
## bar under its card. Every own building type of both factions in data/units (26 today) is
## selected at the six sizes of ScreenSizes.ALL and at the two real 360 dp wide phones held upright
## (`web_phone_portrait`, `notch_design_portrait`; the six sizes run at headless density, wider in
## dp): the chip, the bar and Mend and Sell (Sell not for a Headquarters) stand inside the safe
## area, the orders are at least 56 x 48 dp and none is outside the bar. The
## widest state, Mend lit and Sell armed with a refund, is checked on the dearest one.

const PER_SCENE: int = 12  ## Buildings spawned in one scene, in the free band below the base.
const PITCH: int = 5
const FIRST_ID: int = 5  ## The spawns after BASE take the ids that follow it.


func test_a_buildings_chip_has_no_name_and_mend_and_sell_fit_for_every_type_at_every_size() -> void:
	var types: Array[String] = _building_types()
	assert_int(types.size()).is_equal(26)
	for screen: Array in _screens():
		var size: Vector2i = screen[0]
		var metrics: UiMetrics = screen[1]
		for from: int in range(0, types.size(), PER_SCENE):
			var batch: Array[String] = types.slice(from, from + PER_SCENE)
			var extra: Array = []
			for at: int in batch.size():
				extra.append([1, batch[at], 1 + PITCH * (at % 6), 23 + PITCH * (at / 6)])
			await _open(size, extra, metrics)
			for at: int in batch.size():
				var why: String = "%s %s" % [size, batch[at]]
				var id: int = FIRST_ID + at
				assert_int(_row(id)).override_failure_message(why + ": spawned").is_greater(-1)
				await _select([id])
				_assert_chip_without_name(why)
				_assert_orders_fit(
					why, not batch[at].ends_with("hq") and batch[at] != "headquarters"
				)


func test_the_widest_orders_a_building_shows_fit_mend_lit_and_sell_armed_on_the_dearest() -> void:
	for screen: Array in _screens():
		var size: Vector2i = screen[0]
		await _open(size, [[1, "fossil_space", 1, 23]], screen[1])
		var snap: MatchSnapshot = _runner.snapshot
		var id: int = FIRST_ID
		var row: int = snap.index_of(id)
		var type: int = snap.type_index[row]
		snap.hp[row] = snap.type_max_hp[type] - 1
		snap.cargo[row] = 1  # Mend is on: the lit plate and its heavier edge.
		await _select([id])
		_tap(_bar.order_button(&"sell"))  # Armed: the amber "+N", the refund now.
		await _tick()
		var why: String = "%s armed" % size
		assert_str(_word(&"sell").theme_type_variation).is_equal(CommandBar.WARN_CAPTION)
		assert_bool(_bar.order_button(&"mend").button_pressed).is_true()
		_assert_chip_without_name(why)
		_assert_orders_fit(why, true)


## [window size, metrics or null]: the six sizes, then the two 360 dp wide phones held upright.
func _screens() -> Array[Array]:
	var out: Array[Array] = []
	for size: Vector2i in ScreenSizes.ALL:
		out.append([size, null])
	for name: StringName in [&"web_phone_portrait", &"notch_design_portrait"]:
		var metrics: UiMetrics = UiProfiles.by_name(name)
		out.append([metrics.window_size, metrics])
	return out


## The chip of the selected type: its card, its health, no label and no name anywhere in it.
func _assert_chip_without_name(why: String) -> void:
	var chip: CommandBar.Chip = _bar.find_child("Chip", true, false) as CommandBar.Chip
	assert_bool(chip.visible).override_failure_message(why).is_true()
	assert_bool(chip.label.visible).override_failure_message(why).is_false()
	assert_str(chip.label.text).override_failure_message(why).is_empty()
	assert_bool(chip.health.visible).override_failure_message(why).is_true()
	assert_bool(chip.card.size.x > 0.0).override_failure_message(why).is_true()
	var safe: Rect2 = _safe()
	(
		assert_bool(safe.encloses(chip.get_global_rect().grow(-0.5)))
		. override_failure_message("%s: chip %s, safe %s" % [why, chip.get_global_rect(), safe])
		. is_true()
	)


func _assert_orders_fit(why: String, with_sell: bool) -> void:
	var safe: Rect2 = _safe()
	(
		assert_bool(safe.encloses(_bar.get_global_rect().grow(-0.5)))
		. override_failure_message("%s: bar %s, safe %s" % [why, _bar.get_global_rect(), safe])
		. is_true()
	)
	var room: Rect2 = _bar.get_global_rect().grow(TOLERANCE_PX)
	var ids: Array = [&"mend", &"sell"] if with_sell else [&"mend"]
	for id: StringName in ids:
		var button: Button = _bar.order_button(id)
		var rect: Rect2 = button.get_global_rect()
		assert_bool(button.is_visible_in_tree()).override_failure_message(why + " " + id).is_true()
		assert_float(rect.size.x).override_failure_message(why + " " + id).is_greater_equal(
			UiScale.dp(56.0) - TOLERANCE_PX
		)
		assert_float(rect.size.y).override_failure_message(why + " " + id).is_greater_equal(
			UiScale.dp(48.0) - TOLERANCE_PX
		)
		(
			assert_bool(safe.encloses(rect.grow(-0.5)))
			. override_failure_message("%s %s: %s outside the safe area %s" % [why, id, rect, safe])
			. is_true()
		)
		(
			assert_bool(room.encloses(rect))
			. override_failure_message("%s %s: %s outside the bar %s" % [why, id, rect, room])
			. is_true()
		)


func _safe() -> Rect2:
	return SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)


## Every own-type structure of data/units, both factions: no speed, a cost or a Headquarters.
func _building_types() -> Array[String]:
	var out: Array[String] = []
	var files: PackedStringArray = DirAccess.get_files_at("res://data/units")
	files.sort()
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var def: UnitDef = load("res://data/units/%s" % file) as UnitDef
		if def != null and def.speed == 0:
			out.append(file.get_basename())
	return out
