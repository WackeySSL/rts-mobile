extends "res://tests/ui/support/building_orders_suite.gd"
## The command bar's building orders (plan P272, ADR 0037 sections 3, 4 and 9) in the main scene at
## the six sizes of ScreenSizes.ALL: Mend and Sell show for one own complete building only; Mend is
## a toggle that sends one MEND; Sell is a two-tap order: it arms on the first tap ("+N" from
## `Production.sale_refund`, amber), sends one SELL on a second tap between `sell_arm_min_ms` (from
## the first release) and `sell_confirm_ms`, and is disarmed by any other touch, the window running
## out or a turn; a hold is no tap. Fixture: support/building_orders_suite.gd.


func test_mend_and_sell_show_for_one_own_building_at_every_size_in_reach_of_a_thumb() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, [SECOND, HQ])
		await _select([BORE])
		var why: String = str(size)
		assert_bool(_bar.visible).override_failure_message(why).is_true()
		for id: StringName in [&"mend", &"sell"]:
			var button: Button = _bar.order_button(id)
			assert_bool(button.is_visible_in_tree()).override_failure_message(why).is_true()
			var rect: Rect2 = button.get_global_rect()
			assert_float(rect.size.x).override_failure_message(why).is_greater_equal(
				UiScale.dp(56.0) - TOLERANCE_PX
			)
			assert_float(rect.size.y).override_failure_message(why).is_greater_equal(
				UiScale.dp(64.0) - TOLERANCE_PX
			)
		assert_bool(_bar.order_button(&"stop").is_visible_in_tree()).is_false()
		var margin_dp: float = SafeAreaMargin.DEFAULT_MARGIN_DP
		var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
		(
			assert_bool(safe.encloses(_bar.get_global_rect().grow(-0.5)))
			. override_failure_message("%s: bar %s, safe %s" % [why, _bar.get_global_rect(), safe])
			. is_true()
		)
		var build: Rect2 = (
			(_main.get_node("Hud").find_child("BuildButton", true, false) as Control)
			. get_global_rect()
		)
		(
			assert_bool(_bar.get_global_rect().intersects(build))
			. override_failure_message(why)
			. is_false()
		)
		# Mend and Sell stand in the bar's scroll, after the chip, in this order.
		assert_bool(_x(&"mend") < _x(&"sell")).override_failure_message(why).is_true()


func test_no_building_order_for_an_enemy_building_a_unit_a_site_and_the_headquarters_has_no_sell(
) -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND, HQ])
	for ids: Array in [[ENEMY_HQ], [TANK], [], [BORE, BARRACKS]]:
		await _select(ids)
		var why: String = str(ids)
		(
			assert_bool(_bar.order_button(&"mend").is_visible_in_tree())
			. override_failure_message(why)
			. is_false()
		)
		(
			assert_bool(_bar.order_button(&"sell").is_visible_in_tree())
			. override_failure_message(why)
			. is_false()
		)
	await _select([OWN_HQ])
	assert_bool(_bar.order_button(&"mend").is_visible_in_tree()).is_true()
	assert_bool(_bar.order_button(&"sell").is_visible_in_tree()).is_false()  # Price 0.
	var snap: MatchSnapshot = _runner.snapshot
	snap.build_left[snap.index_of(BORE)] = 30  # A site: cancelled from the drawer instead.
	await _select([BORE])
	assert_bool(_bar.order_button(&"mend").is_visible_in_tree()).is_false()
	assert_bool(_bar.order_button(&"sell").is_visible_in_tree()).is_false()


func test_mend_sends_one_mend_on_then_off_by_the_switch_the_snapshot_shows_and_buzzes() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(BORE)
	# At full health with the switch off the button stays in place, dimmed and not tappable.
	assert_bool(_bar.order_button(&"mend").visible).is_true()
	assert_bool(_bar.order_button(&"mend").disabled).is_true()
	_tap(_bar.order_button(&"mend"))
	assert_int(_sent.size()).is_equal(0)
	snap.hp[row] = snap.type_max_hp[snap.type_index[row]] - 1
	await _tick()
	assert_bool(_bar.order_button(&"mend").disabled).is_false()
	assert_bool(_bar.order_button(&"mend").button_pressed).is_false()
	_tap(_bar.order_button(&"mend"))
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.MEND)
	assert_int(_sent[0].target_id).is_equal(BORE)
	assert_array(_sent[0].payload).is_equal([1])
	assert_array(_buzzes).is_equal([_controller.settings.haptic_ms])
	snap.cargo[row] = 1  # The sim switched it on.
	await _tick()
	assert_bool(_bar.order_button(&"mend").button_pressed).is_true()  # Lit.
	assert_str(_word(&"mend").theme_type_variation).is_equal(CommandBar.LIT_CAPTION)
	_tap(_bar.order_button(&"mend"))
	assert_int(_sent.size()).is_equal(2)
	assert_array(_sent[1].payload).is_equal([0])
	snap.cargo[row] = 0  # It stopped by itself at full health.
	await _tick()
	assert_bool(_bar.order_button(&"mend").button_pressed).is_false()
	assert_str(_word(&"mend").theme_type_variation).is_equal(CommandBar.CAPTION)
	assert_array(_controller.selection.selected).is_equal([BORE])  # Mend keeps the selection.


func test_sell_arms_on_the_first_tap_shows_the_refund_and_sends_one_sell_on_the_second() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(BORE)
	var type: int = snap.type_index[row]
	snap.hp[row] = snap.type_max_hp[type] / 2  # Half health.
	var expect: int = Production.sale_refund(
		snap.type_cost[type], PERCENT, snap.hp[row], snap.type_max_hp[type]
	)
	assert_int(expect).is_greater(0)
	assert_str(_word(&"sell").text).is_equal("SELL")
	_tap(_bar.order_button(&"sell"))
	await _tick()
	assert_int(_sent.size()).is_equal(0)  # The first tap only arms.
	assert_str(_word(&"sell").text).is_equal("+%d" % expect)
	assert_str(_word(&"sell").theme_type_variation).is_equal(CommandBar.WARN_CAPTION)
	_now += 500
	_tap(_bar.order_button(&"sell"))
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.SELL)
	assert_int(_sent[0].target_id).is_equal(BORE)
	assert_bool(_sent[0].payload.is_empty()).is_true()
	assert_array(_buzzes).is_equal([_controller.settings.haptic_ms])
	await _tick()
	assert_str(_word(&"sell").text).is_equal("SELL")  # Disarmed by the send.


func test_the_label_follows_the_building_health_while_armed() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(BORE)
	var type: int = snap.type_index[row]
	_tap(_bar.order_button(&"sell"))
	await _tick()
	var full: int = Production.sale_refund(snap.type_cost[type], PERCENT, 1, 1)
	assert_str(_word(&"sell").text).is_equal("+%d" % full)
	snap.hp[row] = snap.type_max_hp[type] / 4  # Hit while armed: the refund drops with it.
	await _tick()
	var quarter: int = Production.sale_refund(
		snap.type_cost[type], PERCENT, snap.hp[row], snap.type_max_hp[type]
	)
	assert_int(quarter).is_less(full)
	assert_str(_word(&"sell").text).is_equal("+%d" % quarter)


## A double-tap's second half (before `sell_arm_min_ms`) is ignored and keeps the arm.
func test_a_second_tap_before_the_minimum_is_ignored_and_keeps_the_arm() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_tap(_bar.order_button(&"sell"))
	_now += _controller.settings.sell_arm_min_ms - 1
	_tap(_bar.order_button(&"sell"))
	await _tick()
	assert_int(_sent.size()).is_equal(0)
	assert_str(_word(&"sell").text).is_not_equal("SELL")  # Still armed.
	_now += 1  # Now `sell_arm_min_ms` after the first tap.
	_tap(_bar.order_button(&"sell"))
	assert_int(_sent.size()).is_equal(1)


## A resting thumb is no tap: a contact of `long_press_ms` or more never arms and never sells.
func test_a_resting_thumb_never_arms_and_never_sells() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_rest(_bar.order_button(&"sell"), 0, 10 * _controller.settings.sell_confirm_ms)
	await _tick()
	assert_int(_sent.size()).is_equal(0)
	assert_str(_word(&"sell").text).is_equal("SELL")  # Not armed by a hold.


## Arm, then the thumb settles on the button 0.3 s later and lifts at 2.5 s: the hold sells nothing
## and disarms.
func test_a_hold_after_the_arming_tap_sells_nothing_and_disarms() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_tap(_bar.order_button(&"sell"))
	_rest(_bar.order_button(&"sell"), 300, 2500)
	await _tick()
	assert_int(_sent.size()).is_equal(0)
	assert_str(_word(&"sell").text).is_equal("SELL")
	_now += _controller.settings.sell_arm_min_ms
	_tap(_bar.order_button(&"sell"))  # Disarmed: this one only arms.
	assert_int(_sent.size()).is_equal(0)


## A slow double-tap: release 0, press 250 ms, release 420 ms. The gap runs from the first release
## to the second press, so it is under `sell_arm_min_ms`: nothing is sold and the arm stays.
func test_a_slow_double_tap_never_sells() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_tap(_bar.order_button(&"sell"))
	_rest(_bar.order_button(&"sell"), 250, 420)
	await _tick()
	assert_int(_sent.size()).is_equal(0)
	assert_str(_word(&"sell").text).is_not_equal("SELL")  # Still armed by the first tap.
	_now += _controller.settings.sell_arm_min_ms  # A second tap far enough from the release sells.
	_tap(_bar.order_button(&"sell"))
	assert_int(_sent.size()).is_equal(1)


func test_a_tap_after_the_window_arms_again_and_sells_nothing() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_tap(_bar.order_button(&"sell"))
	_now += _controller.settings.sell_confirm_ms
	_tap(_bar.order_button(&"sell"))
	await _tick()
	assert_int(_sent.size()).is_equal(0)
	assert_str(_word(&"sell").text).is_not_equal("SELL")
	_now += _controller.settings.sell_arm_min_ms
	_tap(_bar.order_button(&"sell"))
	assert_int(_sent.size()).is_equal(1)


func test_the_window_running_out_disarms_and_so_does_any_other_touch() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_tap(_bar.order_button(&"sell"))
	await _tick()
	assert_str(_word(&"sell").text).is_not_equal("SELL")
	assert_bool(_bar.is_processing()).is_true()  # The window is watched while Sell is armed.
	_now += _controller.settings.sell_confirm_ms
	await await_idle_frame()  # A real frame sees the window out.
	assert_str(_word(&"sell").text).is_equal("SELL")
	assert_bool(_bar.is_processing()).is_false()
	_tap(_bar.order_button(&"sell"))
	assert_str(_word(&"sell").text).is_not_equal("SELL")
	# A touch on another control (Mend) or on the map disarms before it does its own work.
	TouchEvents.press(get_viewport(), 0, _bar.order_button(&"mend").get_global_rect().get_center())
	assert_str(_word(&"sell").text).is_equal("SELL")
	TouchEvents.release(
		get_viewport(), 0, _bar.order_button(&"mend").get_global_rect().get_center()
	)
	_sent.clear()
	_now += 100000
	_tap(_bar.order_button(&"sell"))
	var ground: Vector2 = get_viewport().get_visible_rect().get_center()
	TouchEvents.press(get_viewport(), 0, ground)
	assert_str(_word(&"sell").text).is_equal("SELL")
	TouchEvents.release(get_viewport(), 0, ground)
	await await_idle_frame()
	for command: Command in _sent:
		assert_int(command.type).is_not_equal(Command.Type.SELL)


func test_selecting_another_building_disarms() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_tap(_bar.order_button(&"sell"))
	await _select([BARRACKS])
	assert_str(_word(&"sell").text).is_equal("SELL")
	_now += _controller.settings.sell_arm_min_ms
	_tap(_bar.order_button(&"sell"))  # Arms the barracks; it does not send for the Deep Bore.
	assert_int(_sent.size()).is_equal(0)


## The button keeps its place and width, whatever it shows, and sits at least as wide as the widest
## "+N" needs; its neighbours do not move.
func test_the_sell_button_keeps_its_width_and_place_armed_or_not_at_every_size() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, [SECOND])
		await _select([BORE])
		var why: String = str(size)
		var mend: Rect2 = _bar.order_button(&"mend").get_global_rect()
		var sell: Rect2 = _bar.order_button(&"sell").get_global_rect()
		var bar: Rect2 = _bar.get_global_rect()
		var snap: MatchSnapshot = _runner.snapshot
		var widest: String = "+%d" % BuildingOrders.widest_refund(snap)
		var word: Label = _word(&"sell")
		var font: Font = word.get_theme_font(&"font")
		var text_px: float = (
			font
			. get_string_size(
				widest, HORIZONTAL_ALIGNMENT_LEFT, -1.0, word.get_theme_font_size(&"font_size")
			)
			. x
		)
		assert_float(sell.size.x).override_failure_message(why).is_greater_equal(text_px)
		_tap(_bar.order_button(&"sell"))
		await _tick()
		assert_str(word.text).override_failure_message(why).is_not_equal("SELL")
		(
			assert_that(_bar.order_button(&"sell").get_global_rect())
			. override_failure_message(why)
			. is_equal(sell)
		)
		(
			assert_that(_bar.order_button(&"mend").get_global_rect())
			. override_failure_message(why)
			. is_equal(mend)
		)
		assert_that(_bar.get_global_rect()).override_failure_message(why).is_equal(bar)
		assert_float(word.size.x).override_failure_message(why).is_less_equal(sell.size.x)


func test_the_last_producer_asks_on_the_question_card_and_only_sell_sends() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [])
	await _select([BARRACKS])
	assert_bool(BuildingOrders.is_last_producer(_runner.snapshot, _row(BARRACKS), 1)).is_true()
	_tap(_bar.order_button(&"sell"))
	_now += 500
	_tap(_bar.order_button(&"sell"))
	await await_idle_frame()
	assert_int(_sent.size()).is_equal(0)  # The card asks first.
	var card: ConfirmDialog = _card()
	assert_bool(card.visible).is_true()
	assert_str(card.question).is_equal("SELLING IT LOSES THE MATCH")
	assert_str(card.yes_text).is_equal("SELL")
	assert_str(card.no_text).is_equal("KEEP")
	_tap(card.find_child("NoButton", true, false) as Button)  # Keep.
	assert_bool(card.visible).is_false()
	assert_int(_sent.size()).is_equal(0)
	_now += 100000
	_tap(_bar.order_button(&"sell"))
	_now += 500
	_tap(_bar.order_button(&"sell"))
	assert_bool(card.visible).is_true()
	_tap(card.find_child("YesButton", true, false) as Button)
	assert_bool(card.visible).is_false()
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.SELL)
	assert_int(_sent[0].target_id).is_equal(BARRACKS)


func test_a_tap_outside_the_card_or_a_turn_of_the_phone_closes_it_with_nothing_sent() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [])
	await _select([BARRACKS])
	_tap(_bar.order_button(&"sell"))
	_now += 500
	_tap(_bar.order_button(&"sell"))
	await await_idle_frame()
	var card: ConfirmDialog = _card()
	assert_bool(card.visible).is_true()
	var panel: Rect2 = (card.column.get_parent() as Control).get_global_rect()
	var outside: Vector2 = Vector2(panel.position.x * 0.5, panel.get_center().y)
	assert_bool(panel.has_point(outside)).is_false()
	TouchEvents.press(get_viewport(), 0, outside)
	TouchEvents.release(get_viewport(), 0, outside)
	await await_idle_frame()
	assert_bool(card.visible).is_false()
	assert_int(_sent.size()).is_equal(0)
	_now += 100000
	_tap(_bar.order_button(&"sell"))
	_now += 500
	_tap(_bar.order_button(&"sell"))
	await await_idle_frame()
	assert_bool(card.visible).is_true()
	get_window().size = ScreenSizes.PORTRAIT[0]  # A turn of the phone.
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(card.visible).is_false()
	assert_int(_sent.size()).is_equal(0)


func test_a_second_producer_sells_without_the_card() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BARRACKS])
	assert_bool(BuildingOrders.is_last_producer(_runner.snapshot, _row(BARRACKS), 1)).is_false()
	_tap(_bar.order_button(&"sell"))
	_now += 500
	_tap(_bar.order_button(&"sell"))
	assert_int(_sent.size()).is_equal(1)
	assert_bool(_card().visible).is_false()


func test_a_turn_of_the_phone_disarms_sell() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_tap(_bar.order_button(&"sell"))
	assert_str(_word(&"sell").text).is_not_equal("SELL")
	get_window().size = ScreenSizes.PORTRAIT[0]
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_word(&"sell").text).is_equal("SELL")
	assert_int(_sent.size()).is_equal(0)
