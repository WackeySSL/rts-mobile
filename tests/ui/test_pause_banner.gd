extends GdUnitTestSuite
## P435 (ADR 0039 section 6, answer 5 A): the one banner of the battle, P430's band at the foot of
## the OPEN pause menu. At the six sizes of ScreenSizes.ALL it shows upright and not sideways, at
## least 16 dp under the last button; none while the content scrolls; made on open, freed on close;
## no rewarded or interstitial ad is asked for or shown meanwhile, and nothing ad-related is in the
## battle scene while the menu is closed.

const AdBandAsserts: GDScript = preload("res://tests/ui/support/ad_band_asserts.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const POLICY_GAP_DP: float = 16.0

var _window_size_before: Vector2i
var _main: Node
var _harness: RefCounted
var _service: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	if _harness != null:
		_harness.dispose()
		_harness = null


func test_the_banner_shows_upright_only_and_lines_up_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var label: String = str(size)
		_main.get_node("Hud/EconomyPill").menu_pressed.emit()
		await _settle()
		var bands: Array[Node] = _bands()
		if size.y > size.x:
			assert_array(bands).override_failure_message(label).has_size(1)
			var band: AdBannerBand = bands[0] as AdBannerBand
			assert_bool(band.get_parent().get_parent().get_parent() == _menu()).is_true()
			assert_bool(band.is_at_safe_bottom()).override_failure_message(label).is_true()
			var strip: Control = AdBandAsserts.strip_of(_service)
			assert_object(strip).override_failure_message(label).is_not_null()
			(
				assert_float(band.global_banner_rect().position.y)
				. override_failure_message(label)
				. is_equal_approx(strip.get_global_rect().position.y, 1.0)
			)
			_assert_clear_of_buttons(label)
			assert_bool(_fake().banner_visible).is_true()
		else:
			assert_array(bands).override_failure_message(label).is_empty()
			assert_bool(_fake().banner_visible).override_failure_message(label).is_false()
		_close()
		await _settle()
		assert_array(_bands()).override_failure_message(label).is_empty()
		assert_bool(_fake().banner_visible).override_failure_message(label).is_false()
		_main.free()
		await await_idle_frame()


func test_the_banner_is_freed_on_close_and_made_again_on_open() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	var first: Node = _bands()[0]
	_close()
	assert_bool(is_instance_valid(first)).is_false()  # Freed, not hidden.
	await _settle()
	assert_int(_service._banner_requests).is_equal(0)
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	assert_object(_bands()[0]).is_not_same(first)


func test_none_while_the_content_scrolls() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	_menu().column.custom_minimum_size.y = float(get_window().size.y)  # Taller than the screen.
	get_viewport().size_changed.emit()  # What a resize or a turn does.
	await _settle()
	assert_array(_bands()).is_empty()
	assert_bool(_fake().banner_visible).is_false()
	_menu().column.custom_minimum_size.y = 0.0
	get_viewport().size_changed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)  # A turn or resize evaluates it again.


func test_a_turn_while_open_moves_the_banner_with_it() -> void:
	await _open(ScreenSizes.PORTRAIT[0])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await _settle()
	assert_array(_bands()).is_empty()
	get_window().size = ScreenSizes.PORTRAIT[0]
	await _settle()
	assert_array(_bands()).has_size(1)


## No rewarded or interstitial ad is loaded for or shown while the menu is open, and none exists in
## the battle scene before it opens.
func test_no_fullscreen_ad_while_the_menu_is_open_and_nothing_before() -> void:
	await _open(ScreenSizes.PORTRAIT[0])
	assert_array(_bands()).is_empty()
	assert_array(_ad_nodes()).is_empty()
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	var fake: FakeAdBackend = _fake()
	assert_array(fake.shows).is_empty()
	for call: String in fake.calls:
		assert_bool(call.begins_with("show:")).override_failure_message(call).is_false()
		assert_bool(call.contains("rewarded") or call.contains("interstitial")).is_false()
	assert_array(_ad_nodes()).has_size(1)  # Only the band.
	_close()
	await _settle()
	assert_array(_ad_nodes()).is_empty()


## The foot is checked while the band is hidden: a drop never asks the service for a banner.
func test_a_banner_that_does_not_fit_is_never_shown() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_menu().column.custom_minimum_size.y = float(get_window().size.y)  # A real overflow.
	_menu().get_viewport().size_changed.emit()
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).is_empty()
	assert_bool(_fake().calls.has("banner")).is_false()
	assert_int(_service._banner_requests).is_equal(0)


func test_no_banner_under_an_open_confirm_dialog() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	(_menu().find_child("RestartButton", true, false) as Button).pressed.emit()
	await _settle()
	assert_array(_bands()).is_empty()
	assert_bool(_fake().banner_visible).is_false()
	(_menu()._restart_dialog as ConfirmDialog).close()
	await _settle()
	assert_array(_bands()).has_size(1)
	assert_bool(_fake().banner_visible).is_true()


## A cutout at the top and a different inset at the bottom: the band lies on the safe rect's own
## bottom, and the band raises no error.
func test_the_band_is_on_the_safe_rect_bottom_with_an_asymmetric_safe_area() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"notch_design_portrait")
	UiScale.set_override(metrics)
	await _open(metrics.window_size)
	UiScale.set_override(metrics)
	var safe: Rect2 = UiScale.safe_rect_base()
	var full: Rect2 = get_viewport().get_visible_rect()
	assert_bool(is_equal_approx(safe.position.y, full.end.y - safe.end.y)).is_false()
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	assert_bool((_bands()[0] as AdBannerBand).is_at_safe_bottom()).is_true()


## A later change of the banner's height (Remove ads, consent, a reload) is checked again.
func test_a_taller_banner_that_no_longer_fits_is_dropped() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	_fake().banner_height = int(float(get_window().size.y) / UiScale.dp(1.0))  # Taller than room.
	_service._refresh_banner()
	await _settle()
	assert_array(_bands()).is_empty()
	assert_bool(_fake().banner_visible).is_false()


func test_close_and_reopen_within_the_awaited_frames_leaves_one_band() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await await_idle_frame()
	_close()
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	assert_int(_service._banner_requests).is_equal(1)


func test_the_end_of_the_match_frees_the_band() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_array(_bands()).has_size(1)
	(_main.get_node("MatchRunner") as MatchRunner).match_ended.emit(0)
	await _settle()
	assert_array(_bands()).is_empty()
	assert_int(_service._banner_requests).is_equal(0)


## Restart and Exit to menu replace the scene with the menu open: the band goes with it.
func test_leaving_the_scene_with_the_menu_open_releases_the_banner() -> void:
	await _open(ScreenSizes.PORTRAIT[1])
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await _settle()
	assert_int(_service._banner_requests).is_equal(1)
	_main.free()
	await _settle()
	assert_int(_service._banner_requests).is_equal(0)
	assert_bool(_fake().banner_visible).is_false()


func _assert_clear_of_buttons(label: String) -> void:
	var strip_top: float = AdBandAsserts.strip_of(_service).get_global_rect().position.y
	for node: Node in _menu().find_children("*", "Button", true, false):
		var button: Button = node as Button
		if not button.is_visible_in_tree():
			continue
		var air: float = strip_top - button.get_global_rect().end.y
		assert_float(air).override_failure_message("%s %s" % [label, button.name]).is_greater_equal(
			UiScale.dp(POLICY_GAP_DP) - 0.01
		)
		assert_float(button.get_global_rect().size.y).is_greater_equal(UiScale.dp(48.0) - 0.5)


## A main scene at `size` with the fake-mode service injected into the pause menu.
func _open(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	if _harness != null:
		_harness.dispose()  # The last size's service goes before the next is made.
		remove_child(_service)
		_service.free()
	_harness = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
	_service = auto_free(_harness.make(true))
	_service.fake_auto_close = false
	add_child(_service)
	_main = auto_free(await MatchRig.open(self))
	_menu().ad_service = _service


func _close() -> void:
	(_main.get_node("Hud/HudStateFeed") as HudStateFeed).state.close(HudState.Unfold.PAUSE)


func _settle() -> void:
	for i: int in 4:
		await await_idle_frame()


func _menu() -> PauseMenu:
	return _main.get_node("Hud/PauseMenu") as PauseMenu


func _fake() -> FakeAdBackend:
	return _service._backend as FakeAdBackend


func _bands() -> Array[Node]:
	return _main.find_children("*", "AdBannerBand", true, false)


## Every node of the battle scene whose script lives in `game/ads`.
func _ad_nodes() -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in _main.find_children("*", "", true, false):
		if node is DoubleXpOffer and node.get_parent().owner is ResultScreen:
			continue  # The match result's rewarded offer (admob-policy matrix), never in the battle.
		var script: Script = node.get_script()
		if script != null and script.resource_path.contains("/ads/"):
			found.append(node)
	return found
