extends "res://tests/ui/support/building_orders_suite.gd"
## The command bar's building orders, states and edges (plan P272): Mend's dimmed and lit looks,
## the Sell button's fixed width for the widest "+N", which rows show neither order, the last
## producer's question card and how long it lives (its building, the match end, a tap outside), and
## that a pause menu confirm keeps the plain rule. Fixture: support/building_orders_suite.gd.


func test_mend_is_dimmed_with_a_grey_word_at_full_health_and_lit_with_a_plate_when_on() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	var mend: Button = _bar.order_button(&"mend")
	assert_bool(mend.disabled).is_true()
	assert_str(_word(&"mend").theme_type_variation).is_equal(CommandBar.DIM_CAPTION)
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = _row(BORE)
	snap.hp[row] = snap.type_max_hp[snap.type_index[row]] - 1
	await _tick()
	assert_bool(mend.disabled).is_false()
	assert_str(_word(&"mend").theme_type_variation).is_equal(CommandBar.CAPTION)
	assert_str(mend.theme_type_variation).is_equal("")
	snap.cargo[row] = 1
	await _tick()
	assert_str(mend.theme_type_variation).is_equal(CommandBar.LIT_PLATE)  # Not colour alone.
	assert_str(_word(&"mend").theme_type_variation).is_equal(CommandBar.LIT_CAPTION)


## The switch is on at full health (the sim clears it at the next period tick): the button stays
## enabled so a tap can turn it off.
func test_mend_with_the_switch_on_at_full_health_stays_enabled_and_a_tap_sends_off() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	await _select([BORE])
	_runner.snapshot.cargo[_row(BORE)] = 1
	await _tick()
	assert_bool(_bar.order_button(&"mend").disabled).is_false()
	_tap(_bar.order_button(&"mend"))
	assert_int(_sent.size()).is_equal(1)
	assert_array(_sent[0].payload).is_equal([0])


func test_a_dying_a_sold_and_a_cancelled_row_show_neither_order() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = _row(BORE)
	var hp: int = snap.hp[row]
	for state: Array in [[0, 0], [hp, Production.SOLD], [hp, Production.CANCELLED]]:
		snap.hp[row] = state[0]
		snap.build_left[row] = state[1]
		await _select([BORE])
		_controller.selection.set_ids(PackedInt32Array([BORE]))
		await _tick()
		var why: String = str(state)
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


## The width is sized for the widest "+N" (a price of millions here), with the padding, in the
## caption the armed word wears.
func test_the_sell_button_is_wide_enough_for_the_widest_refund_with_its_padding() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	var snap: MatchSnapshot = _runner.snapshot
	snap.type_cost[snap.type_index[_row(BORE)]] = 9999999
	await _select([BORE])
	var word: Label = _word(&"sell")
	var font: Font = word.get_theme_font(&"font", CommandBar.WARN_CAPTION)
	var px: int = word.get_theme_font_size(&"font_size", CommandBar.WARN_CAPTION)
	var widest: String = "+" + "8".repeat(str(BuildingOrders.widest_refund(snap)).length())
	var text_px: float = font.get_string_size(widest, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var need: float = text_px + 2.0 * UiScale.dp(CommandBar.SELL_PAD_DP)
	assert_float(_bar.order_button(&"sell").size.x).is_greater_equal(need - TOLERANCE_PX)
	assert_int(px).is_greater_equal(18)  # The armed number is 18 sp or more.


## With the second barracks a site, the first is the last producer: the card asks.
func test_a_site_is_no_second_producer_so_the_card_asks() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [SECOND])
	_runner.snapshot.build_left[_row(SPARE)] = 30
	await _select([BARRACKS])
	assert_bool(BuildingOrders.is_last_producer(_runner.snapshot, _row(BARRACKS), 1)).is_true()
	_tap(_bar.order_button(&"sell"))
	_now += 500
	_tap(_bar.order_button(&"sell"))
	await await_idle_frame()
	assert_bool(_card().visible).is_true()
	assert_int(_sent.size()).is_equal(0)


func _ask_with_the_card() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [])
	await _select([BARRACKS])
	_tap(_bar.order_button(&"sell"))
	_now += 500
	_tap(_bar.order_button(&"sell"))
	await await_idle_frame()
	assert_bool(_card().visible).is_true()


## The match ends under the card: it closes, and the first tap on the screen that rises is not
## taken as an answer to a question that is gone.
func test_the_card_closes_at_the_match_end_and_does_not_eat_the_next_tap() -> void:
	await _ask_with_the_card()
	var answers: Array[int] = []
	_card().cancelled.connect(func() -> void: answers.append(1))
	_runner.match_ended.emit(2)
	assert_bool(_card().visible).is_false()
	var outside: Vector2 = Vector2(4.0, 4.0)
	TouchEvents.press(get_viewport(), 0, outside)
	TouchEvents.release(get_viewport(), 0, outside)
	assert_array(answers).is_empty()
	assert_int(_sent.size()).is_equal(0)


func test_the_card_closes_when_its_building_leaves_the_selection() -> void:
	await _ask_with_the_card()
	_controller.selection.clear()
	await await_idle_frame()
	assert_bool(_card().visible).is_false()
	assert_int(_sent.size()).is_equal(0)


## The card sells the building it asked about.
func test_the_cards_sell_sends_the_building_it_asked_about() -> void:
	await _ask_with_the_card()
	_tap(_card().find_child("YesButton", true, false) as Button)
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].target_id).is_equal(BARRACKS)


## The pause menu's confirms keep the plain rule: a touch outside the panel answers nothing.
func test_a_pause_menu_confirm_ignores_a_tap_outside_its_panel() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], [])
	var menu: Node = _main.get_node("Hud/PauseMenu")
	var dialog: ConfirmDialog = menu._surrender_dialog
	assert_bool(dialog.dismiss_outside).is_false()
	dialog.open()
	await await_idle_frame()
	await await_idle_frame()
	var outside: Vector2 = get_viewport().get_visible_rect().end - Vector2(4.0, 4.0)
	assert_bool(dialog.panel.get_global_rect().has_point(outside)).is_false()
	TouchEvents.press(get_viewport(), 0, outside)
	TouchEvents.release(get_viewport(), 0, outside)
	assert_bool(dialog.visible).is_true()
