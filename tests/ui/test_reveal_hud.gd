extends GdUnitTestSuite
## The sweep on the battle-screen HUD (plan P235, ADR 0036 sections 11 and 12), in the real scene at
## the six sizes of ScreenSizes.ALL: the enemy's badge (lit while on, dimmed with a pause mark while
## paused, gone at 0 and for the player's own sweep), its warning line from the STRIKE event of kind
## REVEAL (once, for every other player, for `life.reveal_warn_ms`), and the owner's strike button
## (no aim: the check mark is lit at once; "On" or "Paused" while the sweep stands; dimmed with the
## low-power glyph while the sim refuses it). Every part is inside the safe rect, at least 48 dp
## and clear of the other HUD controls. The match is paused; the snapshot is written in place, as
## test_strike_controls does. Player 1 (local) has a space centre, id 1; player 2 a Headquarters.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const SPACE: int = 1
const BORE: int = 3
const SPAWNS: Array[Array] = [[1, "fossil_space", 6, 6], [2, "renew_hq", 20, 20]]
const OTHERS: Array[String] = [
	"EconomyPill", "GroupColumn", "CommandBar", "BuildButton", "StrikeControls", "RadarScope"
]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _aim: StrikeAim
var _badge: RevealBadge


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func test_the_enemy_badge_follows_the_sweep_state_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = "size %s" % size
		_set_reveal([0, 0, 0])
		assert_bool(_badge.visible).override_failure_message(why).is_false()
		_set_reveal([0, 1, 0])  # The player's own sweep is no badge.
		assert_bool(_badge.visible).override_failure_message(why).is_false()
		for state: int in [Reveal.State.ON, Reveal.State.PAUSED]:
			_set_reveal([0, 0, state])
			assert_array([_badge.visible, _badge.state]).override_failure_message(why).is_equal(
				[true, state]
			)
			_check_rect(_badge, why)
		_set_reveal([0, 0, 0])
		assert_bool(_badge.visible).override_failure_message(why).is_false()  # At 0 it goes.


func test_the_warning_line_shows_once_for_an_enemy_sweep_and_goes_with_its_time() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = "size %s" % size
		var warn: float = float(_badge.life.reveal_warn_ms)
		_fire_event(1)  # The player's own sweep: no warning for the one who fires.
		assert_float(_badge.line_ms).override_failure_message(why).is_equal(0.0)
		_fire_event(2)
		assert_float(_badge.line_ms).override_failure_message(why).is_equal(warn)
		assert_bool(_badge.visible).override_failure_message(why).is_true()
		var line: Label = _badge.get_child(0)
		assert_bool(line.visible).override_failure_message(why).is_true()
		var dp: float = UiScale.base_px_per_dp()
		assert_float(line.size.x).override_failure_message(why).is_greater_equal(152.0 * dp - 2.0)
		assert_float(_badge.size.x).override_failure_message(why).is_less_equal(
			(220.0 + 8.0 + 48.0) * dp + 2.0
		)
		var font: Font = line.get_theme_font("font")  # The text is not cut inside its plate.
		var need: float = (
			font
			. get_string_size(
				line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.get_theme_font_size("font_size")
			)
			. x
		)
		assert_float(need).override_failure_message(why).is_less_equal(line.size.x)
		_check_rect(_badge, why)
		_badge.advance(warn - 1.0)
		assert_bool(_badge.visible).override_failure_message(why).is_true()
		_badge.advance(2.0)
		assert_bool(_badge.visible).override_failure_message(why).is_false()  # No sweep, no line.


func test_the_owners_button_has_no_aim_and_shows_on_paused_and_low_power() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = "size %s" % size
		var button: StrikeButton = _main.find_child("StrikeButton", true, false)
		_wait_no_more()
		assert_bool(_aim.reveal).override_failure_message(why).is_true()
		assert_bool(button.is_visible_in_tree()).override_failure_message(why).is_true()
		assert_bool(_aim.begin()).override_failure_message(why).is_true()
		await await_idle_frame()
		var confirm: Button = _main.find_child("StrikeConfirm", true, false)
		(
			assert_bool(confirm.visible and not confirm.disabled)
			. override_failure_message(why)
			. is_true()
		)
		assert_str(_foot(button)).override_failure_message(why).is_equal("Ready")  # No "Tap map".
		_aim.cancel()
		# A low-power refusal: dimmed, the glyph, no aim.
		_runner.snapshot.power_used[1] = _runner.snapshot.power_made[1] + 1
		_aim.refresh()
		assert_array([button.low_power, _aim.begin()]).override_failure_message(why).is_equal(
			[true, false]
		)
		_runner.snapshot.power_used[1] = 0
		# The sweep stands: the button shows it.
		_runner.snapshot.reveal_site[1] = SPACE
		_set_reveal([0, 1, 0])
		assert_array([button.sweep, _foot(button)]).override_failure_message(why).is_equal(
			[1, "On"]
		)
		_set_reveal([0, 2, 0])
		assert_array([button.sweep, _foot(button)]).override_failure_message(why).is_equal(
			[2, "Paused"]
		)
		assert_bool(_aim.begin()).override_failure_message(why).is_false()


func test_a_ready_bore_keeps_a_full_card_while_the_sweep_is_paused() -> void:
	await _open(ScreenSizes.ALL[0], true)
	var button: StrikeButton = _main.find_child("StrikeButton", true, false)
	var snap: MatchSnapshot = _runner.snapshot
	snap.ready_tick[snap.index_of(SPACE)] = 0
	snap.ready_tick[snap.index_of(BORE)] = 0
	snap.reveal_site[1] = SPACE
	_set_reveal([0, 2, 0])
	# The standing sweep never binds: the Bore does, ready, with a small mark and no dim.
	assert_array([_aim.building_id, _aim.sweep_bound, _aim.reveal]).is_equal([BORE, false, false])
	assert_array([button.sweep, button.bound, button.low_power, _foot(button)]).is_equal(
		[2, false, false, "Ready"]
	)
	_set_reveal([0, 1, 0])
	assert_array([button.sweep, button.bound]).is_equal([1, false])


func test_the_warning_ignores_other_strikes_clears_on_a_new_match_and_waits_under_the_unfolds(
) -> void:
	await _open(ScreenSizes.ALL[0])
	for kind: int in [Strike.Kind.RUPTURE, Strike.Kind.BLACKOUT]:
		_fire_event(2, kind)
		assert_float(_badge.line_ms).is_equal(0.0)
	_fire_event(2)
	var warn: float = float(_badge.life.reveal_warn_ms)
	assert_float(_badge.line_ms).is_equal(warn)
	for unfold: HudState.Unfold in [
		HudState.Unfold.DRAWER, HudState.Unfold.RADAR, HudState.Unfold.PAUSE
	]:
		_badge.feed.state.open(unfold)
		assert_bool(_badge.visible).override_failure_message(str(unfold)).is_false()
		_badge.advance(warn * 2.0)  # The clock waits while it is covered.
		assert_float(_badge.line_ms).override_failure_message(str(unfold)).is_equal(warn)
		_badge.feed.state.close(unfold)
		assert_bool(_badge.visible).override_failure_message(str(unfold)).is_true()
	_runner.snapshot.match_serial += 1  # A new match: the old warning is gone.
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_float(_badge.line_ms).is_equal(0.0)
	assert_bool(_badge.visible).is_false()


func test_the_placement_buttons_keep_clear_of_the_badge() -> void:
	await _open(ScreenSizes.ALL[0])
	var ghost: GhostControls = _main.get_node("Hud/GhostControls") as GhostControls
	assert_bool(ghost.clear_of.has(_badge)).is_true()


func _foot(button: StrikeButton) -> String:
	var ready: Label = button.find_child("StrikeReady", true, false)
	return ready.text if ready.visible else ""


## The space centre is charged: its ready tick is the snapshot's stamp.
func _wait_no_more() -> void:
	_runner.snapshot.ready_tick[_runner.snapshot.index_of(SPACE)] = 0
	_aim.refresh()


func _set_reveal(states: Array) -> void:
	_runner.snapshot.reveal = PackedInt32Array(states)
	_aim.refresh()
	_badge.refresh()


## The STRIKE record of a sweep fired by `owner`, as the sim writes it, then a tick's signal.
func _fire_event(owner: int, kind: int = Strike.Kind.REVEAL) -> void:
	_runner.snapshot.events = PackedInt32Array([World.Event.STRIKE, SPACE, 0, 0, kind, owner, 0, 0])
	_runner.ticked.emit(_runner.snapshot.tick)
	_runner.snapshot.events = PackedInt32Array()


## The badge's node is inside the safe rect and clear of every other visible HUD control; its
## drawn badge (48 dp at least) is the node's own rect.
func _check_rect(badge: RevealBadge, why: String) -> void:
	var rect: Rect2 = badge.get_global_rect()
	var area: Control = _main.get_node("Hud").find_child("SafeArea", true, false)
	var full: Rect2 = get_viewport().get_visible_rect()
	var inner: Rect2 = Rect2(
		area.get_theme_constant("margin_left"),
		area.get_theme_constant("margin_top"),
		(
			full.size.x
			- area.get_theme_constant("margin_left")
			- area.get_theme_constant("margin_right")
		),
		(
			full.size.y
			- area.get_theme_constant("margin_top")
			- area.get_theme_constant("margin_bottom")
		)
	)
	var dp: float = UiScale.base_px_per_dp()
	(
		assert_bool(inner.grow(0.5).encloses(rect))
		. override_failure_message("%s: %s outside %s" % [why, rect, inner])
		. is_true()
	)
	assert_float(minf(rect.size.x, rect.size.y)).override_failure_message(why).is_greater_equal(
		48.0 * dp - 0.5
	)
	for name: String in OTHERS:
		var other: Control = _main.get_node("Hud").find_child(name, true, false)
		if other.is_visible_in_tree():
			var clash: String = (
				"%s: %s %s over %s %s" % [why, badge.name, rect, name, other.get_global_rect()]
			)
			(
				assert_bool(rect.intersects(other.get_global_rect()))
				. override_failure_message(clash)
				. is_false()
			)


## A new main scene at `size`, its match paused, the Commands caught.
func _open(size: Vector2i, with_bore: bool = false) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	if with_bore:
		spawns.append(Rig.spawn(1, "fossil_strike", 12, 12))
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario(spawns)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_aim = _main.get_node("StrikeAim")
	_badge = _main.get_node("Hud/RevealBadge")
	await await_idle_frame()
