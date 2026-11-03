extends GdUnitTestSuite
## The economy pill's detail card (plan P119b, ADR 0025 sections 1-3) in the main scene, opened and
## closed with real touches (InputEventScreenTouch through the GUI) at the six sizes of
## ScreenSizes.ALL and at every profile of both orientations: a tap on the credits or the power
## opens it under the pill, its rect is the layout's (`HudCorners.CARD`), its content is the
## snapshot's (credits with the income per minute, the tankers, the power used and made, and a chip
## for each own building type that uses power), any next touch closes it (on the card and on the
## pill's numbers too, and that touch then does its own work), opening one unfold closes the other,
## and no Command is sent but the ones a gesture on the map sends itself. The flashes are
## test_economy_flash.gd's, the income ring's own rules test_income_ring.gd's, the state's rules
## test_hud_state*.gd's.
## Player 1 (the Derrick League) has a Headquarters and a Turbine Hall (they make 120 power), two
## Bunkhouses, a Heavy Yard and a Redoubt (they use 100), two Tankers and a Flarejack; player 2 has
## buildings and a tanker of its own, which the card must not count.

const CardHeights: GDScript = preload("res://tests/support/card_heights.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const HOW_TO_PLAY: String = "res://docs/HOW_TO_PLAY.md"
const ICONS: String = "res://assets/art/svg/icons/%s.svg"
const ROSTER: Array = [
	"headquarters",
	"power_plant",
	"barracks",
	"vehicle_factory",
	"defence_turret",
	"light_tank",
	"harvester",
]
## Own buildings and units besides the Headquarters: [file, x, y].
const MORE: Array = [
	["power_plant", 10, 6],
	["barracks", 13, 6],
	["barracks", 16, 6],
	["vehicle_factory", 6, 10],
	["defence_turret", 11, 10],
	["light_tank", 12, 14],
	["harvester", 9, 14],
	["harvester", 10, 14],
]
## The other player's: a Bunkhouse (renew_barracks) and a tanker, neither is counted.
const ENEMY: Array = [["renew_barracks", 20, 24], ["renew_tanker", 22, 20]]
## Every kind of own building that uses power, for the card at its tallest.
const ALL_CONSUMERS: Array = [
	["refinery", 10, 6],
	["barracks", 14, 6],
	["vehicle_factory", 6, 10],
	["defence_turret", 10, 10],
	["fossil_radar", 13, 10],
	["fossil_strike", 16, 10],
]
const ALL_ROSTER: Array = [
	"headquarters",
	"refinery",
	"barracks",
	"vehicle_factory",
	"defence_turret",
	"fossil_radar",
	"fossil_strike",
]
const PLAYER: int = 1
## What the card shows of the Derrick League's three consumers: display name and the power used.
const CHIPS: Dictionary[String, int] = {"Bunkhouse": 40, "Heavy Yard": 40, "Redoubt": 20}

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _placement: PlacementController
var _feed: HudStateFeed
var _state: HudState
var _pill: EconomyPill
var _now_ms: int = 0
var _sent: Array[Command] = []


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
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()
	get_window().size = _window_size_before


## A tap on the credits opens the card, a tap on the power does too; it stands where the layout
## puts it, under the pill, and the match goes on without a Command.
func test_a_tap_on_the_credits_or_the_power_opens_the_card_under_the_pill() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		for area: String in ["CreditsTap", "PowerTap"]:
			var why: String = "%s: %s" % [size, area]
			assert_bool(_card().visible).override_failure_message(why).is_false()
			assert_bool(_state.is_open(HudState.Unfold.ECONOMY)).is_false()
			await _tap_control(area)
			assert_bool(_card().visible).override_failure_message(why).is_true()
			(
				assert_bool(_state.is_open(HudState.Unfold.ECONOMY))
				. override_failure_message(why)
				. is_true()
			)
			_check_rect(why)
			assert_int(_card().mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
			await _tap(_ground())  # Anything closes it.
			await _settle()
			assert_bool(_card().visible).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(str(size)).is_empty()


## The card's rect is `HudCorners.place`'s: the pill's left edge, a gap under the pill, the card's
## width (280 dp, or what the safe rect leaves), its content's height, inside the safe rect and
## clear of the pill, at every profile of both orientations, with and without a low-power line.
func test_the_card_stands_where_the_layout_puts_it_at_every_profile() -> void:
	await _open(ScreenSizes.ALL[0])
	for profile: StringName in _every_profile():
		await _turn(profile)
		for low: bool in [false, true]:
			var snap: MatchSnapshot = _runner.snapshot
			snap.power_made[PLAYER] = 60 if low else 120
			snap.tick += 1
			await _tap_control("CreditsTap")
			_check_rect("%s, low %s" % [profile, low])
			await _tap(_ground())
			await _settle()
			assert_bool(_card().visible).is_false()


## What the card says is the snapshot's: the credits, the income per minute of the last minute of
## `stat_harvested`, the tankers, the power used and made, and a chip for each own building type
## that uses power, with the power its buildings use together. The other player's rows are not
## counted. Everything is inside the card and nothing overlaps; the numbers are HUD numbers and
## their digits keep fixed slots, so the figure does not jitter while the card is open.
func test_the_card_shows_the_economy_of_the_snapshot() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var snap: MatchSnapshot = _runner.snapshot
		snap.credits[PLAYER] = 4321
		_feed_income(snap, 50, 90)  # 50 a second for 90 s: 3 000 in the last minute.
		await _tap_control("CreditsTap")
		assert_str(_text("CardCredits")).override_failure_message(why).is_equal("4321")
		assert_str(_text("CardIncome")).override_failure_message(why).is_equal("+3000")
		assert_str(_text("CardTankers")).override_failure_message(why).is_equal("2")
		assert_str(_text("CardPower")).override_failure_message(why).is_equal("100/120")
		assert_bool((_node("CardWarning") as Control).visible).is_false()
		assert_str(_glyph("CardPowerGlyph")).is_equal(ICONS % "glyph_power")
		assert_dict(_chips()).override_failure_message(why + ": %s" % [_chips()]).is_equal(CHIPS)
		assert_int(_chips().size()).is_equal(3)
		_check_inside(why)
		var number: Label = (_node("CardCredits") as DigitRow).get_child(0) as Label
		var points: float = (
			float(number.get_theme_font_size(&"font_size")) / UiScale.base_px_per_dp()
		)
		assert_float(points).override_failure_message(why).is_greater_equal(17.5)  # 18 dp numbers.
		var caption: Label = _node("CardTankersCaption") as Label
		points = float(caption.get_theme_font_size(&"font_size")) / UiScale.base_px_per_dp()
		assert_float(points).override_failure_message(why).is_greater_equal(13.5)  # 14 dp text.
		# The digits keep their slots too: another figure of as many digits stands in the same places.
		var narrow: Array[Rect2] = _digit_rects(_node("CardCredits") as DigitRow)
		snap.credits[PLAYER] = 8888
		snap.tick += 1
		_pill.refresh()
		var wide: Array[Rect2] = _digit_rects(_node("CardCredits") as DigitRow)
		assert_array(narrow).has_size(4)
		for index: int in narrow.size():
			assert_that(wide[index]).override_failure_message(why).is_equal(narrow[index])


## The chips follow the building types in the order of the snapshot's types, and a building counts
## as the power rule counts it (Power.run, ADR 0018 section 4): not while it is a construction site
## and not while a blackout holds it offline. The numbers beside them are the snapshot's.
func test_the_chips_count_a_building_as_the_power_rule_does() -> void:
	await _open(ScreenSizes.ALL[1])
	var snap: MatchSnapshot = _runner.snapshot
	var order: Array[String] = []
	for type_id: StringName in [&"barracks", &"vehicle_factory", &"defence_turret"]:
		order.append(snap.type_names[snap.type_ids.find(type_id)])
	order.sort_custom(
		func(a: String, b: String) -> bool: return snap.type_names.find(a) < snap.type_names.find(b)
	)
	await _tap_control("CreditsTap")
	assert_array(_chip_names()).is_equal(order)
	var turret: int = _row_of(snap, &"defence_turret")
	snap.build_left[turret] = 100  # A site: it uses nothing yet.
	snap.power_used[PLAYER] = 80
	snap.tick += 1
	_pill.refresh()
	assert_dict(_chips()).is_equal({"Bunkhouse": 40, "Heavy Yard": 40})
	assert_str(_text("CardPower")).is_equal("80/120")
	snap.build_left[turret] = 0
	var until: int = snap.tick + 5
	snap.offline_until[turret] = until  # Blacked out: nothing, up to the tick before `until`...
	snap.tick = until - 1
	_pill.refresh()
	assert_dict(_chips()).is_equal({"Bunkhouse": 40, "Heavy Yard": 40})
	snap.tick = until  # ...and counted again at the stamp that reaches it (Power.run's rule).
	_pill.refresh()
	assert_dict(_chips()).is_equal(CHIPS)
	var barracks: int = _row_of(snap, &"barracks")
	snap.hp[barracks] = 0
	snap.owner[barracks] = 2  # Taken (or lost): one Bunkhouse of two is player 1's.
	snap.power_used[PLAYER] = 80
	snap.tick += 1
	_pill.refresh()
	assert_dict(_chips()).is_equal({"Bunkhouse": 20, "Heavy Yard": 40, "Redoubt": 20})
	assert_array(_sent).is_empty()


## Low power is on the card as a line and a shape: the triangle for the bolt and a line that says
## production slows and defences go offline (and nothing of the radar); the line goes with the low
## state.
func test_low_power_adds_the_line_and_the_triangle_to_the_card() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var snap: MatchSnapshot = _runner.snapshot
		snap.power_made[PLAYER] = 60  # Uses 100.
		snap.tick += 1
		_pill.refresh()
		await _tap_control("PowerTap")
		var warning: Label = _node("CardWarning") as Label
		assert_bool(warning.visible).override_failure_message(why).is_true()
		assert_str(_text("CardPower")).is_equal("100/60")
		assert_str(_glyph("CardPowerGlyph")).is_equal(ICONS % "glyph_low_power")
		var said: String = warning.text.to_lower()
		assert_bool(said.contains("production")).override_failure_message(why + said).is_true()
		assert_bool(said.contains("defences")).override_failure_message(why + said).is_true()
		assert_bool(said.contains("radar")).override_failure_message(why + said).is_false()
		_check_rect(why)
		_check_inside(why)
		assert_bool(_pill.is_low()).is_true()  # The pill's hook is untouched.
		snap.power_made[PLAYER] = 120
		snap.tick += 1
		_pill.refresh()
		await _settle()  # The container tells its new size a frame later.
		assert_bool(warning.visible).override_failure_message(why).is_false()
		assert_str(_glyph("CardPowerGlyph")).is_equal(ICONS % "glyph_power")
		_check_rect(why)  # Shorter now, and still where the layout puts it.
		snap.power_made[PLAYER] = 100  # Exactly enough is not low (Power.is_low).
		snap.tick += 1
		_pill.refresh()
		assert_bool(warning.visible).override_failure_message(why).is_false()
		assert_str(_glyph("CardPowerGlyph")).is_equal(ICONS % "glyph_power")


## The card at its tallest (every kind of consumer, low power) is `CardHeights.TALLEST_DP` high
## (within its spread) and stands inside the safe rect at the six sizes and at every profile, the
## shortest phone screens and the narrowest upright one included, with its chips inside it. The
## command bar may lie under it there (HudCorners lets the card cover it).
func test_the_card_at_its_tallest_fits_every_size_and_profile() -> void:
	await _open(ScreenSizes.ALL[0], ALL_CONSUMERS, ALL_ROSTER)
	var places: Array[Callable] = []
	for size: Vector2i in ScreenSizes.ALL:
		places.append(_to_size.bind(size))
	for profile: StringName in _every_profile():
		places.append(_turn.bind(profile))
	var tallest: float = 0.0
	for place: Callable in places:
		await place.call()
		var snap: MatchSnapshot = _runner.snapshot
		snap.power_made[PLAYER] = 10
		snap.tick += 1
		await _tap_control("PowerTap")
		var why: String = "%s" % [get_window().size]
		assert_int(_chip_names().size()).override_failure_message(why).is_equal(6)
		assert_bool((_node("CardWarning") as Control).visible).is_true()
		_check_rect(why)
		_check_inside(why)
		var height: float = _card().size.y / UiScale.base_px_per_dp()
		assert_float(height).override_failure_message(why).is_between(
			CardHeights.TALLEST_DP - CardHeights.SPREAD_DP, CardHeights.TALLEST_DP
		)
		tallest = maxf(tallest, height)
		await _tap(_ground())
		await _settle()
	assert_float(tallest).is_greater(CardHeights.TALLEST_DP - 4.0)  # The number is the card's.


## The opening state (a Headquarters and a power plant: no consumer, no low-power line) is a short
## card, as tall as its content and not as tall as a default: at every size and profile it is the
## layout's rect, and well under the 120 dp a card that was not measured would have.
func test_the_card_with_no_consumer_is_as_tall_as_its_content() -> void:
	var opening: Array = [["power_plant", 10, 6]]
	await _open(ScreenSizes.ALL[0], opening, ["headquarters", "power_plant"])
	var places: Array[Callable] = []
	for size: Vector2i in ScreenSizes.ALL:
		places.append(_to_size.bind(size))
	for profile: StringName in _every_profile():
		places.append(_turn.bind(profile))
	for place: Callable in places:
		await place.call()
		await _tap_control("CreditsTap")
		var why: String = "%s" % [get_window().size]
		assert_int(_chip_names().size()).override_failure_message(why).is_equal(0)
		assert_bool((_node("CardWarning") as Control).visible).is_false()
		_check_rect(why)
		_check_inside(why)
		var height: float = _card().size.y / UiScale.base_px_per_dp()
		assert_float(height).override_failure_message("%s: %s dp" % [why, height]).is_less(100.0)
		await _tap(_ground())
		await _settle()


## The chips are the sim's own power totals, tick by tick: a blackout on a World turret, a tick at
## a time through the real sim and the pill's reads of each published snapshot. On every tick the
## chips add up to `power_used`, the turret's chip is gone for exactly the blackout and back at the
## tick that reaches `offline_until`.
func test_the_chips_add_up_to_the_sims_power_used_through_a_blackout() -> void:
	await _open(ScreenSizes.ALL[0])
	await _tap_control("CreditsTap")
	var world: World = _runner.world
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = world.index_of(snap.unit_id[_row_of(snap, &"defence_turret")])
	var until: int = world.tick + 4
	world.offline_until[row] = until
	var seen: Dictionary[bool, int] = {true: 0, false: 0}  # Ticks with the turret out, and in.
	for _step: int in 8:
		_runner.run_ticks(1)
		snap = _runner.snapshot
		_pill.refresh()
		var total: int = 0
		for sum: int in _chips().values():
			total += sum
		var out: bool = until > snap.tick
		var why: String = "tick %d (offline until %d)" % [snap.tick, until]
		assert_int(total).override_failure_message(why).is_equal(snap.power_used[PLAYER])
		assert_bool(_chips().has("Redoubt")).override_failure_message(why).is_equal(not out)
		assert_str(_text("CardPower")).is_equal("%d/%d" % [total, snap.power_made[PLAYER]])
		seen[out] += 1
	assert_int(seen[true]).is_equal(3)  # Ticks until-3 .. until-1 (the first step is until-3).
	assert_int(seen[false]).is_greater(0)


## A second tap on the numbers closes the card and does not open it again, and the next one opens
## it: the touch that closes the card is the pill's own. HOW_TO_PLAY says "tap the numbers again".
func test_a_tap_on_the_numbers_while_the_card_shows_closes_it_and_the_next_opens_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		for area: String in ["CreditsTap", "PowerTap"]:
			await _tap_control(area)
			assert_bool(_card().visible).override_failure_message(why + area).is_true()
			await _tap_control(area)
			assert_bool(_card().visible).override_failure_message(why + area).is_false()
			assert_int(_state.current).is_equal(HudState.Unfold.NONE)
			await _tap_control("CreditsTap" if area == "PowerTap" else "PowerTap")
			assert_bool(_card().visible).override_failure_message(why + area).is_true()  # The other one.
			await _tap(_ground())
			await _settle()
		assert_array(_sent).override_failure_message(why).is_empty()


## A gesture on the map (tap, long-press box, double-tap, pan, pinch) closes the card and still does
## its own work: with a unit selected the tap on the ground is a MOVE. A touch on the card closes it
## and does nothing (the card is a HUD control: no order, no selection); a touch on a control of the
## HUD closes it and that control does its own work.
func test_any_next_touch_closes_the_card_and_does_its_own_work() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var tank: PackedInt32Array = PackedInt32Array([_unit_of(&"light_tank")])
		_controller.selection.set_ids(tank)
		await _tap_control("CreditsTap")
		await _tap(_ground())  # On the map: a MOVE.
		await _settle()
		assert_bool(_card().visible).override_failure_message(why).is_false()
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
		_sent.clear()
		await _tap_control("CreditsTap")
		await _tap(_card().get_global_rect().get_center())  # On the card: nothing.
		await _settle()
		assert_bool(_card().visible).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).is_empty()
		assert_array(_controller.selection.selected).is_equal(tank)
		_controller.selection.set_ids(PackedInt32Array())  # So that All army has something to do.
		await _tap_control("PowerTap")
		await _tap_control("AllArmy")  # A control of the HUD: its own work, the selection.
		await _settle()
		assert_bool(_card().visible).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).is_empty()
		assert_array(_controller.selection.selected).override_failure_message(why).is_equal(tank)
		# The same through the other gestures of the map: a pan, a double-tap and a pinch.
		await _tap_control("PowerTap")
		_drag(_ground(), Vector2(80.0, 30.0))
		await _settle()
		assert_bool(_card().visible).override_failure_message(why + ": pan").is_false()
		await _tap_control("PowerTap")
		_pinch(_ground(), 100.0, 150.0)
		await _settle()
		assert_bool(_card().visible).override_failure_message(why + ": pinch").is_false()
		await _tap_control("PowerTap")  # A long-press with its box: nothing in it clears the selection.
		_box(_ground(), _ground() + Vector2(60.0, 40.0))
		await _settle()
		assert_bool(_card().visible).override_failure_message(why + ": box").is_false()
		assert_array(_controller.selection.selected).override_failure_message(why).is_empty()
		await _tap_control("PowerTap")  # A double-tap on a tank selects the tanks of its type.
		_double_tap(_tank_at(tank[0]))
		await _settle()
		assert_bool(_card().visible).override_failure_message(why + ": double-tap").is_false()
		assert_array(_controller.selection.selected).override_failure_message(why).is_equal(tank)
		assert_array(_sent).override_failure_message(why).is_empty()


## Opening one unfold closes the other, both ways: the card closes the drawer and the full map
## (pinned too; the pill asks for it, but it is folded while the drawer is open), and the drawer,
## the full map and the pause menu close the card. PAUSE takes every touch,
## so the pill cannot open the card behind it.
func test_the_card_and_the_other_unfolds_close_one_another() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		for other: HudState.Unfold in [HudState.Unfold.DRAWER, HudState.Unfold.RADAR]:
			var why: String = "%s: %d" % [size, other]
			_state.open(other)
			if other == HudState.Unfold.DRAWER:
				# The pill is folded while the drawer is open (P120d), so nothing taps it there.
				await _settle()
				assert_bool(_pill.visible).override_failure_message(why).is_false()
				_state.open(HudState.Unfold.ECONOMY)
				await _settle()
			else:
				await _tap_control("CreditsTap")  # The pill asks, and opening the card closes it.
			assert_int(_state.current).override_failure_message(why).is_equal(
				HudState.Unfold.ECONOMY
			)
			assert_bool(_card().visible).override_failure_message(why).is_true()
			_state.open(other)  # And the other closes the card.
			await _settle()
			assert_bool(_card().visible).override_failure_message(why).is_false()
			_state.close(other)
			await _settle()  # The pill is back when the drawer is gone.
		_state.open(HudState.Unfold.RADAR)
		_state.pinned = true
		await _tap_control("PowerTap")
		assert_int(_state.current).is_equal(HudState.Unfold.ECONOMY)
		assert_bool(_card().visible).is_true()
		_state.pinned = false
		_state.open(HudState.Unfold.PAUSE)
		await _settle()
		assert_bool(_card().visible).override_failure_message(str(size)).is_false()
		await _tap_control("CreditsTap")
		assert_int(_state.current).is_equal(HudState.Unfold.PAUSE)
		assert_bool(_card().visible).override_failure_message(str(size)).is_false()
		assert_array(_sent).override_failure_message(str(size)).is_empty()


## A placement that begins closes the card (it folds what a gesture on the map folds), a new match
## starts without it, and a turn keeps it open and puts it where the other layout wants it.
func test_placement_a_new_match_and_a_turn() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		await _tap_control("CreditsTap")
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		await _settle()
		assert_bool(_card().visible).override_failure_message(why + ": placement").is_false()
		_placement.cancel()
		await _tap_control("CreditsTap")
		_runner.start()
		_feed._process(0.0)  # The next frame sees another match.
		await _settle()
		assert_bool(_card().visible).override_failure_message(why + ": new match").is_false()
		assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	await _open(ScreenSizes.ALL[1])
	await _tap_control("PowerTap")
	for size: Vector2i in ScreenSizes.ALL:
		UiScale.clear_override()
		get_window().size = size
		await _settle()
		assert_bool(_card().visible).override_failure_message("turn to %s" % size).is_true()
		assert_int(_state.current).is_equal(HudState.Unfold.ECONOMY)
		_check_rect("turn to %s" % size)
	assert_array(_sent).is_empty()


## The income ring is made once and the card's figure follows the match's own clock: a new match
## starts it again.
func test_the_income_ring_is_made_once_and_a_new_match_starts_it_again() -> void:
	await _open(ScreenSizes.ALL[0])
	var ring: IncomeRing = _pill._ring
	var snap: MatchSnapshot = _runner.snapshot
	_feed_income(snap, 50, 90)
	assert_int(ring.per_minute()).is_equal(3000)
	assert_int(ring._ring.size()).is_equal(60)
	snap.match_serial += 1  # Another match: its own first sample.
	snap.tick = 0
	snap.stat_harvested[PLAYER] = 700
	_pill.refresh()
	assert_int(ring.per_minute()).is_equal(0)
	assert_object(_pill._ring).is_same(ring)
	assert_int(ring._ring.size()).is_equal(60)
	_feed_income(snap, 10, 30, 700)
	assert_int(ring.per_minute()).is_equal(300)
	await _tap_control("CreditsTap")
	assert_str(_text("CardIncome")).is_equal("+300")


## KNOWN (P119c review, HudState / HudStateFeed untouched by this row): a finger held on a HUD
## control keeps the card's guard set, because only a first finger clears it. A tap on the pill
## while another finger is down on a control goes open, shut, shut, until that finger lifts and a
## new first finger goes down. If P119c's follow-up changes this, this test changes with it.
func test_known_a_finger_held_on_a_control_keeps_the_guard_set() -> void:
	await _open(ScreenSizes.ALL[0])
	var control: Vector2 = (_node("AllArmy") as Control).get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 1, control)  # Held down on a HUD control.
	await _tap_control("CreditsTap")
	assert_bool(_card().visible).is_true()  # Open: the guard was clear.
	await _tap_control("CreditsTap")
	assert_bool(_card().visible).is_false()  # Shut: the touch that closes it.
	await _tap_control("CreditsTap")
	assert_bool(_card().visible).override_failure_message("held finger: shut again").is_false()
	await _tap_control("CreditsTap")
	assert_bool(_card().visible).is_false()
	TouchEvents.release(get_viewport(), 1, control)
	await _tap_control("CreditsTap")  # A new first finger.
	assert_bool(_card().visible).is_true()
	assert_array(_sent).is_empty()


## A press for a finger that is still down means its release was lost (HudStateFeed): it is a new
## touch, a first one when no other finger is down, so it clears the guard and its tap opens the
## card.
func test_a_press_for_a_finger_still_down_counts_as_a_lost_release() -> void:
	await _open(ScreenSizes.ALL[0])
	var pill: Vector2 = (_node("CreditsTap") as Control).get_global_rect().get_center()
	await _tap_control("CreditsTap")
	assert_bool(_card().visible).is_true()
	TouchEvents.press(get_viewport(), 0, pill)  # Closes the card; the release is lost.
	await _settle()
	assert_bool(_card().visible).is_false()
	TouchEvents.press(get_viewport(), 0, pill)  # The same finger down again, with no release between.
	TouchEvents.release(get_viewport(), 0, pill)
	await _settle()
	assert_bool(_card().visible).override_failure_message("a lost release is a new touch").is_true()
	await _tap(_ground())
	await _settle()


## ADR 0025 section 19's P119b row: the card, "tap the numbers again to close", the red "-N" and the
## green "+N", in "The screen in battle", with the setting named and no number in the text, and no
## Teach mark (the ADR gives the row none).
func test_how_to_play_has_the_p119b_rows() -> void:
	var text: String = FileAccess.get_file_as_string(HOW_TO_PLAY)
	var section: String = text.get_slice("## The screen in battle", 1).get_slice("\n## ", 0)
	var rows: Array[String] = []
	for line: String in section.split("\n"):
		if line.contains("economy_flash_ms") or line.contains("Tap the credits or the power"):
			rows.append(line)
	assert_array(rows).is_not_empty()
	var joined: String = " ".join(rows).to_lower()
	for phrase: String in [
		"Tap the credits or the power",
		"income per minute",
		"tankers",
		"the next touch closes it",
		"tap the numbers again",
		"-N",
		"+N",
		"counts down",
		"economy_flash_ms",
	]:
		assert_bool(joined.contains(phrase.to_lower())).override_failure_message(phrase).is_true()
	assert_bool(joined.contains("on a control (which then does its own work)")).is_true()
	assert_bool(joined.contains("under construction")).is_false()  # Not a thing before P130.
	for row: String in rows:  # ADR 0025 section 19 marks neither row "(yes)": Teach stays empty.
		assert_bool(row.ends_with("| |")).override_failure_message(row.left(40)).is_true()


## The expected rect of the card: the layout's own function on the pill's inputs.
func _check_rect(why: String) -> void:
	var dp: float = UiScale.base_px_per_dp()
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 12.0)
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.left_taken = HudLayout.first_visible_width(_node("TopLeft") as Control) / dp
	shown.card = true
	shown.card_height = _card().get_combined_minimum_size().y / dp
	var planned: Rect2 = HudCorners.place(safe, HudLayout.is_portrait(), dp, false, shown)[
		HudCorners.CARD
	]
	var card: Rect2 = _card().get_global_rect()
	var pill: Rect2 = _pill.get_global_rect()
	var said: String = (
		"%s: card %s, planned %s, pill %s, safe %s" % [why, card, planned, pill, safe]
	)
	assert_float(card.position.x).override_failure_message(said).is_equal_approx(
		planned.position.x, 0.5
	)
	assert_float(card.position.y).override_failure_message(said).is_equal_approx(
		planned.position.y, 0.5
	)
	assert_float(card.size.x).override_failure_message(said).is_equal_approx(planned.size.x, 0.5)
	assert_float(card.size.y).override_failure_message(said).is_equal_approx(planned.size.y, 0.5)
	assert_float(card.position.x).override_failure_message(said).is_equal_approx(
		pill.position.x, 0.5
	)
	assert_float(card.position.y).override_failure_message(said).is_equal_approx(
		pill.end.y + 8.0 * dp, 1.5
	)  # The pill's height is rounded to whole px.
	assert_float(card.size.x).override_failure_message(said).is_less_equal(280.0 * dp + 0.5)
	assert_float(card.size.x).override_failure_message(said).is_equal_approx(
		minf(280.0 * dp, safe.end.x - pill.position.x), 0.5
	)
	assert_bool(safe.grow(0.5).encloses(card)).override_failure_message(said).is_true()
	assert_bool(card.intersects(pill)).override_failure_message(said).is_false()


## Every part of the card is inside it, and the chips and the two lines overlap nothing.
func _check_inside(why: String) -> void:
	var card: Rect2 = _card().get_global_rect()
	var parts: Array[Rect2] = []
	for node_name: String in ["CardCreditsRow", "CardStatusRow"]:
		parts.append((_node(node_name) as Control).get_global_rect())
	for name_of: String in ["CardCreditsGlyph", "CardCredits", "CardIncome", "CardPerMinute"]:
		var rect: Rect2 = (_node(name_of) as Control).get_global_rect()
		(
			assert_bool(card.grow(0.5).encloses(rect))
			. override_failure_message("%s: %s" % [why, name_of])
			. is_true()
		)
	for name_of: String in ["CardTankersCaption", "CardTankers", "CardPowerGlyph", "CardPower"]:
		var rect: Rect2 = (_node(name_of) as Control).get_global_rect()
		(
			assert_bool(card.grow(0.5).encloses(rect))
			. override_failure_message("%s: %s" % [why, name_of])
			. is_true()
		)
	assert_bool(parts[0].intersects(parts[1])).override_failure_message(why).is_false()
	var chips: Array[Rect2] = []
	for chip: Node in (_node("CardChips") as Control).get_children():
		if (chip as Control).visible:
			var rect: Rect2 = (chip as Control).get_global_rect()
			(
				assert_bool(card.grow(0.5).encloses(rect))
				. override_failure_message("%s: %s" % [why, chip.name])
				. is_true()
			)
			for other: Rect2 in chips:
				(
					assert_bool(other.intersects(rect))
					. override_failure_message(why + ": chips")
					. is_false()
				)
			chips.append(rect)
	var warning: Control = _node("CardWarning") as Control
	if warning.visible:
		(
			assert_bool(card.grow(0.5).encloses(warning.get_global_rect()))
			. override_failure_message(why)
			. is_true()
		)
		for chip_rect: Rect2 in chips:
			(
				assert_bool(chip_rect.intersects(warning.get_global_rect()))
				. override_failure_message(why)
				. is_false()
			)


## Credits per second `rate` for `seconds` seconds, from tick 0 on, through the pill's reads of
## the published snapshot (`snap` is the runner's); `base` is the total at second 0.
func _feed_income(snap: MatchSnapshot, rate: int, seconds: int, base: int = 0) -> void:
	for second: int in range(0, seconds + 1):
		snap.tick = second * Sim.TICK_RATE
		snap.stat_harvested[PLAYER] = base + rate * second
		_pill.refresh()


func _card() -> EconomyCard:
	return _main.get_node("Hud/EconomyCard") as EconomyCard


func _text(node_name: String) -> String:
	return (_node(node_name) as DigitRow).text


func _glyph(node_name: String) -> String:
	return (_node(node_name) as TextureRect).texture.resource_path


## The chips on show: display name -> power used.
func _chips() -> Dictionary[String, int]:
	var shown: Dictionary[String, int] = {}
	for chip: Node in (_node("CardChips") as Control).get_children():
		if (chip as Control).visible:
			var label: Label = chip.find_child("Name", true, false) as Label
			shown[label.text] = int((chip.find_child("Sum", true, false) as DigitRow).text)
	return shown


func _chip_names() -> Array[String]:
	var names: Array[String] = []
	for chip: Node in (_node("CardChips") as Control).get_children():
		if (chip as Control).visible:
			names.append((chip.find_child("Name", true, false) as Label).text)
	return names


func _digit_rects(row: DigitRow) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child: Node in row.get_children():
		if (child as Control).visible:
			rects.append((child as Control).get_global_rect())
	return rects


## The row of the first unit of type `type_id` in `snap` that player 1 owns.
func _row_of(snap: MatchSnapshot, type_id: StringName) -> int:
	for row: int in snap.unit_count():
		if snap.owner[row] == PLAYER and snap.type_ids[snap.type_index[row]] == type_id:
			return row
	return -1


func _unit_of(type_id: StringName) -> int:
	return _runner.snapshot.unit_id[_row_of(_runner.snapshot, type_id)]


## A tap on the middle of control `node_name`, then a frame for the card to follow the state.
func _tap_control(node_name: String) -> void:
	await _tap((_node(node_name) as Control).get_global_rect().get_center())
	await _settle()


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
	await await_idle_frame()


func _drag(from: Vector2, by: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, from + by, by)
	TouchEvents.release(get_viewport(), 0, from + by)
	_now_ms += 1000


func _double_tap(at: Vector2) -> void:
	for _repeat: int in 2:
		TouchEvents.press(get_viewport(), 0, at)
		_now_ms += 50
		TouchEvents.release(get_viewport(), 0, at)
		_now_ms += 100
	_now_ms += 1000


## Holds the long-press time at `from`, drags to `to` and lets go.
func _box(from: Vector2, to: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	_now_ms += _touch.settings.long_press_ms
	_touch._process(0.0)
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000


## Where unit `id` is on the screen, with the camera on it.
func _tank_at(id: int) -> Vector2:
	var row: int = _runner.snapshot.index_of(id)
	var units: UnitLayer = _main.get_node("UnitLayer")
	_camera.centre_on(_camera.screen_to_world(units.unit_screen_position(row)))
	return units.unit_screen_position(row)


func _pinch(centre: Vector2, from_half: float, to_half: float) -> void:
	var left: Vector2 = centre - Vector2(from_half, 0.0)
	var right: Vector2 = centre + Vector2(from_half, 0.0)
	TouchEvents.press(get_viewport(), 0, left)
	TouchEvents.press(get_viewport(), 1, right)
	var left_to: Vector2 = centre - Vector2(to_half, 0.0)
	var right_to: Vector2 = centre + Vector2(to_half, 0.0)
	TouchEvents.drag(get_viewport(), 0, left_to, left_to - left)
	TouchEvents.drag(get_viewport(), 1, right_to, right_to - right)
	TouchEvents.release(get_viewport(), 1, right_to)
	TouchEvents.release(get_viewport(), 0, left_to)
	_now_ms += 1000


## A ground point clear of the HUD and of the buildings, at the middle of the view.
func _ground() -> Vector2:
	_camera.centre_on(IsoProjection.cell_centre_px(16, 12))
	return get_viewport().get_visible_rect().size * 0.5


## Every device profile, landscape, portrait and the design's notch insets.
func _every_profile() -> Array[StringName]:
	var names: Array[StringName] = []
	for profile: StringName in UiProfiles.all():
		names.append(profile)
	for profile: StringName in UiProfiles.portrait():
		names.append(profile)
	for profile: StringName in UiProfiles.notch_design():  # The design's insets, both ways.
		names.append(profile)
	return names


func _node(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## The window at one of the six sizes with the engine's own metrics, settled.
func _to_size(size: Vector2i) -> void:
	UiScale.clear_override()
	get_window().size = size
	await _settle()


## Turns the window to a profile's size, with its metrics, and lets the handlers and the
## containers settle.
func _turn(profile_name: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile_name)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await _settle()


## A new main scene at `size`: the Derrick League's player 1 with `more` and `roster`, the match
## paused, the Commands caught, the pill's and the feed's own frames off and the touch clock ours.
func _open(size: Vector2i, more: Array = MORE, roster: Array = ROSTER) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	var scenario: ScenarioDef = Rig.scenario_for(PLAYER, "headquarters", more, roster)
	if more == MORE:
		for entry: Array in ENEMY:
			scenario.spawns.append(Buildings.spawn(2, entry[0], entry[1], entry[2]))
			scenario.roster.append(load("res://data/units/%s.tres" % entry[0]) as UnitDef)
	_runner.scenario = scenario
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_feed = _node("HudStateFeed") as HudStateFeed
	_state = _feed.state
	_feed.set_process(false)
	_pill = _node("EconomyPill") as EconomyPill
	_pill.set_process(false)
	var instant: InputSettings = _camera.settings.duplicate()  # The snap is a tween on wall time.
	instant.zoom_snap_ms = 0
	_camera.settings = instant
	(_node("BuildSidebar") as BuildSidebar).set_process(false)
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(16, 12))
	_runner.run_ticks(1)  # The sim's first ECONOMY: the power totals of the rows.
	if roster.has("power_plant"):
		Rig.make_ready(_runner.snapshot)
	Rig.explore(_runner.snapshot)
	await _settle()
