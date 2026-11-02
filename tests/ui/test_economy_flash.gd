extends GdUnitTestSuite
## The economy pill's spend and income flashes (plan P119b, ADR 0025 section 3), from crafted
## snapshots in the main scene at the six sizes of ScreenSizes.ALL: a fall in the credits shows a
## red "-N" chip under the credits and the number counts down to the new value, a rise shows a green
## "+N" chip and the number at once, both for `economy_flash_ms` of frame time, stepped here with
## `_process(delta)` (the pill's own frames are off, so nothing runs on wall time). Changes inside
## that time add up and start it again; a new match, the first read and a flash time of 0 show no
## flash; nothing is written at rest and the digits keep their slots. The card is
## test_economy_card.gd's, the pill's look and layout are test_economy_pill*.gd's. The match is
## paused, so only the snapshots a test writes are on show, and no Command is sent.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const SETTINGS: String = "res://data/input_settings.tres"
const FLASH_MS: int = 1000  ## `economy_flash_ms` of data/input_settings.tres.
## WCAG 2.1 AA: 4.5 for text.
const AA_TEXT: float = 4.5

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _feed: HudStateFeed
var _pill: EconomyPill
var _controller: PlayerController
var _sent: Array[Command] = []
var _tick: int = 0
var _serial: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()


func test_the_data_file_gives_one_second() -> void:
	assert_int(InputSettings.new().economy_flash_ms).is_equal(FLASH_MS)
	assert_int(load(SETTINGS).economy_flash_ms).is_equal(FLASH_MS)


## A spend: the red chip says how much, the number counts down in the flash time and ends on the new
## value, and the chip goes with the time.
func test_a_fall_shows_a_red_chip_and_counts_the_number_down() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_publish(1000)
		assert_bool(_chip().visible).override_failure_message(why).is_false()
		_publish(400)
		assert_bool(_chip().visible).override_failure_message(why).is_true()
		assert_str(_chip_text().text).override_failure_message(why).is_equal("-600")
		assert_that(_chip_colour()).override_failure_message(why).is_equal(_token(&"danger"))
		assert_str(_credits().text).override_failure_message(why).is_equal("1000")  # Counts from here.
		var seen: Dictionary[int, String] = {250: "850", 500: "700", 750: "550"}
		var elapsed: int = 0
		for at: int in seen:
			_step(at - elapsed)
			elapsed = at
			assert_str(_credits().text).override_failure_message("%s, %d ms" % [why, at]).is_equal(
				seen[at]
			)
			assert_bool(_chip().visible).override_failure_message(why).is_true()
		_step(FLASH_MS - 1 - elapsed)  # One ms short of the time.
		assert_bool(_chip().visible).override_failure_message(why).is_true()
		assert_str(_credits().text).override_failure_message(why).is_equal("401")
		_step(1)
		assert_bool(_chip().visible).override_failure_message(why).is_false()
		assert_str(_credits().text).override_failure_message(why).is_equal("400")
		_step(5000)  # And it stays.
		assert_str(_credits().text).override_failure_message(why).is_equal("400")
		assert_bool(_chip().visible).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).is_empty()


## An income (a tanker's delivery, a refund): the green chip, the number at once.
func test_a_rise_shows_a_green_chip_and_the_number_at_once() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_publish(100)
		_publish(280)
		assert_bool(_chip().visible).override_failure_message(why).is_true()
		assert_str(_chip_text().text).override_failure_message(why).is_equal("+180")
		assert_that(_chip_colour()).override_failure_message(why).is_equal(_token(&"ok"))
		assert_that(_chip_colour()).is_not_equal(_token(&"danger"))
		assert_str(_credits().text).override_failure_message(why).is_equal("280")
		_step(FLASH_MS - 1)
		assert_bool(_chip().visible).override_failure_message(why).is_true()
		assert_str(_credits().text).override_failure_message(why).is_equal("280")
		_step(1)
		assert_bool(_chip().visible).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).is_empty()


## The chip says the sign in text, the colour is not the only word: "-" and "+", dark digits that
## read on the red and on the green (WCAG), and it is under the credits, inside the safe rect, clear
## of the pill, whichever way the phone is held. It is a cue and takes no touch.
func test_the_chip_is_under_the_credits_readable_and_takes_no_touch() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		for change: int in [-300, 300]:
			var why: String = "%s: %+d" % [size, change]
			_publish(1000)
			_publish(1000 + change)
			await _settle()
			var chip: Rect2 = _chip().get_global_rect()
			var pill: Rect2 = _pill.get_global_rect()
			var tap: Rect2 = (_hud("CreditsTap") as Control).get_global_rect()
			var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 12.0)
			assert_bool(_chip().visible).override_failure_message(why).is_true()
			assert_bool(_chip_text().text.begins_with("-" if change < 0 else "+")).is_true()
			assert_float(chip.position.x).override_failure_message(why).is_equal_approx(
				tap.position.x, 1.0
			)
			assert_float(chip.position.y).override_failure_message(why).is_greater_equal(
				pill.end.y + UiScale.dp(EconomyPill.CHIP_GAP_DP) - 1.5
			)
			assert_bool(chip.intersects(pill)).override_failure_message(why).is_false()
			assert_bool(safe.grow(0.5).encloses(chip)).override_failure_message(why).is_true()
			assert_int(_chip().mouse_filter).override_failure_message(why).is_equal(
				Control.MOUSE_FILTER_IGNORE
			)
			var digits: Color = _pill.get_theme_color(&"font_color", &"PowerNumberLow")
			var box: Color = _chip_colour()
			assert_float(_contrast(digits, box)).override_failure_message(why).is_greater_equal(
				AA_TEXT
			)
			var digit: Label = _chip_text().get_child(1) as Label
			assert_str(str(digit.theme_type_variation)).is_equal("PowerNumberLow")
			var points: float = (
				float(digit.get_theme_font_size(&"font_size")) / UiScale.base_px_per_dp()
			)
			assert_float(points).override_failure_message(why).is_greater_equal(17.5)  # 18 dp.
			_step(FLASH_MS)


## Changes inside the flash time add to the chip and start the time again; a rise inside a fall's
## time nets against it and the number keeps counting to the new value; the net sign gives the
## colour and a net of zero shows no chip; a change after the time starts a chip of its own.
func test_changes_inside_the_flash_time_add_up_and_start_the_time_again() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_publish(2000)
		_publish(1700)  # -300
		_step(600)
		_publish(1500)  # -200 more, 600 ms in.
		assert_str(_chip_text().text).override_failure_message(why).is_equal("-500")
		_step(FLASH_MS - 1)  # The time started again at the second fall.
		assert_bool(_chip().visible).override_failure_message(why).is_true()
		_step(1)
		assert_bool(_chip().visible).override_failure_message(why).is_false()
		assert_str(_credits().text).override_failure_message(why).is_equal("1500")
		_publish(1000)  # -500, a chip of its own after the time.
		assert_str(_chip_text().text).override_failure_message(why).is_equal("-500")
		_step(100)
		_publish(1100)  # +100 inside the fall: net -400, red; the number counts on to 1100.
		assert_str(_chip_text().text).override_failure_message(why).is_equal("-400")
		assert_that(_chip_colour()).is_equal(_token(&"danger"))
		_publish(1600)  # +500 more: net +100, green.
		assert_str(_chip_text().text).override_failure_message(why).is_equal("+100")
		assert_that(_chip_colour()).is_equal(_token(&"ok"))
		_publish(1500)  # -100: net 0, no chip.
		assert_bool(_chip().visible).override_failure_message(why).is_false()
		_publish(1700)  # +200 from there: a chip again.
		assert_str(_chip_text().text).override_failure_message(why).is_equal("+200")
		assert_bool(_chip().visible).override_failure_message(why).is_true()
		_step(FLASH_MS)
		assert_bool(_chip().visible).override_failure_message(why).is_false()


## A delivery arrives in steps of a few ticks: one chip adds them up, not one chip per step.
func test_a_delivery_in_steps_shows_one_sum() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(1000)
	for step: int in 5:
		_step(100)
		_publish(1000 + 25 * (step + 1))
		assert_str(_chip_text().text).is_equal("+%d" % (25 * (step + 1)))
	assert_str(_credits().text).is_equal("1125")
	_step(FLASH_MS)
	assert_bool(_chip().visible).is_false()


## The number counts to its target and a rise that lifts the target above what is shown ends the
## count at once; a fall during a count starts again from what is shown.
func test_a_rise_above_the_shown_number_ends_the_count_and_a_fall_restarts_it() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(1000)
	_publish(400)
	_step(500)
	assert_str(_credits().text).is_equal("700")
	_publish(900)  # Above the 700 on screen: shown at once.
	assert_str(_credits().text).is_equal("900")
	_step(FLASH_MS)
	assert_str(_credits().text).is_equal("900")  # And the count did not go on.
	_publish(300)
	_step(500)
	assert_str(_credits().text).is_equal("600")
	_publish(100)  # Another fall: from the 600 shown to 100, over a whole time.
	assert_str(_credits().text).is_equal("600")
	_step(500)
	assert_str(_credits().text).is_equal("350")
	_step(500)
	assert_str(_credits().text).is_equal("100")


## Nothing is written at rest: the same figures on new ticks write no text, a count writes the
## number once per shown change and at most once per frame, and the chip's text is written when
## its sum changes, not per frame.
func test_no_text_is_written_per_frame_at_rest() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(500)
	_publish(300)
	_step(FLASH_MS)
	var credits: int = _credits().writes
	var chip: int = _chip_text().writes
	for frame: int in 120:
		_step(16)
		_publish(300)  # A new tick, the same figures.
	assert_int(_credits().writes).is_equal(credits)
	assert_int(_chip_text().writes).is_equal(chip)
	_publish(100)  # A count of 200 over 1 000 one-ms frames: 200 changes.
	chip = _chip_text().writes
	var seen: String = _credits().text
	var changes: int = 0
	for frame: int in FLASH_MS:
		var before: int = _credits().writes
		_step(1)
		assert_int(_credits().writes - before).is_less_equal(1)
		if _credits().text != seen:
			seen = _credits().text
			changes += 1
	assert_int(changes).is_equal(200)
	assert_int(_credits().writes - credits).is_equal(changes)
	assert_int(_chip_text().writes).is_equal(chip)  # The chip's sum did not change.


## The digits keep their places: the glyphs, the digit slots, the bar and the pill do not move
## while the chip comes, the number counts and the chip goes, and the pill gets no wider for it.
func test_the_digits_keep_their_slots_and_nothing_moves_through_a_flash() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		_publish(9999)
		await _settle()
		var why: String = str(size)
		var rest: Dictionary[String, Rect2] = _rects()
		var first_digit: Rect2 = _credits().get_child(0).get_global_rect()
		_publish(1111)  # Counting down: 9999, 8xxx ... 1111, every digit changes.
		for stage: int in 6:
			_step(200)
			assert_that(_rects()).override_failure_message("%s: stage %d" % [why, stage]).is_equal(
				rest
			)
			var digits: Array[Rect2] = _digit_rects(_credits())
			assert_that(digits[0]).override_failure_message(why).is_equal(first_digit)
			for index: int in digits.size():
				assert_float(digits[index].size.x).is_equal(digits[0].size.x)  # One slot width.
				assert_float(digits[index].position.x).is_equal_approx(
					first_digit.position.x + index * digits[0].size.x, 0.5
				)
		assert_str(_credits().text).override_failure_message(why).is_equal("1111")


## A new match starts without a flash, and so does the first read: the numbers show as they are.
func test_the_first_read_and_a_new_match_show_no_flash() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(5000)
	assert_bool(_chip().visible).is_false()
	assert_str(_credits().text).is_equal("5000")
	_publish(4000)
	assert_bool(_chip().visible).is_true()
	_serial += 1  # The next match: other credits, a fresh state.
	_publish(200)
	assert_bool(_chip().visible).is_false()
	assert_str(_credits().text).is_equal("200")
	_step(FLASH_MS)
	assert_str(_credits().text).is_equal("200")
	_publish(150)  # And inside the new match the flashes work again.
	assert_str(_chip_text().text).is_equal("-50")


## `economy_flash_ms` is the time: another value gives another time, and 0 turns the flashes off.
func test_the_flash_time_is_the_settings_and_zero_turns_it_off() -> void:
	await _open(ScreenSizes.ALL[0])
	var settings: InputSettings = _feed.state.settings.duplicate() as InputSettings
	settings.economy_flash_ms = 400  # The shared file's table is never written.
	_feed.state.settings = settings
	_publish(1000)
	_publish(600)
	_step(399)
	assert_bool(_chip().visible).is_true()
	assert_str(_credits().text).is_equal("601")
	_step(1)
	assert_bool(_chip().visible).is_false()
	assert_str(_credits().text).is_equal("600")
	assert_int(load(SETTINGS).economy_flash_ms).is_equal(FLASH_MS)
	settings.economy_flash_ms = 0
	_publish(300)
	assert_bool(_chip().visible).is_false()
	assert_str(_credits().text).is_equal("300")
	_publish(900)
	assert_bool(_chip().visible).is_false()
	assert_str(_credits().text).is_equal("900")


## A count-down keeps the time it began with: a change of `economy_flash_ms` in the middle of one
## does not make the number jump or overshoot, the count ends when it was due to, and the credits
## row remembers what it shows.
func test_a_count_keeps_its_own_time_when_the_setting_changes_in_the_middle() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(1000)
	_publish(400)  # A count of 1 000 ms.
	_step(500)
	assert_str(_credits().text).is_equal("700")
	var settings: InputSettings = _feed.state.settings.duplicate() as InputSettings
	settings.economy_flash_ms = 400
	_feed.state.settings = settings
	_step(250)  # Three quarters of the count's own time.
	assert_str(_credits().text).is_equal("550")
	_step(249)
	assert_str(_credits().text).is_equal("401")
	_step(1)
	assert_str(_credits().text).is_equal("400")
	settings.economy_flash_ms = 0
	_step(100)
	assert_str(_credits().text).is_equal("400")
	assert_int(_pill._written).is_equal(400)


## A turn mid-flash keeps the chip, its sum and its time, and moves it under the credits of the
## other layout.
func test_a_turn_keeps_the_flash_and_moves_the_chip_under_the_credits() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(1000)
	_publish(400)
	_step(300)
	for size: Vector2i in ScreenSizes.ALL:
		UiScale.clear_override()
		get_window().size = size
		await _settle()
		var why: String = str(size)
		var tap: Rect2 = (_hud("CreditsTap") as Control).get_global_rect()
		assert_bool(_chip().visible).override_failure_message(why).is_true()
		assert_str(_chip_text().text).override_failure_message(why).is_equal("-600")
		assert_float(_chip().get_global_rect().position.x).is_equal_approx(tap.position.x, 1.0)
		assert_float(_chip().get_global_rect().position.y).override_failure_message(why).is_greater(
			_pill.get_global_rect().end.y
		)
	_step(699)
	assert_bool(_chip().visible).is_true()  # 300 + 699: one ms of the time left.
	_step(1)
	assert_bool(_chip().visible).is_false()


## The hook of P89's pulse stays: the flashes do not touch the low-power state.
func test_the_low_power_state_is_unchanged_by_the_flashes() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(1000, 100, 60)
	assert_bool(_pill.is_low()).is_false()
	_publish(300, 100, 140)
	assert_bool(_pill.is_low()).is_true()
	assert_bool(_chip().visible).is_true()
	_publish(300, 100, 40)
	assert_bool(_pill.is_low()).is_false()


## The pill shows nothing of a flash while the card is open (the card has the credits), and the
## chip comes back with the card's close if its time is not over. The card opens and closes with
## real touches on the pill's numbers and on the map.
func test_the_chip_waits_while_the_economy_card_shows() -> void:
	await _open(ScreenSizes.ALL[0])
	_publish(1000)
	_publish(700)
	await _tap((_hud("CreditsTap") as Control).get_global_rect().get_center())
	assert_bool(_feed.state.is_open(HudState.Unfold.ECONOMY)).is_true()
	assert_bool(_chip().visible).is_false()
	_step(500)
	await _tap(get_viewport().get_visible_rect().size * 0.5)  # On the map: the card closes.
	assert_bool(_feed.state.is_open(HudState.Unfold.ECONOMY)).is_false()
	assert_bool(_chip().visible).is_true()
	_step(500)
	assert_bool(_chip().visible).is_false()


## Moves the pill's frame time on by `ms`. The pill's own frames are off, so this is its only clock.
func _step(ms: int) -> void:
	_pill._process(ms / 1000.0)


## One crafted tick: three players' columns, the local player (player 1) in index 1, and the other
## player's numbers beside it so a read of the wrong index shows them.
func _publish(credits: int, made: int = 100, used: int = 40) -> void:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = _serial
	snap.credits = PackedInt32Array([0, credits, 9000])
	snap.power_made = PackedInt32Array([0, made, 777])
	snap.power_used = PackedInt32Array([0, used, 777])
	_tick += 1
	snap.tick = _tick
	_runner.snapshot = snap
	_pill.refresh()


func _chip() -> PanelContainer:
	return _hud("Flash") as PanelContainer


func _chip_text() -> DigitRow:
	return _hud("FlashText") as DigitRow


func _credits() -> DigitRow:
	return _hud("Credits") as DigitRow


func _chip_colour() -> Color:
	return (_chip().get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color


func _token(token: StringName) -> Color:
	return _pill.get_theme_color(token, &"HudTokens")


func _rects() -> Dictionary[String, Rect2]:
	var rects: Dictionary[String, Rect2] = {"Pill": _pill.get_global_rect()}
	for node_name: String in ["CreditsGlyph", "Credits", "PowerGlyph", "PowerBar", "PowerText"]:
		rects[node_name] = (_hud(node_name) as Control).get_global_rect()
	return rects


func _digit_rects(row: DigitRow) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child: Node in row.get_children():
		if (child as Control).visible:
			rects.append((child as Control).get_global_rect())
	return rects


## WCAG 2.1 relative luminance of an sRGB colour.
static func _luminance(color: Color) -> float:
	var linear: Array[float] = []
	for channel: float in [color.r, color.g, color.b]:
		linear.append(
			channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)
		)
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


## WCAG 2.1 contrast ratio of two colours, 1 to 21.
static func _contrast(first: Color, second: Color) -> float:
	var light: float = maxf(_luminance(first), _luminance(second))
	var dark: float = minf(_luminance(first), _luminance(second))
	return (light + 0.05) / (dark + 0.05)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## A finger down and up at `at` (base px), then the frames the card needs to follow the state.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await _settle()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size` with the match paused, the Commands caught and the pill's and the
## feed's own frames off (the test steps them).
func _open(size: Vector2i) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_feed = _hud("HudStateFeed") as HudStateFeed
	_feed.set_process(false)
	_pill = _hud("EconomyPill") as EconomyPill
	_pill.set_process(false)
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_serial = 0
	await _settle()
